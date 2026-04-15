;; -*- no-byte-compile: t; -*-

;;; Development
(package! nix-ts-mode)
(package! nixfmt)
(package! ob-nix)
(package! nix-mode)              ; Nix language support
(package! forge)                 ; GitHub/GitLab integration for magit
(package! claude-code :recipe (:host github :repo "stevemolitor/claude-code.el"))

;;; Productivity
(package! org-roam)              ; Zettelkasten note-taking
(package! org-journal)           ; Daily journaling
(package! org-drawio)
(package! deft)                  ; Quick note search (ui/deft module disabled in init.el)

;;; Editing enhancements
(package! multiple-cursors)      ; Edit multiple locations at once (module disabled in init.el)
(package! expand-region)         ; Smart region selection
(package! string-inflection)     ; Convert between snake_case, camelCase, etc.
(package! undo-tree)             ; Visual undo history

;;; Language support
(package! toml-mode)             ; TOML files
(package! web-mode)              ; HTML/CSS/JS (lang/web module disabled in init.el)
(package! dockerfile-mode)       ; Dockerfiles

;;; Themes and UI
(package! rainbow-delimiters)    ; Color-coded parentheses
