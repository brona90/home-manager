# Guard: the linters this repo gates on must come from THIS flake, not from the
# flake registry of whichever machine happens to run the command.
#
# Not to be confused with lib/lint-tools.nix, which BUILDS the bundle
# (packages.<system>.lint-tools). This file only guards how it is resolved.
#
# Reads .github/workflows/ci.yml and modules/emacs/vanilla/verify.sh.
#
# Inputs, passed by checks/default.nix. Nothing in this file reads flake.nix's
# scope; if it is not in this list, it is not available here.
#   pkgs -- `pkgsFor system` for the system being checked.
#
# Paths are relative to THIS file, so anything at the repo root reads `../`.
{pkgs}: {
  # The linters must keep coming from this flake, not from the
  # runner's flake registry.
  #
  # `nix run nixpkgs#<tool>` resolves through the REGISTRY, which
  # is a property of the machine running the command and not of
  # this repo. verify.sh and ci.yml each did that, so the two ran
  # whatever versions they each resolved. PR #21 went red on
  # exactly that: shellcheck renumbered one finding (SC2329 in
  # 0.11, SC2317 in earlier releases), the file suppressed only
  # the newer code, it passed locally on 0.11.0 and failed CI on
  # an older one. Both now resolve packages.<system>.lint-tools.
  #
  # Guarded because the failure mode is invisible until the day
  # the two versions happen to disagree, which is to say: on
  # somebody else's pull request.
  lint-tools-pinned =
    pkgs.runCommand "lint-tools-pinned" {
      nativeBuildInputs = [pkgs.yq-go];
      ciWorkflow = ../.github/workflows/ci.yml;
      verifySh = ../modules/emacs/vanilla/verify.sh;
    } ''
      # (a) no step of the lint job may resolve a tool from the
      #     registry. yq reads the parsed YAML, so the explanatory
      #     comments in ci.yml are excluded for free.
      yq -e '[.jobs.lint.steps[] | select((.run // "") | contains("nixpkgs#"))] | length == 0' "$ciWorkflow" >/dev/null \
        || { echo 'GUARD: a ci.yml lint step resolves a tool through nixpkgs# -- that is the runner registry, not this flake. Use .#lint-tools.'; exit 1; }

      # (b) nor may the emacs gate. Comments are stripped first so
      #     the paragraph explaining all this may name the thing.
      if grep -vE '^[[:space:]]*#' "$verifySh" | grep -q 'nixpkgs#'; then
        echo 'GUARD: verify.sh resolves a linter through nixpkgs# -- that is the runner registry, not this flake. Use $REPO#lint-tools.'
        exit 1
      fi

      # (c) and it must not reach for --impure again. This was the
      #     only --impure in the repo (`nix eval --impure --expr
      #     builtins.currentSystem`); `nix config show system`
      #     answers the same question from nix's settings. Kept in
      #     this guard rather than a new one because it is the same
      #     file and the same claim: what this gate runs is a
      #     function of the flake, not of the machine.
      if grep -vE '^[[:space:]]*#' "$verifySh" | grep -q -- '--impure'; then
        echo 'GUARD: verify.sh uses --impure. For the system double use `nix config show system`.'
        exit 1
      fi

      touch $out
    '';
}
