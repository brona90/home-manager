# The devShell / hook-installer contract, guarded from both sides.
#
# These two guards share a file deliberately: either one alone is satisfied by
# the bug the other catches. A devShell that does nothing at all is perfectly
# "light", and an installer that re-runs on every `cd` certainly does "install
# hooks". Changing one without reading the other is the mistake this file
# exists to make awkward.
#
# Inputs, passed by checks/default.nix. Nothing in this file reads flake.nix's
# scope; if it is not in this list, it is not available here.
#   pkgs -- `pkgsFor system` for the system being checked.
#   dev  -- lib/dev-shell.nix's output set for this system, i.e.
#           `devShellFor system`: `.shell` (verbatim what devShells.default is
#           on an unpinned system), `.installHooks` and `.gitHooksInstaller`.
#           The DERIVATION is what gets inspected, never lib/dev-shell.nix's
#           source -- see the note on devshell-stays-light below for the earlier
#           cut of that guard which a re-introduced regression sailed past.
#
# Paths are relative to THIS file, so anything at the repo root reads `../`.
{
  pkgs,
  dev,
}: {
  # The devShell must stay off the expensive path, AND the hooks
  # must still actually get installed. These two guards are a pair:
  # either one alone can be satisfied by the bug the other catches.
  #
  # History: devShells.default used to inherit git-hooks.nix's
  # shellHook AND its enabledPackages. Between them that put ~56s of
  # evaluation on every `cd` into the repo whenever flake.lock had
  # moved -- which it does every week, unattended, via
  # update-flake.yml. Measured cold `direnv export bash` was 55-58s
  # here on a warm store, and over five minutes on one that also had
  # to fetch.
  #
  # Read off the devShell DERIVATION, not off lib/dev-shell.nix's
  # `shellHook` attribute: the first cut of this guard inspected the
  # latter, and a deliberate re-introduction of the regression --
  # `mkShell { shellHook = shellHook + preCommit.shellHook; }` --
  # sailed straight past it. A guard has to be shown failing.
  devshell-stays-light =
    pkgs.runCommand "devshell-stays-light" {
      # dev.shell is verbatim what devShells.default is on this
      # system (x86_64-linux is not pinned). It is reached through the
      # `dev` argument rather than through `devShells` because
      # flake.nix's outputs is a plain attrset, not rec -- that
      # attribute is not in scope even in flake.nix.
      hookText = dev.shell.shellHook or "";
      # The other way back in is `buildInputs = pre-commit.enabledPackages`.
      inputPaths =
        builtins.concatStringsSep "\n"
        (map toString (
          (dev.shell.buildInputs or [])
          ++ (dev.shell.nativeBuildInputs or [])
        ));
      passAsFile = ["hookText" "inputPaths"];
    } ''
      # git-hooks.nix's installer is identifiable by the line it logs
      # when it rewrites a repo. If that text is in the shellHook, the
      # whole derivation is being evaluated on the `cd` path again.
      if grep -q 'git-hooks.nix: updating' "$hookTextPath"; then
        echo 'GUARD: devShells.default runs the git-hooks.nix installer again.'
        echo '       That is ~19s of evaluation on every `cd` after a flake.lock bump.'
        echo '       Hook installation belongs in `nix run .#install-hooks`; see lib/dev-shell.nix.'
        exit 1
      fi
      # Same argument for the linters, which are the other ~22s. They reach
      # PATH via .direnv/lint-tools, which install-hooks materialises.
      if grep -qE '/nix/store/[a-z0-9]{32}-(shellcheck|statix|deadnix|alejandra|pre-commit)' \
           "$hookTextPath" "$inputPathsPath"; then
        echo 'GUARD: devShells.default pulls in a linter or pre-commit store path directly.'
        echo '       Use packages.lint-tools via .direnv/lint-tools instead.'
        exit 1
      fi
      touch $out
    '';

  # ... and the counterweight: install-hooks must really run the
  # upstream installer. A fast shell that quietly stopped writing
  # .git/hooks/pre-commit would be a regression, not a fix.
  install-hooks-installs-hooks =
    pkgs.runCommand "install-hooks-installs-hooks" {
      installer = "${dev.gitHooksInstaller}/bin/hm-git-hooks-install";
      appText = builtins.readFile ../lib/install-hooks.sh;
      passAsFile = ["appText"];
    } ''
      # (a) the wrapped script really is git-hooks.nix's installer,
      #     not an empty stub left behind by an upstream API change.
      grep -q 'git-hooks.nix: updating' "$installer" \
        || { echo 'GUARD: hm-git-hooks-install no longer contains the git-hooks.nix installer.'; exit 1; }

      # (b) the app actually invokes it.
      grep -q '@GIT_HOOKS_INSTALLER@' "$appTextPath" \
        || { echo 'GUARD: lib/install-hooks.sh no longer invokes the git-hooks installer.'; exit 1; }

      # (c) and refuses to stamp success it did not achieve. Without
      #     this the devShell would believe the hooks were installed
      #     and never retry.
      grep -q 'was not installed' "$appTextPath" \
        || { echo 'GUARD: lib/install-hooks.sh no longer verifies that .git/hooks/pre-commit exists before stamping.'; exit 1; }

      # (d) and can still REPAIR a deleted hook. git-hooks.nix's
      #     installer converges on .pre-commit-config.yaml alone: with
      #     that symlink intact it returns without touching
      #     .git/hooks, so a deleted pre-commit hook is never restored
      #     and the devShell asks for a reinstall on every `cd`
      #     forever. Dropping the symlink first is the repair.
      grep -q 'rm -f "$repo/.pre-commit-config.yaml"' "$appTextPath" \
        || { echo 'GUARD: lib/install-hooks.sh cannot repair a deleted pre-commit hook -- it must clear .pre-commit-config.yaml first.'; exit 1; }

      # (e) the warm hooks must be rooted in the SHARED git dir, not
      #     under a per-worktree .direnv. .git/hooks is shared by every
      #     worktree, so a root that `direnv prune` or
      #     `git worktree remove` can take away is shorter-lived than
      #     the hook it protects -- and a collected script makes every
      #     `git checkout` in every worktree print an exec error.
      grep -qF 'gcroots="$hooks/.hm-gcroots"' "$appTextPath" \
        || { echo 'GUARD: install-hooks no longer roots the warm hooks in the shared git dir.'; exit 1; }
      grep -qF 'pin "@WARM_DIRENV_STORE@" "$gcroots/warm-direnv"' "$appTextPath" \
        || { echo 'GUARD: warm-direnv is no longer GC-rooted; one nix-collect-garbage breaks every git checkout.'; exit 1; }

      # (f) ... and the hooks must survive losing it anyway, WHILE
      #     something notices. Both halves or neither: an unguarded
      #     exec is noisy on every checkout, and a guarded one with no
      #     repair is a permanent silent no-op -- the "gate that can
      #     only pass" shape this repo keeps getting bitten by.
      grep -qF '[ -x @WARM_DIRENV@ ] || exit 0' "$appTextPath" \
        || { echo 'GUARD: the warm hooks exec a store path unguarded; a collected path errors on every checkout.'; exit 1; }
      grep -qF '.hm-gcroots/warm-direnv' ${../lib/dev-shell-hook.sh} \
        || { echo 'GUARD: the devShell no longer notices a collected warm-direnv, so the guarded exec would fail silently forever.'; exit 1; }

      # (g) a FRESH WORKTREE MUST BE ABLE TO COMMIT, AND BE LINTED.
      #
      #     .git/hooks belongs to the clone; .pre-commit-config.yaml
      #     does not, because the generated hook passes a relative
      #     --config. So `git worktree add` used to leave behind a
      #     worktree the shared pre-commit hook fires in with no config,
      #     and every commit in it died with "No .pre-commit-config.yaml
      #     file was found". This repo's workflow is entirely
      #     worktree-based, so that was every new branch.
      #
      #     Three parts, and all three are needed: record the config
      #     path in the shared git dir, root the linker that reads it,
      #     and actually call the linker from the shared hooks.
      grep -qF 'pin "$pc_config" "$gcroots/pre-commit-config"' "$appTextPath" \
        || { echo 'GUARD: install-hooks no longer records the pre-commit config in the shared git dir.'; \
             echo '       Without it `git worktree add` produces a worktree that cannot commit.'; exit 1; }
      grep -qF 'pin "@LINK_PC_CONFIG_STORE@" "$gcroots/link-pc-config"' "$appTextPath" \
        || { echo 'GUARD: hm-link-pc-config is no longer GC-rooted.'; exit 1; }
      grep -qF 'if [ -x @LINK_PC_CONFIG@ ]; then @LINK_PC_CONFIG@ || true; fi' "$appTextPath" \
        || { echo 'GUARD: the shared post-checkout hook no longer links a new worktree its .pre-commit-config.yaml.'; \
             echo '       That hook firing on `git worktree add` is the only moment the worktree can be fixed'; \
             echo '       before its first commit is refused.'; exit 1; }
      grep -qF '.hm-gcroots/pre-commit-config' ${../lib/dev-shell-hook.sh} \
        || { echo 'GUARD: the devShell can no longer repair a worktree with no .pre-commit-config.yaml.'; exit 1; }

      # (g2) core.hooksPath must be cleared after the installer runs.
      #
      #     git-hooks.nix's last act is
      #       git config --local core.hooksPath "$common_dir/hooks"
      #     with $common_dir stripped of the working copy prefix. Run
      #     from the main checkout that stores the RELATIVE `.git/hooks`
      #     -- and in a linked worktree `.git` is a file, so that names
      #     nothing, git finds no hooks, and every commit in every
      #     worktree of the clone goes through UNLINTED in silence.
      #     Demonstrated, not deduced: a deliberately misformatted .nix
      #     file committed clean in a fresh worktree.
      #
      #     Which of the two broken states a clone is in depends only on
      #     whether install-hooks last ran from the main checkout
      #     (silently unlinted) or from a worktree (every commit
      #     refused). Neither is acceptable, and unsetting fixes both:
      #     git resolves hooks against the common dir on its own.
      #     Anchored to the start of a line on purpose. The first cut of
      #     this guard was a plain -F for the command text, and deleting
      #     the actual `git config` call did not fail it: the same
      #     string survives in the "Fix with: ..." advice this script
      #     prints when the unset fails. A guard a COMMENT can satisfy
      #     is not a guard, and this one was caught by being run against
      #     a tree with the invariant deliberately broken.
      grep -qE '^[[:space:]]*git config --local --unset-all core\.hooksPath' "$appTextPath" \
        || { echo 'GUARD: install-hooks no longer clears core.hooksPath after the git-hooks installer sets it.'; \
             echo '       A relative core.hooksPath makes linked worktrees run NO hooks and commit unlinted.'; exit 1; }

      # (g3) ... and nothing may resolve the hooks directory through
      #     core.hooksPath alone, because that call FAILS in a linked
      #     worktree while the config is still relative -- which is the
      #     state of every clone that has not re-run install-hooks yet.
      #     All three scripts need the common-dir fallback.
      for f in ${../lib/install-hooks.sh} ${../lib/link-pc-config.sh} ${../lib/dev-shell-hook.sh}; do
        grep -qF 'path-format=absolute --git-common-dir' "$f" \
          || { echo "GUARD: $f resolves the hooks directory without a common-dir fallback."; \
               echo '       `--git-path hooks` fatals in a linked worktree when core.hooksPath is relative.'; exit 1; }
      done

      # (h) ... and it must be fixed by CONFIGURING the worktree, never
      #     by making the config optional. `pre-commit install
      #     --allow-missing-config` unblocks the commit by skipping
      #     every linter, and so does the PRE_COMMIT_ALLOW_NO_CONFIG
      #     escape hatch pre-commit advertises in that error. Both
      #     convert "this worktree is misconfigured" into "this worktree
      #     is not linted", silently. A blocked commit is recoverable; a
      #     quietly unlinted one is the gate that can only pass.
      if grep -q -- '--allow-missing-config' "$appTextPath" "$installer"; then
        echo 'GUARD: the pre-commit hook is being installed with --allow-missing-config.'
        echo '       That makes a worktree without a config commit UNLINTED instead of'
        echo '       being told it is misconfigured. Give the worktree a config instead;'
        echo '       see lib/link-pc-config.sh.'
        exit 1
      fi
      touch $out
    '';
}
