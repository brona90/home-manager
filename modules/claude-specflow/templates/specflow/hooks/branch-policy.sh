#!/usr/bin/env bash
# PreToolUse hook (matcher: Bash) — deterministic git branch policy.
#
# Blocks:
#   1. Commits made while on a protected branch (master / main / development)
#   2. Force pushes (git push --force / -f / --force-with-lease / a "+" refspec)
#   3. Direct pushes to a protected branch, however the refspec names it (master, HEAD:master,
#      +master, refs/heads/master), and --all / --mirror
#
# Per the repo Git model: feature branches -> development -> master. Work happens on feature
# branches; integration branches are updated via merged PRs, not direct commits/pushes.
#
# Protocol: read tool-call JSON on stdin; to block, emit a deny decision and exit 0.
#
# WHY THIS PARSES THE COMMAND STRING
#
# The hook fires BEFORE the command runs, and all it is given is the command text. It has no
# way to observe the shell that will execute it, so the directory a commit will land in has to
# be inferred. A bare "git rev-parse" in the hook's own cwd is wrong: the hook runs in the main
# checkout, which is normally sitting on a protected branch, while commands targeting a git
# worktree take the form "cd <dir> && git ..." or "git -C <dir> ...". Reading the branch here
# misreports a worktree feature-branch commit as a commit on master and blocks it — breaking
# the worktree workflow this repo recommends.
#
# Inference is approximate, so the two directions of error are NOT treated alike. This is a
# safety control: its job is denying. Whenever the effective directory cannot be established
# the answer is DENY, never "assume it is fine". An earlier attempt at this fix resolved one
# directory and fell back to "|| true" on failure, which turned every parse miss into a silent
# ALLOW: "cd <worktree> && cd <main> && git commit" and "cd <nonexistent> && git commit" both
# slipped a commit onto master past it. Hence the token walk below, and hence the explicit
# unresolved-denies arm.
set -euo pipefail

# >>> CONFIGURE: protected branches for your repo <<<
PROTECTED='master|main|development|develop'
# <<< end configuration >>>

input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"
[ -z "$cmd" ] && exit 0

deny() {
  jq -n --arg reason "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}

# --- command-string analysis -------------------------------------------------

TAB="$(printf '\t')"
NL="$(printf '\n')"
BSLASH=$'\\' # a literal backslash, spelled so shellcheck does not read it as a quoting slip

# Quote-aware tokenizer. Fills TOKENS[] with a parallel TOKKIND[] of "word"/"op". Nothing is
# evaluated: the string is walked one character at a time, so a shell operator inside quotes
# stays part of its token. That distinction carries weight — the command
#   echo "a && cd /elsewhere" && git commit
# must not be read as containing a cd.
TOKENS=()
TOKKIND=()
tokenize() {
  local s="$1"
  local n=${#s}
  local i=0 c tok="" have=0
  TOKENS=()
  TOKKIND=()
  while [ "$i" -lt "$n" ]; do
    c="${s:i:1}"
    case "$c" in
      "'")
        i=$((i + 1))
        while [ "$i" -lt "$n" ] && [ "${s:i:1}" != "'" ]; do
          tok+="${s:i:1}"
          i=$((i + 1))
        done
        i=$((i + 1))
        have=1
        ;;
      '"')
        i=$((i + 1))
        while [ "$i" -lt "$n" ] && [ "${s:i:1}" != '"' ]; do
          # A backslash inside double quotes escapes the next character, which is how a
          # literal quote reaches the middle of a token.
          if [ "${s:i:1}" = "$BSLASH" ] && [ $((i + 1)) -lt "$n" ]; then
            i=$((i + 1))
          fi
          tok+="${s:i:1}"
          i=$((i + 1))
        done
        i=$((i + 1))
        have=1
        ;;
      "$BSLASH")
        i=$((i + 1))
        if [ "$i" -lt "$n" ]; then
          tok+="${s:i:1}"
          i=$((i + 1))
        fi
        have=1
        ;;
      ' ' | "$TAB")
        if [ "$have" -eq 1 ]; then
          TOKENS+=("$tok")
          TOKKIND+=("word")
          tok=""
          have=0
        fi
        i=$((i + 1))
        ;;
      '&' | '|' | ';' | '(' | ')' | '{' | '}' | "$NL")
        # Every one of these can begin a new command, so whatever follows is in command
        # position. Grouping characters are included so
        #   (cd <dir> && git commit)
        # reads the same way as the unparenthesised form.
        if [ "$have" -eq 1 ]; then
          TOKENS+=("$tok")
          TOKKIND+=("word")
          tok=""
          have=0
        fi
        TOKENS+=("$c")
        TOKKIND+=("op")
        i=$((i + 1))
        ;;
      *)
        tok+="$c"
        i=$((i + 1))
        have=1
        ;;
    esac
  done
  if [ "$have" -eq 1 ]; then
    TOKENS+=("$tok")
    TOKKIND+=("word")
  fi
}

# Resolve a cd / -C argument against the directory in force at that point. Done with a real cd
# in a subshell, so relative paths, ".." and symlinks resolve the way the shell would. Prints
# the empty string when the path does not resolve; callers treat that as unresolved, and
# unresolved denies.
#
# A leading "~" or "$HOME" is expanded by hand: the hook sees the command before the shell
# expands anything, so an unexpanded tilde would just be a directory that does not exist.
# Written as prefix removals rather than case patterns because a literal ~ or $HOME in a
# pattern trips shellcheck (SC2088 / SC2016), and those two warnings are worth keeping live
# for the places where they would mean a real bug.
resolve_dir() {
  local base="$1" p="$2" out
  local homevar="\$HOME"
  if [ "$p" = "${homevar}" ]; then
    p="$HOME"
  elif [ "${p#"${homevar}/"}" != "$p" ]; then
    p="$HOME/${p#"${homevar}/"}"
  elif [ "$p" = "~" ]; then
    p="$HOME"
  elif [ "${p#'~/'}" != "$p" ]; then
    p="$HOME/${p#'~/'}"
  fi
  [ -n "$base" ] || return 0
  out="$(cd "$base" 2>/dev/null && cd "$p" 2>/dev/null && pwd -P)" || out=""
  printf '%s' "$out"
}

# Branch name for a directory, or one of the sentinels below. "?" cannot appear in a git ref
# name, so no sentinel can collide with a real branch.
UNRESOLVED='?unresolved' # not a directory, or not a git repository
FREEHEAD='?freehead'     # detached HEAD, or an unborn branch in a fresh repo
branch_of() {
  local d="$1" b
  if [ -z "$d" ] || [ ! -d "$d" ] || ! git -C "$d" rev-parse --git-dir >/dev/null 2>&1; then
    printf '%s' "$UNRESOLVED"
    return 0
  fi
  if b="$(git -C "$d" symbolic-ref --quiet --short HEAD 2>/dev/null)"; then
    # symbolic-ref answers on an unborn HEAD too, where rev-parse does not. A repo with no
    # commits has no shared history to protect, so its first commit stays allowed even though
    # the branch is called master.
    if git -C "$d" rev-parse --verify --quiet HEAD >/dev/null 2>&1; then
      printf '%s' "$b"
    else
      printf '%s' "$FREEHEAD"
    fi
    return 0
  fi
  printf '%s' "$FREEHEAD"
}

# True for a shell variable assignment word (NAME=value). In command position it is a prefix
# on the command that follows, not the command itself.
is_assignment() {
  [[ "$1" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]
}

# The branch a push refspec writes to. A leading "+" is a force marker, not part of the name;
# the destination is whatever follows the ":" (the source, when there is no ":"); a full
# refs/heads/ name and its short form are the same branch.
push_destination() {
  local r="${1#+}"
  case "$r" in
    *:*) r="${r##*:}" ;;
  esac
  printf '%s' "${r#refs/heads/}"
}

is_protected() {
  printf '%s\n' "$1" | grep -Eq "^($PROTECTED)$"
}

# Walk the token stream, tracking the working directory as cd moves it, and record the
# directory each git commit would actually run in. One command line can hold several git
# invocations targeting different directories, so every one is recorded and every one checked.
#
# Arguments: the command string, and the directory it starts in. The walk recurses on the
# command strings handed to "bash -c", "eval" and "env -S", starting them in the directory in
# force at that point. A git reached that way is still git; before this, every such commit fell
# through to the legacy arm below, which checks the HOOK's cwd and so allowed
# "bash -c 'cd <main> && git commit'" from a feature worktree.
#
# Wrappers that run their arguments as a command (env, command, sudo, nice, timeout, ...) and
# leading NAME=value assignments are skipped with their options, leaving the word after them in
# command position. "env -C <dir>" and "sudo -D <dir>" move the directory for that one command.
# An option this walk does not know is taken to have no argument; if that is wrong, the next
# word is misread as the command, git goes unseen, and the result is exactly the pre-wrapper
# behaviour -- the legacy arm -- not a new hole.
COMMIT_DIRS=()
FOUND_COMMIT=0
FOUND_FORCE_PUSH=0
FOUND_PROTECTED_PUSH=0
analyze() {
  tokenize "$1"
  # Copied out of the globals because a recursive call re-tokenizes and overwrites them.
  local -a toks=("${TOKENS[@]}") kinds=("${TOKKIND[@]}")
  local running="$2"
  local at_start=1
  local idx=0 total=${#toks[@]}
  local tok j gdir sub t forced here wset wdir wrapper hascmd str
  local pend npos endopts
  wset=0
  wdir=""
  while [ "$idx" -lt "$total" ]; do
    if [ "${kinds[$idx]}" = "op" ]; then
      at_start=1
      wset=0
      idx=$((idx + 1))
      continue
    fi
    tok="${toks[$idx]}"
    if [ "$at_start" -eq 1 ]; then
      if [ "$wset" -eq 1 ]; then here="$wdir"; else here="$running"; fi
      if is_assignment "$tok"; then
        idx=$((idx + 1))
        continue
      fi
      case "$tok" in
        env | */env | command | builtin | exec | nohup | time | sudo | */sudo | doas | */doas \
          | nice | */nice | ionice | */ionice | timeout | */timeout | stdbuf | */stdbuf)
          wrapper="${tok##*/}"
          idx=$((idx + 1))
          while [ "$idx" -lt "$total" ] && [ "${kinds[$idx]}" = "word" ]; do
            t="${toks[$idx]}"
            case "$wrapper:$t" in
              *:--)
                idx=$((idx + 1))
                break
                ;;
              env:-C | env:--chdir | sudo:-D | sudo:--chdir)
                wset=1
                wdir=""
                if [ $((idx + 1)) -lt "$total" ] && [ "${kinds[$((idx + 1))]}" = "word" ]; then
                  wdir="$(resolve_dir "$here" "${toks[$((idx + 1))]}")"
                fi
                idx=$((idx + 2))
                ;;
              env:--chdir=* | sudo:--chdir=*)
                wset=1
                wdir="$(resolve_dir "$here" "${t#--chdir=}")"
                idx=$((idx + 1))
                ;;
              env:-S | env:--split-string | env:--split-string=*)
                # The rest of the line is one command string that env splits and runs.
                if [ "$t" = "${t#--split-string=}" ]; then
                  str=""
                  idx=$((idx + 1))
                else
                  str="${t#--split-string=}"
                  idx=$((idx + 1))
                fi
                while [ "$idx" -lt "$total" ] && [ "${kinds[$idx]}" = "word" ]; do
                  str+=" ${toks[$idx]}"
                  idx=$((idx + 1))
                done
                if [ "$wset" -eq 1 ]; then here="$wdir"; fi
                analyze "$str" "$here"
                break
                ;;
              env:-u | env:--unset | sudo:-u | sudo:-g | sudo:-p | sudo:-C | sudo:-U \
                | sudo:-r | sudo:-t | sudo:-T | doas:-u | doas:-C | nice:-n | ionice:-c \
                | ionice:-n | timeout:-s | timeout:-k | stdbuf:-i | stdbuf:-o | stdbuf:-e \
                | exec:-a)
                idx=$((idx + 2))
                ;;
              env:*)
                if is_assignment "$t" || [ "${t#-}" != "$t" ]; then
                  idx=$((idx + 1))
                else
                  break
                fi
                ;;
              *:-*) idx=$((idx + 1)) ;;
              *) break ;;
            esac
          done
          # timeout's first operand is the duration, not the command.
          if [ "$wrapper" = timeout ] && [ "$idx" -lt "$total" ] && [ "${kinds[$idx]}" = "word" ]; then
            idx=$((idx + 1))
          fi
          # Still in command position: the loop comes back round to the wrapped command.
          continue
          ;;
        eval)
          str=""
          idx=$((idx + 1))
          while [ "$idx" -lt "$total" ] && [ "${kinds[$idx]}" = "word" ]; do
            str+=" ${toks[$idx]}"
            idx=$((idx + 1))
          done
          analyze "$str" "$here"
          at_start=0
          continue
          ;;
        bash | sh | zsh | dash | ksh | */bash | */sh | */zsh | */dash | */ksh)
          hascmd=0
          j=$((idx + 1))
          while [ "$j" -lt "$total" ] && [ "${kinds[$j]}" = "word" ]; do
            t="${toks[$j]}"
            case "$t" in
              --rcfile | --init-file | -o | +o | -O | +O) j=$((j + 2)) ;;
              --) j=$((j + 1)) && break ;;
              --*) j=$((j + 1)) ;;
              -*c*)
                hascmd=1
                j=$((j + 1))
                ;;
              -* | +*) j=$((j + 1)) ;;
              *) break ;;
            esac
          done
          if [ "$hascmd" -eq 1 ] && [ "$j" -lt "$total" ] && [ "${kinds[$j]}" = "word" ]; then
            # The words after the command string are $0, $1, ... -- arguments, not commands.
            analyze "${toks[$j]}" "$here"
          fi
          ;;
        cd)
          if [ $((idx + 1)) -lt "$total" ] && [ "${kinds[$((idx + 1))]}" = "word" ]; then
            running="$(resolve_dir "$here" "${toks[$((idx + 1))]}")"
          else
            # Bare cd goes to $HOME, which is not the directory we were tracking.
            running="$HOME"
          fi
          ;;
        git | */git)
          gdir="$here"
          sub=""
          forced=0
          pend=0
          npos=0
          endopts=0
          j=$((idx + 1))
          while [ "$j" -lt "$total" ] && [ "${kinds[$j]}" = "word" ]; do
            t="${toks[$j]}"
            if [ -z "$sub" ]; then
              # Still in git's own options, ahead of the subcommand.
              case "$t" in
                -C)
                  if [ $((j + 1)) -lt "$total" ] && [ "${kinds[$((j + 1))]}" = "word" ]; then
                    gdir="$(resolve_dir "$here" "${toks[$((j + 1))]}")"
                    j=$((j + 1))
                  else
                    gdir=""
                  fi
                  ;;
                --git-dir=* | --work-tree=* | --git-dir | --work-tree)
                  # These relocate the repository by a route this hook does not model.
                  # Unmodelled means unverifiable, which means deny.
                  gdir=""
                  ;;
                -c | --namespace | --exec-path | --config-env)
                  j=$((j + 1))
                  ;;
                -*) : ;;
                *) sub="$t" ;;
              esac
            elif [ "$sub" = push ]; then
              # push's own arguments: options, then <remote>, then refspecs. Every refspec's
              # destination is checked, so "HEAD:master", "+master" and "refs/heads/master"
              # are read as the push to master they are.
              if [ "$pend" -eq 1 ]; then
                pend=0
              elif [ "$endopts" -eq 0 ] && [ "${t#-}" != "$t" ]; then
                case "$t" in
                  --) endopts=1 ;;
                  -o | --push-option | --repo | --receive-pack | --exec) pend=1 ;;
                  --force | --force-with-lease | --force-with-lease=* | --force-if-includes)
                    forced=1
                    ;;
                  --all | --branches | --mirror) FOUND_PROTECTED_PUSH=1 ;;
                  --*) : ;;
                  *f*) forced=1 ;; # a short-option cluster with f in it: -f, -uf, -fu
                esac
              else
                npos=$((npos + 1))
                if [ "$npos" -ge 2 ]; then
                  # A leading + on a refspec forces that one update.
                  [ "${t#+}" != "$t" ] && forced=1
                  if is_protected "$(push_destination "$t")"; then
                    FOUND_PROTECTED_PUSH=1
                  fi
                fi
              fi
            else
              case "$t" in
                --force | -f | --force-with-lease | --force-with-lease=* | --force-if-includes)
                  forced=1
                  ;;
              esac
            fi
            j=$((j + 1))
          done
          case "$sub" in
            commit)
              FOUND_COMMIT=1
              COMMIT_DIRS+=("$gdir")
              ;;
            push)
              [ "$forced" -eq 1 ] && FOUND_FORCE_PUSH=1
              ;;
          esac
          ;;
      esac
      at_start=0
    fi
    idx=$((idx + 1))
  done
}

analyze "$cmd" "$PWD"

# --- policy ------------------------------------------------------------------

# 1) Force push -> always blocked.
#
# The substring test is kept exactly as it was and the token-based test is added to it. The
# substring form cannot see a force push written as "git -C <dir> push --force", because it
# requires git and push to be adjacent; the token form reads the subcommand properly. Union,
# so this can only ever block more than it did before.
if [ "$FOUND_FORCE_PUSH" -eq 1 ] \
   || { printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+push' \
        && printf '%s' "$cmd" | grep -Eq -- '--force-with-lease|--force([[:space:]]|$)|[[:space:]]-f([[:space:]]|$)'; }; then
  deny "Blocked: force push. Rewriting shared history is not allowed; reconcile with a normal push/merge instead."
fi

# 2) Direct push to a protected branch (git push <remote> <protected>).
#
# Same union as above. The grep only sees a protected name with whitespace right before it, so
# "HEAD:master", "+master" and "refs/heads/master" all went past it; the token walk reads each
# refspec's destination instead, and also counts --all / --mirror, which push every branch.
if [ "$FOUND_PROTECTED_PUSH" -eq 1 ] \
   || { printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+push' \
        && printf '%s' "$cmd" | grep -Eq "[[:space:]]($PROTECTED)([[:space:]]|:|$)"; }; then
  deny "Blocked: direct push to a protected branch ($PROTECTED). Use a feature branch and open a PR."
fi

# 3) Commit while on a protected branch — in whichever directory the commit runs in.
if [ "$FOUND_COMMIT" -eq 1 ]; then
  for dir in "${COMMIT_DIRS[@]}"; do
    branch="$(branch_of "$dir")"
    case "$branch" in
      "$UNRESOLVED")
        deny "Blocked: cannot determine which branch this commit would land on — the target directory did not resolve to a git repository. This hook denies rather than guess. Run the command from the target directory, or give git -C an absolute path."
        ;;
      "$FREEHEAD") : ;;
      *)
        if printf '%s\n' "$branch" | grep -Eq "^($PROTECTED)$"; then
          deny "Blocked: commit on protected branch '$branch'. Create a feature branch first (feature/...), then commit."
        fi
        ;;
    esac
  done
elif printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+commit'; then
  # A commit the token walk could not attribute to an invocation — nested inside "bash -c",
  # behind "env", or reached some other way. The directory is unknown, so this falls back to
  # the pre-existing behaviour exactly: check the hook's own cwd. Deliberately unchanged from
  # before this hook learned about worktrees. This arm fires on odd input, where widening it
  # would invent false positives rather than remove them.
  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  if printf '%s\n' "$branch" | grep -Eq "^($PROTECTED)$"; then
    deny "Blocked: commit on protected branch '$branch'. Create a feature branch first (feature/...), then commit."
  fi
fi

exit 0
