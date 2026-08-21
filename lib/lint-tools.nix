# lint-tools -- every linter this repo gates on, out of THIS flake's nixpkgs.
#
# WHY IT EXISTS: modules/emacs/vanilla/verify.sh used to resolve each linter
# from PATH first and fall back to `nix run nixpkgs#<tool>`. That fallback
# resolves through the RUNNER's flake registry, not through this flake's
# pinned nixpkgs input, so the same gate ran different tool versions locally
# and in CI. .github/workflows/ci.yml's lint job installed a third set the
# same way.
#
# It has already cost a red CI. On PR #21 shellcheck renumbered one finding --
# SC2329 ("this function is never invoked") in 0.11, SC2317 ("command appears
# to be unreachable") in earlier releases. verify.sh suppressed only SC2329,
# passed locally on 0.11.0 out of the profile, and failed CI on an older one
# out of the registry. Naming both codes fixed that instance; naming one
# derivation fixes the class.
#
# Both consumers now resolve THIS package, so the versions agree by
# construction rather than by both machines happening to have the same tool
# installed. The pre-commit hooks were already consistent with it: the
# git-hooks input follows nixpkgs, so its statix/deadnix/alejandra/shellcheck
# come from the same lock.
#
# actionlint is included even though verify.sh does not run it: ci.yml does,
# through the identical registry fallback, and leaving one tool unpinned
# leaves the class open.
#
# CAVEAT, x86_64-darwin: pkgsFor serves that platform from the pinned
# nixpkgs-26.05-darwin input, because 26.11 deleted the platform outright. An
# Intel Mac therefore gets 26.05 linter versions while every other platform
# gets the channel. That divergence is forced by the pin rather than chosen
# here, it does not touch the local-vs-CI pair this exists to fix (both
# x86_64-linux), and it expires with the pin -- see the nixpkgs-darwin-intel
# input in flake.nix.
{
  symlinkJoin,
  actionlint,
  alejandra,
  deadnix,
  shellcheck,
  statix,
}:
symlinkJoin {
  name = "lint-tools";
  paths = [actionlint alejandra deadnix shellcheck statix];
  meta.description = "Linters pinned to this flake's nixpkgs, shared by verify.sh and CI";
}
