# shellcheck shell=bash
#
# Body of the post-merge / post-checkout / post-rewrite git hooks installed by
# `nix run .#install-hooks`.
#
# WHAT IT IS FOR. nix-direnv's cache is keyed on flake.nix/flake.lock, so the
# operation that invalidates it is a git operation -- `git pull` taking the
# weekly update-flake.yml bump, or a checkout between branches whose flakes
# differ. The refill then ambushes whichever `cd` happens next. Doing it here
# means the refill overlaps with the user reading the pull output instead.
#
# THREE RULES, all of them things this got wrong first:
#   * it must not delay the git command;
#   * it must not stack up duplicate refills;
#   * it must say nothing when it works.

marker_repo=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -n "$marker_repo" ] || exit 0
[ -f "$marker_repo/.envrc" ] || exit 0

# post-checkout also fires for `git checkout -- <path>`, where $3 is 0. Nothing
# about a file checkout can invalidate the flake cache.
if [ "${HM_WARM_STAGE:-}" = post-checkout ]; then
  [ "${3:-1}" = 1 ] || exit 0
  # And a branch switch only matters if it moved something the cache keys on.
  # A failure here (e.g. the null OID during `git worktree add`) falls through
  # to warming, which is the safe direction.
  if git diff --quiet "${1:-}" "${2:-}" -- flake.nix flake.lock .envrc 2>/dev/null; then
    exit 0
  fi
fi

# direnv shells out to `nix`, and a git hook does not necessarily have it:
# hooks fired from Emacs/magit or any non-login context get /usr/bin, not the
# nix profile. Look in the usual places and give up quietly if there is none --
# a missing warm-up is a slow `cd`, which is exactly the status quo, whereas a
# noisy hook is a new problem on every commit.
for candidate in \
  "$HOME/.nix-profile/bin" \
  /nix/var/nix/profiles/default/bin \
  /run/current-system/sw/bin; do
  [ -x "$candidate/nix" ] && PATH="$PATH:$candidate"
done
export PATH
command -v nix >/dev/null 2>&1 || exit 0

mkdir -p "$marker_repo/.direnv" 2>/dev/null || exit 0
lock="$marker_repo/.direnv/warm.lock"

# mkdir is atomic, so the directory is the lock. `git pull` fires post-merge
# once, but a rebase fires post-rewrite alongside it, and neither should start
# a second copy of a job that takes tens of seconds. A run killed mid-flight
# would strand the lock, hence the liveness check.
if ! mkdir "$lock" 2>/dev/null; then
  held=$(cat "$lock/pid" 2>/dev/null) || held=""
  if [ -n "$held" ] && kill -0 "$held" 2>/dev/null; then
    exit 0
  fi
  rm -rf "$lock" 2>/dev/null
  mkdir "$lock" 2>/dev/null || exit 0
fi

# `exec 3>&- ...` is load-bearing: whoever invoked git may be capturing the
# hook's output on a descriptor above 2 and reading it to EOF, and an inherited
# descriptor keeps the caller blocked however carefully stdin/stdout/stderr are
# redirected. direnv does exactly this on FD 3, and it cost 9.4s per `cd`
# before the close was added; a git front-end is entitled to do the same.
#
# SC2016 is deliberate: nothing in the body may be expanded here.
# shellcheck disable=SC2016
nohup sh -c '
  exec 3>&- 4>&- 5>&- 6>&- 7>&- 8>&- 9>&-
  echo $$ >"$2/pid"
  cd "$1" || exit 0
  direnv export bash >/dev/null 2>>"$1/.direnv/warm.log"
  rm -rf "$2"
' sh "$marker_repo" "$lock" </dev/null >/dev/null 2>&1 &
disown 2>/dev/null || true

exit 0
