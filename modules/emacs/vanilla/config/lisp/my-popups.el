;;; my-popups.el --- transient buffers in one bottom window -*- lexical-binding: t; -*-

;;; Commentary:

;; Doom's `:ui popup' is ~1400 lines of popup MANAGER: a display-buffer action
;; of its own, a per-popup window-parameter plist, a `:ttl' reaper, an
;; ESC-to-close hook and a `vslot' axis for stacking.  ZERO of that is ported
;; and no package replaces it.  What follows is the 80% that matters, built
;; entirely out of Emacs 30 built-ins, in one screen.
;;
;; TWO PACKAGES WERE EVALUATED AND REJECTED.  Write this down, because both
;; will be proposed again:
;;
;;   * `popper' (20260302.22).  Buys popup CYCLING and per-project grouping and
;;     nothing else this file lacks -- and it does NOT solve the problem people
;;     reach for it to solve, because `popper-display-popup-at-bottom' calls
;;     `display-buffer-in-side-window' itself.  It is a layer over the same
;;     built-in, not an alternative to it.  It also has the consult-imenu trap
;;     this config has already been bitten by twice: only `popper-mode' carries
;;     an autoload cookie, so `popper-toggle', `popper-cycle' and
;;     `popper-raise-popup' would be void on the keypress, and
;;     `popper-echo-mode' lives in a separate file (popper-echo.el) that
;;     nothing loads.  Three extra `use-package' forms to get less than
;;     `window-toggle-side-windows' gives for free.
;;
;;   * `shackle' (20240402).  Two commits in six years, and it covers only the
;;     part `display-buffer-alist' already does well in Emacs 30.
;;
;; THE THREE BUILT-INS THIS FILE IS MADE OF, all verified `fboundp' in this
;; build by the gate:
;;
;;   1. `display-buffer-in-side-window' + `window-sides-slots'.  A side window
;;      is not part of the frame's MAIN window tree, so `C-w s', `C-w v' and
;;      the window-splitting commands never carve it up, and a popup can never
;;      become the window a file opens in.  That property is the whole feature.
;;
;;   2. The `mode-line-format' WINDOW PARAMETER (built in since Emacs 26).
;;      This is Doom's `:modeline nil', exactly, with no manager behind it:
;;      the value `none' means the window draws no mode line at all, and it is
;;      per-WINDOW, so the same buffer shown elsewhere keeps its mode line.
;;
;;   3. `window-toggle-side-windows' (window.el:1190).  PRELOADED and
;;      INTERACTIVE, so it needs no `use-package' form and cannot be void.  It
;;      is Doom's `+popup/toggle' AND `+popup/restore' in ONE command: on the
;;      way out it saves `window-state-get' into the frame's `window-state'
;;      parameter and deletes every side window; called again with no side
;;      windows it puts that state back.  It is bound to `SPC ~' in
;;      my-bindings.el, with all the other leader keys, so the gate's leader
;;      walk covers it.
;;
;;      It is BETTER than Doom's, which falls back to showing *Messages* when
;;      it has nothing to restore.  This one errors with "No side windows state
;;      found", which is the honest answer.
;;
;; ONE BOTTOM POPUP, EVER.  `window-sides-slots' is set to one bottom slot
;; below.  That is not a size limit, it is the layout decision: Emacs's side
;; windows put two bottom slots SIDE BY SIDE (`window-sides-vertical' is nil,
;; and full-width bottom popups are the point), so a second slot would give two
;; 40-column popups on an 80-column frame rather than Doom's two stacked ones.
;; Reuse is the better failure mode; see "vslot" in GRADUATION.md.
;;
;; WHAT THIS FILE DOES NOT TOUCH, AND MUST NOT.  `display-buffer-alist' already
;; has two entries when this file loads, and both deliberately produce ORDINARY
;; windows rather than side windows:
;;
;;   ("^\\*claude:"      ...) from my-claude.el
;;   ("^ \\*lilypond: "  ...) from my-lilypond.el
;;
;; The Claude one is a BUG FIX and the reason is spelled out at length in
;; my-claude.el: `claude-diff--show-1' calls `delete-other-windows' and then
;; rebuilds a three-pane layout, which only works if the Claude window is
;; deletable -- and window.el:4381 signals "Cannot make side window the only
;; window".  Every regexp below is disjoint from those two, and the gate proves
;; it by displaying a `*claude:' buffer WITH a popup open and asserting the
;; Claude window still has a nil `window-side'.
;;
;; `no-delete-other-windows' IS THEREFORE NOT USED HERE, even though it is the
;; obvious next built-in (window.el:4387-4402: a non-side window's
;; `delete-other-windows' collapses only `window-main-window' when it is
;; present).  Putting it on these popups would make them survive
;; `delete-other-windows' -- which is precisely option (c) that my-claude.el
;; considered and rejected, and it would break claude-diff's layout for every
;; user of `SPC h f'.  If it is ever wanted, it is a claude-diff redesign, not
;; a window parameter.
;;
;; `no-other-window' IS ALSO NOT USED, and that is a call rather than an
;; oversight.  Doom sets it on every popup and gets away with it because
;; `+popup/other' exists to jump into one.  There is no such command here and
;; no popup manager to hang one off, so `no-other-window' would leave a popup
;; you can see and cannot select -- unscrollable, unquittable, mouse-only.  The
;; gate asserts the *Help* popup IS reachable by `other-window', so this
;; decision is checked rather than merely written down.
;;
;; `:ttl' IS NOT PORTED.  See GRADUATION.md for the full argument; the short
;; version is that with one bottom slot the VISIBLE clutter Doom's reaper
;; existed for cannot happen, what is left is buffer-list clutter that
;; `SPC b O' already answers, and a wall-clock timer that kills buffers is the
;; one thing here that could destroy work and the one thing this gate cannot
;; test.

;;; Code:

;; (left top right bottom).  Only `bottom' is constrained: nothing in this
;; config makes a left or top side window, and verify.el makes a RIGHT one as
;; the control for the claude-diff guard -- capping that side would break the
;; test rather than the feature.
;;
;; `setq' rather than `setopt': `window-sides-slots' is a plain defcustom with
;; no `:set' function, unlike `which-key-dont-use-unicode' in init.el.
(setq window-sides-slots '(nil nil nil 1))

;; THE SECOND HALF OF `SPC ~', AND THE GATE FOUND IT.
;;
;; `window-toggle-side-windows' saves the frame with `window-state-get' and
;; restores it with `window-state-put'.  `window--state-get-1' copies a window
;; PARAMETER into that state only if the parameter is named in
;; `window-persistent-parameters', whose default is
;;
;;   ((window-slot . writable) (window-side . writable)
;;    (context . writable) (clone-of . t))
;;
;; -- so `window-side' and `window-slot' survive the round trip and
;; `mode-line-format' DOES NOT.  Measured before this line existed: hide with
;; `SPC ~', show with `SPC ~', and the popup came back with a mode line on it,
;; permanently, for the rest of the session.  Nothing errors and nothing warns;
;; the config just quietly stops doing half of what it says it does.  This is
;; what Doom's popup manager is doing when it re-applies
;; `+popup-window-parameters' on restore.
;;
;; `writable' rather than `t': the value stored is the symbol `none', which
;; reads and prints, so the parameter can also survive a `desktop-save' state
;; rather than only an in-memory one.
(add-to-list 'window-persistent-parameters '(mode-line-format . writable))

;; ---------------------------------------------------------------------------
;; The rules.
;;
;; `display-buffer-in-side-window' is used ALONE -- deliberately NOT
;; `(display-buffer-reuse-window display-buffer-in-side-window)' the way the
;; claude and lilypond rules are written.  Those two need reuse because their
;; windows are ordinary and must be re-found where they are; a popup has one
;; place it belongs, and `display-buffer-in-side-window' already reuses the
;; window sitting in the slot.  Adding `display-buffer-reuse-window' would let
;; these rules find the buffer in a MAIN window and then stamp
;; `mode-line-format . none' onto it, leaving a mode-line-less editing window
;; behind.
;;
;; `(dedicated . side)' rather than `. t'.  The value is not decoration:
;; `window--display-buffer' re-dedicates a REUSED window only when the alist
;; value is exactly `side' (window.el:7381), which is what keeps the popup
;; dedicated as buffers rotate through the slot.  `t' would additionally make
;; it STRONGLY dedicated, and a strongly dedicated window is one `switch-to-
;; buffer' away from an error -- which-key shares this slot (its
;; `which-key-side-window-slot' is 0 and its location is `bottom') and swaps
;; its buffer in on every leader prefix.

;; (a) Documentation.  `*Help*', `*Apropos*', `*eldoc*' / `*eldoc for X*' and
;; `*info*'.  SELECTED, which is Doom's `:select t' on the same buffers: you
;; press `SPC h f' to READ the answer, and with `no-other-window' off this is
;; the only thing that puts point where the text is.  `body-function' is the
;; Emacs 30 way to do it and needs no `help-window-select' global.
;;
;; NOTE `helpful' is NOT in this regexp.  The package is not in package.nix, so
;; a `\\*helpful' branch would be a rule that can never match -- dead code in
;; the file whose job is to be short.  Add it in the same commit that adds the
;; package, not before.
(add-to-list 'display-buffer-alist
             '("\\`\\*\\(?:[Hh]elp\\|Apropos\\|eldoc\\|info\\)"
               (display-buffer-in-side-window)
               (side . bottom)
               (slot . 0)
               (window-height . 0.42)
               (dedicated . side)
               (body-function . select-window)
               (window-parameters (mode-line-format . none))))

;; (b) Flymake's diagnostic lists -- `SPC c x' and `SPC c X'.  Buffer names are
;; "*Flymake diagnostics for `BUFFER'*" and the project variant
;; (flymake.el:1975, :2087), so the anchor is all that can be matched.
;; SELECTED for the same reason as (a): a list you cannot move point into is
;; not a list, it is a picture of one.
(add-to-list 'display-buffer-alist
             '("\\`\\*Flymake diagnostics"
               (display-buffer-in-side-window)
               (side . bottom)
               (slot . 0)
               (window-height . 0.3)
               (dedicated . side)
               (body-function . select-window)
               (window-parameters (mode-line-format . none))))

;; (c) Log buffers you glance at and dismiss.  NOT selected: `post-command-
;; select-window . nil' is Doom's `:select nil', and the nil is load-bearing --
;; window.el looks the key up with `assq', so a present-but-nil entry means
;; "re-select whatever was selected before", while omitting the entry means
;; "leave the selection wherever it landed".  Same reasoning, same spelling, as
;; the claude and lilypond rules.
(add-to-list 'display-buffer-alist
             '("\\`\\*\\(?:Messages\\|Warnings\\|Compile-Log\\)\\*"
               (display-buffer-in-side-window)
               (side . bottom)
               (slot . 0)
               (window-height . 0.3)
               (dedicated . side)
               (post-command-select-window . nil)
               (window-parameters (mode-line-format . none))))

;; (d) `*compilation*' -- `SPC c c' / `SPC c C' / `SPC p c'.  The ONE popup
;; that KEEPS ITS MODE LINE, and the exception is the point: compilation state
;; ("run", "exit [1]") is rendered in `mode-line-process' and nowhere else in
;; the buffer.  Doom strips it here too and relies on the echo area; that is a
;; worse trade for a window you are watching rather than reading.
;;
;; Not selected, so `SPC c c' leaves point in the source file.  `next-error'
;; and `compile-goto-error' are unaffected: `display-buffer' never picks a side
;; window for the SOURCE buffer, so the jump lands in the main window.
(add-to-list 'display-buffer-alist
             '("\\`\\*compilation\\*"
               (display-buffer-in-side-window)
               (side . bottom)
               (slot . 0)
               (window-height . 0.3)
               (dedicated . side)
               (post-command-select-window . nil)))

(provide 'my-popups)
;;; my-popups.el ends here
