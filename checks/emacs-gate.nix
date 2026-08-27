# Guard: CI must actually start Emacs, and it must start a daemon.
#
# Reads .github/workflows/ci.yml -- as parsed YAML through yq wherever it can,
# so the explanatory comments in that file are excluded for free.
#
# Inputs, passed by checks/default.nix. Nothing in this file reads flake.nix's
# scope; if it is not in this list, it is not available here.
#   pkgs -- `pkgsFor system` for the system being checked.
#
# Paths are relative to THIS file, so anything at the repo root reads `../`.
{pkgs}: {
  # CI must actually start Emacs, and it must start a DAEMON.
  #
  # `emacs --batch` does NOT load init.el at all, so a batch check
  # reports success while having loaded nothing. That is how six
  # leader keys reached master bound to void commands (PR #15) with
  # every CI job green. modules/emacs/vanilla/verify.sh starts a
  # real daemon from the store configDir and walks the actual
  # leader keymap; ci.yml runs it in the build-home job.
  #
  # This guard exists because the failure mode of a deleted gate is
  # a GREEN CI, and this repo has already been bitten by exactly
  # that shape: `build-home` carried a job-level
  # `if: github.event_name == 'push'`, so it reported "skipping" on
  # every pull request and no PR ever built the Linux closure
  # (observed on PR #14). Hence (a) as well as (b) and (c).
  ci-emacs-gate =
    pkgs.runCommand "ci-emacs-gate" {
      nativeBuildInputs = [pkgs.yq-go];
      ciWorkflow = ../.github/workflows/ci.yml;
    } ''
      # (a) build-home must not be gated off for pull requests again.
      #     Its event-dependence lives in the matrix, not in a
      #     job-level `if` (which cannot see the matrix context and so
      #     can only skip the WHOLE job, Linux build included).
      yq -e '.jobs["build-home"] | has("if") | not' "$ciWorkflow" >/dev/null \
        || { echo 'GUARD: build-home has a job-level `if` again -- that is what made it skip on every PR (#14). Gate the matrix, not the job.'; exit 1; }

      # (b) exactly one build-home step runs the Emacs gate.
      yq -e '[.jobs["build-home"].steps[] | select((.run // "") | contains("modules/emacs/vanilla/verify.sh"))] | length == 1' "$ciWorkflow" >/dev/null \
        || { echo 'GUARD: no build-home step runs modules/emacs/vanilla/verify.sh -- the only CI step that starts Emacs is gone.'; exit 1; }

      # (c) nothing in ci.yml may run Emacs in batch mode. Comments are
      #     stripped first so the explanatory ones may say the word.
      if grep -vE '^[[:space:]]*#' "$ciWorkflow" | grep -q -- '--batch'; then
        echo 'GUARD: --batch does not load init.el; the Emacs gate must start a real daemon.'
        exit 1
      fi

      touch $out
    '';
}
