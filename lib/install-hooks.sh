# shellcheck shell=bash
#
# Body of `nix run .#install-hooks`. This is the expensive half of the devShell
# that used to run inline in the shellHook on every `cd`: evaluating
# git-hooks.nix and the linters cost ~42s between them. It is a once-per-clone
# job (plus a background refresh when flake.lock moves), so it lives out here
# where nobody waits on it at a prompt.
#
# No `errexit` (see bashOptions in lib/dev-shell.nix): the vendored git-hooks
# installer is upstream's generated text and is not written to survive it.
# Exit codes are read explicitly instead.

repo=$(git rev-parse --show-toplevel) || {
  echo "install-hooks: not inside a git working tree" >&2
  exit 1
}
hooks=$(git rev-parse --path-format=absolute --git-path hooks) || {
  echo "install-hooks: cannot resolve the hooks directory" >&2
  exit 1
}

# --uninstall exists because .git/hooks is SHARED by every worktree of the
# clone, so installing from a feature branch changes how git behaves in
# worktrees checked out at commits that know nothing about any of this. That
# is fine (see README: the hooks are branch-agnostic and degrade to no-ops),
# but "fine" is only defensible if it is also reversible on demand.
#
# It removes ONLY what this script wrote, identified by marker, and never
# touches the pre-commit hook -- that one is git-hooks.nix's, it predates this
# change, and removing it would silently stop linting commits.
if [ "${1:-}" = "--uninstall" ]; then
  removed=0
  for stage in post-merge post-checkout post-rewrite; do
    target="$hooks/$stage"
    if [ -e "$target" ] && grep -qF "home-manager: managed by nix run .#install-hooks" "$target" 2>/dev/null; then
      rm -f "$target" && removed=$((removed + 1))
    elif [ -e "$target" ]; then
      echo "install-hooks: $stage is not ours; left alone" >&2
    fi
  done
  rm -rf "$hooks/.hm-gcroots"
  rm -f "$hooks/.hm-install-hooks-stamp" "$hooks/.hm-install-hooks.log"
  rm -rf "$hooks/.hm-install-hooks.lock"
  echo "install-hooks: removed $removed warm hook(s); the pre-commit hook was left in place"
  exit 0
fi

# 1. git hooks, via git-hooks.nix's own installer.
#
#    First, force its hand if the hook is actually gone. That installer is
#    convergent on ONE thing: if $repo/.pre-commit-config.yaml already points
#    at the expected store path it returns immediately, without ever looking
#    at .git/hooks. So a pre-commit hook that was deleted, or left dangling by
#    a `nix-collect-garbage`, would not be reinstalled -- the installer would
#    report success, the verification at the bottom of this script would fail,
#    and the devShell would ask for a reinstall on every `cd`, forever.
#    Removing the symlink it converges on is what makes the repair path work.
installed_pre_commit=$(sed -n 's#^exec \(/nix/store/[^ ]*\)/bin/pre-commit.*#\1#p' "$hooks/pre-commit" 2>/dev/null)
if [ ! -x "$hooks/pre-commit" ] ||
  [ -z "$installed_pre_commit" ] ||
  [ ! -x "$installed_pre_commit/bin/pre-commit" ]; then
  rm -f "$repo/.pre-commit-config.yaml"
fi

"@GIT_HOOKS_INSTALLER@"
status=$?
if [ "$status" -ne 0 ]; then
  echo "install-hooks: git-hooks.nix installer failed (exit $status)" >&2
  exit "$status"
fi

# 2. Pin the store paths the installed hooks point at.
#
#    Every hook this script writes is an absolute /nix/store path, and nothing
#    else keeps those alive: one `nix-collect-garbage` and .git/hooks is a
#    directory of dangling execs. Demonstrated rather than theorised: point
#    the hook at a collected path and every `git checkout`, in every worktree,
#    prints
#      post-checkout: exec: .../hm-warm-direnv: not found
#    a papercut whose cause is nowhere near its symptom.
#
#    WHERE the root lives matters as much as that it exists. .git/hooks is
#    shared by every worktree of the clone, so a root under one worktree's
#    .direnv is strictly shorter-lived than the hook it protects: `direnv
#    prune`, a cache clean, or `git worktree remove` on the worktree that
#    happened to run the installer takes the root away and leaves the shared
#    hook pointing at a collectable path. Not hypothetical -- the measurement
#    harness for this very change wiped .direnv repeatedly. So roots for
#    SHARED hooks live in the SHARED git dir, beside the hooks they protect.
#
#    .direnv/lint-tools is deliberately left per-worktree: it is on that
#    worktree's PATH, and losing it is self-healing, because the devShell sees
#    the directory missing and reinstalls.
gcroots="$hooks/.hm-gcroots"
mkdir -p "$repo/.direnv" "$gcroots"
pin() {
  local target=$1 link=$2
  if command -v nix-store >/dev/null 2>&1 &&
    nix-store --add-root "$link" --indirect --realise "$target" >/dev/null; then
    return 0
  fi
  # No nix-store, or the daemon refused: the symlink still makes the tools
  # reachable, it just is not protected from a collection.
  ln -sfn "$target" "$link"
}

# The linter bundle the devShell puts on PATH (per-worktree, self-healing).
pin "@LINT_TOOLS@" "$repo/.direnv/lint-tools" || {
  echo "install-hooks: could not materialise the linter bundle" >&2
  exit 1
}
# The warm-cache hook body and the pre-commit closure: shared hooks depend on
# these, so they are rooted in the shared git dir. warm-direnv's root doubles
# as the devShell's health sentinel -- see lib/dev-shell-hook.sh, which tests
# it with a plain `[ -e ]` (following the symlink, so a collected target reads
# as absent) and schedules a reinstall.
pin "@WARM_DIRENV_STORE@" "$gcroots/warm-direnv" || true
pin "@GIT_HOOKS_INSTALLER_STORE@" "$gcroots/git-hooks-installer" || true

# 3. Background cache-warm hooks. Deliberately hand-installed rather than
#    declared as git-hooks.nix stages, even though it supports these three:
#    pre-commit's own wrapper insists on a per-worktree .pre-commit-config.yaml
#    and complains on every checkout in a worktree that has not got one yet --
#    which is precisely the state `git worktree add` leaves behind -- and it
#    would put a python interpreter start in front of every checkout and merge.
#    A hook whose entire job is to be silent and instant is the wrong place for
#    either. These are written AFTER the git-hooks installer above, which is
#    the only thing in the repo that runs `pre-commit uninstall`.
warn_marker="home-manager: managed by nix run .#install-hooks"
install_warm_hook() {
  local stage=$1 path tmp
  path="$hooks/$stage"

  if [ -e "$path" ] && ! grep -qF "$warn_marker" "$path" 2>/dev/null; then
    echo "install-hooks: $stage hook already exists and is not ours; leaving it alone" >&2
    return 0
  fi

  tmp="$path.hm-new"
  {
    echo '#!/bin/sh'
    echo "# $warn_marker -- see lib/warm-direnv.sh"
    echo "HM_WARM_STAGE=$stage"
    echo "export HM_WARM_STAGE"
    # Belt as well as braces. The root above should mean this path never
    # disappears, but if it ever does, the right failure for a hook whose only
    # job is an invisible optimisation is to do nothing -- not to print an
    # exec error on every checkout, merge and rebase in every worktree.
    #
    # Degrading silently would normally be the worse bug (a "gate" that can
    # only pass), so it is paired: the devShell tests the same store path
    # through $gcroots/warm-direnv on every `cd` and reinstalls when it is
    # gone. Nothing here is allowed to fail quietly AND permanently.
    echo "[ -x @WARM_DIRENV@ ] || exit 0"
    echo "exec @WARM_DIRENV@ \"\$@\""
  } >"$tmp" || return 1

  # Compare before replacing: this runs on every install, and rewriting an
  # identical hook only churns mtimes that watch tools react to.
  if [ -f "$path" ] && cmp -s "$tmp" "$path"; then
    rm -f "$tmp"
    return 0
  fi
  chmod +x "$tmp" && mv -f "$tmp" "$path"
}

for stage in post-merge post-checkout post-rewrite; do
  if ! install_warm_hook "$stage"; then
    echo "install-hooks: failed to install the $stage warm hook" >&2
    exit 1
  fi
done

# 4. Verify before stamping. The point of moving this work off the `cd` path
#    was NOT to stop doing it: a stamp written over a hook that never appeared
#    would make the devShell believe it is done and never try again.
if [ ! -x "$hooks/pre-commit" ]; then
  echo "install-hooks: BUG: $hooks/pre-commit was not installed" >&2
  exit 1
fi
if [ ! -e "$repo/.pre-commit-config.yaml" ]; then
  echo "install-hooks: BUG: $repo/.pre-commit-config.yaml was not created" >&2
  exit 1
fi
# The warm hooks' root is also the devShell's sentinel for them. If it is not
# there, the sentinel reads "collected" on every `cd` and the devShell would
# schedule a reinstall forever, so refuse to stamp rather than set up a loop.
if [ ! -e "$gcroots/warm-direnv" ]; then
  echo "install-hooks: BUG: $gcroots/warm-direnv was not rooted" >&2
  exit 1
fi

printf '%s\n' "@HOOKS_STAMP@" >"$hooks/.hm-install-hooks-stamp"
echo "install-hooks: pre-commit hook installed in $hooks"
