;;; $DOOMDIR/config.el -*- lexical-binding: t; -*-

;; Place your private configuration here! Remember, you do not need to run 'doom
;; sync' after modifying this file!

(require 'cl-lib)

;; LilyPond mode setup - load from system installation
(when-let ((lily-bin (executable-find "lilypond")))
  (let* ((lily-dir (file-name-directory lily-bin))
         ;; Candidate elisp locations, relative to the resolved bin dir. The
         ;; version-numbered directory is GLOBBED rather than listed: the old
         ;; list named "2.24.4" explicitly, the installed tree is
         ;; share/lilypond/2.26.0/elisp, and that probe had therefore been
         ;; matching nothing for as long as 2.26 has been installed. It was
         ;; harmless -- share/emacs/site-lisp is what actually resolves -- but
         ;; it was also the one line a reader would consult to learn which
         ;; LilyPond this config targets, and it was lying.
         (elisp-paths (append
                       (list (expand-file-name "../share/emacs/site-lisp" lily-dir)
                             (expand-file-name "../share/lilypond/current/elisp" lily-dir))
                       (file-expand-wildcards
                        (expand-file-name "../share/lilypond/*/elisp" lily-dir)))))
    (dolist (path elisp-paths)
      (when (file-directory-p path)
        (add-to-list 'load-path path))))
  
  ;; Load lilypond-mode
  (require 'lilypond-mode nil t)
  
  (with-eval-after-load 'lilypond-mode
    ;; LilyPond 2.26 renamed EVERY symbol to lowercase ("Change all prefixes to
    ;; lowercase to follow the Elisp convention"), so `LilyPond-mode' -- the
    ;; 2.24 name hardcoded here until now -- does not exist against the
    ;; lilypond in the nix profile (2.26.0).  Nothing announced that:
    ;; `auto-mode-alist' pointed at a void function, the checker was defined
    ;; `:modes' a mode that never activated, and the build-on-save hook below
    ;; was added to a hook that never ran.  All three were silently dead.
    ;;
    ;; Resolved at load time rather than hardcoded, because darwin gets
    ;; lilypond from Homebrew (home/common.nix skips the nix package there)
    ;; and may still be on 2.24.
    (defconst my/lilypond-mode-symbol
      (cond ((fboundp 'lilypond-mode) 'lilypond-mode)   ; 2.26+
            ((fboundp 'LilyPond-mode) 'LilyPond-mode))  ; 2.24 and earlier
      "Whichever casing of the LilyPond major mode this lilypond ships.")

    (when my/lilypond-mode-symbol
      (add-to-list 'auto-mode-alist (cons "\\.ly\\'"  my/lilypond-mode-symbol))
      (add-to-list 'auto-mode-alist (cons "\\.ily\\'" my/lilypond-mode-symbol))

      ;; Flycheck integration
      (after! flycheck
        (flycheck-define-checker lilypond
          "A LilyPond syntax checker."
          :command ("lilypond"
                    (eval my/lilypond-extra-args)
                    "-dno-print-pages" "-o" temporary-file-name source)
          ;; The column is OPTIONAL on warnings: 2.26 emits a bare
          ;; "file.ly:1: warning: no \\version statement found" with no column,
          ;; so a pattern that requires one drops every warning on the floor.
          ;; Errors do carry a column.
          :error-patterns
          ((error   line-start (file-name) ":" line ":" column ": error: " (message) line-end)
           (warning line-start (file-name) ":" line ":" (optional column ":") " warning: " (message) line-end)
           (error   line-start "fatal error: " (message) line-end))
          ;; Both casings: `flycheck-define-checker' only records these, so
          ;; naming a mode that does not exist on this machine is harmless.
          :modes (lilypond-mode LilyPond-mode))
        (add-to-list 'flycheck-checkers 'lilypond)))))

;; ── LilyPond: auto-build on save + refresh open PDF buffers ────────
;; Generic for any .ly file. Project-specific flags (e.g. --include
;; for custom fonts) can be set per-directory in .dir-locals.el:
;;
;;   ((lilypond-mode . ((my/lilypond-extra-args . ("--include" "/path")))))
;;
;; Note the lowercase mode name -- see the 2.26 rename above. A .dir-locals.el
;; written against `LilyPond-mode' will never match.

(defcustom my/lilypond-extra-args nil
  "Extra arguments passed to `lilypond' when auto-building on save."
  :type '(repeat string)
  :group 'lilypond
  :safe #'listp)

(defvar my/lilypond--processes (make-hash-table :test 'equal)
  "Hash of source-path → running lilypond process.")

(defun my/lilypond--refresh-pdfs (dir base)
  "Revert open PDF buffers under DIR whose filename starts with BASE.
Matches `<base>.pdf`, `<base>-C.pdf`, `<base>-Bb.pdf`, etc."
  (dolist (buf (buffer-list))
    (with-current-buffer buf
      (when (and buffer-file-name
                 (string-match-p "\\.pdf\\'" buffer-file-name)
                 (file-in-directory-p buffer-file-name dir)
                 (string-prefix-p base
                                  (file-name-nondirectory buffer-file-name)))
        (ignore-errors (revert-buffer t t t))))))

(defun my/lilypond-build-on-save ()
  "Asynchronously rebuild the just-saved .ly file, then refresh any
open PDF buffers it produces."
  (when (and buffer-file-name
             (string-match-p "\\.ly\\'" buffer-file-name))
    (let* ((src  buffer-file-name)
           (dir  (file-name-directory src))
           (base (file-name-base src))
           (buf  (get-buffer-create (format " *lilypond: %s*" base)))
           (old  (gethash src my/lilypond--processes))
           (default-directory dir))
      (when (and old (process-live-p old))
        (ignore-errors (kill-process old)))
      (with-current-buffer buf
        (let ((inhibit-read-only t)) (erase-buffer)))
      (let ((proc (apply #'start-process
                         (format "lilypond-%s" base)
                         buf "lilypond"
                         (append my/lilypond-extra-args
                                 (list "-o" base src)))))
        (puthash src proc my/lilypond--processes)
        (set-process-query-on-exit-flag proc nil)
        (message "LilyPond: building %s…" (file-name-nondirectory src))
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
               (message "LilyPond: %s FAILED — see %s"
                        (file-name-nondirectory src) (buffer-name buf))
               (display-buffer buf)))))))))

;; Hook the mode that actually exists (see the 2.26 rename above). Guarded
;; because `my/lilypond-mode-symbol' is only defined when lilypond-mode loaded
;; at all -- on a machine with no lilypond binary this file must still load.
(when (bound-and-true-p my/lilypond-mode-symbol)
  (add-hook (intern (format "%s-hook" my/lilypond-mode-symbol))
            (lambda ()
              (add-hook 'after-save-hook #'my/lilypond-build-on-save nil t))))

;; user-full-name / user-mail-address are intentionally omitted here —
;; they are already set in ~/.gitconfig by the home-manager git module.

(setq ispell-program-name "aspell")

;; Common Lisp: use sbcl as the inferior lisp for SLIME
(setq inferior-lisp-program "sbcl")

;; Java LSP: point lsp-java at the Nix-provided jdtls so it doesn't auto-download
(after! lsp-java
  (when-let* ((jdtls-bin (executable-find "jdtls"))
              (pkg-root (expand-file-name "../" (file-name-directory (file-truename jdtls-bin))))
              (install-dir (expand-file-name "share/java/jdtls/" pkg-root)))
    (when (file-directory-p install-dir)
      (setq lsp-java-server-install-dir install-dir))))

(setq doom-font (font-spec :family "VictorMono Nerd Font" :size 18))

;; For nerd-icons symbols specifically
(setq nerd-icons-font-family "Symbols Nerd Font Mono")

(custom-set-faces!
  '(font-lock-comment-face :slant italic)
  '(font-lock-keyword-face :slant italic)
  '(font-lock-string-face :slant italic)
  '(font-lock-doc-face :slant italic))

;; If you or Emacs can't find your font, use 'M-x describe-font' to look them
;; up, `M-x eval-region' to execute elisp code, and 'M-x doom/reload-font' to
;; refresh your font settings. If Emacs still can't find your font, it likely
;; wasn't installed correctly. Font issues are rarely Doom issues!

;; There are two ways to load a theme. Both assume the theme is installed and
;; available. You can either set `doom-theme' or manually load a theme with the
;; `load-theme' function. This is the default:
(setq doom-theme 'doom-gruvbox)

;; 2-way diff review for Claude Code edits (claude-diff.el).
;; Loaded eagerly at top level — NOT inside the deferred use-package!
;; below — because the PermissionRequest hook calls
;; `emacsclient --eval (claude-diff-from-hook ...)' and must work even
;; when claude-code.el has never been loaded (e.g. Claude running in a
;; plain vterm).
(load! "claude-diff")

;; Diff review keybindings (same SPC l prefix as claude-code below)
(map! :leader
      (:prefix ("l" . "claude")
       :desc "Approve changes"    "a" #'claude-diff-approve
       :desc "Deny changes"       "x" #'claude-diff-deny
       :desc "Dismiss diff"       "D" #'claude-diff-dismiss
       :desc "Next change"        "n" #'claude-diff-next-change
       :desc "Prev change"        "p" #'claude-diff-prev-change
       :desc "Scroll diff up"     "j" #'claude-diff-scroll-up
       :desc "Scroll diff down"   "k" #'claude-diff-scroll-down))

;; Claude Code: AI-assisted coding via Claude CLI in vterm (stays deferred)
(use-package! claude-code
  :init
  (map! :leader
        (:prefix ("l" . "claude")
         :desc "Start Claude"   "l" #'claude-code-run
         :desc "Send region"    "r" #'claude-code-send-region
         :desc "Switch buffer"  "b" #'claude-code-switch-to-buffer
         :desc "Menu"           "m" #'claude-code-transient))
  :config
  ;; claude-code-run and friends call `projectile-project-root', which returns
  ;; nil from non-project buffers (*scratch*, etc.).  Advise
  ;; `claude-code-normalize-project-root' -- the single choke-point in
  ;; claude-code-core.el, which `claude-code-run', `claude-code-switch-to-buffer'
  ;; and `claude-code-buffer-name' all go through -- to fall back to
  ;; `default-directory'.
  ;;
  ;; THE COMBINATOR IS THE FIX; IT IS NOT COSMETIC.  This was written as
  ;; `:filter-return' against a claude-code that RETURNED nil outside a project,
  ;; giving "(wrong-type-argument stringp nil)" downstream.  Upstream
  ;; (claude-code-core.el, packaged 20260812.1216) now reads
  ;;
  ;;   (if project-root (directory-file-name project-root)
  ;;     (user-error "Current directory is not part of a project"))
  ;;
  ;; and a `:filter-return' advice NEVER RUNS WHEN THE FUNCTION SIGNALS -- there
  ;; is no return value to filter.  The advice was therefore dead code guarding
  ;; nothing, and `SPC l l' from *scratch* has been raising that user-error ever
  ;; since upstream changed.
  ;;
  ;; `:filter-args' is the right answer rather than `:around' because the fault
  ;; is in the ARGUMENT, not in the call: substituting `default-directory' for a
  ;; nil PROJECT-ROOT sends the unmodified upstream function down its own success
  ;; branch, so the guard still fires for every other caller and upstream keeps
  ;; doing the trailing-slash normalisation.  An `:around' would have to
  ;; re-implement or condition-case that body, and would silently swallow a real
  ;; `user-error' from a future upstream.  Passing `default-directory' with its
  ;; trailing slash intact is deliberate: the advised function calls
  ;; `directory-file-name' on it.
  ;;
  ;; Kept deliberately identical to the vanilla port in
  ;; modules/emacs/vanilla/config/lisp/my-claude.el -- same package, same
  ;; upstream function; the two must not drift.
  (define-advice claude-code-normalize-project-root
      (:filter-args (args) fallback-dir)
    "Fall back to `default-directory' when ARGS names no project root.
`projectile-project-root' returns nil in *scratch* and in any other buffer
outside a project."
    (list (or (car args) default-directory)))
  ;; Open Claude Code in bottom third of the frame.
  ;; Doom's popup manager overrides display-buffer-alist, so use set-popup-rule!
  (set-popup-rule! "^\\*claude:"
    :side 'bottom
    :height 0.33
    :select nil
    :quit nil
    :ttl nil
    :modeline t))

;; ─── GPG pinentry (pinentry-emacs-frame custom Assuan wrapper) ─────
;; Direct epg/epa callers prompt in the minibuffer of the frame that
;; initiated the call.  gpg-agent has allow-loopback-pinentry enabled
;; in modules/gpg.nix, so no pinentry binary is involved here.
(setq epg-pinentry-mode 'loopback)

;; Emacs half of the pinentry-emacs-frame wrapper.  Frame selection is
;; explicit and does NOT raise / re-focus — `with-selected-frame' only
;; rebinds `selected-frame' inside its body, so `read-passwd' renders
;; on the correct minibuffer without stealing OS focus.
(defun my/pinentry--pick-frame ()
  "Choose the MRU focused frame without switching focus."
  (or (and (fboundp 'frame-focus-state)
           (cl-find-if (lambda (f) (eq (frame-focus-state f) t))
                       (frame-list)))
      (and (fboundp 'get-mru-frame) (get-mru-frame t))
      (selected-frame)))

(defun my/pinentry-read-pin (desc prompt err)
  "Prompt for a GPG passphrase.  Return a string, or :cancel on C-g."
  (let ((frame (my/pinentry--pick-frame))
        (full  (concat (and (> (length err) 0)  (concat err "\n"))
                       (and (> (length desc) 0) (concat desc "\n"))
                       (or prompt "Passphrase: "))))
    (condition-case _
        (with-selected-frame frame (or (read-passwd full) :cancel))
      (quit :cancel))))

(defun my/pinentry-yes-or-no-p (desc)
  "CONFIRM handler for pinentry-emacs-frame.  Return t or nil."
  (let ((frame (my/pinentry--pick-frame)))
    (condition-case _
        (with-selected-frame frame (yes-or-no-p (concat desc " ")))
      (quit nil))))

;; This determines the style of line numbers in effect. If set to `nil', line
;; numbers are disabled. For relative line numbers, set this to `relative'.
(setq display-line-numbers-type t)

;; If you use `org' and don't want your org files in the default location below,
;; change `org-directory'. It must be set before org loads!
(setq org-directory "~/org/")

;; ─────────────────────────────────────────────────────────────────────
;; Org foundation: agenda, capture, TODO workflow
;; ─────────────────────────────────────────────────────────────────────
(after! org
  ;; Which files the agenda (SPC o a) scans. Deliberately a curated list
  ;; rather than the whole ~/org dir, so old scratch/learning files don't
  ;; pollute the agenda. Add files here as you create them.
  (setq org-agenda-files
        (mapcar (lambda (f) (expand-file-name f org-directory))
                '("inbox.org" "todo.org" "projects.org"
                  "gcal.org" "gcal-louis.org" "gcal-cog.org")))

  ;; A simple, legible task lifecycle. The letters in (..) are fast-select
  ;; keys; @ = prompt for a note, ! = timestamp the state change.
  (setq org-todo-keywords
        '((sequence "TODO(t)" "NEXT(n)" "WAIT(w@/!)" "|" "DONE(d)" "CANCELLED(c@)")))
  (setq org-log-done 'time          ; stamp CLOSED: when a task is finished
        org-log-into-drawer t)      ; tuck state-change logs into a :LOGBOOK:

  ;; Refile: move a captured item into todo.org / projects.org with SPC m r.
  (setq org-refile-targets '((org-agenda-files :maxlevel . 3))
        org-refile-use-outline-path 'file
        org-outline-path-complete-in-steps nil)

  ;; Capture templates (SPC X, or `org-capture'). Each drops a new entry
  ;; into the right file so you never lose a thought.
  (setq org-capture-templates
        '(("t" "Todo -> inbox" entry
           (file+headline "inbox.org" "Inbox")
           "* TODO %?\n%U\n%i" :empty-lines 1)
          ("n" "Note -> inbox" entry
           (file+headline "inbox.org" "Inbox")
           "* %?\n%U\n%i" :empty-lines 1)
          ("e" "Event -> personal calendar (syncs to Google)" entry
           (file+headline "gcal.org" "brona90@gmail.com")
           "* %?\n%^T\n" :empty-lines 1)))

  ;; Daily dashboard: `SPC o a' then `d' = one screen with the next 3 days of
  ;; calendar/scheduled/deadlines, then your NEXT actions, then what you're
  ;; waiting on.
  (setq org-agenda-custom-commands
        '(("d" "Daily dashboard"
           ((agenda "" ((org-agenda-span 3)
                        (org-agenda-start-day "0d") ; pin to today (global default is "-3d")
                        (org-deadline-warning-days 14)
                        (org-agenda-overriding-header "Next 3 days")))
            (todo "NEXT" ((org-agenda-overriding-header "Next actions")))
            (todo "WAIT" ((org-agenda-overriding-header "Waiting on"))))))))

;; ─────────────────────────────────────────────────────────────────────
;; org-gcal: two-way Google Calendar <-> org sync
;; ─────────────────────────────────────────────────────────────────────
;; FIRST-TIME SETUP (one time):
;;   1. Create a Google Cloud OAuth client (type "Desktop app") with the
;;      Calendar API enabled; add brona90@gmail.com as a Test user.
;;   2. Store the credentials in sops (encrypted, reproducible):
;;        sops set secrets/secrets.yaml '["org_gcal"]["client_id"]'     '"...id..."'
;;        sops set secrets/secrets.yaml '["org_gcal"]["client_secret"]' '"...secret..."'
;;      sops-nix (modules/sops.nix) decrypts them on `hms` to
;;      ~/.config/sops-nix/secrets/org_gcal_client_{id,secret}.
;; After `hms`: open an org file, run M-x org-gcal-sync (or SPC m G s) and
;; complete the browser auth once.
(use-package! org-gcal
  :after org
  :commands (org-gcal-sync org-gcal-fetch org-gcal-post-at-point)
  :config
  ;; Client id/secret come from sops-nix (decrypted to ~/.config/sops-nix/secrets/).
  ;; See modules/sops.nix (org_gcal/*) and the encrypted secrets/secrets.yaml.
  (let ((dir (expand-file-name "~/.config/sops-nix/secrets/")))
    (cl-flet ((slurp (f)
                (let ((p (expand-file-name f dir)))
                  (when (file-readable-p p)
                    (string-trim (with-temp-buffer (insert-file-contents p)
                                                   (buffer-string)))))))
      (when-let ((id (slurp "org_gcal_client_id")))     (setq org-gcal-client-id id))
      (when-let ((sec (slurp "org_gcal_client_secret"))) (setq org-gcal-client-secret sec))))
  ;; org-gcal registers its oauth2-auto provider at load time, but the creds
  ;; above are set AFTER load — so re-register now or auth fails with
  ;; "oauth2-auto: Unknown provider: org-gcal".
  (when (and org-gcal-client-id org-gcal-client-secret)
    (org-gcal-reload-client-id-secret))
  ;; Keep the OAuth token store in a writable home path (the Nix store is RO).
  (setq org-gcal-token-file (expand-file-name "~/.config/org-gcal/token.plstore"))
  ;; Encrypt the OAuth token store to a DEDICATED passphrase-less GPG key
  ;; (050C…1930, uid "org-gcal-token", private key managed in sops and imported by
  ;; modules/sops.nix). Because that key has NO passphrase, gpg-agent decrypts it
  ;; with ZERO prompts on every read — while the main signing key (0DF8…0FC6) stays
  ;; passphrase-protected. This is why a fetch no longer asks for a passphrase.
  (setq plstore-encrypt-to '("050C399D3A6B013DD2C93F899BC379782DFE1930"))
  ;; Move the oauth2-auto refresh-token store OUT of ~/.cache/doom (which
  ;; `doom clean` wipes, forcing a re-auth) into a stable home path.
  (when (boundp 'oauth2-auto-plstore)
    (setq oauth2-auto-plstore (expand-file-name "~/.config/org-gcal/oauth2-auto.plist")))
  ;; Keep the org files small. org-gcal expands recurring events into one entry
  ;; per instance, so the fetch window is the main size lever. Past events beyond
  ;; the window are moved to <file>_archive (auto-archive) rather than bloating the
  ;; live file. 14 days back + 45 forward is plenty for the agenda.
  (setq org-gcal-up-days 14
        org-gcal-down-days 45
        org-gcal-auto-archive t)
  ;; calendar-id  ->  org file. Two-way: editing these headings pushes to Google.
  ;; NOTE: gcal-cog.org maps to the "COG" calendar — a Google Apps Script-populated
  ;; mirror of the Cognizant calendar. Treat it READ-ONLY: pull with `org-gcal-fetch'
  ;; (SPC m G f) and don't edit its headings (edits would hit the mirror, not the
  ;; real Cognizant calendar). (Work calendar was deleted upstream — removed here.)
  (setq org-gcal-fetch-file-alist
        '(("brona90@gmail.com" . "~/org/gcal.org")
          ("oe0etoam5k8o95sqd1qnisio44@group.calendar.google.com" . "~/org/gcal-louis.org")
          ("140a3ad65e2a46fe9a58a74035d2e489482e704c008622767304b36ca33c4b47@group.calendar.google.com" . "~/org/gcal-cog.org")))
  ;; org-gcal populates buffers but never saves them (that's what made COG look
  ;; empty). Chain a save onto every fetch/sync so events always land on disk.
  (defun my/org-gcal-save-buffers (&optional result)
    "Save modified org-gcal-managed buffers (live gcal*.org files + their _archive)."
    (dolist (b (buffer-list))
      (with-current-buffer b
        (when (and buffer-file-name
                   (string-match-p "/org/gcal.*\\.org\\(_archive\\)?\\'" buffer-file-name)
                   (buffer-modified-p))
          (save-buffer))))
    result)
  (defun my/org-gcal--save-after (orig &rest args)
    "Around-advice: save org-gcal buffers once the (async) ORIG completes."
    (let ((d (apply orig args)))
      (if (and (fboundp 'deferred-p) (deferred-p d))
          (deferred:nextc d #'my/org-gcal-save-buffers)
        (my/org-gcal-save-buffers)
        d)))
  (advice-add 'org-gcal-sync  :around #'my/org-gcal--save-after)
  (advice-add 'org-gcal-fetch :around #'my/org-gcal--save-after))

;; org-gcal keys under the org localleader: SPC m G (s)ync / (f)etch / (p)ost.
(map! :after org
      :localleader
      :map org-mode-map
      (:prefix ("G" . "gcal")
       :desc "Sync (fetch + push)" "s" #'org-gcal-sync
       :desc "Fetch (pull only)"   "f" #'org-gcal-fetch
       :desc "Post event at point" "p" #'org-gcal-post-at-point))

;; Auto-fetch the calendars in the background: ~90s after the daemon starts, then
;; every 30 min. The auto-save advice above writes the results to disk, so the
;; agenda stays current with no manual `SPC m G f'. Adjust the interval below.
(defun my/org-gcal-fetch-safe ()
  "Background-fetch Google Calendar if org-gcal is configured."
  (when (and (require 'org-gcal nil t) (bound-and-true-p org-gcal-client-id))
    (org-gcal-fetch)))
(defvar my/org-gcal-fetch-timer nil "Repeating timer for background Google Calendar fetch.")
(when (timerp my/org-gcal-fetch-timer) (cancel-timer my/org-gcal-fetch-timer))
(setq my/org-gcal-fetch-timer
      (run-at-time 90 (* 30 60) #'my/org-gcal-fetch-safe))


;; Whenever you reconfigure a package, make sure to wrap your config in an
;; `after!' block, otherwise Doom's defaults may override your settings. E.g.
;;
;;   (after! PACKAGE
;;     (setq x y))
;;
;; The exceptions to this rule:
;;
;;   - Setting file/directory variables (like `org-directory')
;;   - Setting variables which explicitly tell you to set them before their
;;     package is loaded (see 'C-h v VARIABLE' to look up their documentation).
;;   - Setting doom variables (which start with 'doom-' or '+').
;;
;; Here are some additional functions/macros that will help you configure Doom.
;;
;; - `load!' for loading external *.el files relative to this one
;; - `use-package!' for configuring packages
;; - `after!' for running code after a package has loaded
;; - `add-load-path!' for adding directories to the `load-path', relative to
;;   this file. Emacs searches the `load-path' when you load packages with
;;   `require' or `use-package'.
;; - `map!' for binding new keys
;;
;; To get information about any of these functions/macros, move the cursor over
;; the highlighted symbol at press 'K' (non-evil users must press 'C-c c k').
;; This will open documentation for it, including demos of how they are used.
;; Alternatively, use `C-h o' to look up a symbol (functions, variables, faces,
;; etc).
;;
;; You can also try 'gd' (or 'C-c c d') to jump to their definition and see how
;; they are implemented.
