# shellcheck shell=bash
#
# devShells.default's shellHook. `.envrc` is `use flake`, and nix-direnv's
# cached .rc ends in `eval "${shellHook:-}"`, so THIS RUNS ON EVERY `cd` INTO
# THE REPO -- warm cache included. Two consequences, both load-bearing:
#
#   1. It must not reference a single Nix derivation. Anything named here has
#      to be EVALUATED before direnv can hand back a prompt, and that
#      evaluation is redone from scratch every time flake.lock moves (weekly,
#      via update-flake.yml). That is the whole bug this file exists to fix;
#      see lib/dev-shell.nix for the numbers.
#   2. It must be cheap in absolute terms. Keep it to a handful of forks.
#
# Everything expensive -- the git-hooks.nix installer, the linter bundle --
# lives behind `nix run .#install-hooks`, started from here only when
# something is actually missing, and backgrounded when the hooks already work.

__hm_dev_bootstrap_bg() {
  local repo=$1 hooks=$2 lock pid log

  lock="$hooks/.hm-install-hooks.lock"
  # mkdir is atomic, so the directory IS the lock -- this is what stops a
  # second `cd` (or a second terminal) spawning a duplicate refresh. A run
  # killed mid-flight would otherwise leave the lock behind forever, hence the
  # liveness check on the pid it recorded.
  if ! mkdir "$lock" 2>/dev/null; then
    pid=$(cat "$lock/pid" 2>/dev/null) || pid=""
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      return 0
    fi
    rm -rf "$lock" 2>/dev/null
    mkdir "$lock" 2>/dev/null || return 0
  fi

  log="$hooks/.hm-install-hooks.log"

  # `exec 3>&- ...` is the whole trick, and it is not optional.
  #
  # direnv does not merely capture the .envrc's stdout: it hands the shell an
  # extra pipe on FD 3 and reads it to EOF before it returns. A child that
  # inherits FD 3 therefore keeps direnv blocked no matter how thoroughly
  # stdin/stdout/stderr are redirected. Measured here with a `sleep 8` stand-in
  # for the real job: nohup + `>/dev/null 2>&1 </dev/null` + disown still made
  # `direnv export bash` take 9364ms; adding this line took it to 713ms.
  # setsid, `--fork` and a double-forking subshell all made no difference,
  # because none of them close descriptors. (FD 5 is direnv's /dev/ptmx; it
  # does not block, but there is no reason for a background job to hold a
  # terminal open either.)
  #
  # SC2016 is likewise the point, not an oversight: the body must NOT be
  # expanded here. The values arrive as positional arguments, so a path
  # containing a space or a quote cannot be re-parsed as shell by the child.
  # shellcheck disable=SC2016
  nohup sh -c '
    exec 3>&- 4>&- 5>&- 6>&- 7>&- 8>&- 9>&-
    echo $$ >"$2/pid"
    nix run "$1#install-hooks" >>"$3" 2>&1
    rm -rf "$2"
  ' sh "$repo" "$lock" "$log" </dev/null >/dev/null 2>&1 &
  disown 2>/dev/null || true
  return 0
}

__hm_dev_bootstrap() {
  local repo hooks stamp want need pc pcc

  want="@HOOKS_STAMP@"

  repo=$(git rev-parse --show-toplevel 2>/dev/null) || return 0
  [ -n "$repo" ] || return 0

  # Linters, populated by `nix run .#install-hooks`. A PATH entry that does
  # not exist is harmless, so this needs no guard and stays correct while a
  # background refresh is still running.
  case ":${PATH}:" in
  *":$repo/.direnv/lint-tools/bin:"*) : ;;
  *) PATH="$repo/.direnv/lint-tools/bin:$PATH" ;;
  esac
  export PATH

  # One fork on the happy path. The fallback exists because `--git-path hooks`
  # honours core.hooksPath, which git-hooks.nix's installer sets relative to the
  # working copy it ran in -- and a relative path cannot be resolved from a
  # linked worktree, where `.git` is a file. Returning early there would leave
  # the worktree with no hooks and no prospect of getting any, since this is
  # what schedules the install. See lib/install-hooks.sh for the whole story.
  hooks=$(git rev-parse --path-format=absolute --git-path hooks 2>/dev/null) || hooks=""
  if [ -z "$hooks" ]; then
    hooks=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 0
    [ -n "$hooks" ] || return 0
    hooks="$hooks/hooks"
  fi

  need=""

  # (a) Is there a pre-commit hook at all? .git/hooks is shared by every
  #     worktree of this clone, so in practice this is once per clone.
  if [ ! -x "$hooks/pre-commit" ]; then
    need=missing
  fi

  # (b) Does it still point at a live store path? Nothing pins the pre-commit
  #     closure, so `nix-collect-garbage` can leave an installed-but-dead hook
  #     behind, and every commit then fails with a bad interpreter.
  if [ -z "$need" ]; then
    pc=$(sed -n 's#^exec \(/nix/store/[^ ]*\)/bin/pre-commit.*#\1#p' "$hooks/pre-commit" 2>/dev/null)
    if [ -z "$pc" ] || [ ! -x "$pc/bin/pre-commit" ]; then
      need=broken
    fi
  fi

  # (c) The generated hook passes a RELATIVE --config=.pre-commit-config.yaml,
  #     so the symlink is per-worktree even though .git/hooks is not: a fresh
  #     `git worktree add` needs one of its own, and without it the SHARED
  #     pre-commit hook refuses every commit in that worktree with "No
  #     .pre-commit-config.yaml file was found". `-e` follows the link, so a
  #     dangling one (target collected) counts as absent, which is what we
  #     want.
  #
  #     The post-checkout hook normally does this the instant the worktree is
  #     created (lib/link-pc-config.sh), so reaching here means either that
  #     hook is not installed yet or it never fired -- `git worktree add
  #     --no-checkout` does not run post-checkout at all. Repair it from the
  #     shared root, which costs one `ln`. Escalating to
  #     `nix run .#install-hooks` would be ~40s at a prompt to produce a
  #     symlink whose target is already recorded; that stays the fallback for
  #     when the root itself is missing or collected.
  if [ -z "$need" ] && [ ! -e "$repo/.pre-commit-config.yaml" ]; then
    pcc=$(readlink -f "$hooks/.hm-gcroots/pre-commit-config" 2>/dev/null) || pcc=""
    if [ -n "$pcc" ] && [ -e "$pcc" ] &&
      ln -sfn "$pcc" "$repo/.pre-commit-config.yaml" 2>/dev/null; then
      # Said out loud rather than done behind the user's back. This worktree
      # was one commit away from an error message whose folk remedy
      # (PRE_COMMIT_ALLOW_NO_CONFIG=1) commits unlinted, and the hook set it
      # has just been given is the installed one, not necessarily the one in
      # this checkout's lib/pre-commit-hooks.nix.
      echo "home-manager: linked .pre-commit-config.yaml for this worktree" >&2
    else
      need=broken
    fi
  fi

  # (d) Linter bundle missing or collected.
  if [ -z "$need" ] && [ ! -e "$repo/.direnv/lint-tools/bin" ]; then
    need=stale
  fi

  # (e) The warm hooks' script collected, or never rooted. This is the other
  #     half of the guarded `exec` in those hooks: they degrade to a silent
  #     no-op rather than erroring on every checkout in every worktree, and
  #     that is only an acceptable trade because something notices and puts
  #     them back. This is that something -- without it, "degrade quietly"
  #     would mean "never warm again, and never say so".
  #
  #     The GC root doubles as the sentinel, so this costs no fork: `-e`
  #     follows the symlink, so a collected target reads as absent.
  if [ -z "$need" ] && [ ! -e "$hooks/.hm-gcroots/warm-direnv" ]; then
    need=stale
  fi

  # (e2) Same shape, for the two things a fresh worktree's config is built
  #      from: the linker the shared hooks call, and the recorded config path
  #      they link to. Both are guarded at the point of use, so losing either
  #      degrades to "new worktrees are not configured" -- which surfaces as a
  #      refused commit rather than an unlinted one, but is still a state
  #      nobody should have to live in. It is also the migration path: a clone
  #      whose hooks were installed before any of this existed has no such
  #      roots, reads as stale here, and reinstalls in the background.
  if [ -z "$need" ] && [ ! -e "$hooks/.hm-gcroots/pre-commit-config" ]; then
    need=stale
  fi
  if [ -z "$need" ] && [ ! -e "$hooks/.hm-gcroots/link-pc-config" ]; then
    need=stale
  fi

  # (f) Installed against an older flake.lock or an older hook set.
  if [ -z "$need" ]; then
    stamp=$(cat "$hooks/.hm-install-hooks-stamp" 2>/dev/null) || stamp=""
    [ "$stamp" = "$want" ] || need=stale
  fi

  [ -n "$need" ] || return 0

  if [ "$need" = stale ]; then
    # Working hooks, just built against an older lock. Commits are already
    # protected, so blocking the prompt for ~40s of re-evaluation would be
    # precisely the bug. Refresh behind the user's back instead.
    echo "home-manager: refreshing git hooks in the background ($hooks/.hm-install-hooks.log)" >&2
    __hm_dev_bootstrap_bg "$repo" "$hooks"
    return 0
  fi

  # missing|broken: there is no working pre-commit hook right now. Blocking is
  # the correct trade here -- it happens once per clone, and a shell that
  # returns fast while leaving commits unlinted is a regression, not a fix.
  echo "home-manager: no working pre-commit hook; installing (once per clone, ~1 min)..." >&2
  if ! nix run "$repo#install-hooks"; then
    echo "home-manager: hook install FAILED -- fix it with: nix run .#install-hooks" >&2
  fi
  return 0
}

__hm_dev_bootstrap
unset -f __hm_dev_bootstrap __hm_dev_bootstrap_bg
