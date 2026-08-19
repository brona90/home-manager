;;; init.el --- vanilla Emacs, hand-built -*- lexical-binding: t; -*-

;; Phase 1 scaffold.  Deliberately small: enough to open files, complete, edit
;; with evil, and run magit -- so that `emacsclient -s vanilla' is a real editor
;; and the daemon/socket plumbing can be tested.  Org, gcal, LilyPond and the
;; Claude integration land in later phases and are NOT here yet; Doom remains
;; the daily driver until they are.
;;
;; FLOOR: Emacs 30.  Linux gets emacs-unstable (31.x) and both Macs get 30.2,
;; because emacs-overlay publishes no darwin binaries and building 31 from
;; source there is an hour on the least-tested stdenv.  So anything 31-only
;; will build fine and then fail on the Macs -- keep to 30 APIs until the Intel
;; Mac question is resolved.
;;
;; Packages come from Nix (see ../package.nix).  Nothing here may fetch.

;;; Code:

(when (< emacs-major-version 30)
  (error "This config targets Emacs 30+; running %s" emacs-version))

(add-to-list 'load-path (expand-file-name "lisp" user-emacs-directory))

;; no-littering must load before the packages whose paths it retargets.
;; Its two directory variables are set in early-init.el.
(require 'no-littering)
(no-littering-theme-backups)
(load custom-file :noerror :nomessage)

(require 'use-package)

;; --- Emacs itself ----------------------------------------------------------

(use-package emacs
  :demand t
  :init
  (setq enable-recursive-minibuffers t
        read-extended-command-predicate #'command-completion-default-include-p
        minibuffer-prompt-properties
        '(read-only t cursor-intangible t face minibuffer-prompt)
        ;; TAB completes when already indented -- the hook corfu needs.
        tab-always-indent 'complete
        ;; Emacs 30: drop the ispell capf out of text modes.  It queries the
        ;; spell process on every completion and is rarely what is wanted.
        text-mode-ispell-word-completion nil
        sentence-end-double-space nil
        require-final-newline t
        create-lockfiles nil
        use-short-answers t
        ring-bell-function #'ignore
        ;; TRAMP hosts must not be able to hang session restore.
        remote-file-name-access-timeout 5)
  (setq-default indent-tabs-mode nil
                fill-column 80)
  :config
  (savehist-mode 1)          ; load-bearing: vertico sorts by history position
  (recentf-mode 1)
  (save-place-mode 1)
  (global-so-long-mode 1)    ; off by default; long lines otherwise wedge Emacs
  (repeat-mode 1)
  (electric-pair-mode 1)
  (show-paren-mode 1)
  (column-number-mode 1)
  (which-key-mode 1)         ; built in since Emacs 30 -- no package needed
  (setq display-line-numbers-type t)
  (add-hook 'prog-mode-hook #'display-line-numbers-mode))

;; --- Appearance ------------------------------------------------------------
;;
;; The font is applied twice on purpose.  This is a DAEMON: at init there is no
;; frame, so set-face-attribute alone applies to nothing, and every frame made
;; later by emacsclient needs it again.  Doom papered over this by re-applying
;; `doom-font' per frame; there is no vanilla equivalent, so we do it by hand.
(defconst my/font-family "VictorMono Nerd Font")
(defconst my/font-height 180)           ; 1/10 pt, i.e. Doom's :size 18

(defun my/apply-font (&optional frame)
  "Apply the default face to FRAME, or to the current frame."
  (when (display-graphic-p frame)
    (set-face-attribute 'default frame
                        :family my/font-family :height my/font-height)))

(add-to-list 'default-frame-alist
             (cons 'font (format "%s-%d" my/font-family (/ my/font-height 10))))
(add-hook 'after-make-frame-functions #'my/apply-font)
(my/apply-font)

(setq nerd-icons-font-family "Symbols Nerd Font Mono")

;; Italic syntax faces, re-applied on every theme load.
;;
;; Doom's `custom-set-faces!' hooked doom-customize-theme-hook, which is the
;; ONLY reason these survived `load-theme' running afterwards.  Emacs 29+
;; `enable-theme-functions' is the exact analogue.  Without it a naive port
;; silently loses the italics the moment the theme loads.
(defun my/italicize-syntax-faces (&optional _theme)
  "Italicise comment, keyword, string and docstring faces."
  (dolist (face '(font-lock-comment-face
                  font-lock-keyword-face
                  font-lock-string-face
                  font-lock-doc-face))
    (set-face-attribute face nil :slant 'italic)))
(add-hook 'enable-theme-functions #'my/italicize-syntax-faces)

(use-package doom-themes
  :demand t
  :config
  (load-theme 'doom-gruvbox t)
  (my/italicize-syntax-faces))

(use-package doom-modeline
  :demand t
  :config (doom-modeline-mode 1))

(use-package rainbow-delimiters
  :hook (prog-mode . rainbow-delimiters-mode))

(use-package hl-todo
  :demand t
  :config (global-hl-todo-mode 1))

;; --- Completion ------------------------------------------------------------

(use-package vertico
  :demand t
  :config (vertico-mode 1))

(use-package orderless
  :demand t
  :init
  ;; completion-category-defaults must be nil.  Packages -- eglot among them --
  ;; append their own category defaults at load time, and those silently
  ;; override completion-styles.  This is why "orderless does nothing in my LSP
  ;; buffers" is the perennial bug report.
  (setq completion-styles '(orderless basic)
        completion-category-overrides '((file (styles partial-completion)))
        completion-category-defaults nil))

(use-package marginalia
  :demand t
  :config (marginalia-mode 1))

(use-package consult
  :demand t
  :init
  (setq register-preview-delay 0.5
        register-preview-function #'consult-register-format
        xref-show-xrefs-function #'consult-xref
        xref-show-definitions-function #'consult-xref
        completion-in-region-function #'consult-completion-in-region)
  :config
  ;; Default preview-key is 'any: every candidate change opens a file.  For the
  ;; file-touching commands that means one visit per keystroke, so debounce
  ;; them.  NOTE: wrapping any of these in your own command means adding YOUR
  ;; command here too -- consult-customize keys on the command symbol.
  (consult-customize
   consult-ripgrep consult-git-grep consult-grep
   consult-bookmark consult-recent-file consult-xref
   :preview-key '(:debounce 0.4 any)))

(use-package embark
  :demand t
  :init (setq prefix-help-command #'embark-prefix-help-command))

(use-package embark-consult
  :demand t
  :after (embark consult))

(use-package corfu
  :demand t
  :init
  ;; Manual completion, on TAB, rather than an auto-popup: with orderless in
  ;; play an auto-popup fires on nearly every keystroke.  Ambient hinting comes
  ;; from completion-preview-mode below instead.
  (setq corfu-auto nil
        corfu-cycle t
        corfu-quit-no-match 'separator)
  :config (global-corfu-mode 1))

(use-package cape
  :demand t
  :init
  (add-hook 'completion-at-point-functions #'cape-file)
  (add-hook 'completion-at-point-functions #'cape-dabbrev))

;; Built in since Emacs 30: one inline greyed candidate.  Complements corfu
;; (ranked popup, on demand) rather than replacing it.
(when (fboundp 'global-completion-preview-mode)
  (global-completion-preview-mode 1))

;; --- Modal editing ---------------------------------------------------------

(use-package evil
  :demand t
  :init
  ;; These must be set BEFORE evil loads.  Values copied from Doom's evil
  ;; module so the muscle memory carries over unchanged.
  (setq evil-want-keybinding nil        ; required by evil-collection
        evil-want-C-g-bindings t
        evil-want-C-i-jump nil
        evil-want-C-u-scroll t
        evil-want-C-u-delete t
        evil-want-C-w-delete t
        evil-want-Y-yank-to-eol t
        evil-respect-visual-line-mode nil
        evil-undo-system 'undo-redo     ; built in since Emacs 28
        evil-symbol-word-search t
        evil-ex-search-vim-style-regexp t
        evil-ex-visual-char-range t
        evil-ex-interactive-search-highlight 'selected-window
        evil-kbd-macro-suppress-motion-error t
        evil-mode-line-format nil)
  :config
  (evil-select-search-module 'evil-search-module 'evil-search)
  (evil-mode 1))

(use-package evil-collection
  :demand t
  :after evil
  :config (evil-collection-init))

(use-package evil-surround
  :demand t
  :after evil
  :config (global-evil-surround-mode 1))

;; --- Leader ----------------------------------------------------------------
;;
;; general.el rather than evil's own `evil-set-leader'.  The difference is not
;; syntax: evil's auxiliary keymaps outrank the global state maps, and
;; evil-collection binds SPC in many read-only modes (magit, dired, help, info,
;; pdf-view).  A plain evil-set-leader leader is therefore shadowed in exactly
;; the buffers a Doom user expects it to work in.  `:keymaps 'override' is a
;; pre-built evil INTERCEPT map, which outranks those.
(use-package general
  :demand t
  :init
  (setq general-override-states
        '(insert emacs hybrid normal visual motion operator replace))
  :config
  (general-create-definer my/leader
    :states '(normal insert visual motion emacs)
    :keymaps 'override
    :prefix "SPC"
    :global-prefix "C-SPC")             ; reachable from insert/emacs state

  (general-create-definer my/local-leader
    :states '(normal insert visual motion emacs)
    :keymaps 'override
    :prefix "SPC m"
    :global-prefix "C-SPC m")

  ;; Doom's most-used leader keys.  Deliberately a small set: the rest get
  ;; added as they are actually missed, rather than transcribing 2500 lines of
  ;; +bindings speculatively.
  (my/leader
    "."   #'find-file
    ","   #'consult-buffer
    "SPC" #'project-find-file
    "/"   #'consult-ripgrep
    ":"   #'execute-extended-command
    "RET" #'consult-bookmark
    "u"   #'universal-argument
    "a"   #'embark-act
    "x"   #'scratch-buffer               ; built in since Emacs 29
    "w"   '(:keymap evil-window-map :which-key "window")
    "h"   '(:keymap help-map           :which-key "help")
    "b"   '(:ignore t :which-key "buffer")
    "bb"  #'consult-buffer
    "bk"  #'kill-current-buffer
    "bs"  #'save-buffer
    "f"   '(:ignore t :which-key "file")
    "ff"  #'find-file
    "fr"  #'consult-recent-file
    "fs"  #'save-buffer
    "g"   '(:ignore t :which-key "git")
    "gg"  #'magit-status
    "p"   '(:keymap project-prefix-map :which-key "project")
    "s"   '(:ignore t :which-key "search")
    "ss"  #'consult-line
    "si"  #'consult-imenu
    "su"  #'vundo
    "q"   '(:ignore t :which-key "quit")
    "qq"  #'save-buffers-kill-terminal
    "qr"  #'restart-emacs))              ; built in since Emacs 29

;; --- Version control -------------------------------------------------------

(use-package magit
  :commands (magit-status magit-dispatch)
  :init (setq magit-define-global-key-bindings nil))

(use-package forge :after magit)

(use-package diff-hl
  :demand t
  :config
  (global-diff-hl-mode 1)
  (add-hook 'magit-pre-refresh-hook  #'diff-hl-magit-pre-refresh)
  (add-hook 'magit-post-refresh-hook #'diff-hl-magit-post-refresh))

;; --- Editing / navigation --------------------------------------------------

(use-package vundo :commands (vundo))
(use-package avy   :commands (avy-goto-char-timer avy-goto-line))

(use-package envrc
  :demand t
  :config (envrc-global-mode 1))

(use-package ws-butler
  :hook (prog-mode . ws-butler-mode))

;; --- Direnv-provided tooling ----------------------------------------------
;; eglot, treesit, project.el and flymake are all built in; language setup
;; lands in a later phase alongside the ts-mode remapping.

(provide 'init)
;;; init.el ends here
