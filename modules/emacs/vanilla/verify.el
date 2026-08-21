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
    ("sample.http" (restclient-mode)    nil nil         "")))

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
    ;; user-error on nil, so Doom's `:filter-return' version of this advice is
    ;; dead code -- measured: with it installed, the call below still signals.
    ;; `:filter-args' normalises before the guard.  `SPC l l' from *scratch*
    ;; depends on this.
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
          (my/verify-leader)
          ;; Languages BEFORE eglot: opening a file is what LOADS each mode,
          ;; and an unloaded mode has not declared its derived-mode parents yet.
          ;; See the note above `my/verify-eglot-hooked'.
          (if samples
              (my/verify-languages samples)
            (my/verify--fail "EMACS_VANILLA_VERIFY_SAMPLES is unset"))
          (my/verify-eglot)
          (my/verify-claude)
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

(provide 'verify)
;;; verify.el ends here
