;;; verify.el --- the emacs-vanilla gate, run inside a real daemon -*- lexical-binding: t; -*-

;;; Commentary:

;; Loaded by ../verify.sh into a DAEMON started from the store config directory.
;; It is not part of the config: it lives beside `config/', not inside it, so it
;; never reaches the store and never loads in a real session.
;;
;; WHY A DAEMON AND NOT `emacs --batch'.  Batch does not load init.el at all, so
;; a batch check answers a question nobody asked.  Worse, batch has no frame,
;; and several things this config gets wrong-by-default are frame-dependent.
;; Every claim below is measured in the same kind of process the user gets.
;;
;; THE RULE THIS FILE EXISTS FOR: a check that can only report PASS is not a
;; check.  So nothing here greps for good news.  Every assertion has an expected
;; value written down next to it, `my/verify--fail' is what decides the exit
;; status, and the language table below is a table of EXPECTATIONS -- if a mode
;; silently changes, the gate goes red rather than printing a different answer.
;;
;; "Decides the exit status" is meant literally, and only became literal once:
;; `my/verify-run-or-signal' at the foot of this file SIGNALS when the failure
;; count is non-zero, and verify.sh's stage 4 reads that as emacsclient's exit
;; code.  Before that it read the report's own "=== PASS" banner back out of
;; the file these checks write -- the one stage in the gate that grepped for
;; good news was the stage the gate exists for.
;;
;; It walks the ACTUAL leader keymap rather than a hand-written list of
;; commands.  That distinction is the whole point: a hand-written list is how
;; six void commands got shipped once already.  The keymap is the thing the
;; user's fingers hit.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)  ; string-remove-suffix

(defvar my/verify--lines nil "Report lines, in order.")
(defvar my/verify--failures 0 "Number of failed assertions.")

(defun my/verify--say (fmt &rest args)
  (push (apply #'format fmt args) my/verify--lines))

(defun my/verify--fail (fmt &rest args)
  (cl-incf my/verify--failures)
  (push (concat "FAIL: " (apply #'format fmt args)) my/verify--lines))

(defun my/verify--ok (fmt &rest args)
  (push (concat "ok   " (apply #'format fmt args)) my/verify--lines))


;;;; ---------------------------------------------------------------------
;;;; (a) Every leader command is fboundp, and every leader key is named
;;;; ---------------------------------------------------------------------

(defun my/verify--walk-keymap (map prefix acc)
  "Collect (KEY-DESCRIPTION COMMAND LABEL) triples from MAP under PREFIX into ACC.
LABEL is the inline name from a (STRING . DEFN) keymap element, or nil."
  (map-keymap
   (lambda (event def)
     (let ((keys (append prefix (list event)))
           (label nil))
       ;; `which-key-add-keymap-based-replacements' rewrites entries to the
       ;; documented (STRING . DEFN) keymap element.  Strip the label the same
       ;; way which-key itself does -- but KEEP it: it is one of the two ways a
       ;; key gets a name here, and throwing it away is what made the first
       ;; version of this check report 298 named keys as unnamed.
       (when (and (consp def) (stringp (car def)))
         (setq label (car def)
               def (cdr def)))
       (cond
        ((keymapp def) (my/verify--walk-keymap def keys acc))
        ((and def (symbolp def) (not (eq def 'ignore)))
         (push (list (key-description (vconcat keys)) def label) (car acc))))))
   map)
  acc)

;; `SPC h', `SPC p' and `SPC w' hand off to `help-map', `project-prefix-map' and
;; `evil-window-map' wholesale.  my-bindings.el names a CURATED SUBSET of each
;; through `which-key-add-keymap-based-replacements'; naming all ~130 entries of
;; Emacs's own help-map was never the criterion and never will be.  So keys
;; under these three prefixes are COUNTED and REPORTED but do not fail the gate,
;; and every other leader key must be named.  Getting this distinction wrong in
;; either direction gives a number that looks authoritative and is not.
(defconst my/verify-borrowed-prefixes '("SPC h " "SPC p " "SPC w ")
  "Leader prefixes that hand off to a whole pre-existing keymap.")

(defun my/verify--borrowed-p (key)
  (seq-some (lambda (pfx) (string-prefix-p pfx key)) my/verify-borrowed-prefixes))

(defun my/verify--named-p (key cmd label)
  "Non-nil if KEY renders as a human name rather than as the symbol CMD.
LABEL is an inline keymap label, which is name enough on its own."
  (or (and label (stringp label))
      ;; `which-key--maybe-replace' ALWAYS returns a cons, so testing it for nil
      ;; would be a check that can only pass; the question is whether the
      ;; description came back CHANGED.  And it matches on the FULL key
      ;; description: general registered "SPC m G f", while walking the map
      ;; bound to SPC yields "m G f".  Pass the bare key and all 738 come back
      ;; unreplaced -- a precise, confident, entirely wrong answer.
      (let* ((raw (cons key (symbol-name cmd)))
             (rep (ignore-errors (which-key--maybe-replace raw))))
        (and rep (not (equal (cdr rep) (cdr raw)))))))

(defun my/verify-leader ()
  "Assert every command reachable from the SPC leader map is `fboundp' and named."
  (my/verify--say "\n== (a) leader map: every command bound, every key named ==")
  ;; Evil normal state, in a real buffer: the leader is an evil INTERCEPT map
  ;; and `key-binding' does not see it from whatever state the daemon is in.
  (with-temp-buffer
    (evil-normal-state)
    (let ((leader (key-binding (kbd "SPC"))))
      (if (not (keymapp leader))
          (my/verify--fail "SPC does not resolve to a keymap (got %S)" leader)
        (let* ((acc (my/verify--walk-keymap leader nil (list nil)))
               ;; The walk starts INSIDE the map bound to SPC, so the keys come
               ;; back without their leading "SPC ".  Every consumer below wants
               ;; the full description.
               (entries (mapcar (lambda (e)
                                  (cons (concat "SPC " (car e)) (cdr e)))
                                (car acc)))
               (void (cl-remove-if (lambda (e) (fboundp (nth 1 e))) entries))
               (ours (cl-remove-if (lambda (e) (my/verify--borrowed-p (car e)))
                                   entries))
               (borrowed (cl-remove-if-not
                          (lambda (e) (my/verify--borrowed-p (car e))) entries))
               (unnamed (cl-remove-if
                         (lambda (e) (apply #'my/verify--named-p e)) ours))
               (unnamed-borrowed
                (cl-remove-if (lambda (e) (apply #'my/verify--named-p e)) borrowed)))
          (my/verify--say "     reachable leader commands: %d (%d ours, %d borrowed)"
                          (length entries) (length ours) (length borrowed))
          (if (null void)
              (my/verify--ok "0 void commands")
            (my/verify--fail "%d VOID commands reachable from the leader"
                             (length void))
            (dolist (v void)
              (my/verify--say "       %-18s %s" (car v) (nth 1 v))))
          (if (null unnamed)
              (my/verify--ok "all %d non-borrowed leader keys carry a name"
                             (length ours))
            (my/verify--fail "%d leader keys render as a raw command symbol"
                             (length unnamed))
            (dolist (u (seq-take unnamed 20))
              (my/verify--say "       %-18s %s" (car u) (nth 1 u))))
          (my/verify--say
           "     borrowed maps (SPC h/p/w): %d of %d named -- unnamed ones are\n     Emacs's own help-map tail and are not a criterion"
           (- (length borrowed) (length unnamed-borrowed)) (length borrowed)))))))


;;;; ---------------------------------------------------------------------
;;;; (b) One real file per language: major mode, and does a parser exist
;;;; ---------------------------------------------------------------------

;; FILE . (ACCEPTABLE-MODES PARSER-EXPECTED LANGUAGE NOTE)
;;
;; PARSER-EXPECTED is not decoration.  Half the value of this table is the
;; entries where it is nil ON PURPOSE -- markdown, LaTeX, restclient and .zsh
;; have no tree-sitter mode in this build, and "no parser" is the CORRECT
;; answer there.  Without writing that down, a future reader adds grammars to
;; package.nix to "fix" it and grows the closure for nothing.
(defconst my/verify-language-cases
  '(("sample.sh"   (bash-ts-mode)       t   bash        "remap sh-mode -> bash-ts-mode")
    ("sample.zsh"  (sh-mode)            nil nil         "MUST hand back: zsh is not bash")
    ("sample.py"   (python-ts-mode)     t   python      "remap python-mode")
    ("sample.js"   (js-ts-mode)         t   javascript  "remap javascript-mode, NOT js-mode")
    ("sample.mjs"  (js-ts-mode)         t   javascript  "no built-in entry at all")
    ("sample.ts"   (typescript-ts-mode) t   typescript  "")
    ("sample.tsx"  (tsx-ts-mode)        t   tsx         "")
    ("sample.json" (json-ts-mode)       t   json        "remap js-json-mode, NOT json-mode")
    ("sample.toml" (toml-ts-mode)       t   toml        "remap conf-toml-mode, NOT toml-mode")
    ("sample.yaml" (yaml-ts-mode)       t   yaml        "")
    ("sample.go"   (go-ts-mode)         t   go          "")
    ("go.mod"      (go-mod-ts-mode)     t   gomod       "defaults to m2-mode (Modula-2)")
    ("sample.rs"   (rust-ts-mode)       t   rust        "")
    ("sample.lua"  (lua-ts-mode)        t   lua         "")
    ("Sample.java" (java-ts-mode)       t   java        "")
    ("sample.nix"  (nix-ts-mode)        t   nix         "packaged mode")
    ("sample.hs"   (haskell-ts-mode)    t   haskell     "packaged mode")
    ("Dockerfile"  (dockerfile-ts-mode) t   dockerfile  "")
    ("sample.md"   (markdown-mode)      nil nil         "no markdown-ts-mode exists")
    ;; AUCTeX renamed the mode between 13 and 14 and kept an alias both ways,
    ;; so BOTH symbols are acceptable -- what is asserted separately below is
    ;; that AUCTeX loaded AT ALL, which is the thing that silently fails.
    ("sample.tex"  (LaTeX-mode latex-mode) nil nil      "AUCTeX via the my/LaTeX-mode shim")
    ("sample.http" (restclient-mode)    nil nil         "")
    ;; LilyPond: the mode's elisp ships INSIDE the lilypond derivation, has no
    ;; autoload cookie anywhere in it, and 2.26 renamed the mode to lowercase.
    ;; All three are ways for a .ly file to land silently in `fundamental-mode',
    ;; which is exactly what this row catches.  There is no lilypond-ts-mode.
    ("sample.ly"   (lilypond-mode)      nil nil         "via the my/lilypond-mode shim")
    ("sample.ily"  (lilypond-mode)      nil nil         "include files get the mode too")))

(defun my/verify-languages (dir)
  "Open one sample file per language from DIR and check mode and parser."
  (my/verify--say "\n== (b) languages: major mode and tree-sitter parser ==")
  ;; eglot-ensure is NEUTERED for the duration.  It is hooked into most of
  ;; these modes, and letting it fire would start jdtls and
  ;; haskell-language-server for real -- turning a 10-second gate into minutes
  ;; and making it depend on servers being healthy, which is a different
  ;; question.  That the hooks are WIRED is asserted in section (d) instead,
  ;; which is the part this config actually decides.
  (advice-add 'eglot-ensure :override #'ignore)
  (unwind-protect
      (progn
        (my/verify--say "     %-13s %-20s %-10s %s"
                        "FILE" "MAJOR-MODE" "PARSER" "")
        (dolist (case my/verify-language-cases)
          (cl-destructuring-bind (file modes parser-expected lang note) case
            (let ((path (expand-file-name file dir)))
              (if (not (file-exists-p path))
                  (my/verify--fail "%s: sample file was never created" file)
                (with-current-buffer (find-file-noselect path)
                  (unwind-protect
                      (let* ((mode major-mode)
                             (parsers (and (fboundp 'treesit-parser-list)
                                           (treesit-parser-list)))
                             (langs (mapcar #'treesit-parser-language parsers))
                             (parser-desc
                              (if parsers
                                  (mapconcat #'symbol-name (delete-dups (copy-sequence langs)) ",")
                                "-")))
                        (my/verify--say "     %-13s %-20s %-10s %s"
                                        file mode parser-desc note)
                        (unless (memq mode modes)
                          (my/verify--fail "%s: major-mode is %s, expected one of %s"
                                           file mode modes))
                        (cond
                         ((and parser-expected (null parsers))
                          (my/verify--fail
                           "%s: no tree-sitter parser; expected `%s' (grammar missing from package.nix?)"
                           file lang))
                         ((and parser-expected (not (memq lang langs)))
                          (my/verify--fail "%s: parsers are %s, expected `%s'"
                                           file langs lang))
                         ((and (not parser-expected) parsers)
                          ;; Not fatal, but it means the table is now wrong.
                          (my/verify--fail
                           "%s: unexpected parser %s -- the expectation table says none"
                           file langs))
                         (t (my/verify--ok "%s -> %s" file mode))))
                    (kill-buffer)))))))
        ;; The AUCTeX shim: the failure mode is silent, so test the cause and
        ;; not just the symptom.  A plain `latex-mode' with `latex' not loaded
        ;; is EXACTLY what all four rejected variants produced.
        (if (featurep 'latex)
            (my/verify--ok "AUCTeX loaded (feature `latex' present)")
          (my/verify--fail
           "AUCTeX did NOT load -- .tex fell through to the built-in latex-mode")))
    (advice-remove 'eglot-ensure #'ignore)))


;;;; ---------------------------------------------------------------------
;;;; (c) *Messages* carries no warnings or errors
;;;; ---------------------------------------------------------------------

;; Lines that are expected and are not defects.  Keep this list SHORT and give
;; every entry a reason; it is the one place where the gate can be talked out
;; of failing, so it is the one place that rots.
(defconst my/verify-message-allowlist
  '("^Loading .* (source|native compiled)"
    ;; The gate itself opens files; visiting one is not a warning.
    "^Wrote "
    "^Warning: Lisp directory .* does not exist"))

(defun my/verify-messages ()
  "Assert *Messages* contains no warning or error lines."
  (my/verify--say "\n== (c) *Messages*: warnings and errors ==")
  (let* ((text (with-current-buffer "*Messages*" (buffer-string)))
         (bad (seq-filter
               (lambda (line)
                 (and (string-match-p
                       "\\(?:^Warning\\|warning:\\|^Error\\|error:\\|void-function\\|void-variable\\|failed to define\\|Cannot open load file\\)"
                       line)
                      (not (seq-some (lambda (re) (string-match-p re line))
                                     my/verify-message-allowlist))))
               (split-string text "\n" t))))
    (if (null bad)
        (my/verify--ok "no warnings or errors in *Messages*")
      (my/verify--fail "%d warning/error lines in *Messages*" (length bad))
      (dolist (line (delete-dups bad))
        (my/verify--say "       %s" line)))))


;;;; ---------------------------------------------------------------------
;;;; (d) eglot: the two additions, and the hooks that are and are not wired
;;;; ---------------------------------------------------------------------

;; Hooked here means: a server for it is installed.  The NOT list is the
;; interesting half -- it is an assertion that nobody has "completed" the set
;; by hooking a language whose server is absent, which would produce a failed
;; connection on every find-file until people learn to ignore eglot errors.
;;
;; ORDER MATTERS: this section runs AFTER the language section, and must.  A
;; mode that has only been autoloaded has not yet run its
;; `derived-mode-add-parents' call, so eglot cannot match it and every packaged
;; mode looks unsupported.  Opening a real file first is what makes the answer
;; mean anything -- and it is the same order the user experiences.
(defconst my/verify-eglot-hooked
  '(bash-ts-mode-hook python-ts-mode-hook js-ts-mode-hook
    typescript-ts-mode-hook tsx-ts-mode-hook json-ts-mode-hook
    toml-ts-mode-hook yaml-ts-mode-hook go-ts-mode-hook go-mod-ts-mode-hook
    rust-ts-mode-hook lua-ts-mode-hook java-ts-mode-hook nix-ts-mode-hook
    haskell-ts-mode-hook dockerfile-ts-mode-hook markdown-mode-hook))

(defconst my/verify-eglot-not-hooked
  '(c-ts-mode-hook c++-ts-mode-hook cmake-ts-mode-hook fortran-mode-hook
    LaTeX-mode-hook latex-mode-hook))

(defun my/verify-eglot ()
  "Assert the eglot contacts and the eglot-ensure hook set."
  (my/verify--say "\n== (d) eglot: contacts and hooks ==")
  (require 'eglot)
  ;; The one gap in eglot's 52 built-in entries.
  (let ((toml (assq 'toml-ts-mode eglot-server-programs)))
    (if (equal (cdr toml) '("taplo" "lsp" "stdio"))
        (my/verify--ok "toml-ts-mode -> %S" (cdr toml))
      (my/verify--fail "toml-ts-mode contact is %S, expected (\"taplo\" \"lsp\" \"stdio\")"
                       (cdr toml))))
  ;; Python must be PINNED, i.e. our entry must come first.  `assoc' order is
  ;; the whole mechanism, so testing membership would prove nothing.
  (let ((entry (cl-find-if (lambda (e)
                             (let ((k (car e)))
                               (and (listp k) (memq 'python-ts-mode k))))
                           eglot-server-programs)))
    (if (equal (cdr entry) '("pyright-langserver" "--stdio"))
        (my/verify--ok "python pinned to %S (first matching entry)" (cdr entry))
      (my/verify--fail "python resolves to %S, expected pyright-langserver --stdio"
                       (cdr entry))))
  ;; nix is ours as of the finding above; assert the exact argv, because the
  ;; executable really is called `nil' and a future reader WILL think that is a
  ;; bug and "fix" it.
  (let ((nix (assq 'nix-ts-mode eglot-server-programs)))
    (if (equal (cdr nix) '("nil"))
        (my/verify--ok "nix-ts-mode -> %S" (cdr nix))
      (my/verify--fail "nix-ts-mode contact is %S, expected (\"nil\")" (cdr nix))))

  ;; THE CHECK THAT EARNED ITS KEEP.  Every mode we hook `eglot-ensure' into
  ;; must actually RESOLVE to a server contact -- asked through eglot's own
  ;; lookup, not by re-implementing its matching rules here.  A hook with no
  ;; contact behind it is an error on every find-file in that language.
  ;;
  ;; This is what caught nix-ts-mode: the design said its
  ;; `derived-mode-add-parents' call made eglot's `nix-mode' entry match, and
  ;; on this build there is no such call, so it matched nothing at all.  A
  ;; hand-written list of "languages we support" would have agreed with the
  ;; design and shipped the bug.
  (if (not (fboundp 'eglot--lookup-mode))
      (my/verify--fail
       "eglot--lookup-mode is gone; this check needs rewriting, not deleting")
    (dolist (h my/verify-eglot-hooked)
      (let* ((mode (intern (string-remove-suffix "-hook" (symbol-name h))))
             (contact (cdr (ignore-errors (eglot--lookup-mode mode)))))
        (cond
         ((not (fboundp mode))
          (my/verify--fail "%s is hooked but the mode is not even defined" mode))
         ((null contact)
          (my/verify--fail
           "%s has eglot-ensure but eglot resolves NO server for it" mode))
         (t nil))))
    (my/verify--ok "all %d eglot-hooked modes resolve to a server contact"
                   (length my/verify-eglot-hooked)))
  (dolist (h my/verify-eglot-hooked)
    (unless (memq 'eglot-ensure (and (boundp h) (symbol-value h)))
      (my/verify--fail "%s is missing eglot-ensure" h)))
  (my/verify--ok "%d mode hooks carry eglot-ensure" (length my/verify-eglot-hooked))
  (dolist (h my/verify-eglot-not-hooked)
    (when (and (boundp h) (memq 'eglot-ensure (symbol-value h)))
      (my/verify--fail "%s has eglot-ensure but its server is NOT installed" h)))
  (my/verify--ok "%d server-less mode hooks correctly left alone"
                 (length my/verify-eglot-not-hooked)))


;;;; ---------------------------------------------------------------------
;;;; (e) Claude: the eager half, the deferred half, and the window rule
;;;; ---------------------------------------------------------------------

;; The seven review commands.  These are NOT allowed to be autoload stubs:
;; `claude-diff-from-hook' is reached by
;; `emacsclient --eval "(claude-diff-from-hook ...)"' from a Claude session
;; that may be running in a plain vterm, or in tmux, or in a terminal that is
;; not this Emacs -- and nothing in that path declares a stub for it, so the
;; file is either loaded at startup or the hook is `void-function'.
(defconst my/verify-claude-diff-eager
  '(claude-diff-from-hook claude-diff-dismiss claude-diff-approve
    claude-diff-deny claude-diff-next-change claude-diff-prev-change
    claude-diff-scroll-up claude-diff-scroll-down))

;; The four session commands.  These SHOULD be stubs before anything loads
;; claude-code.el -- that is the deferral working.
(defconst my/verify-claude-code-deferred
  '(claude-code-run claude-code-send-region claude-code-switch-to-buffer
    claude-code-transient))

(defun my/verify--dba-entry (regexp)
  "Return the `display-buffer-alist' entry whose condition is REGEXP."
  (assoc regexp display-buffer-alist))

(defun my/verify-claude ()
  "Assert the Claude integration: eager review, deferred session, bottom window."
  (my/verify--say "\n== (e) claude: diff review, session, window rule ==")

  ;; -- the eager half -------------------------------------------------------
  (if (featurep 'claude-diff)
      (my/verify--ok "claude-diff is LOADED (not merely autoloadable)")
    (my/verify--fail
     "claude-diff is not loaded -- the PermissionRequest hook's --eval will be void-function"))
  (let ((stubs (seq-filter (lambda (s)
                             (or (not (fboundp s))
                                 (autoloadp (symbol-function s))))
                           my/verify-claude-diff-eager)))
    (if (null stubs)
        (my/verify--ok "all %d claude-diff commands are real definitions"
                       (length my/verify-claude-diff-eager))
      (my/verify--fail "%d claude-diff commands are void or still stubs: %S"
                       (length stubs) stubs)))

  ;; -- the deferred half ----------------------------------------------------
  (let ((void (seq-remove #'fboundp my/verify-claude-code-deferred)))
    (if (null void)
        (my/verify--ok "all %d claude-code commands are bound (autoload stubs)"
                       (length my/verify-claude-code-deferred))
      (my/verify--fail "%d claude-code commands are VOID: %S" (length void) void)))

  ;; -- THE WINDOW RULE, MEASURED RATHER THAN READ ---------------------------
  ;;
  ;; The bug this exists for: `claude-diff-show' calls `delete-other-windows',
  ;; and window.el:4381 signals "Cannot make side window the only window" when
  ;; the selected window is a side window -- which it is whenever the hook
  ;; fires while the user sits in the Claude popup.  Doom's +popup module
  ;; shimmed that with a `delete-other-windows' WINDOW PARAMETER; vanilla has
  ;; no such shim, so the rule must produce an ORDINARY window.
  ;;
  ;; Checking that the alist entry SAYS `display-buffer-at-bottom' is not
  ;; enough -- that is reading the design back to itself.  So this actually
  ;; displays a buffer, reads the window's `window-side' parameter, and tries
  ;; the very call that used to throw.
  (let ((entry (my/verify--dba-entry "^\\*claude:")))
    (if (null entry)
        (my/verify--fail "no display-buffer-alist entry for \"^\\\\*claude:\"")
      (my/verify--ok "display rule: %S" entry)
      (when (memq 'display-buffer-in-side-window (cadr entry))
        (my/verify--fail
         "the claude rule uses display-buffer-in-side-window -- delete-other-windows WILL signal"))
      (unless (assq 'post-command-select-window (cddr entry))
        (my/verify--fail
         "the claude rule has no post-command-select-window entry (Doom's :select nil)"))))
  (save-window-excursion
    (let ((buf (get-buffer-create "*claude:/verify*")))
      (unwind-protect
          (let ((win (display-buffer buf)))
            (cond
             ((not (window-live-p win))
              (my/verify--fail "display-buffer refused to show a *claude:* buffer"))
             ((window-parameter win 'window-side)
              (my/verify--fail
               "the claude window IS a side window (window-side=%S) -- claude-diff-show will signal"
               (window-parameter win 'window-side)))
             (t
              (my/verify--ok "the claude window is an ordinary window (window-side nil)")
              (let ((err (condition-case e
                             (progn (select-window win) (delete-other-windows) nil)
                           (error e))))
                (if err
                    (my/verify--fail
                     "delete-other-windows from the claude window SIGNALLED %S" err)
                  (my/verify--ok
                   "delete-other-windows from the claude window succeeds"))))))
        (kill-buffer buf))))

  ;; -- THE OTHER HALF: the caller's guard -----------------------------------
  ;;
  ;; The display rule above only covers the Claude buffer.  The hook fires
  ;; from wherever point is, and this config has another side window in normal
  ;; use -- `which-key-popup-type' is `side-window'.  So
  ;; `claude-diff--select-main-window' has to make `delete-other-windows' legal
  ;; from ANY side window.
  ;;
  ;; The CONTROL is the important part.  Asserting only that the guarded call
  ;; succeeds would pass just as happily if side windows had stopped signalling
  ;; altogether, or if this test never managed to build a side window in the
  ;; first place -- a check that can only report PASS.  So the unguarded call
  ;; is made first, and it is a FAILURE if it does NOT signal.
  (save-window-excursion
    (let ((buf (get-buffer-create "*verify-side-window*")))
      (unwind-protect
          (let ((win (display-buffer-in-side-window buf '((side . right)))))
            (if (not (window-live-p win))
                (my/verify--fail "could not create a side window; the guard below is untested")
              (select-window win)
              (let ((control (condition-case e (progn (delete-other-windows) nil)
                               (error e))))
                (if (null control)
                    (my/verify--fail
                     "delete-other-windows from a SIDE window did not signal -- this control no longer tests anything")
                  (my/verify--ok "control: bare delete-other-windows from a side window signals %S"
                                 (cadr control))
                  (select-window win)
                  (let ((guarded (condition-case e
                                     (progn (claude-diff--select-main-window)
                                            (delete-other-windows)
                                            nil)
                                   (error e))))
                    (if guarded
                        (my/verify--fail
                         "claude-diff--select-main-window did NOT make it safe: %S" guarded)
                      (my/verify--ok
                       "claude-diff--select-main-window makes delete-other-windows safe from a side window")))))))
        (kill-buffer buf))))

  ;; -- loading claude-code for real -----------------------------------------
  ;;
  ;; `fboundp' on an autoload stub proves the KEY is bound; it does not prove
  ;; the stub names the right file.  Loading is the only way to know.
  (if (not (require 'claude-code nil t))
      (my/verify--fail "(require 'claude-code) FAILED -- the leader keys are stubs over nothing")
    (my/verify--ok "claude-code loads")
    (let ((bad (seq-filter (lambda (s)
                             (or (not (fboundp s))
                                 (autoloadp (symbol-function s))))
                           my/verify-claude-code-deferred)))
      (if (null bad)
          (my/verify--ok "all %d claude-code commands resolved to real definitions"
                         (length my/verify-claude-code-deferred))
        (my/verify--fail "%S did not resolve after loading claude-code" bad)))
    ;; The advice.  Upstream's `claude-code-normalize-project-root' SIGNALS a
    ;; user-error on nil, so a `:filter-return' version of this advice is dead
    ;; code -- measured: with that version installed, the call below still
    ;; signals.  `:filter-args' normalises before the guard reaches it.
    ;; `SPC l l' from *scratch* depends on this, so the assertion is on the
    ;; RESULT (a string comes back) rather than on which combinator is
    ;; installed: the combinator is the current means, the string is the
    ;; requirement.
    (let ((res (condition-case e
                   (claude-code-normalize-project-root nil)
                 (error e))))
      (cond
       ((stringp res)
        (my/verify--ok "normalize-project-root nil -> %S (fallback advice live)" res))
       (t
        (my/verify--fail
         "normalize-project-root nil gave %S -- the fallback advice is not doing its job"
         res))))))


;;;; ---------------------------------------------------------------------
;;;; (f) LilyPond: the mode, the flymake backend, the build hook
;;;; ---------------------------------------------------------------------

;; FILE . (EXPECTED-COUNT EXPECTED-TYPE EXPECTED-LINE WHY)
;;
;; The `nil' rows are as load-bearing as the others.  `ly-clean.ly' proves the
;; backend does not invent diagnostics; `ly-include.ly' proves the temp file is
;; compiled with `-I <source dir>' -- without that flag its relative \include
;; fails and lilypond cascades into three errors that are not in the user's
;; file at all (measured).
(defconst my/verify-lilypond-cases
  '(("ly-clean.ly"   0   nil      nil "a valid file must produce nothing")
    ("ly-warn.ly"    1   :warning 1   "2.26 emits this warning with NO COLUMN")
    ("ly-error.ly"   2   :error   2   "errors DO carry a column")
    ("ly-include.ly" 0   nil      nil "relative \\include survives the temp file")))

(defun my/verify--lilypond-run (path)
  "Run the LilyPond flymake backend over PATH.
Return a list of (TYPE LINE TEXT) triples, or the symbol `timeout' if the
process never answered.

The triples are extracted WHILE THE SOURCE BUFFER IS STILL ALIVE.  Returning
the `flymake-diagnostic' objects instead cost a debugging round: their
positions are only meaningful inside their buffer, and reading them after the
`kill-buffer' below fails with \"Selecting deleted buffer\" -- which reads like
a broken backend rather than like a broken test."
  (let ((got 'pending)
        (result nil))
    (with-current-buffer (find-file-noselect path)
      (unwind-protect
          (progn
            (my/lilypond-flymake (lambda (diags &rest _) (setq got diags)))
            (let ((n 0))
              (while (and (eq got 'pending) (< n 600))
                (accept-process-output nil 0.05)
                (cl-incf n)))
            (unless (eq got 'pending)
              (setq result
                    (mapcar (lambda (d)
                              (list (flymake-diagnostic-type d)
                                    (save-excursion
                                      (goto-char (flymake-diagnostic-beg d))
                                      (line-number-at-pos))
                                    (flymake-diagnostic-text d)))
                            got))))
        (kill-buffer)))
    (if (eq got 'pending) 'timeout result)))

(defun my/verify-lilypond (dir)
  "Assert the LilyPond integration using sample files from DIR."
  (my/verify--say "\n== (f) lilypond: mode, flymake backend, build-on-save ==")
  (require 'flymake)

  ;; -- how it was found -----------------------------------------------------
  (if (bound-and-true-p my/lilypond-site-lisp)
      (my/verify--ok "site-lisp: %s" my/lilypond-site-lisp)
    (my/verify--fail
     "my/lilypond-site-lisp is nil -- lilypond-mode.el is not on load-path, so .ly gets fundamental-mode"))
  (if (and (bound-and-true-p my/lilypond-executable)
           (file-executable-p my/lilypond-executable))
      (my/verify--ok "lilypond: %s" my/lilypond-executable)
    (my/verify--fail "my/lilypond-executable is nil or not executable: %S"
                     (bound-and-true-p my/lilypond-executable)))
  ;; The shim is what `auto-mode-alist' must name.  Naming `lilypond-mode'
  ;; directly works on 2.26 and breaks on a 2.24 Homebrew Mac, which is a
  ;; failure nothing on Linux would ever see.
  (let ((target (cdr (assoc "\\.ly\\'" auto-mode-alist))))
    (if (eq target 'my/lilypond-mode)
        (my/verify--ok "auto-mode-alist \\.ly\\' -> my/lilypond-mode (the casing shim)")
      (my/verify--fail "auto-mode-alist \\.ly\\' -> %S, expected my/lilypond-mode" target)))

  ;; -- what a .ly buffer looks like -----------------------------------------
  (let ((path (expand-file-name "ly-clean.ly" dir)))
    (if (not (file-exists-p path))
        (my/verify--fail "ly-clean.ly: sample file was never created")
      (with-current-buffer (find-file-noselect path)
        (unwind-protect
            (progn
              (if (eq major-mode 'lilypond-mode)
                  (my/verify--ok "major-mode is lilypond-mode (2.26 lowercase)")
                (my/verify--fail "major-mode is %S, expected lilypond-mode" major-mode))
              (if (equal comment-start "%")
                  (my/verify--ok "comment-start is \"%%\"")
                (my/verify--fail "comment-start is %S, expected \"%%\" -- the mode did not really run"
                                 comment-start))
              (if (memq 'my/lilypond-flymake flymake-diagnostic-functions)
                  (my/verify--ok "flymake backend registered buffer-locally")
                (my/verify--fail "my/lilypond-flymake is NOT on flymake-diagnostic-functions"))
              ;; DELIBERATE: registered but not enabled.  Turning flymake on
              ;; here would mean TWO lilypond processes on every save, because
              ;; build-on-save already runs one.  If someone "helpfully" adds
              ;; (flymake-mode 1) this line is what says so out loud.
              (if (bound-and-true-p flymake-mode)
                  (my/verify--fail
                   "flymake-mode is ON in a .ly buffer -- that doubles the lilypond runs per save; it is meant to be SPC t f")
                (my/verify--ok "flymake-mode is off by default (SPC t f turns it on)"))
              (if (memq 'my/lilypond-build-on-save after-save-hook)
                  (my/verify--ok "build-on-save hooked buffer-locally")
                (my/verify--fail "my/lilypond-build-on-save is NOT on after-save-hook")))
          (kill-buffer)))))

  ;; -- the failure buffer's display rule ------------------------------------
  ;; The leading space is not a typo: the buffer is " *lilypond: BASE*".
  (if (my/verify--dba-entry "^ \\*lilypond: ")
      (my/verify--ok "display rule for the lilypond failure buffer is present")
    (my/verify--fail
     "no display-buffer-alist entry for \"^ \\\\*lilypond: \" -- Doom's popup manager used to place it"))

  ;; -- THE BACKEND, RUN FOR REAL --------------------------------------------
  (dolist (case my/verify-lilypond-cases)
    (cl-destructuring-bind (file count type line why) case
      (let ((path (expand-file-name file dir)))
        (if (not (file-exists-p path))
            (my/verify--fail "%s: sample file was never created" file)
          (let ((diags (my/verify--lilypond-run path)))
            (cond
             ((eq diags 'timeout)
              (my/verify--fail "%s: the flymake backend never reported" file))
             ((/= (length diags) count)
              (my/verify--fail "%s: %d diagnostic(s), expected %d (%s): %S"
                               file (length diags) count why
                               (mapcar (lambda (d) (nth 2 d)) diags)))
             ((null type)
              (my/verify--ok "%s -> 0 diagnostics (%s)" file why))
             (t
              (cl-destructuring-bind (got-type got-line text) (car diags)
                (cond
                 ((not (eq got-type type))
                  (my/verify--fail "%s: first diagnostic is %S, expected %S (%s)"
                                   file got-type type why))
                 ((/= got-line line)
                  (my/verify--fail "%s: first diagnostic on line %d, expected %d (%s)"
                                   file got-line line why))
                 (t
                  (my/verify--ok "%s -> %d %S at line %d: %s"
                                 file (length diags) got-type got-line
                                 text))))))))))))


;;;; ---------------------------------------------------------------------
;;;; (g) Popups: one bottom side window, and a toggle that goes both ways
;;;; ---------------------------------------------------------------------

;; lisp/my-popups.el replaces Doom's ~1400-line `:ui popup' with
;; `window-sides-slots', four `display-buffer-alist' rules and one preloaded
;; command.  There are no packages behind it, so there is nothing to be void --
;; which means the usual failure mode of this config does not apply and a
;; DIFFERENT one does: the rules are DATA, and data that says the right thing
;; and does the wrong thing reads exactly like data that works.
;;
;; So nothing below reads the alist back to itself.  Every claim is made by
;; displaying a real buffer on the daemon's real frame (F1, 80x25 -- side
;; windows behave there; measured) and asking the resulting window.
;;
;; THE TOGGLE IS TESTED IN BOTH DIRECTIONS.  A one-way test would pass on a
;; `window-toggle-side-windows' that had lost `window-state-put' entirely --
;; hiding works, and you would find out that restore does not the first time
;; you pressed `SPC ~' twice.  The round trip IS the feature.

(defconst my/verify-popup-height-fraction 0.42
  "The `window-height' my-popups.el gives the documentation rule.
Duplicated here on purpose: a gate that imports the value it is checking
against can only ever agree with itself.")

(defun my/verify--side-windows ()
  "Return the live side windows of the selected frame."
  (seq-filter (lambda (w) (window-parameter w 'window-side))
              (window-list nil 'nomini)))

(defun my/verify--ordinary-window-p (regexp name)
  "Display a buffer called NAME and report whether its window is ordinary.
REGEXP is only used for the message.  Returns non-nil on success."
  (let ((buf (get-buffer-create name)))
    (unwind-protect
        (let ((win (display-buffer buf)))
          (cond
           ((not (window-live-p win))
            (my/verify--fail "display-buffer refused to show %S" name)
            nil)
           ((window-parameter win 'window-side)
            (my/verify--fail
             "%s -> %S is a SIDE window (window-side=%S); the popup rules have swallowed it"
             regexp name (window-parameter win 'window-side))
            nil)
           (t
            (my/verify--ok "%s -> %S stays an ordinary window (window-side nil)"
                           regexp name)
            win)))
      (kill-buffer buf))))

(defun my/verify-popups ()
  "Assert the popup layer: side window, no mode line, toggle both ways."
  (my/verify--say "\n== (g) popups: bottom side window, modeline, SPC ~ ==")

  (if (featurep 'my-popups)
      (my/verify--ok "my-popups is loaded")
    (my/verify--fail "my-popups is NOT loaded -- init.el is missing its require"))

  ;; -- the layout decision, stated as a number ------------------------------
  ;; (left top right bottom).  Bottom is capped at ONE slot: two bottom slots
  ;; are rendered SIDE BY SIDE, not stacked, so the cap is what makes a second
  ;; popup replace the first instead of halving it.
  (if (equal (nth 3 window-sides-slots) 1)
      (my/verify--ok "window-sides-slots = %S (one bottom slot)" window-sides-slots)
    (my/verify--fail "window-sides-slots = %S -- bottom slot count is not 1"
                     window-sides-slots))

  ;; -- `SPC ~' --------------------------------------------------------------
  ;; `key-binding' reporting the right symbol is not the check; this config has
  ;; shipped six keys that did exactly that and were void on the press.
  (with-temp-buffer
    (evil-normal-state)
    (let ((cmd (key-binding (kbd "SPC ~"))))
      (cond
       ((not (eq cmd 'window-toggle-side-windows))
        (my/verify--fail "SPC ~ resolves to %S, expected window-toggle-side-windows" cmd))
       ((not (fboundp cmd))
        (my/verify--fail "SPC ~ -> %S is VOID" cmd))
       ((not (commandp cmd))
        (my/verify--fail "SPC ~ -> %S is not a command" cmd))
       (t
        (my/verify--ok "SPC ~ -> %S, fboundp and interactive" cmd)))))

  ;; -- the popup itself, measured on a real frame ---------------------------
  (save-window-excursion
    (delete-other-windows (window-main-window))
    (let* ((root-height (window-total-height (frame-root-window)))
           (want (round (* root-height my/verify-popup-height-fraction)))
           (main (selected-window)))
      (describe-function 'car)
      (let ((win (get-buffer-window "*Help*")))
        (cond
         ((not (window-live-p win))
          (my/verify--fail "*Help* was not displayed at all"))
         (t
          (if (eq (window-parameter win 'window-side) 'bottom)
              (my/verify--ok "*Help* is a BOTTOM side window (slot %S)"
                             (window-parameter win 'window-slot))
            (my/verify--fail "*Help* window-side is %S, expected `bottom'"
                             (window-parameter win 'window-side)))
          ;; Height, with a tolerance: `window--display-buffer' rounds
          ;; (* root-height fraction) and then only resizes as far as
          ;; `window--resizable-p' allows, so demanding equality would make
          ;; this assertion a report on the gate's own frame size.
          (let ((got (window-total-height win)))
            (if (<= (abs (- got want)) 2)
                (my/verify--ok "*Help* height %d lines (wanted ~%d of %d)"
                               got want root-height)
              (my/verify--fail "*Help* height %d lines, wanted ~%d of %d (tolerance 2)"
                               got want root-height)))
          ;; Doom's `:modeline nil', with no manager: the WINDOW parameter.
          (let ((mlf (window-parameter win 'mode-line-format)))
            (if (eq mlf 'none)
                (my/verify--ok "*Help* mode-line-format window parameter is `none'")
              (my/verify--fail "*Help* mode-line-format window parameter is %S, expected `none'"
                               mlf)))
          ;; WEAK dedication, and the value matters: `window--display-buffer'
          ;; re-dedicates a REUSED window only when the alist value is exactly
          ;; `side', and `t' would make it strongly dedicated -- which-key
          ;; swaps its own buffer through this very slot on every leader key.
          (let ((ded (window-dedicated-p win)))
            (cond
             ((eq ded 'side) (my/verify--ok "*Help* window is weakly dedicated (`side')"))
             ((eq ded t)
              (my/verify--fail "*Help* window is STRONGLY dedicated -- which-key shares this slot"))
             (t (my/verify--fail "*Help* window dedication is %S, expected `side'" ded))))
          ;; Doom's `:select t', via the Emacs 30 `body-function' entry.
          (if (eq (selected-window) win)
              (my/verify--ok "*Help* is selected (body-function . select-window)")
            (my/verify--fail "*Help* is not selected; body-function did not take"))
          ;; THE CONTROL FOR NOT SETTING `no-other-window'.  my-popups.el
          ;; deliberately omits it because there is no `+popup/other' here to
          ;; get back into a popup with.  If someone adds it, this goes red
          ;; rather than the user silently losing the ability to scroll help.
          (if (window-parameter win 'no-other-window)
              (my/verify--fail
               "the popup has no-other-window set -- there is no `+popup/other' here, so it would be unreachable")
            (my/verify--ok "the popup does not carry no-other-window"))
          ;; And the same claim behaviourally, because the parameter is only
          ;; the mechanism people know about. Walk the whole cycle rather than
          ;; stepping once: `other-window' is cyclic and the frame is not
          ;; guaranteed to hold exactly two windows here.
          (select-window main)
          (let ((n (length (window-list nil 'nomini)))
                (found nil))
            (dotimes (_ n)
              (other-window 1)
              (when (eq (selected-window) win) (setq found t)))
            (if found
                (my/verify--ok "the popup is reachable with `other-window'; cycle was %S"
                               (window-list nil 'nomini))
              (my/verify--fail
               "`other-window' never reaches the popup -- it would be unscrollable; windows were %S"
               (window-list nil 'nomini))))

          ;; -- THE ROUND TRIP -------------------------------------------------
          (window-toggle-side-windows)
          (let ((sides (my/verify--side-windows)))
            (if (and (null sides) (null (get-buffer-window "*Help*")))
                (my/verify--ok "SPC ~ (1st) hid every side window")
              (my/verify--fail "SPC ~ (1st) left %d side window(s) and help-window %S"
                               (length sides) (get-buffer-window "*Help*"))))
          (window-toggle-side-windows)
          (let ((back (get-buffer-window "*Help*")))
            (cond
             ((not (window-live-p back))
              (my/verify--fail "SPC ~ (2nd) did NOT bring the popup back"))
             ((not (eq (window-parameter back 'window-side) 'bottom))
              (my/verify--fail "SPC ~ (2nd) restored *Help* as window-side %S"
                               (window-parameter back 'window-side)))
             ((not (eq (window-parameter back 'mode-line-format) 'none))
              (my/verify--fail
               "SPC ~ (2nd) restored *Help* without its mode-line-format parameter (%S)"
               (window-parameter back 'mode-line-format)))
             (t
              (my/verify--ok "SPC ~ (2nd) restored the popup, still bottom, still no mode line")))))))))

  ;; -- `*compilation*' is the ONE popup that keeps its mode line ------------
  ;; Compilation state ("run", "exit [1]") lives in `mode-line-process' and
  ;; nowhere else in the buffer.  This asserts the exception is real, not a
  ;; regexp that failed to match.
  (save-window-excursion
    (delete-other-windows (window-main-window))
    (let ((buf (get-buffer-create "*compilation*")))
      (unwind-protect
          (let ((win (display-buffer buf)))
            (cond
             ((not (window-live-p win))
              (my/verify--fail "*compilation* was not displayed"))
             ((not (eq (window-parameter win 'window-side) 'bottom))
              (my/verify--fail "*compilation* window-side is %S, expected `bottom'"
                               (window-parameter win 'window-side)))
             ((window-parameter win 'mode-line-format)
              (my/verify--fail
               "*compilation* mode-line-format parameter is %S -- the exit status is invisible"
               (window-parameter win 'mode-line-format)))
             (t
              (my/verify--ok "*compilation* is a bottom popup and KEEPS its mode line"))))
        (kill-buffer buf))))

  ;; -- COMPOSITION with the two rules that were already here ----------------
  ;;
  ;; my-claude.el's "^\\*claude:" entry and my-lilypond.el's "^ \\*lilypond: "
  ;; entry both deliberately produce ORDINARY windows.  The Claude one is a bug
  ;; fix: `claude-diff--show-1' calls `delete-other-windows' and rebuilds three
  ;; panes, which only works if its window is deletable.  A popup regexp that
  ;; drifted wide enough to catch either would break that, and it would break
  ;; it the way regexps break -- silently and only in use.
  ;;
  ;; The Claude case is checked HERE AGAIN, with a popup already on screen,
  ;; which is what section (e) cannot cover: the frame there has no side window
  ;; from these rules in it.
  (save-window-excursion
    (delete-other-windows (window-main-window))
    (describe-function 'cdr)
    (let ((popup (get-buffer-window "*Help*")))
      (if (not (window-live-p popup))
          (my/verify--fail "could not open a popup; the composition checks below are untested")
        (let ((claude (my/verify--ordinary-window-p "^\\*claude:" "*claude:/verify-popups*")))
          (when claude
            ;; And it must still be able to clear the frame -- including the
            ;; popup.  If someone adds `no-delete-other-windows' to the popup
            ;; rules, the popup survives, claude-diff's "bottom third" becomes a
            ;; third of the main area, and the Claude buffer ends up on screen
            ;; twice.  my-claude.el rejected that as option (c); this is the
            ;; assertion that keeps it rejected.
            (let* ((buf (get-buffer-create "*claude:/verify-popups*"))
                   (win (display-buffer buf))
                   (err (condition-case e
                            (progn (select-window win) (delete-other-windows) nil)
                          (error e))))
              (cond
               (err (my/verify--fail
                     "delete-other-windows from the claude window WITH a popup open signalled %S"
                     err))
               ((my/verify--side-windows)
                (my/verify--fail
                 "delete-other-windows left %d side window(s) standing -- no-delete-other-windows is set somewhere"
                 (length (my/verify--side-windows))))
               (t
                (my/verify--ok
                 "delete-other-windows from the claude window clears the popup too")))
              (kill-buffer buf)))))))
  (save-window-excursion
    (delete-other-windows (window-main-window))
    (my/verify--ordinary-window-p "^ \\*lilypond: " " *lilypond: verify*")))


;;;; ---------------------------------------------------------------------
;;;; (h) Appearance: the gruvbox palette, and the italics that outlive it
;;;; ---------------------------------------------------------------------

;; Added when `doom-themes' was dropped for upstream `gruvbox-theme'.  The two
;; palettes are near-identical, so the swap is exactly the kind of change that
;; looks fine in a screenshot and is wrong in a detail nobody rechecks.
;;
;; WHY THIS READS `theme-settings' AND NOT `face-attribute'.  Measured: the
;; daemon's initial frame F1 has `(display-color-cells)' = 0, and
;; `(face-attribute 'default :background)' on it returns "unspecified-bg" no
;; matter which theme is loaded.  An assertion against that would have been
;; green with NO theme at all.  `theme-settings' holds the spec the theme
;; actually installed, so this asks the theme what it will paint with rather
;; than asking a colourless frame what it painted.
;;
;; The italics are the opposite case and ARE read off the face: :slant is
;; frame-independent here, and it is the half of this section with real
;; history.  `my/italicize-syntax-faces' hangs on `enable-theme-functions', and
;; a theme swap is precisely when a hook keyed on theme loading gets lost --
;; the graduation notes flagged that a naive port drops the italics the moment
;; `load-theme' runs.  Asserting them here means the next theme change cannot
;; drop them quietly.

(defconst my/verify-theme 'gruvbox-dark-medium
  "The theme init.el is expected to have enabled.")

(defconst my/verify-theme-colors '(:background "#282828" :foreground "#ebdbb2")
  "Expected truecolor `default' face of `my/verify-theme'.
Written out rather than read from the theme, so this cannot agree with
itself.  #282828 is gruvbox `dark0', which is what makes MEDIUM the variant
that matches the retired `doom-gruvbox' -- hard is #1d2021 and soft #32302f.")

(defun my/verify--theme-default-spec ()
  "Return the `default' face spec `my/verify-theme' installed, or nil."
  (nth 3 (seq-find (lambda (e)
                     (and (eq (nth 0 e) 'theme-face)
                          (eq (nth 1 e) 'default)))
                   (get my/verify-theme 'theme-settings))))

(defun my/verify-appearance ()
  "Assert the theme, its palette, and the italic syntax faces."
  (my/verify--say "\n== (h) appearance: gruvbox palette, italics, modeline ==")

  ;; EXACTLY one theme.  `equal' against a one-element list, not `memq': two
  ;; stacked themes is a real and silent failure mode -- the second one wins
  ;; for the faces it defines and the first shows through everywhere else.
  (if (equal custom-enabled-themes (list my/verify-theme))
      (my/verify--ok "custom-enabled-themes = %S" custom-enabled-themes)
    (my/verify--fail "custom-enabled-themes = %S, expected exactly (%s)"
                     custom-enabled-themes my/verify-theme))

  ;; Doom is retired, so its theme pack must be OUT OF THE CLOSURE and not
  ;; merely unloaded.  `locate-library' searches load-path, which is what the
  ;; Nix package set builds -- so this fails if doom-themes comes back into
  ;; package.nix even if nothing loads it.
  (if (locate-library "doom-themes")
      (my/verify--fail "doom-themes is still on load-path (%s) -- it should have left package.nix with Doom"
                       (locate-library "doom-themes"))
    (my/verify--ok "doom-themes is not on load-path"))

  ;; ... whereas doom-modeline is a standalone MELPA package that only wants
  ;; nerd-icons, and it deliberately STAYED.  Asserted so that "drop the other
  ;; doom-* package too" is a gate failure and therefore a decision.
  (if (bound-and-true-p doom-modeline-mode)
      (my/verify--ok "doom-modeline-mode is on (kept: not a Doom artefact)")
    (my/verify--fail "doom-modeline-mode is off"))

  ;; -- the palette ----------------------------------------------------------
  (let ((spec (my/verify--theme-default-spec)))
    (if (null spec)
        (my/verify--fail "%s installed no `default' face spec" my/verify-theme)
      ;; The truecolor branch, i.e. the one a real GUI or 24-bit terminal gets.
      ;; Selected by min-colors rather than by position: autothemer's ordering
      ;; is an implementation detail, and taking `car' would make this
      ;; assertion depend on it.
      (let ((truecolor
             (seq-find (lambda (branch)
                         (let ((disp (car branch)))
                           (and (consp disp)
                                (seq-some (lambda (c)
                                            (and (consp c)
                                                 (eq (car c) 'min-colors)
                                                 (>= (cadr c) 16777215)))
                                          disp))))
                       spec)))
        (if (null truecolor)
            (my/verify--fail "%s `default' has no min-colors>=16777215 branch: %S"
                             my/verify-theme spec)
          (let ((attrs (cadr truecolor)))
            (dolist (k '(:background :foreground))
              (let ((got (plist-get attrs k))
                    (want (plist-get my/verify-theme-colors k)))
                (if (equal got want)
                    (my/verify--ok "%s default %s = %s" my/verify-theme k got)
                  (my/verify--fail "%s default %s = %S, expected %S"
                                   my/verify-theme k got want)))))))))

  ;; -- the italics ----------------------------------------------------------
  ;; All four faces `my/italicize-syntax-faces' touches, because the hook
  ;; either ran or it did not, and a single face would not tell that apart
  ;; from a theme that happens to italicise comments on its own.
  (dolist (face '(font-lock-comment-face
                  font-lock-keyword-face
                  font-lock-string-face
                  font-lock-doc-face))
    (let ((slant (face-attribute face :slant)))
      (if (eq slant 'italic)
          (my/verify--ok "%s is italic" face)
        (my/verify--fail "%s :slant is %S, expected italic -- `my/italicize-syntax-faces' did not survive `load-theme'"
                         face slant)))))


;;;; ---------------------------------------------------------------------
;;;; (i) org-gcal: the background timer, and the gate NOT firing it
;;;; ---------------------------------------------------------------------

;; RUNS FIRST.  See the driver.
;;
;; The 30-minute fetch timer came back when Doom was retired: it was withheld
;; for the whole parallel period because two daemons cannot both own
;; ~/org/gcal*.org.  This gate starts a THIRD real daemon out of the store,
;; and a gate daemon that fetched would recreate that exact two-writer case
;; against the user's live one -- with real calendar data on the losing side.
;;
;; my-org.el therefore keys `my/org-gcal-fetch-inhibit' off the environment
;; variable verify.sh already exports.  Both halves are asserted here, because
;; either alone is satisfiable by the bug the other catches: a gate that only
;; checked the timer would go green on a config that fetches during the gate,
;; and one that only checked the inhibit would go green on a config that has
;; lost the timer entirely.
;;
;; Then the timer is CANCELLED.  The inhibit already makes it a no-op; this is
;; the belt to those braces, and it costs one line against the case where the
;; daemon took most of verify.sh's 120s readiness budget to come up and the
;; 90-second initial delay has already elapsed.

(defconst my/verify-gcal-fetch-interval (* 30 60)
  "Expected repeat interval of the background fetch, in seconds.
Duplicated from my-org.el on purpose -- a gate that imports the number it
checks can only agree with itself.")

(defun my/verify-org-gcal-timer ()
  "Assert the background fetch timer exists and is inhibited here, then cancel it."
  (my/verify--say "\n== (i) org-gcal: background fetch timer (and why it must not fire here) ==")

  (if (fboundp 'my/org-gcal-fetch-safe)
      (my/verify--ok "my/org-gcal-fetch-safe is defined")
    (my/verify--fail "my/org-gcal-fetch-safe is VOID -- the timer would error every 30 minutes"))

  (if (bound-and-true-p my/org-gcal-fetch-inhibit)
      (my/verify--ok "my/org-gcal-fetch-inhibit is non-nil -- this daemon will not touch ~/org/gcal*.org")
    (my/verify--fail
     "my/org-gcal-fetch-inhibit is nil in the GATE daemon: it would fetch the real calendar and write ~/org/gcal*.org underneath the user's Emacs.  verify.sh must export EMACS_VANILLA_VERIFY_OUT before the daemon starts"))

  (let ((timer (bound-and-true-p my/org-gcal-fetch-timer)))
    (cond
     ((not (timerp timer))
      (my/verify--fail "my/org-gcal-fetch-timer is %S, expected a timer -- the background fetch is gone"
                       timer))
     ((not (equal (timer--repeat-delay timer) my/verify-gcal-fetch-interval))
      (my/verify--fail "my/org-gcal-fetch-timer repeats every %Ss, expected %d"
                       (timer--repeat-delay timer) my/verify-gcal-fetch-interval))
     (t
      (my/verify--ok "my/org-gcal-fetch-timer repeats every %ds"
                     my/verify-gcal-fetch-interval)
      (cancel-timer timer)
      (my/verify--ok "timer cancelled for the remainder of the gate")))))


;;;; ---------------------------------------------------------------------
;;;; Driver
;;;; ---------------------------------------------------------------------

(defun my/verify-run ()
  "Run every check and write the report to $EMACS_VANILLA_VERIFY_OUT."
  (setq my/verify--lines nil
        my/verify--failures 0)
  (let ((out (getenv "EMACS_VANILLA_VERIFY_OUT"))
        (samples (getenv "EMACS_VANILLA_VERIFY_SAMPLES")))
    (my/verify--say "emacs-vanilla gate -- %s" (emacs-version))
    (my/verify--say "config: %s" user-emacs-directory)
    (condition-case err
        (progn
          ;; FIRST, before anything else can take time: cancel the org-gcal
          ;; background fetch. Its initial delay is 90 seconds from daemon
          ;; start and verify.sh allows up to 120 for readiness alone, so
          ;; every section below is potentially past it. See section (i).
          (my/verify-org-gcal-timer)
          (my/verify-leader)
          ;; Languages BEFORE eglot: opening a file is what LOADS each mode,
          ;; and an unloaded mode has not declared its derived-mode parents yet.
          ;; See the note above `my/verify-eglot-hooked'.
          (if samples
              (my/verify-languages samples)
            (my/verify--fail "EMACS_VANILLA_VERIFY_SAMPLES is unset"))
          (my/verify-eglot)
          (my/verify-claude)
          ;; AFTER claude: section (e) proves the claude rule on a frame with
          ;; no popup in it, and (g) then proves the same thing again with one
          ;; open. Losing that ordering turns two independent measurements into
          ;; one.
          (my/verify-popups)
          ;; AFTER the popup section: (g) measures window heights against
          ;; the frame, and this one only reads faces and theme data so it
          ;; cannot disturb that -- but putting it before would mean any
          ;; frame surgery added here later silently changed (g)'s numbers.
          (my/verify-appearance)
          (if samples
              (my/verify-lilypond samples)
            (my/verify--fail "EMACS_VANILLA_VERIFY_SAMPLES is unset"))
          ;; LAST: the language section visits files, and anything that goes
          ;; wrong while doing so must land in *Messages* before it is read.
          (my/verify-messages))
      (error (my/verify--fail "gate itself errored: %S" err)))
    (my/verify--say "\n=== %s: %d failed assertion(s) ==="
                    (if (zerop my/verify--failures) "PASS" "FAIL")
                    my/verify--failures)
    (let ((report (mapconcat #'identity (nreverse my/verify--lines) "\n")))
      (when out
        (with-temp-file out (insert report "\n")))
      report)))

(defun my/verify-run-or-signal ()
  "Run every check, then SIGNAL if any assertion failed.

This is what ../verify.sh calls, and it exists so that stage 4 can
decide on an EXIT CODE rather than on the text of the report.
`emacsclient' is indifferent to the value a form returns -- nil, t,
0 and \"\" all leave it exiting 0 -- and turns a server-side signal
into exit status 1.  Signalling is therefore the only way a failed
assertion in HERE becomes a non-zero status out THERE.

Handing the count back for the shell to read would be the same
defect in a new spelling.  The report used to be searched for a
`=== PASS' banner, and captured text -- void command symbols in
section (a), *Messages* lines in section (c) -- stayed clear of
column 0 only by the accident of a format string opening with
seven spaces.

`my/verify-run' is unchanged and is still the one to call by hand:
it REPORTS, and this one DECIDES.  Returns nil, so a passing run
prints nil back at the shell instead of the whole report."
  (my/verify-run)
  (unless (zerop my/verify--failures)
    (error "Emacs-vanilla gate: %d failed assertion(s); see the report above"
           my/verify--failures))
  nil)

(provide 'verify)
;;; verify.el ends here
