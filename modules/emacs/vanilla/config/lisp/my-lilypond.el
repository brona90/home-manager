;;; my-lilypond.el --- LilyPond: mode, flymake, build-on-save -*- lexical-binding: t; -*-

;;; Commentary:

;; Ported from the FIXED doom.d/config.el (PR #17), not from the version that
;; had been quietly dead for two years.  Four facts decide almost every line
;; here, and each of them was measured against the installed lilypond
;; (2.26.0, from the Nix profile) rather than recalled:
;;
;;   1. LILYPOND 2.26 RENAMED EVERY SYMBOL TO LOWERCASE.  The header of
;;      lilypond-mode.el says so in as many words: "Changed 2024 Yiyu Zhou ...
;;      Change all prefixes to lowercase to follow the Elisp convention".  The
;;      major mode is `lilypond-mode'.  `LilyPond-mode' -- the name the Doom
;;      config hardcoded -- does not exist here.  Nothing announced that:
;;      `auto-mode-alist' pointed at a void function, the checker was defined
;;      `:modes' a mode that never activated, and the build-on-save hook was
;;      added to a hook that never ran.  All three were silently dead.
;;
;;      A machine may still have 2.24, so the mode is reached through a SHIM
;;      that dispatches on whichever casing the loaded file defines.  darwin is
;;      the realistic case: home/common.nix skips the nix lilypond there and
;;      Homebrew's version moves on its own schedule.
;;
;;   2. THE ELISP SHIPS INSIDE THE LILYPOND DERIVATION, at
;;      share/emacs/site-lisp/.  It is not an `emacsPackages' attribute and it
;;      is not on MELPA, so package.nix cannot add it the way it adds magit.
;;      The store path arrives as `my/nix-lilypond-site-lisp' (see
;;      lisp/my-nix-paths.el, generated) and is put on `load-path' below.
;;
;;   3. lilypond-mode.el CARRIES NO AUTOLOAD COOKIE.  Verified: `grep -r
;;      ";;;###autoload"' over the whole site-lisp directory returns nothing.
;;      Upstream's own lilypond-init.el supplies the autoload and the
;;      `auto-mode-alist' entries, and it is meant to be dropped into
;;      site-start.d -- which nothing here does.  Without an explicit autoload,
;;      `set-auto-mode' finds an unbound symbol, prints "Ignoring unknown mode"
;;      and leaves the buffer in `fundamental-mode'.
;;
;;   4. THE COLUMN IS OPTIONAL ON WARNINGS.  Measured output from 2.26.0:
;;
;;        file.ly:1: warning: no \version statement found, please add
;;        file.ly:2:11: error: unknown command: `\nosuchcommand'
;;        fatal error: failed files: "file.ly"
;;
;;      A pattern that requires a column drops EVERY warning on the floor.  The
;;      diagnostics are also multi-line -- the message continues onto following
;;      lines and errors are followed by a two-line source excerpt -- so only
;;      the first line is matched.
;;
;; WHAT CHANGED FROM DOOM, beyond the casing:
;;
;;   * flycheck -> flymake.  There is no flycheck in this package set and
;;     flymake is built in.  See `my/lilypond-flymake'.
;;   * `:group 'lilypond' -> `:group 'my-lilypond'.  There is no `lilypond'
;;     customisation group: lilypond's elisp contains no `defgroup' at all
;;     (verified), so Doom's `:group' was inventing a phantom group.
;;   * The failure buffer gets an explicit `display-buffer-alist' entry.  Doom's
;;     popup manager was displaying it; vanilla has no popup manager.
;;
;; ONE DELIBERATE BEHAVIOURAL DIFFERENCE, and it is the "is this wasteful"
;; question asked out loud: running lilypond on BOTH flymake and build-on-save
;; means TWO lilypond processes per save.  In Doom that is what happened,
;; because Doom's `:checkers syntax' module turns flycheck on globally.  Here
;; flymake is NOT turned on globally -- init.el declares it `:commands' only,
;; and the sole thing that enables it automatically is eglot, which never
;; manages a .ly buffer.  So the default in this config is ONE lilypond per
;; save: the build, which is the run that produces the PDF the user is looking
;; at, and whose failure buffer carries lilypond's own error text anyway.
;;
;; The flymake BACKEND is still registered on every LilyPond buffer, so `SPC t
;; f' turns inline diagnostics on for anyone who wants them and accepts the
;; second process.  Registering a backend costs nothing when `flymake-mode' is
;; off: `flymake-diagnostic-functions' is only consulted by a running flymake.
;; That is the trade -- cheap by default, available on request -- rather than
;; deleting one of the two.

;;; Code:

(require 'use-package)
(require 'seq)

;;;; ---------------------------------------------------------------------
;;;; Finding lilypond
;;;; ---------------------------------------------------------------------

(defun my/lilypond--probe-site-lisp ()
  "Find lilypond's elisp beside the `lilypond' on `exec-path', or nil.
Only reached where package.nix left `my/nix-lilypond-site-lisp' nil -- in
practice darwin, where lilypond comes from Homebrew.

Ported from doom.d/config.el, with one fix: the binary is resolved through
`file-truename' first.  Homebrew's /opt/homebrew/bin/lilypond is a SYMLINK
into ../Cellar/lilypond/<version>/bin/, so without the truename the
\"../share\" probes resolve against /opt/homebrew and find nothing.

The version-numbered directory is GLOBBED rather than named.  The Doom
original named \"2.24.4\" explicitly and had therefore been matching nothing
for as long as 2.26 had been installed."
  (when-let* ((bin (executable-find "lilypond")))
    (let ((dir (file-name-directory (file-truename bin))))
      (seq-find #'file-directory-p
                (append (list (expand-file-name "../share/emacs/site-lisp" dir)
                              (expand-file-name "../share/lilypond/current/elisp" dir))
                        (file-expand-wildcards
                         (expand-file-name "../share/lilypond/*/elisp" dir)))))))

(defconst my/lilypond-site-lisp
  (or (bound-and-true-p my/nix-lilypond-site-lisp)
      (my/lilypond--probe-site-lisp))
  "Directory holding lilypond-mode.el, or nil if none was found.
`bound-and-true-p' rather than a plain reference because lisp/my-nix-paths.el
is GENERATED, and `my.emacs.vanilla.manageConfig = false' hands
~/.config/emacs to a working copy that does not contain it.")

(defconst my/lilypond-executable
  (or (bound-and-true-p my/nix-lilypond-executable)
      (executable-find "lilypond"))
  "Absolute path to the `lilypond' binary, or nil.
Resolved once, from Nix where Nix provides it, so that a build and a flymake
run cannot disagree about which lilypond they mean.")

(when my/lilypond-site-lisp
  (add-to-list 'load-path my/lilypond-site-lisp))

;;;; ---------------------------------------------------------------------
;;;; The mode
;;;; ---------------------------------------------------------------------

(defun my/lilypond-mode ()
  "Load lilypond-mode.el, then hand off to whichever casing it defines.
2.26+ defines `lilypond-mode'; 2.24 and earlier define `LilyPond-mode'.

Resolved at CALL time rather than at config time on purpose: the two Macs may
be on a different lilypond from the Linux hosts, and this file has to be
correct on all of them without a per-host branch.

When lilypond is absent entirely the buffer is left in `fundamental-mode' with
a message saying so -- deliberately not an error, because opening a .ly file
on a machine without lilypond is a reasonable thing to do."
  (interactive)
  (if (not (require 'lilypond-mode nil t))
      (message "LilyPond: lilypond-mode.el is not on load-path; leaving %s in fundamental-mode"
               (buffer-name))
    (cond ((fboundp 'lilypond-mode) (lilypond-mode))   ; 2.26+
          ((fboundp 'LilyPond-mode) (LilyPond-mode))   ; 2.24 and earlier
          (t (message "LilyPond: lilypond-mode.el defines neither `lilypond-mode' nor `LilyPond-mode'")))))

;; Same shape as the AUCTeX shim in my-lang.el, and for a related reason: the
;; symbol that `auto-mode-alist' names must be one WE control.  `:commands'
;; still emits (autoload 'lilypond-mode "lilypond-mode"), which is the correct
;; file for that symbol and is what makes `M-x lilypond-mode' work.
;;
;; NOTE for .dir-locals.el: the major mode really is `lilypond-mode' (the shim
;; hands off to it), so
;;   ((lilypond-mode . ((my/lilypond-extra-args . ("--include" "/path")))))
;; matches.  A file written against `LilyPond-mode' never will.
(use-package lilypond-mode
  :mode (("\\.ly\\'" . my/lilypond-mode)
         ("\\.ily\\'" . my/lilypond-mode))
  :commands (lilypond-mode))

;;;; ---------------------------------------------------------------------
;;;; Diagnostics
;;;; ---------------------------------------------------------------------

(defgroup my-lilypond nil
  "LilyPond integration for this config."
  :group 'tools
  :prefix "my/lilypond-")

(defcustom my/lilypond-extra-args nil
  "Extra arguments passed to `lilypond' by the build and the flymake backend.
Project-specific flags (e.g. --include for custom fonts) belong in a
per-directory .dir-locals.el:

  ((lilypond-mode . ((my/lilypond-extra-args . (\"--include\" \"/path\")))))"
  :type '(repeat string)
  :group 'my-lilypond
  :safe #'listp)

;; Two capture groups are optional-aware on purpose; see fact 4 in the
;; commentary.  The FILE part is filled in per run with the temp file's own
;; path, so an error reported in an \include'd file -- which carries a
;; different filename -- does not get attributed to the wrong buffer.
(defconst my/lilypond--diagnostic-format
  "^%s:\\([0-9]+\\):\\(?:\\([0-9]+\\):\\)? \\(warning\\|error\\): \\(.*\\)$"
  "Format string for the per-file diagnostic regexp.
%s is replaced with the `regexp-quote'd path lilypond was asked to compile.")

(defvar-local my/lilypond--flymake-proc nil
  "The lilypond process serving this buffer's most recent flymake run.")

(declare-function flymake-make-diagnostic "flymake")
(declare-function flymake-diag-region "flymake")
(declare-function flymake-log "flymake")

(defun my/lilypond--collect (source re)
  "Collect flymake diagnostics for SOURCE from the current buffer using RE.
The current buffer is the process output buffer."
  (let (diags)
    (goto-char (point-min))
    (while (re-search-forward re nil t)
      (let* ((line (string-to-number (match-string 1)))
             (col (and (match-string 2) (string-to-number (match-string 2))))
             (type (if (equal (match-string 3) "error") :error :warning))
             (text (match-string 4))
             (region (flymake-diag-region source line col)))
        (when region
          (push (flymake-make-diagnostic source (car region) (cdr region)
                                         type text)
                diags))))
    ;; `fatal error:' lines carry no file or line, so they are pinned to line
    ;; 1.  The one exception is the "failed files:" summary, which 2.26 emits
    ;; once per failing run in ADDITION to the per-line errors above -- it is
    ;; pure duplication and reporting it would put a red squiggle on line 1 of
    ;; every file that has an error anywhere.
    (goto-char (point-min))
    (while (re-search-forward "^fatal error: \\(.*\\)$" nil t)
      (let ((text (match-string 1)))
        (unless (string-prefix-p "failed files:" text)
          (when-let* ((region (flymake-diag-region source 1)))
            (push (flymake-make-diagnostic source (car region) (cdr region)
                                           :error text)
                  diags)))))
    (nreverse diags)))

(defun my/lilypond-flymake (report-fn &rest _ignored)
  "A `flymake' backend for LilyPond.
Runs `lilypond' over a temporary copy of the buffer and calls REPORT-FN with
the diagnostics it printed."
  (require 'flymake)
  (if (null my/lilypond-executable)
      ;; :panic rather than an empty list.  An empty list claims the file is
      ;; clean; :panic tells flymake this backend cannot answer and stops it
      ;; retrying a program that is not installed.
      (funcall report-fn :panic :explanation "no lilypond on exec-path")
    ;; A still-running process is answering a question about text that no
    ;; longer exists.  Kill it BEFORE starting the replacement.
    (when (process-live-p my/lilypond--flymake-proc)
      (kill-process my/lilypond--flymake-proc))
    (let* ((source (current-buffer))
           ;; THE TEMP FILE BREAKS RELATIVE \include.  Measured: a copy of a
           ;; file that does `\include "inc.ily"', compiled from /tmp, fails
           ;; with `cannot find file: `inc.ily'' and then cascades into
           ;; unknown-command errors for everything the include defined --
           ;; i.e. the backend would invent a screenful of errors that are not
           ;; in the user's file.  `-I <source dir>' fixes it, and is preferred
           ;; over writing the temp file into the source directory, which would
           ;; litter the user's tree and trip the after-save build watcher.
           (src-dir (expand-file-name
                     (if buffer-file-name
                         (file-name-directory buffer-file-name)
                       default-directory)))
           (tmp (make-temp-file "flymake-lilypond-" nil ".ly"))
           ;; -dno-print-pages suppresses the PDF, but lilypond still wants an
           ;; -o; give it a temp basename so nothing lands next to the source.
           (out (make-temp-name
                 (expand-file-name "flymake-lilypond-out-" temporary-file-directory)))
           (re (format my/lilypond--diagnostic-format (regexp-quote tmp))))
      (save-restriction
        (widen)
        (write-region nil nil tmp nil 'silent))
      (setq my/lilypond--flymake-proc
            (make-process
             :name "lilypond-flymake"
             :noquery t
             :connection-type 'pipe
             :buffer (generate-new-buffer " *lilypond-flymake*")
             :command (append (list my/lilypond-executable
                                    "-dno-print-pages" "-I" src-dir)
                              my/lilypond-extra-args
                              (list "-o" out tmp))
             :sentinel
             (lambda (proc _event)
               (when (memq (process-status proc) '(exit signal))
                 (unwind-protect
                     ;; BAIL UNLESS THIS PROCESS IS STILL THE CURRENT ONE.
                     ;; Without the guard an obsoleted run reports its stale
                     ;; diagnostics over the top of a newer one's.
                     (if (with-current-buffer source
                           (eq proc my/lilypond--flymake-proc))
                         (with-current-buffer (process-buffer proc)
                           (funcall report-fn (my/lilypond--collect source re)))
                       (flymake-log :debug "obsolete lilypond process %s" proc))
                   (ignore-errors (delete-file tmp))
                   (kill-buffer (process-buffer proc))))))))))

;;;; ---------------------------------------------------------------------
;;;; Build on save
;;;; ---------------------------------------------------------------------
;;
;; Ported from doom.d/config.el.  Every function it uses is built in, so the
;; only changes are the resolved executable and the mode-name casing (which is
;; handled by `my/lilypond-setup' below rather than in here).
;;
;; The exit status IS load-bearing and it IS trustworthy: measured on 2.26.0,
;; a clean file and a warning-only file both exit 0, and a file with an error
;; exits 1.  (Measure it with a real shell, not through a layer that eats `$?'.)

(defvar my/lilypond--processes (make-hash-table :test 'equal)
  "Hash of source-path -> running lilypond process.")

(defun my/lilypond--refresh-pdfs (dir base)
  "Revert open PDF buffers under DIR whose filename starts with BASE.
Matches `<base>.pdf', `<base>-C.pdf', `<base>-Bb.pdf', etc.

NOTE: pdf-tools is NOT in this package set, so a .pdf buffer here is
`doc-view-mode', not `pdf-view-mode'.  `revert-buffer' still re-renders it;
what is lost relative to Doom is pdf-view's scroll-position preservation, so
the view jumps back to page one on every rebuild.  Adding pdf-tools is a line
in package.nix and a poppler in the closure -- a deliberate decision, not an
oversight, and not made here."
  (dolist (buf (buffer-list))
    (with-current-buffer buf
      (when (and buffer-file-name
                 (string-match-p "\\.pdf\\'" buffer-file-name)
                 (file-in-directory-p buffer-file-name dir)
                 (string-prefix-p base
                                  (file-name-nondirectory buffer-file-name)))
        (ignore-errors (revert-buffer t t t))))))

(defun my/lilypond-build-on-save ()
  "Asynchronously rebuild the just-saved .ly file.
Then refresh any open PDF buffers it produces."
  (when (and buffer-file-name
             my/lilypond-executable
             (string-match-p "\\.ly\\'" buffer-file-name))
    (let* ((src buffer-file-name)
           (dir (file-name-directory src))
           (base (file-name-base src))
           (buf (get-buffer-create (format " *lilypond: %s*" base)))
           (old (gethash src my/lilypond--processes))
           (default-directory dir))
      (when (and old (process-live-p old))
        (ignore-errors (kill-process old)))
      (with-current-buffer buf
        (let ((inhibit-read-only t)) (erase-buffer)))
      (let ((proc (apply #'start-process
                         (format "lilypond-%s" base)
                         buf my/lilypond-executable
                         (append my/lilypond-extra-args
                                 (list "-o" base src)))))
        (puthash src proc my/lilypond--processes)
        (set-process-query-on-exit-flag proc nil)
        (message "LilyPond: building %s..." (file-name-nondirectory src))
        (set-process-sentinel
         proc
         (lambda (p _event)
           (when (memq (process-status p) '(exit signal))
             (remhash src my/lilypond--processes)
             (if (zerop (process-exit-status p))
                 (progn
                   (message "LilyPond: %s built"
                            (file-name-nondirectory src))
                   (my/lilypond--refresh-pdfs dir base))
               (message "LilyPond: %s did not build -- see %s"
                        (file-name-nondirectory src) (buffer-name buf))
               (display-buffer buf)))))))))

;; Doom's popup manager put that failure buffer on screen; vanilla has no popup
;; manager, so the rule is written out.  Bottom, a third of the frame, and NOT
;; selected -- point stays in the source file so the next keystroke edits the
;; music rather than scrolling a log.
;;
;; The leading space in the regexp is not a typo: the buffer is named
;; " *lilypond: BASE*", and a leading space is what keeps it out of the buffer
;; list.  `display-buffer' shows such a buffer perfectly well.
(add-to-list 'display-buffer-alist
             '("^ \\*lilypond: "
               (display-buffer-reuse-window display-buffer-at-bottom)
               (window-height . 0.3)
               (post-command-select-window . nil)))

;;;; ---------------------------------------------------------------------
;;;; Wiring
;;;; ---------------------------------------------------------------------

(defun my/lilypond-setup ()
  "Wire the flymake backend and build-on-save into this LilyPond buffer."
  ;; `require' rather than trusting the autoload: `flymake-diagnostic-functions'
  ;; must be `defvar'ed before `add-hook' gives it a buffer-local value, or the
  ;; later defvar and the local binding argue about which is which.
  (require 'flymake)
  ;; REGISTERED, NOT ENABLED -- see the trade in the commentary.  The backend
  ;; runs only while `flymake-mode' is on, which is `SPC t f'.
  (add-hook 'flymake-diagnostic-functions #'my/lilypond-flymake nil t)
  (add-hook 'after-save-hook #'my/lilypond-build-on-save nil t))

;; BOTH casings.  On 2.26 only `lilypond-mode-hook' ever runs and the other is
;; an unused variable; on a 2.24 Homebrew Mac it is the other way round.  Two
;; `add-hook' calls is the whole cost of not caring which one is installed.
(add-hook 'lilypond-mode-hook #'my/lilypond-setup)
(add-hook 'LilyPond-mode-hook #'my/lilypond-setup)

(provide 'my-lilypond)
;;; my-lilypond.el ends here
