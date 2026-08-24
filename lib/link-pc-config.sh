# shellcheck shell=bash
#
# Body of `hm-link-pc-config`, run from the shared post-checkout / post-merge /
# post-rewrite hooks that `nix run .#install-hooks` installs.
#
# THE BUG. `.git/hooks` belongs to the CLONE and is shared by every worktree.
# `.pre-commit-config.yaml` does NOT: the hook git-hooks.nix generates passes a
# RELATIVE `--config=.pre-commit-config.yaml`, which pre-commit resolves against
# the worktree it was invoked in. So `git worktree add` produces a worktree that
# the shared pre-commit hook fires in and that has no config, and every commit
# there dies with
#
#     No .pre-commit-config.yaml file was found
#     - To temporarily silence this, run `PRE_COMMIT_ALLOW_NO_CONFIG=1 git ...`
#
# This repo's whole workflow is worktree-based, so that is every new branch.
#
# WHY NOT JUST MAKE THE CONFIG OPTIONAL. `pre-commit install
# --allow-missing-config` unblocks the commit by SKIPPING the linters, and so
# does the environment variable in pre-commit's own advice. Both turn "this
# worktree is misconfigured" into "this worktree is not linted", silently, which
# is the gate-that-can-only-pass shape this repo keeps getting bitten by. The
# fix has to be to give the worktree a config, not to stop needing one.
#
# WHY IT IS SAFE TO SHARE ONE CONFIG. The generated config is a JSON file whose
# every entry is an absolute /nix/store path -- one per linter -- with nothing
# worktree-specific, or even repo-specific, in it. And the pre-commit hook in
# `.git/hooks` already pins ONE pre-commit closure for all worktrees, so
# pointing them at the matching config makes the arrangement more consistent,
# not less. A worktree sitting on a
# commit with a different `lib/pre-commit-hooks.nix` is linted by the installed
# hook set rather than by its own -- exactly as it already was for the hook
# itself. See README, "These hooks belong to the clone, not to the branch".
#
# NO `errexit`: this runs on ordinary git commands. Every failure path below
# reports and returns 0 rather than making `git checkout` look broken.

repo=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -n "$repo" ] || exit 0

# Not a single `--git-path hooks`: that honours core.hooksPath, which
# git-hooks.nix's installer sets to a value relative to the working copy it ran
# in, and a relative path cannot be resolved from a linked worktree because
# `.git` is a file there. It fails outright -- which for this script would mean
# the worktree quietly never gets a config. lib/install-hooks.sh carries the
# full explanation and the permanent repair.
hooks=$(git rev-parse --path-format=absolute --git-path hooks 2>/dev/null) || hooks=""
if [ -z "$hooks" ]; then
  hooks=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || exit 0
  [ -n "$hooks" ] || exit 0
  hooks="$hooks/hooks"
fi

# No pre-commit hook means nothing is blocking a commit here, and dropping a
# config into a clone that never asked for one would be litter.
[ -x "$hooks/pre-commit" ] || exit 0

# `-e` follows the symlink, so a dangling one -- target collected by
# `nix-collect-garbage` -- reads as absent and gets repaired here, rather than
# waiting to fail at commit time.
[ -e "$repo/.pre-commit-config.yaml" ] && exit 0

# The config store path, recorded by install-hooks as a GC root in the SHARED
# git dir, beside the shared hook that needs it. Resolved to the store path
# rather than linked through the root: `install-hooks -- --uninstall` deletes
# `.hm-gcroots` wholesale, and a link through it would silently break the
# config of every worktree in the clone.
target=$(readlink -f "$hooks/.hm-gcroots/pre-commit-config" 2>/dev/null) || target=""

if [ -z "$target" ] || [ ! -e "$target" ]; then
  # Loud on purpose. Staying quiet here would hand the user precisely the
  # confusing pre-commit error this script exists to prevent, at commit time,
  # with no clue where it came from.
  echo "home-manager: $repo has no .pre-commit-config.yaml and the shared copy" >&2
  echo "  is missing or has been garbage-collected, so commits in this worktree" >&2
  echo "  will be REFUSED by the pre-commit hook. Repair it with:" >&2
  echo "      nix run .#install-hooks" >&2
  echo "  Silencing pre-commit instead would commit this worktree unlinted." >&2
  exit 0
fi

if ! ln -sfn "$target" "$repo/.pre-commit-config.yaml" 2>/dev/null; then
  echo "home-manager: could not write $repo/.pre-commit-config.yaml;" >&2
  echo "  commits in this worktree will be refused by the pre-commit hook." >&2
  exit 0
fi

exit 0
