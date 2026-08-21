;;; my-claude.el --- Claude Code: the vterm session and the diff review -*- lexical-binding: t; -*-

;;; Commentary:

;; Two halves that are deliberately independent:
;;
;;   claude-diff.el   the 2-way before/after review, driven by the
;;                    PermissionRequest and PostToolUse hooks in
;;                    modules/claude-code.nix.  LOADED EAGERLY.
;;   claude-code      yuya373/claude-code-emacs -- Claude itself, running in a
;;                    vterm.  Deferred behind `:commands'.
;;
;; WHY claude-diff IS EAGER AND claude-code IS NOT.  The PermissionRequest hook
;; runs
;;
;;   emacsclient -s "$EMACS_SOCKET_NAME" --eval "(claude-diff-from-hook \"...\")"
;;
;; and `--eval' does NOT trigger an autoload for a function that has no stub --
;; it fails with `void-function'.  The hook has to work when Claude is running
;; in a plain vterm, in a tmux pane, or in a terminal that is not this Emacs at
;; all, i.e. when claude-code.el has never been loaded and never will be.  So
;; the review side is required outright; the session side, which nothing but a
;; keypress ever reaches, stays deferred like everything else in this config.
;;
;; THE SOCKET.  `EMACS_SOCKET_NAME' in that command line comes from the systemd
;; unit -- see modules/emacs/default.nix.  Emacs never exports it to
;; subprocesses (it is read by the emacsclient BINARY), so with two daemons
;; running, a hook fired from a vterm in THIS one would otherwise reach the
;; daily driver instead.
;;
;; THE WINDOW RULE IS THE BUG FIX, AND IT IS ONE OF TWO HALVES.
;;
;; `claude-diff--show-1' calls `delete-other-windows' with no argument, and
;; window.el:4381 signals
;;
;;   "Cannot make side window the only window"
;;
;; when the SELECTED window is a side window -- which it is every time the hook
;; fires while the user is sitting in the Claude popup.  In Doom this never
;; surfaced because the +popup module installs a `delete-other-windows' WINDOW
;; PARAMETER on every popup and window.el calls that instead of signalling.
;;
;; Emacs 30 offers three answers.  TWO OF THEM ARE TAKEN, and which does what
;; matters, because they fix different halves of the problem:
;;
;;   (a) THE CALLER, fixed in claude-diff.el: `claude-diff--select-main-window'
;;       selects `window-main-window' -- the frame's non-side area -- before
;;       deleting.  That makes the call legal WHEREVER the hook fired from,
;;       including from side windows that have nothing to do with Claude.  This
;;       config already has one of those in normal use: `which-key-popup-type'
;;       is `side-window'.  A rule about the Claude buffer could never have
;;       covered that.
;;
;;   (b) THE BUFFER, fixed here: `display-buffer-at-bottom' makes an ORDINARY
;;       window with no `window-side' parameter.  This is not redundant with
;;       (a) -- it is what makes the LAYOUT ALGORITHM correct.  Read
;;       `claude-diff--show-1': it deliberately clears the frame and then
;;       rebuilds three panes, Before | After across the top two thirds and the
;;       Claude buffer in the bottom third, restoring the user's real layout
;;       from `claude-diff--saved-wconf' on dismiss.  That only works if the
;;       Claude window is DELETABLE.
;;
;;   (c) NOT TAKEN: `(window-parameters . ((no-delete-other-windows . t)))' on
;;       a side window, so that `delete-other-windows' leaves the Claude window
;;       standing (window.el:4387-4402).  It is the most interesting of the
;;       three and it is worth writing down why it lost, because it will be
;;       proposed again:
;;
;;         * It is not a drop-in.  With the Claude window surviving,
;;           `claude-diff--show-1' still runs its `(split-window root
;;           (- vterm-height) 'below)' and `(set-window-buffer bottom-win
;;           claude-buf)' -- so the Claude buffer would be on screen TWICE, and
;;           the "bottom third" would be a third of the main area rather than of
;;           the frame.  Taking (c) means rewriting the layout code, not adding
;;           a parameter.
;;         * That rewrite cannot be tested from here.  Exercising this path
;;           needs a live Claude session in a vterm inside this daemon and a
;;           real GUI frame; the gate can prove the window is not a side window
;;           and that `delete-other-windows' does not signal, and it can prove
;;           nothing about how the three panes look.  Rewriting layout code on
;;           the one path with no test is where bugs ship.
;;         * And it is a genuinely different design, not a smaller version of
;;           this one: it would mean claude-diff builds a layout AROUND a
;;           persistent Claude side window instead of composing one.  That is a
;;           reasonable thing to want -- `window-toggle-side-windows' is
;;           preloaded and interactive and would give it a free show/hide, which
;;           is Doom's `+popup/toggle' and `+popup/restore' in one command -- but
;;           it is a redesign of claude-diff.el, and it should be done as one,
;;           with a way to see the result.
;;
;; Doom's other popup keywords have no vanilla counterpart and need none:
;; `:quit nil', `:ttl nil' and `:modeline t' are all popup-MANAGER concepts --
;; a manager that can close popups on ESC, reap them on a timer, and swap their
;; mode line.  Vanilla has no such manager and nothing here wants one.
;;
;; PROJECTILE IS A HARD DEPENDENCY AND IT STAYS.  claude-code requires it in 7
;; files; `claude-code-buffer-name' is built from `projectile-project-root' and
;; the MCP tools use `projectile-project-files' and `projectile-project-type',
;; for which project.el has no analogue.  It is never enabled as a mode and it
;; takes no key -- `SPC p' remains project.el's `project-prefix-map'.  This is
;; private plumbing, not a second project system.

;;; Code:

(require 'use-package)

;; Eager -- see the commentary.  This is the file the hook reaches.
(require 'claude-diff)

;; `display-buffer-alist' is consulted by `display-buffer' BEFORE the ACTION
;; argument its caller passed (window.el builds the action list as
;; overriding-action, then the alist match, then ACTION).  That matters here:
;; `claude-code-run' ends in `switch-to-buffer-other-window', which supplies
;; `display-buffer--other-window-action'.  This entry outranks it.
;;
;; `(dedicated . nil)' is written out rather than left implicit because a
;; future reader WILL be tempted to make it t, and `claude-diff--show-1' calls
;; `set-window-buffer' on the window that ends up holding this buffer -- which
;; signals against a window strongly dedicated to something else.
;;
;; `(post-command-select-window . nil)' is Doom's `:select nil'.  The nil is
;; not the same as omitting the entry: window.el looks the key up with `assq',
;; so a present-but-nil entry means "re-select whatever was selected before",
;; undoing the selection `switch-to-buffer-other-window' just made.  Omitting
;; it means "leave the selection wherever it landed".
(add-to-list 'display-buffer-alist
             '("^\\*claude:"
               (display-buffer-reuse-window display-buffer-at-bottom)
               (window-height . 0.33)
               (dedicated . nil)
               (post-command-select-window . nil)))

;; All four commands live in claude-code-core.el and claude-code-ui.el, and
;; claude-code.el `require's both at load time -- so (autoload SYM
;; "claude-code"), which is what `:commands' emits, really does define them.
;; That is the magit case, not the consult case; the consult sub-packages need
;; a form each precisely because nothing `require's them.
(use-package claude-code
  :commands (claude-code-run
             claude-code-send-region
             claude-code-switch-to-buffer
             claude-code-transient)
  :config
  ;; THE DOOM ADVICE, WITH ITS ADVICE-COMBINATOR CHANGED, AND THE CHANGE IS
  ;; THE POINT.
  ;;
  ;; doom.d/config.el has
  ;;
  ;;   (define-advice claude-code-normalize-project-root
  ;;       (:filter-return (root) fallback-dir)
  ;;     (or root (directory-file-name default-directory)))
  ;;
  ;; written against a claude-code whose `claude-code-normalize-project-root'
  ;; RETURNED nil outside a project, giving "(wrong-type-argument stringp
  ;; nil)".  Upstream has since fixed that -- the packaged version reads
  ;;
  ;;   (if project-root (directory-file-name project-root)
  ;;     (user-error "Current directory is not part of a project"))
  ;;
  ;; and its docstring says the `user-error' exists so callers get a readable
  ;; message.  A `:filter-return' advice never runs when the function SIGNALS,
  ;; so the Doom advice is now dead code guarding nothing: `SPC l l' from
  ;; *scratch* raises the user-error either way.
  ;;
  ;; `:filter-args' normalises the argument BEFORE the guard sees it, which
  ;; restores the intended behaviour against both the old and the new upstream.
  ;; `claude-code-normalize-project-root' is the single choke-point -- every
  ;; caller in claude-code-core.el goes through it -- so one advice covers
  ;; `claude-code-run', `claude-code-switch-to-buffer' and the buffer namer.
  (define-advice claude-code-normalize-project-root
      (:filter-args (args) fallback-dir)
    "Fall back to `default-directory' when ARGS names no project root.
`projectile-project-root' returns nil in *scratch* and in any other buffer
outside a project."
    (list (or (car args) default-directory))))

(provide 'my-claude)
;;; my-claude.el ends here
