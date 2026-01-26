;; -*- no-byte-compile: t; -*-

;;; Development
(package! nix-ts-mode)
(package! nixfmt)
(package! ob-nix)
(package! nix-mode)              ; Nix language support
(package! magit)                 ; Git porcelain (usually already in Doom)
(package! git-gutter)            ; Show git diff in gutter
(package! forge)                 ; GitHub/GitLab integration for magit

;;; Productivity
(package! org-roam)              ; Zettelkasten note-taking
(package! org-journal)           ; Daily journaling
(package! org-drawio)
(package! deft)                  ; Quick note search
(package! pdf-tools)             ; Better PDF viewing

;;; Editing enhancements
(package! multiple-cursors)      ; Edit multiple locations at once
(package! expand-region)         ; Smart region selection
(package! string-inflection)     ; Convert between snake_case, camelCase, etc.
(package! undo-tree)             ; Visual undo history

;;; Language support
(package! yaml-mode)             ; YAML files
(package! toml-mode)             ; TOML files
(package! markdown-mode)         ; Markdown
(package! web-mode)              ; HTML/CSS/JS
(package! dockerfile-mode)       ; Dockerfiles

;;; Themes and UI
(package! doom-themes)           ; Already included, but good to list
(package! all-the-icons)         ; Icons (already in Doom)
(package! rainbow-delimiters)    ; Color-coded parentheses

;;; Utilities
(package! which-key)             ; Show available keybindings (already in Doom)
(package! company)               ; Completion framework (already in Doom)
(package! projectile)            ; Project management (already in Doom)
