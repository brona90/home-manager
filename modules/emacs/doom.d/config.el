;;; $DOOMDIR/config.el -*- lexical-binding: t; -*-

;; Place your private configuration here! Remember, you do not need to run 'doom
;; sync' after modifying this file!

(require 'cl-lib)

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
  ;; claude-code-run and friends call projectile-project-root, which returns
  ;; nil from non-project buffers (*scratch*, etc.), causing "stringp, nil".
  ;; Advise normalize-project-root (the single choke-point in claude-code-core)
  ;; to fall back to default-directory.
  (define-advice claude-code-normalize-project-root (:filter-return (root) fallback-dir)
    (or root (directory-file-name default-directory)))
  ;; Open Claude Code in bottom third of the frame.
  ;; Doom's popup manager overrides display-buffer-alist, so use set-popup-rule!
  (set-popup-rule! "^\\*claude:"
    :side 'bottom
    :height 0.33
    :select nil
    :quit nil
    :ttl nil
    :modeline t)
  ;; Load 2-way diff review (claude-diff.el)
  (load! "claude-diff")
  ;; Diff review keybindings under the same SPC l prefix
  (map! :leader
        (:prefix "l"
         :desc "Approve changes"    "a" #'claude-diff-approve
         :desc "Deny changes"       "x" #'claude-diff-deny
         :desc "Dismiss diff"       "D" #'claude-diff-dismiss
         :desc "Next change"        "n" #'claude-diff-next-change
         :desc "Prev change"        "p" #'claude-diff-prev-change
         :desc "Scroll diff up"     "j" #'claude-diff-scroll-up
         :desc "Scroll diff down"   "k" #'claude-diff-scroll-down)))

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
