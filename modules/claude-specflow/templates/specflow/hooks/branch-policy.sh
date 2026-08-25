#!/usr/bin/env bash
# PreToolUse hook (matcher: Bash) — deterministic git branch policy.
#
# Blocks:
#   1. Commits made while on a protected branch (master / main / development)
#   2. Force pushes (git push --force / -f / --force-with-lease)
#   3. Direct pushes to a protected branch
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

# Walk the token stream, tracking the working directory as cd moves it, and record the
# directory each git commit would actually run in. One command line can hold several git
# invocations targeting different directories, so every one is recorded and every one checked.
COMMIT_DIRS=()
FOUND_COMMIT=0
FOUND_FORCE_PUSH=0
analyze() {
  local running="$PWD"
  local at_start=1
  local idx=0 total=${#TOKENS[@]}
  local tok j gdir sub t forced
  while [ "$idx" -lt "$total" ]; do
    if [ "${TOKKIND[$idx]}" = "op" ]; then
      at_start=1
      idx=$((idx + 1))
      continue
    fi
    tok="${TOKENS[$idx]}"
    if [ "$at_start" -eq 1 ]; then
      case "$tok" in
        cd)
          if [ $((idx + 1)) -lt "$total" ] && [ "${TOKKIND[$((idx + 1))]}" = "word" ]; then
            running="$(resolve_dir "$running" "${TOKENS[$((idx + 1))]}")"
          else
            # Bare cd goes to $HOME, which is not the directory we were tracking.
            running="$HOME"
          fi
          ;;
        git | */git)
          gdir="$running"
          sub=""
          forced=0
          j=$((idx + 1))
          while [ "$j" -lt "$total" ] && [ "${TOKKIND[$j]}" = "word" ]; do
            t="${TOKENS[$j]}"
            if [ -z "$sub" ]; then
              # Still in git's own options, ahead of the subcommand.
              case "$t" in
                -C)
                  if [ $((j + 1)) -lt "$total" ] && [ "${TOKKIND[$((j + 1))]}" = "word" ]; then
                    gdir="$(resolve_dir "$running" "${TOKENS[$((j + 1))]}")"
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

tokenize "$cmd"
analyze

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
if printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+push' \
   && printf '%s' "$cmd" | grep -Eq "[[:space:]]($PROTECTED)([[:space:]]|:|$)"; then
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
