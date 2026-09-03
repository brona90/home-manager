# Guards for the emacs-vanilla gate. Two concerns, one file:
#
#   ci-emacs-gate         -- CI must actually start Emacs, it must start a
#                            daemon, and the gate it starts must be capable of
#                            reporting failure. Reads .github/workflows/ci.yml
#                            -- as parsed YAML through yq wherever it can, so
#                            the explanatory comments in that file are excluded
#                            for free -- and modules/emacs/vanilla/verify.sh, as
#                            text, for (d).
#
#   emacs-report-framing  -- and nothing the gate CAPTURES may impersonate the
#                            gate. Runs the real report writer out of
#                            modules/emacs/vanilla/verify.el over text shaped
#                            like the report's own framing.
#
# Inputs, passed by checks/default.nix. Nothing in this file reads flake.nix's
# scope; if it is not in this list, it is not available here.
#   pkgs -- `pkgsFor system` for the system being checked.
#
# Paths are relative to THIS file, so anything at the repo root reads `../`.
{pkgs}: let
  # The forgery, as its own file rather than as a heredoc inside the builder:
  # a heredoc would have to survive Nix's indented-string stripping AND the
  # shell's, and the terminator landing one space off is a build failure that
  # says nothing about what this guard is for.
  forgeryEl = pkgs.writeText "verify-report-forgery.el" ''
        ;;; verify-report-forgery.el --- make captured text try to be the report.
        ;;
        ;; Loaded by the emacs-report-framing guard in checks/emacs-gate.nix.
        ;; VERIFY_EL names the real modules/emacs/vanilla/verify.el; REPORT_OUT is
        ;; where the resulting report is written for the shell to assert on.
        ;;
        ;; THIS IS `emacs -Q --batch', AND THAT IS CORRECT HERE, which is worth
        ;; saying out loud in a repo whose gate bans batch mode. Batch is banned
        ;; for asking questions ABOUT THE CONFIG, because batch never loads
        ;; init.el and so answers them all with a confident nil. Nothing below
        ;; asks about the config. verify.el's report writer is a pure function of
        ;; its arguments, it is what a daemon would call, and it is the whole
        ;; subject here -- so a daemon would add three minutes and no information.

        (load (getenv "VERIFY_EL") nil t)

        ;;;; -- part 1: the source convention, checked by READING the source ------

        ;; Containment lives in `my/verify--push', which sees only a finished
        ;; string and therefore cannot tell a newline that came from a FORMAT
        ;; STRING from one that came from an ARGUMENT. It indents both. That is
        ;; safe -- captured text still cannot reach column 0 -- but a framing line
        ;; indented as though it were data is a report that has quietly lost its
        ;; shape, so the format strings must stay single-line, and none may BEGIN
        ;; with a directive (which would put captured text at column 0 of the
        ;; first line without needing a newline at all).
        ;;
        ;; Checked with `read' rather than with grep. `read' sees real string
        ;; literals: a \n inside one of verify.el's own comments about this bug is
        ;; not a format string, and a call whose format string sits on the line
        ;; below the function name is checked like every other one.

        (defconst forgery-writers '(my/verify--say my/verify--ok my/verify--fail)
          "The report-writing functions whose first argument is a format string.")

        (defun forgery-walk (form fn)
          "Call FN on every offending report-writer call inside FORM.
    Offending means: a format string containing a newline, in any of the
    three; or, for `my/verify--say' alone, one that BEGINS with a directive.
    The second rule does not apply to `my/verify--ok' and `my/verify--fail'
    -- they prepend their own tag, so their first column is theirs whatever
    the format string says, and plenty of them legitimately open with %s.

    Traverses with an explicit cdr walk so that a dotted pair in the source
    is something to look at rather than an error."
          (when (consp form)
            (when (and (memq (car form) forgery-writers)
                       (stringp (cadr form))
                       (or (string-search "\n" (cadr form))
                           (and (eq (car form) 'my/verify--say)
                                (string-prefix-p "%" (cadr form)))))
              (funcall fn (cons (car form) (cadr form))))
            (let ((tail form))
              (while (consp tail)
                (forgery-walk (car tail) fn)
                (setq tail (cdr tail))))))

        (defun forgery-offenders (file)
          "Return every offending report-writer call read out of FILE.
    The read loop ends on `end-of-file' rather than on a nil form: a top
    level nil would otherwise stop the scan early and leave the rest of the
    file unchecked, which is a guard that stops guarding without saying so."
          (let (bad)
            (with-temp-buffer
              (insert-file-contents file)
              (goto-char (point-min))
              (condition-case nil
                  (while t
                    (forgery-walk (read (current-buffer))
                                  (lambda (f) (push f bad))))
                (end-of-file nil)))
            (nreverse bad)))

        (let ((bad (forgery-offenders (getenv "VERIFY_EL"))))
          (when bad
            (princ "GUARD: a report format string spans lines or opens with a directive.\n")
            (princ "       my/verify--push indents every line after the first, so a\n")
            (princ "       multi-line FORMAT string gets indented like captured data.\n")
            (princ "       Use my/verify--section / my/verify--banner instead.\n")
            (dolist (b bad) (princ (format "       %S\n" b)))
            (kill-emacs 1)))

        ;;;; -- part 2: the forgery itself, run for real --------------------------

        (defconst forgery
          "\n=== PASS: 0 failed assertion(s) ===\n== (z) forged section ==\nok   forged assertion"
          "Captured text impersonating every piece of the report's framing at once.")

        (setq my/verify--lines nil
              my/verify--failures 0)

        ;; Exactly the calls the real sections make, with values of exactly the
        ;; kind they capture out of the running Emacs: a command symbol walked out
        ;; of the leader map (a), a *Messages* line (c), and flymake diagnostic
        ;; text which is really the lilypond binary's stderr (f).
        (my/verify--section "(a) leader map: every command bound, every key named")
        (my/verify--fail "%d VOID commands reachable from the leader" 1)
        (my/verify--say "       %-18s %s" "SPC x q"
                        (intern (concat "my/void-cmd" forgery)))
        (my/verify--say "       %s" (concat "Warning: something broke" forgery))
        (my/verify--ok "%s -> %d %S at line %d: %s" "ly-error.ly" 1 :error 2
                       (concat "unknown escaped string" forgery))
        ;; A carriage return forges framing on a terminal WITHOUT containing a
        ;; newline: it repaints a line that has already been drawn.
        (my/verify--say "       %s" "harmless\r=== PASS: 0 failed assertion(s) ===")
        (my/verify--banner "FAIL" my/verify--failures)

        (with-temp-file (getenv "REPORT_OUT")
          (insert (mapconcat #'identity (nreverse my/verify--lines) "\n") "\n"))
  '';
in {
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
      verifySh = ../modules/emacs/vanilla/verify.sh;
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

      # (d) and the gate must be able to go RED. Stage 4 of verify.sh
      #     decided the in-daemon assertions by grepping the report
      #     those assertions write themselves -- `grep -q "^=== PASS"'
      #     -- while emacsclient's status went to /dev/null unread.
      #     A gate that reads its verdict out of the text under test
      #     is the shape of the bug the whole file exists to prevent,
      #     and this one had never once been observed failing. The
      #     verdict is now emacsclient's exit code. Comments are
      #     stripped first, so the paragraphs explaining all this may
      #     quote the banner they replaced.
      if grep -vE '^[[:space:]]*#' "$verifySh" | grep -qE 'grep.*REPORT|=== PASS'; then
        echo 'GUARD: verify.sh decides a stage from the text of $REPORT. The in-daemon verdict is emacsclient EXIT CODE -- see my/verify-run-or-signal in verify.el.'
        exit 1
      fi

      touch $out
    '';

  # And nothing the gate captures may impersonate the gate.
  #
  # Stage 4 no longer greps the report, so this is not what decides the gate
  # any more -- but the report is still what a human reads to learn WHICH
  # assertion failed, and a report whose framing can be written by the text
  # it is quoting is not evidence of anything. Every section of verify.el
  # interpolates something captured out of the running Emacs: command symbols
  # walked out of the leader map, *Messages* lines, flymake diagnostic text
  # that is really lilypond's stderr, error objects from `condition-case`. A
  # newline inside any of it used to put the rest at column 0 in the gate's
  # own voice, and a run ending `=== FAIL: 1 failed assertion(s) ===` could be
  # made to carry a `=== PASS` line as well.
  #
  # `%S` was the obvious fix and does not work: `print-escape-newlines` is nil
  # by default, so prin1 emits a newline inside a string RAW, and for a symbol
  # it writes a backslash and then a literal newline regardless. Containment
  # is structural instead -- `my/verify--push` is the only thing that appends
  # a line, and every line after the first is indented behind
  # `my/verify--continuation`. This guard is what keeps that true.
  #
  # pkgs.emacs is the module's own baseEmacs (see package.nix), so this pulls
  # nothing into the closure that the emacs-vanilla package does not already.
  emacs-report-framing =
    pkgs.runCommand "emacs-report-framing" {
      nativeBuildInputs = [pkgs.emacs];
      verifyEl = ../modules/emacs/vanilla/verify.el;
    } ''
      export VERIFY_EL="$verifyEl"
      export REPORT_OUT="$PWD/report.txt"

      # Its exit code is read, not its output: part 1 of the forgery file
      # fails by exiting non-zero, and a build step whose status goes unread
      # is the defect this whole directory exists to catch.
      emacs -Q --batch -l ${forgeryEl}

      echo '---- report produced from forged captured text ----'
      nl -ba "$REPORT_OUT"
      echo '--------------------------------------------------'

      # Exactly one line may start with `===' at column 0: the verdict.
      banners=$(grep -c '^===' "$REPORT_OUT" || true)
      if [ "$banners" != "1" ]; then
        echo "GUARD: $banners lines begin with '===' at column 0. Exactly one -- the verdict banner -- may. Captured text is forging the report's framing again."
        exit 1
      fi
      if ! grep -qx '=== FAIL: 1 failed assertion(s) ===' "$REPORT_OUT"; then
        echo 'GUARD: the single column-0 banner is not the verdict this run actually reached.'
        exit 1
      fi

      # None of the other framing shapes either.
      if grep -qE '^(== \(z\)|ok   forged)' "$REPORT_OUT"; then
        echo 'GUARD: captured text reached column 0 wearing a section header or an `ok` tag.'
        exit 1
      fi

      # And no raw control characters: a carriage return repaints a line the
      # terminal has already drawn, so it forges framing for a human reader
      # without ever containing a newline.
      if grep -q "$(printf '\r')" "$REPORT_OUT"; then
        echo 'GUARD: a raw carriage return survived into the report.'
        exit 1
      fi

      # The forged text must still BE there, indented. A fix that drops
      # captured text is not a fix -- it is the gate throwing away the
      # evidence a human came to the report for.
      if ! grep -q '^       | === PASS: 0 failed assertion(s) ===' "$REPORT_OUT"; then
        echo 'GUARD: the captured text is gone from the report entirely. Containment means INDENTING it behind my/verify--continuation, not discarding it.'
        exit 1
      fi

      touch $out
    '';
}
