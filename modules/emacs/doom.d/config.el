;;; $DOOMDIR/config.el -*- lexical-binding: t; -*-

;; Place your private configuration here! Remember, you do not need to run 'doom
;; sync' after modifying this file!

;; LilyPond mode setup - load from system installation
(when-let ((lily-bin (executable-find "lilypond")))
  (let* ((lily-dir (file-name-directory lily-bin))
         ;; Try common elisp locations relative to bin
         (elisp-paths (list
                       (expand-file-name "../share/emacs/site-lisp" lily-dir)
                       (expand-file-name "../share/lilypond/current/elisp" lily-dir)
                       (expand-file-name "../share/lilypond/2.24.4/elisp" lily-dir))))
    (dolist (path elisp-paths)
      (when (file-directory-p path)
        (add-to-list 'load-path path))))
  
  ;; Load lilypond-mode
  (require 'lilypond-mode nil t)
  
  (with-eval-after-load 'lilypond-mode
    (add-to-list 'auto-mode-alist '("\\.ly\\'" . LilyPond-mode))
    (add-to-list 'auto-mode-alist '("\\.ily\\'" . LilyPond-mode))
    
    ;; Flycheck integration
    (after! flycheck
      (flycheck-define-checker lilypond
        "A LilyPond syntax checker."
        :command ("lilypond" "-dno-print-pages" "-o" temporary-file-name source)
        :error-patterns
        ((error line-start (file-name) ":" line ":" column ": error: " (message) line-end)
         (warning line-start (file-name) ":" line ":" column ": warning: " (message) line-end))
        :modes LilyPond-mode)
      (add-to-list 'flycheck-checkers 'lilypond))))

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

;; Claude Code: AI-assisted coding via Claude CLI in vterm
(use-package! claude-code
  :init
  (map! :leader
        (:prefix ("l" . "claude")
         :desc "Start Claude"   "l" #'claude-code-run
         :desc "Send region"    "r" #'claude-code-send-region
         :desc "Switch buffer"  "b" #'claude-code-switch-to-buffer
         :desc "Menu"           "m" #'claude-code-transient))
  :config
  ;; Open Claude Code in bottom third of the frame.
  ;; Doom's popup manager overrides display-buffer-alist, so use set-popup-rule!
  (set-popup-rule! "^\\*claude:"
    :side 'bottom
    :height 0.33
    :select nil
    :quit nil
    :ttl nil
    :modeline t))

;; ──────────────────────────────────────────────────────────────────
;; Claude Code 3-way diff: git HEAD vs your working copy vs Claude's edit
;; ──────────────────────────────────────────────────────────────────
(defvar claude-diff--snapshots (make-hash-table :test #'equal)
  "Hash table mapping absolute file paths to their pre-edit content.")

(defvar claude-diff--watchers nil
  "List of active file-notify descriptors.")

(defvar claude-diff--active nil
  "Non-nil when Claude Code file watching is active.")

(defvar claude-diff--pending-diffs (make-hash-table :test #'equal)
  "Files with pending diffs waiting for review.")

(defun claude-diff--git-root ()
  "Return the git repository root for the current project."
  (string-trim (shell-command-to-string "git rev-parse --show-toplevel")))

(defun claude-diff--git-head-content (file)
  "Return the content of FILE at git HEAD, or nil if untracked."
  (let* ((root (claude-diff--git-root))
         (rel (file-relative-name file root))
         (out (with-temp-buffer
                (let ((exit-code (call-process "git" nil t nil "show" (concat "HEAD:" rel))))
                  (when (zerop exit-code)
                    (buffer-string))))))
    out))

(defun claude-diff--snapshot-file (file)
  "Save the current content of FILE into the snapshot table."
  (when (and (file-exists-p file) (not (file-directory-p file)))
    (with-temp-buffer
      (insert-file-contents file)
      (puthash file (buffer-string) claude-diff--snapshots))))

(defun claude-diff--snapshot-tracked-files ()
  "Snapshot all git-tracked files in the current project."
  (let* ((root (claude-diff--git-root))
         (files (split-string
                 (shell-command-to-string "git ls-files --full-name") "\n" t)))
    (dolist (rel files)
      (claude-diff--snapshot-file (expand-file-name rel root)))))

(defun claude-diff--make-temp-buffer (name content)
  "Create a temporary buffer named NAME with CONTENT."
  (let ((buf (generate-new-buffer name)))
    (with-current-buffer buf
      (insert (or content ""))
      (set-buffer-modified-p nil)
      (setq buffer-read-only t))
    buf))

(defun claude-diff--review-file (file)
  "Show 3-way ediff for FILE: git HEAD vs pre-edit snapshot vs Claude's version."
  (let* ((head-content (claude-diff--git-head-content file))
         (snap-content (gethash file claude-diff--snapshots))
         (basename (file-name-nondirectory file))
         (buf-head (claude-diff--make-temp-buffer
                    (format "*HEAD: %s*" basename)
                    head-content))
         (buf-snap (claude-diff--make-temp-buffer
                    (format "*pre-edit: %s*" basename)
                    snap-content))
         (buf-claude (find-file-noselect file t)))
    ;; Revert to pick up Claude's disk changes
    (with-current-buffer buf-claude
      (revert-buffer t t t))
    (if (and head-content snap-content)
        (ediff-buffers3 buf-head buf-snap buf-claude)
      ;; Fall back to 2-way if no HEAD or no snapshot
      (ediff-buffers (or buf-snap buf-head) buf-claude))))

(defun claude-diff--on-file-change (_event-or-file)
  "Handle a file change event from file-notify or direct call."
  (let* ((file (if (stringp _event-or-file)
                   _event-or-file
                 ;; file-notify event: (DESCRIPTOR ACTION FILE [FILE1])
                 (nth 2 _event-or-file)))
         (action (if (stringp _event-or-file) 'changed (nth 1 _event-or-file))))
    (when (and file
               claude-diff--active
               (memq action '(changed created))
               (file-exists-p file)
               (not (file-directory-p file))
               ;; Only trigger for files we snapshotted
               (gethash file claude-diff--snapshots)
               ;; Skip if content is actually the same
               (not (string= (gethash file claude-diff--snapshots)
                              (with-temp-buffer
                                (insert-file-contents file)
                                (buffer-string)))))
      (puthash file t claude-diff--pending-diffs)
      (message "Claude edited %s — review with SPC l d" (file-name-nondirectory file))
      ;; Auto-pop the diff
      (claude-diff--review-file file)
      ;; Update snapshot to the new content so we don't re-trigger
      (claude-diff--snapshot-file file))))

(defun claude-diff--watch-directory (dir)
  "Set up recursive file watching on DIR."
  (when (file-directory-p dir)
    ;; Watch the directory itself
    (condition-case nil
        (push (file-notify-add-watch dir '(change) #'claude-diff--on-file-change)
              claude-diff--watchers)
      (error nil))
    ;; Watch subdirectories (non-hidden, skip .git)
    (dolist (entry (directory-files dir t))
      (when (and (file-directory-p entry)
                 (not (string-match-p "/\\." (file-name-nondirectory entry))))
        (claude-diff--watch-directory entry)))))

(defun claude-diff-start ()
  "Start watching for Claude Code file edits. Snapshots all tracked files."
  (interactive)
  (claude-diff-stop)
  (claude-diff--snapshot-tracked-files)
  (claude-diff--watch-directory (claude-diff--git-root))
  (setq claude-diff--active t)
  (message "Claude diff watcher active — monitoring %d files"
           (hash-table-count claude-diff--snapshots)))

(defun claude-diff-stop ()
  "Stop watching for file edits and clean up."
  (interactive)
  (dolist (w claude-diff--watchers)
    (ignore-errors (file-notify-rm-watch w)))
  (setq claude-diff--watchers nil
        claude-diff--active nil)
  (clrhash claude-diff--snapshots)
  (clrhash claude-diff--pending-diffs)
  (message "Claude diff watcher stopped."))

(defun claude-diff-review-pending ()
  "Review all pending Claude edits one by one."
  (interactive)
  (let ((files (hash-table-keys claude-diff--pending-diffs)))
    (if (null files)
        (message "No pending Claude diffs to review.")
      (dolist (file files)
        (claude-diff--review-file file)
        (remhash file claude-diff--pending-diffs)))))

;; Auto-start watcher when Claude Code launches
(advice-add 'claude-code-run :after
            (lambda (&rest _)
              (unless claude-diff--active
                (claude-diff-start))))

;; Keybindings under the existing SPC l prefix
(map! :leader
      (:prefix ("l" . "claude")
       :desc "Diff watcher on"    "w" #'claude-diff-start
       :desc "Diff watcher off"   "W" #'claude-diff-stop
       :desc "Review pending"     "d" #'claude-diff-review-pending))

;; This determines the style of line numbers in effect. If set to `nil', line
;; numbers are disabled. For relative line numbers, set this to `relative'.
(setq display-line-numbers-type t)

;; If you use `org' and don't want your org files in the default location below,
;; change `org-directory'. It must be set before org loads!
(setq org-directory "~/org/")


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
