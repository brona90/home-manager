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
(package! org-gcal)              ; Two-way sync between org files and Google Calendar
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

;;; Disabled module packages
;; android-mode ships with Doom's `:lang java` module but is only useful for
;; Android development (SDK/emulator integration), which we don't do. Its source
;; lives on codeberg.org, which intermittently 504s during the Darwin CI eval —
;; nix-doom-emacs-unstraightened fetches every source uncached via IFD
;; (allowSubstitutes = false), so a transient codeberg outage breaks the build.
;; Disabling it removes that dependency without affecting JDT/Java LSP.
(package! android-mode :disable t)

;;; Themes and UI
(package! rainbow-delimiters)    ; Color-coded parentheses
