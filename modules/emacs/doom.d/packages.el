;; -*- no-byte-compile: t; -*-

;;; Development
(package! nix-ts-mode)
(package! nixfmt)
(package! ob-nix)
(package! nix-mode)              ; Nix language support
(package! forge)                 ; GitHub/GitLab integration for magit
;; NOT stevemolitor/claude-code.el, whatever a :recipe here would say.
;; nix-doom-emacs-unstraightened IGNORES :recipe and resolves the name against
;; emacs-overlay's MELPA set, where `claude-code' is yuya373/claude-code-emacs.
;; That is what the daemon has always loaded -- verified: the running Emacs
;; reports claude-code-20260812.1216 with "Author: Yuya Minami", and
;; `claude-code-normalize-project-root' (advised in config.el) exists only in
;; yuya373's claude-code-core.el. The old :recipe was decoration that described
;; a package this config has never run; it is removed rather than corrected so
;; nobody "fixes" the code to match it.
(package! claude-code)

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

;; org-pdftools ships with Doom's `:lang org` module (org+pdf-tools link
;; integration). Emacs 30.2 ABORTS while native-compiling it on aarch64-darwin:
;; the compile subprocess dies with SIGABRT and nixpkgs' elisp builder surfaces
;; that as `Wrong type argument: number-or-marker-p, "Abort trap: 6"` -- it tried
;; to use the crash message as an exit code. The failure cascades all the way up
;; (org-pdftools -> emacs-with-packages -> doom-emacs -> home-manager-generation),
;; so both Macs cannot build at all.
;;
;; It appeared with the 2026-08-19 flake.lock bump and is deterministic, not a
;; flaky runner: it failed identically in the CI and Validate runs. Nothing in
;; this config references org-pdftools -- it arrives only via the module -- and
;; pdf-tools itself (`:tools pdf`) is unaffected, so disabling costs only the
;; org-link-to-a-PDF-page integration.
;;
;; Deliberately a disable rather than a lock revert: the bump also carried the
;; nixpkgs 26.11 move that the x86_64-darwin pin exists to absorb, and reverting
;; it would undo a working automated update to dodge one broken package.
(package! org-pdftools :disable t)

;;; Themes and UI
(package! rainbow-delimiters)    ; Color-coded parentheses
