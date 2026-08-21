;;; early-init.el --- pre-init, pre-package, pre-native-compile -*- lexical-binding: t; -*-

;; Runs before package.el initialises and before the first frame is created.
;; Everything here is either a redirect that MUST happen before something else
;; computes a path, or a frame setting that MUST happen before a frame exists.
;;
;; NOTE for Emacs 31: site-start.el is loaded BEFORE early-init.el there, which
;; is the reverse of 30.x.  Under Nix that is an improvement -- load-path and
;; native-comp-eln-load-path are already correct when this file runs -- but do
;; not add code here that assumes it goes first.

;;; Code:

;; --- 1. Native compilation cache ------------------------------------------
;;
;; Every package in this config is byte- AND native-compiled by nixpkgs at
;; build time (the emacs build-support runs batch-native-compile over every
;; .el), and the wrapper exports EMACSNATIVELOADPATH.  So no PACKAGE is ever
;; JIT-compiled.  What does get JIT-compiled is our own lisp/*.el, and its
;; default target is inside user-emacs-directory -- which is a read-only Nix
;; store path here.  Redirect it or every startup writes an error.
;;
;; startup-redirect-eln-cache replaces only the FIRST, writable entry of
;; native-comp-eln-load-path and leaves the store entries behind it intact.
;; Never `setq' native-comp-eln-load-path directly: that drops the store paths
;; and forces a full recompile of everything nixpkgs already compiled.
(when (fboundp 'startup-redirect-eln-cache)
  (startup-redirect-eln-cache
   (expand-file-name "emacs/eln-cache/"
                     (or (getenv "XDG_CACHE_HOME") "~/.cache/"))))
(setq native-comp-async-report-warnings-errors 'silent)

;; --- 2. Package management is Nix's job -----------------------------------
;;
;; package.el must never initialise, never touch the network, and never create
;; an elpa/ directory inside the read-only config.  use-package-always-ensure
;; already defaults to nil in Emacs 29+, so `:ensure nil' on every form is
;; redundant; the ensure-function override below makes a stray `:ensure t'
;; inert rather than a network fetch.
(setq package-enable-at-startup nil)
(setq use-package-always-ensure nil)
(setq use-package-ensure-function #'ignore)

;; Defer by default.  The win is not `:defer' itself, it is never letting
;; use-package emit an implicit `require': a form with `:config' and no
;; autoload keyword IS a require.  Packages that genuinely must load eagerly
;; say `:demand t'.
;;
;; WHAT MAKES DEFERRAL WORK HERE IS use-package, NOT NIX.  It is tempting to
;; assume the generated autoloads in the Nix closure leave every command
;; reachable for free.  They do not, because `package-enable-at-startup' is nil
;; directly above: startup.el gates `package-activate-all' on it, and without
;; that call nothing loads a single autoload file.  Measured in this build:
;;
;;   package-enable-at-startup nil -> 0 packages activated; magit-status,
;;                                    vundo, avy-goto-char-timer,
;;                                    evil-org-mode and org-gcal-sync are all
;;                                    unbound
;;   (package-activate-all)        -> 58 activated, all of them bound
;;
;; So every reachable command here is reachable because a `use-package' form
;; named it in `:commands', `:hook', `:mode', `:bind' or `:after' -- those are
;; what emit the autoload stubs.  THE RULE THAT FOLLOWS: a package with none of
;; those keywords and no `:demand t' is not lazy, it is ABSENT, and it fails as
;; "void-function", not as "package missing".  It bites hardest on language
;; modes, whose packaged `auto-mode-alist' entries never register either, so
;; `:mode' has to be spelled out.
;;
;; Re-enabling package.el activation is not the fix: it would scan and activate
;; all 58 at startup, which is the cost being avoided, and it would want an
;; elpa/ directory inside the read-only config.
(setq use-package-always-defer t)

;; --- 3. Frame settings, before the first frame ----------------------------
;;
;; Set these via default-frame-alist rather than calling (menu-bar-mode -1):
;; the frame is then never built with them, instead of built and then resized.
;; frame-inhibit-implied-resize is the single biggest startup win available --
;; without it every font/UI change can trigger a window-system resize round
;; trip.
(setq frame-inhibit-implied-resize t)
(push '(menu-bar-lines . 0) default-frame-alist)
(push '(tool-bar-lines . 0) default-frame-alist)
(push '(vertical-scroll-bars) default-frame-alist)
(setq inhibit-startup-screen t
      inhibit-startup-echo-area-message user-login-name
      initial-scratch-message nil)

;; --- 4. Startup GC ---------------------------------------------------------
;;
;; Raised for startup only and restored on emacs-startup-hook.  Deliberately
;; NOT most-positive-fixnum: a threshold that large defers collection until the
;; first GC is enormous and visibly stutters.  Restored to a modest steady-state
;; value rather than the 800k default, which is far too small for a modern
;; session.
(setq gc-cons-threshold (* 64 1024 1024)
      gc-cons-percentage 0.6)
(add-hook 'emacs-startup-hook
          (lambda ()
            (setq gc-cons-threshold (* 32 1024 1024)
                  gc-cons-percentage 0.2)))

;; --- 5. Writable state, out of the read-only config directory -------------
;;
;; no-littering retargets recentf, savehist, bookmark, project, transient, url,
;; tramp, eshell, backups and auto-save.  These two variables must be set
;; before it loads, which is why they are here rather than in init.el.
(setq no-littering-etc-directory
      (expand-file-name "emacs/" (or (getenv "XDG_STATE_HOME") "~/.local/state/")))
(setq no-littering-var-directory
      (expand-file-name "emacs/" (or (getenv "XDG_CACHE_HOME") "~/.cache/")))
(setq custom-file (expand-file-name "custom.el" no-littering-etc-directory))

;; NOT set: site-run-file.  Disabling it is actively wrong under Nix -- the
;; nixpkgs site-start.el is what builds load-path from NIX_PROFILES, extends
;; native-comp-eln-load-path, and sets tramp-remote-path and INFOPATH.

(provide 'early-init)
;;; early-init.el ends here
