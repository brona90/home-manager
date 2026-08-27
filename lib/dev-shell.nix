# The devShell, its hook bootstrap, and the linter bundle.
#
# THE PROBLEM THIS SHAPE SOLVES
#
# .envrc is `use flake`, so every `cd` into this repo runs `nix print-dev-env`
# for devShells.default. nix-direnv caches the result, but that cache is keyed
# on flake.nix/flake.lock -- and flake.lock moves every week, unattended, via
# .github/workflows/update-flake.yml. So the first `cd` after each bump pays a
# full uncached evaluation of whatever devShells.default mentions, at an
# interactive prompt, with no indication of why the terminal is dead.
#
# Measured on x86_64-linux, one run of `nix eval --no-eval-cache` per line so
# the figures are comparable (warm store, so this is evaluation alone):
#
#     packages.tmux-helper       -- the bare flake-load floor       ~8s
#     packages.lint-tools        -- the linters alone              ~31s
#     the old devShells.default  -- git-hooks AND the linters       ~50s
#     this devShells.default                                        ~7s
#
# Read the excess over the floor: the linters cost ~22s and git-hooks ~19s,
# and they overlap. NEITHER is "the" cost -- pulling out one and leaving the
# other in would have left roughly half the problem standing, which is why
# both had to go.
#
# Two things that are NOT the cause, both checked rather than assumed:
#
#   * It is not a substituter miss. `nix build --dry-run` against an empty
#     chroot store says the old devShell needs 107 paths fetched (233 MiB)
#     and just 2 derivations built locally; this one needs 45 paths (122 MiB)
#     and 1. The caches have it -- the cost is evaluation plus download, not
#     local compilation, so more caching would not have helped.
#   * It is not per-hook. git-hooks.lib.run costs essentially the same with
#     zero hooks enabled as with four, so trimming the hook list buys nothing.
#
# THE SPLIT
#
# devShells.default now references no derivation beyond bare stdenv, and its
# shellHook (lib/dev-shell-hook.sh) is plain shell against the filesystem. The
# expensive halves moved behind `nix run .#install-hooks`, which the shellHook
# starts itself:
#
#   * no working pre-commit hook  -> foreground, blocking. Once per clone.
#     Fast-but-unhooked is a regression, so this case deliberately waits.
#   * hooks work but are stale    -> background, silent-ish, lock-guarded.
#
# Full cold `direnv export bash`, the number actually felt at the prompt,
# interleaved against a worktree of master on the same machine with nix's eval
# cache cleared before each run (a real flake.lock bump changes the lock's
# CONTENT, so it gives the flake a new identity and a cold eval cache --
# `touch`ing the lock does not, and an earlier version of this measurement
# fooled itself that way, reporting 6s for the unchanged shell):
#
#     master:  54.8s, 57.9s        this branch:  12.2s, 10.2s
#     warm, both: 0.5-0.8s
#
# The trade is checked, not trusted: see `checks.devshell-stays-light` and
# `checks.install-hooks-installs-hooks`, both in checks/dev-shell.nix.
{
  pkgs,
  # git-hooks.lib.<system>.run { ... }. Referenced ONLY from installHooks --
  # anything in `shell` that touched this would undo the whole split.
  preCommit,
  # packages.<system>.lint-tools (lib/lint-tools.nix). Referenced ONLY from
  # installHooks, for the same reason as preCommit: ~31s of evaluation.
  lintTools,
  # Cheap content hash of (flake.lock, lib/pre-commit-hooks.nix). When it
  # changes, the installed hooks are stale and get refreshed in the
  # background.
  hooksStamp,
}: rec {
  # git-hooks.nix's generated installer, wrapped verbatim.
  #
  # writeShellScriptBin, not writeShellApplication, on purpose: the body is
  # upstream's generated text (backticks, unquoted expansions, a `for` loop
  # over `pre-commit uninstall`), so running shellcheck over it would only
  # report on code this repo does not own, and imposing `set -e` on it would
  # abort the install the first time an uninstall of an absent hook type
  # returns non-zero.
  gitHooksInstaller =
    pkgs.writeShellScriptBin "hm-git-hooks-install"
    preCommit.shellHook;

  # Lever two: nix-direnv's cache is invalidated by a git operation (a pull
  # that takes the weekly lock bump, a checkout between branches), so refill it
  # right there instead of leaving it to ambush the next `cd`. Installed as
  # post-merge/post-checkout/post-rewrite by install-hooks.
  warmDirenv = pkgs.writeShellApplication {
    name = "hm-warm-direnv";
    runtimeInputs = [pkgs.git pkgs.direnv pkgs.coreutils];
    # No errexit: this hook runs on ordinary git commands, and its worst
    # allowed outcome is doing nothing. Aborting a warm-up on a non-zero
    # `git diff --quiet` (which returns 1 to mean "there were changes") would
    # be exactly backwards.
    bashOptions = ["nounset" "pipefail"];
    text = builtins.readFile ./warm-direnv.sh;
  };

  # The other half of those three hooks, and the only correctness-critical
  # half. .git/hooks is shared by the clone but .pre-commit-config.yaml is not
  # (the generated hook passes a RELATIVE --config), so `git worktree add`
  # leaves behind a worktree the shared pre-commit hook fires in and that has no
  # config -- and every commit there is refused. This links it, at the moment
  # the worktree is created.
  #
  # A separate script from warmDirenv on purpose: that one is an optimisation
  # with several early exits and is allowed to do nothing at all, this one is
  # not, and folding a must-run job into a may-no-op one loses the distinction.
  #
  # `readlink -f` and `ln` are why this is a derivation with coreutils on PATH
  # rather than a couple of lines inlined into the generated hook body: a git
  # hook fired from magit or a GUI gets /usr/bin, not the nix profile.
  linkPcConfig = pkgs.writeShellApplication {
    name = "hm-link-pc-config";
    runtimeInputs = [pkgs.git pkgs.coreutils];
    # No errexit, for warmDirenv's reason: this runs on ordinary git commands.
    # It reads its own exit codes and reports rather than aborting a checkout.
    bashOptions = ["nounset" "pipefail"];
    text = builtins.readFile ./link-pc-config.sh;
  };

  installHooks = pkgs.writeShellApplication {
    name = "install-hooks";
    runtimeInputs = [pkgs.git pkgs.coreutils];
    # errexit dropped deliberately -- lib/install-hooks.sh reads exit codes
    # itself so that a failure of the vendored installer is reported rather
    # than silently truncating the script.
    bashOptions = ["nounset" "pipefail"];
    text =
      builtins.replaceStrings
      [
        "@GIT_HOOKS_INSTALLER@"
        "@GIT_HOOKS_INSTALLER_STORE@"
        "@LINT_TOOLS@"
        "@WARM_DIRENV@"
        "@WARM_DIRENV_STORE@"
        "@LINK_PC_CONFIG@"
        "@LINK_PC_CONFIG_STORE@"
        "@HOOKS_STAMP@"
      ]
      [
        "${gitHooksInstaller}/bin/hm-git-hooks-install"
        "${gitHooksInstaller}"
        "${lintTools}"
        "${warmDirenv}/bin/hm-warm-direnv"
        "${warmDirenv}"
        "${linkPcConfig}/bin/hm-link-pc-config"
        "${linkPcConfig}"
        hooksStamp
      ]
      (builtins.readFile ./install-hooks.sh);
  };

  # Read from a real .sh file rather than written inline so that it is
  # shellcheck-able as itself (checks.devshell-hook-lint) -- the shellHook of
  # an mkShell gets no linting from Nix, and this one is on the interactive
  # hot path where a typo shows up as a broken prompt.
  shellHook =
    builtins.replaceStrings ["@HOOKS_STAMP@"] [hooksStamp]
    (builtins.readFile ./dev-shell-hook.sh);

  shell = pkgs.mkShell {inherit shellHook;};
}
