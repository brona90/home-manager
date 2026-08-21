;;; my-bindings.el --- the discoverable SPC leader menu -*- lexical-binding: t; -*-

;;; Commentary:

;; The point of this file is DISCOVERABILITY, not key count.  Spacemacs and
;; Doom are not liked because SPC is shorter than C-x; they are liked because
;; pressing SPC and waiting shows a menu of NAMED things, and every prefix in
;; that menu is itself a named group.  So the rule here is absolute:
;;
;;   EVERY leader binding and EVERY leader prefix carries a human-readable
;;   :which-key description.
;;
;; A binding that shows up as `consult-line' instead of "Search buffer" is a
;; bug in this file, and the gate in the commit message checks for it.
;;
;; THREE mechanisms, because which-key learns names three different ways:
;;
;;   1. `'(command :which-key "Name")' -- general's extended definition.  This
;;      pushes a (KEY-REGEXP . "Name") entry onto `which-key-replacement-alist'
;;      keyed on the FULL key description ("SPC b k"), so it only ever names
;;      keys general itself bound.
;;
;;   2. `'(:ignore t :which-key "buffer")' -- names a PREFIX.  `:ignore t'
;;      makes general skip the keymap write entirely (general--extract-def
;;      returns `:ignore' and the binding loop drops it), so this is safe to
;;      write in any order relative to the bindings underneath the prefix; it
;;      cannot clobber them.
;;
;;   3. `which-key-add-keymap-based-replacements' -- for BORROWED maps.
;;      `SPC p', `SPC h' and `SPC w' hand off to `project-prefix-map',
;;      `help-map' and `evil-window-map'.  general never sees the individual
;;      keys in those maps, so mechanism 1 cannot reach them and the popup
;;      would show 40 raw command names.  This one works by rewriting each
;;      binding in the keymap to the documented `(STRING . DEFN)' keymap
;;      element -- which is why the command symbol in each pair has to be
;;      RIGHT: passing the wrong one silently rebinds the key.  The gate
;;      asserts `key-binding' still resolves to the intended command for a
;;      sample of these.
;;
;; Key CHOICES follow Doom's modules/config/default/+evil-bindings.el (and
;; modules/lang/org/config.el for the localleader) so ten years of muscle
;; memory transfers.  Where Doom's command does not exist outside Doom the key
;; is kept and pointed at the nearest vanilla equivalent; those are listed in
;; GRADUATION.md.  Doom keys whose feature simply is not here (workspaces,
;; popups, treemacs, snippets, lookup/docsets, ssh-deploy, crdt) are left
;; UNBOUND rather than repurposed -- an unbound key is honest, a key that does
;; something surprising is not.
;;
;; THE TRAP THAT BIT THIS CONFIG TWICE: `package-enable-at-startup' is nil (see
;; early-init.el), so nothing loads package autoloads.  Naming a command here
;; does NOT make it exist.  Every command below has to be reachable via a
;; `use-package' `:commands'/`:autoload'/`:hook'/`:demand' form in init.el, or
;; via Emacs's own loaddefs, or it fails `void-function' on the keypress while
;; `key-binding' happily reports the right symbol.  Checking the binding proves
;; nothing; checking `fboundp' does.

;;; Code:

(require 'which-key)

(declare-function my/leader "init")
(declare-function my/local-leader "init")

;;;; Commands Doom has and vanilla does not
;;
;; Deliberately a short list.  Each one exists because a Doom key is muscle
;; memory and the built-in nearest neighbour would land on a different key or
;; prompt for an argument the Doom command infers.  Anything needing more than
;; a handful of lines was left unbound instead.

(defun my/notes-directory ()
  "Return `org-directory' as a directory name, with a fallback.
Read at call time rather than load time: my-org.el sets `org-directory'
with a top-level `setq', but this file must not depend on having been
loaded after it."
  (file-name-as-directory
   (expand-file-name (or (bound-and-true-p org-directory) "~/org/"))))

(defun my/search-project-for-symbol-at-point ()
  "Ripgrep the project for the symbol under point.
Doom's `+default/search-project-for-symbol-at-point', on the same `SPC *'."
  (interactive)
  (consult-ripgrep nil (or (thing-at-point 'symbol t) "")))

(defun my/search-buffer-for-symbol-at-point ()
  "Search the current buffer for the symbol under point.
Doom's `+vertico/search-symbol-at-point', on the same `SPC s S'."
  (interactive)
  (consult-line (or (thing-at-point 'symbol t) "")))

(defun my/search-cwd ()
  "Ripgrep `default-directory' rather than the project root.
Doom's `+default/search-cwd', on the same `SPC s d'."
  (interactive)
  (consult-ripgrep default-directory))

(defun my/search-notes ()
  "Ripgrep the notes directory.  Doom's `+default/org-notes-search'."
  (interactive)
  (consult-ripgrep (my/notes-directory)))

(defun my/find-in-notes ()
  "Find a file under the notes directory.  Doom's `+default/find-in-notes'."
  (interactive)
  (let ((default-directory (my/notes-directory)))
    (call-interactively #'find-file)))

(defun my/kill-other-buffers ()
  "Kill every other file-visiting buffer.  Doom's `doom/kill-other-buffers'.
Deliberately file-visiting only: killing every non-file buffer would take
*Messages*, the magit process buffer and the eglot event log with it."
  (interactive)
  (let ((killed 0))
    (dolist (buf (buffer-list))
      (when (and (not (eq buf (current-buffer)))
                 (buffer-file-name buf))
        (kill-buffer buf)
        (setq killed (1+ killed))))
    (message "Killed %d buffer(s)" killed)))

(defun my/yank-buffer-path (&optional root)
  "Copy the current buffer's path to the kill ring, relative to ROOT.
Doom's `+default/yank-buffer-path'."
  (interactive)
  (let ((filename (or buffer-file-name
                      (bound-and-true-p list-buffers-directory))))
    (unless filename
      (user-error "This buffer is not visiting a file"))
    (let ((path (abbreviate-file-name
                 (if root (file-relative-name filename root) filename))))
      (kill-new path)
      (message "Copied path: %s" path))))

(defun my/yank-buffer-path-relative-to-project ()
  "Copy the current buffer's project-relative path to the kill ring.
Doom's `+default/yank-buffer-path-relative-to-project'."
  (interactive)
  (my/yank-buffer-path (project-root (project-current t))))

(defun my/eval-buffer-or-region ()
  "Evaluate the region if it is active, else the whole buffer.
ELISP ONLY, unlike Doom's `+eval/buffer-or-region', which dispatches on
major mode through quickrun.  Named accordingly in the menu so the
difference is visible before you press it."
  (interactive)
  (if (use-region-p)
      (let ((beg (region-beginning)) (end (region-end)))
        (deactivate-mark)
        (eval-region beg end)
        (message "Evaluated region"))
    (eval-buffer)
    (message "Evaluated buffer")))

;; consult's preview debounce keys on the COMMAND symbol, so a wrapper around
;; consult-ripgrep gets the raw default (`any') and opens one file per
;; keystroke unless it is listed too.  Here rather than in the consult block in
;; init.el because `consult--customize-put' tests `functionp' when the consult
;; block's `:config' runs, and at that point these three do not exist yet -- it
;; logs "neither a command nor a source" and drops them.  Measured: with them
;; in init.el, `consult--customize-alist' had no entry for `my/search-cwd'.
(with-eval-after-load 'consult
  (consult-customize
   my/search-cwd my/search-notes my/search-project-for-symbol-at-point
   :preview-key '(:debounce 0.4 any)))

;;;; Names for the borrowed keymaps
;;
;; `which-key-add-keymap-based-replacements' rewrites each key to the keymap
;; element `("Name" . COMMAND)'.  That is a normal Emacs binding, so `C-h k'
;; and `C-w h' keep working; which-key's `which-key--get-keymap-bindings-1'
;; special-cases `(STRING . DEFN)' and renders the STRING.
;;
;; A pleasant side effect: because these are the REAL maps, `C-w' and `C-h'
;; now show the same names as `SPC w' and `SPC h'.
;;
;; Only the keys a Doom user reaches for are named.  The rest still show their
;; command name, which is a worse label but never a wrong one.

(which-key-add-keymap-based-replacements evil-window-map
  "h" '("Window left"          . evil-window-left)
  "j" '("Window down"          . evil-window-down)
  "k" '("Window up"            . evil-window-up)
  "l" '("Window right"         . evil-window-right)
  "H" '("Move window far left" . evil-window-move-far-left)
  "J" '("Move window bottom"   . evil-window-move-very-bottom)
  "K" '("Move window top"      . evil-window-move-very-top)
  "L" '("Move window far right" . evil-window-move-far-right)
  "s" '("Split below"          . evil-window-split)
  "S" '("Split below"          . evil-window-split)
  "v" '("Split right"          . evil-window-vsplit)
  "w" '("Next window"          . evil-window-next)
  "W" '("Previous window"      . evil-window-prev)
  "p" '("Most recent window"   . evil-window-mru)
  "n" '("New window"           . evil-window-new)
  "c" '("Close window"         . evil-window-delete)
  "q" '("Quit window"          . evil-quit)
  "o" '("Close other windows"  . delete-other-windows)
  "x" '("Exchange windows"     . evil-window-exchange)
  "r" '("Rotate downwards"     . evil-window-rotate-downwards)
  "R" '("Rotate upwards"       . evil-window-rotate-upwards)
  "t" '("Top-left window"      . evil-window-top-left)
  "b" '("Bottom-right window"  . evil-window-bottom-right)
  "T" '("Detach to new tab"    . tab-window-detach)
  "f" '("Find file other window" . ffap-other-window)
  "=" '("Balance windows"      . balance-windows)
  "+" '("Increase height"      . evil-window-increase-height)
  "-" '("Decrease height"      . evil-window-decrease-height)
  ">" '("Increase width"       . evil-window-increase-width)
  "<" '("Decrease width"       . evil-window-decrease-width)
  "_" '("Set height"           . evil-window-set-height)
  "|" '("Set width"            . evil-window-set-width))

;; `project-prefix-map' is bound WITHOUT project.el being loaded -- Emacs's own
;; loaddefs carry the whole prefix map as an autoload form, which is why
;; `SPC p f' already worked.  `defvar-keymap' in project.el will not clobber an
;; already-bound variable, so these names survive the eventual real load; the
;; gate proves that by requiring project afterwards and re-checking.
(which-key-add-keymap-based-replacements project-prefix-map
  "f"   '("Find file"              . project-find-file)
  "F"   '("Find file (+external)"  . project-or-external-find-file)
  "d"   '("Find directory"         . project-find-dir)
  "D"   '("Dired"                  . project-dired)
  "b"   '("Switch to buffer"       . project-switch-to-buffer)
  "C-b" '("List buffers"           . project-list-buffers)
  "k"   '("Kill project buffers"   . project-kill-buffers)
  "p"   '("Switch project"         . project-switch-project)
  "g"   '("Find regexp"            . project-find-regexp)
  "G"   '("Find regexp (+external)" . project-or-external-find-regexp)
  "r"   '("Query replace regexp"   . project-query-replace-regexp)
  "c"   '("Compile in project"     . project-compile)
  "v"   '("VC dir"                 . project-vc-dir)
  "s"   '("Shell"                  . project-shell)
  "e"   '("Eshell"                 . project-eshell)
  "x"   '("M-x in project"         . project-execute-extended-command)
  "o"   '("Any command"            . project-any-command)
  "!"   '("Shell command"          . project-shell-command)
  "&"   '("Async shell command"    . project-async-shell-command))

(which-key-add-keymap-based-replacements help-map
  "f" '("Function"           . describe-function)
  "v" '("Variable"           . describe-variable)
  "k" '("Key"                . describe-key)
  "c" '("Key briefly"        . describe-key-briefly)
  "o" '("Symbol"             . describe-symbol)
  "m" '("Major/minor modes"  . describe-mode)
  "x" '("Command"            . describe-command)
  "b" '("All bindings"       . describe-bindings)
  "w" '("Where is command"   . where-is)
  "a" '("Apropos command"    . apropos-command)
  "d" '("Apropos docs"       . apropos-documentation)
  "i" '("Info"               . info)
  "r" '("Emacs manual"       . info-emacs-manual)
  "R" '("Info manual..."     . info-display-manual)
  "S" '("Symbol in manual"   . info-lookup-symbol)
  "p" '("Finder by keyword"  . finder-by-keyword)
  "P" '("Package"            . describe-package)
  "l" '("Recent keys"        . view-lossage)
  "e" '("Messages buffer"    . view-echo-area-messages)
  "t" '("Emacs tutorial"     . help-with-tutorial)
  "s" '("Syntax table"       . describe-syntax)
  "." '("Local help at point" . display-local-help)
  "q" '("Quit help"          . help-quit))

;;;; The leader map

(my/leader
  ;;; Top level -- the keys that are worth one keystroke after SPC.
  "SPC" '(project-find-file                    :which-key "Find file in project")
  "."   '(find-file                            :which-key "Find file")
  ","   '(consult-buffer                       :which-key "Switch buffer")
  "<"   '(switch-to-buffer                     :which-key "Switch buffer (plain)")
  "`"   '(evil-switch-to-windows-last-buffer   :which-key "Switch to last buffer")
  "'"   '(vertico-repeat                       :which-key "Resume last search")
  "/"   '(consult-ripgrep                      :which-key "Search project")
  "*"   '(my/search-project-for-symbol-at-point :which-key "Search project for symbol")
  ";"   '(pp-eval-expression                   :which-key "Eval expression")
  ":"   '(execute-extended-command             :which-key "M-x")
  "RET" '(consult-bookmark                     :which-key "Jump to bookmark")
  "u"   '(universal-argument                   :which-key "Universal argument")
  "a"   '(embark-act                           :which-key "Act on thing at point")
  "A"   '(embark-dwim                          :which-key "Do the obvious thing")
  "x"   '(scratch-buffer                       :which-key "Scratch buffer")
  "X"   '(org-capture                          :which-key "Org capture")

  ;;; SPC b --- buffer
  "b"   '(:ignore t :which-key "buffer")
  "b["  '(previous-buffer          :which-key "Previous buffer")
  "b]"  '(next-buffer              :which-key "Next buffer")
  "bb"  '(consult-buffer           :which-key "Switch buffer")
  "bB"  '(switch-to-buffer         :which-key "Switch buffer (plain)")
  "bc"  '(clone-indirect-buffer    :which-key "Clone buffer")
  "bC"  '(clone-indirect-buffer-other-window :which-key "Clone buffer other window")
  "bd"  '(kill-current-buffer      :which-key "Kill buffer")
  "bi"  '(ibuffer                  :which-key "Buffer list (ibuffer)")
  "bk"  '(kill-current-buffer      :which-key "Kill buffer")
  "bl"  '(evil-switch-to-windows-last-buffer :which-key "Switch to last buffer")
  "bm"  '(bookmark-set             :which-key "Set bookmark")
  "bM"  '(bookmark-delete          :which-key "Delete bookmark")
  "bn"  '(next-buffer              :which-key "Next buffer")
  "bN"  '(evil-buffer-new          :which-key "New empty buffer")
  "bO"  '(my/kill-other-buffers    :which-key "Kill other buffers")
  "bp"  '(previous-buffer          :which-key "Previous buffer")
  "br"  '(revert-buffer            :which-key "Revert buffer")
  "bR"  '(rename-buffer            :which-key "Rename buffer")
  "bs"  '(save-buffer              :which-key "Save buffer")
  "bS"  '(evil-write-all           :which-key "Save all buffers")
  "bx"  '(scratch-buffer           :which-key "Scratch buffer")
  "bz"  '(bury-buffer              :which-key "Bury buffer")

  ;;; SPC c --- code
  ;;
  ;; eglot rather than lsp-mode, so these are Doom's `+eglot' keys.  `c d' and
  ;; `c D' go through xref rather than Doom's `+lookup/': xref covers etags and
  ;; elisp as well as eglot, but there is no dumb-jump/online FALLBACK chain
  ;; behind it, so with no server and no tags the key simply fails.
  "c"   '(:ignore t :which-key "code")
  "ca"  '(eglot-code-actions       :which-key "LSP code action")
  "cc"  '(compile                  :which-key "Compile")
  "cC"  '(recompile                :which-key "Recompile")
  "cd"  '(xref-find-definitions    :which-key "Jump to definition")
  "cD"  '(xref-find-references     :which-key "Jump to references")
  "ce"  '(my/eval-buffer-or-region :which-key "Eval buffer/region (elisp)")
  "cf"  '(eglot-format             :which-key "Format buffer/region")
  "ci"  '(eglot-find-implementation :which-key "Find implementations")
  "cj"  '(eglot-find-declaration   :which-key "Jump to declaration")
  "ck"  '(eldoc-doc-buffer         :which-key "Documentation at point")
  "cl"  '(eglot                    :which-key "Start LSP server")
  "cL"  '(eglot-shutdown           :which-key "Shut down LSP server")
  "cr"  '(eglot-rename             :which-key "LSP rename")
  "cR"  '(eglot-reconnect          :which-key "Reconnect LSP server")
  "ct"  '(eglot-find-typeDefinition :which-key "Find type definition")
  "cw"  '(delete-trailing-whitespace :which-key "Delete trailing whitespace")
  "cx"  '(consult-flymake          :which-key "List errors")
  "cX"  '(flymake-show-project-diagnostics :which-key "List project errors")

  ;;; SPC f --- file
  "f"   '(:ignore t :which-key "file")
  "fd"  '(dired-jump               :which-key "Find directory")
  "fD"  '(delete-file              :which-key "Delete a file")
  "ff"  '(find-file                :which-key "Find file")
  "fl"  '(locate                   :which-key "Locate file")
  "fr"  '(consult-recent-file      :which-key "Recent files")
  "fR"  '(rename-visited-file      :which-key "Rename/move this file")
  "fs"  '(save-buffer              :which-key "Save file")
  "fS"  '(write-file               :which-key "Save file as...")
  "fy"  '(my/yank-buffer-path      :which-key "Yank file path")
  "fY"  '(my/yank-buffer-path-relative-to-project :which-key "Yank project-relative path")

  ;;; SPC g --- git
  ;;
  ;; diff-hl stands in for Doom's vc-gutter module, so `g s'/`g r'/`g ]'/`g ['
  ;; keep their Doom meanings on a different implementation.
  "g"   '(:ignore t :which-key "git")
  "g/"  '(magit-dispatch           :which-key "Magit dispatch")
  "g."  '(magit-file-dispatch      :which-key "Magit file dispatch")
  "g'"  '(forge-dispatch           :which-key "Forge dispatch")
  "g]"  '(diff-hl-next-hunk        :which-key "Next hunk")
  "g["  '(diff-hl-previous-hunk    :which-key "Previous hunk")
  "gb"  '(magit-branch-checkout    :which-key "Switch branch")
  "gB"  '(magit-blame-addition     :which-key "Blame")
  "gC"  '(magit-clone              :which-key "Clone repo")
  "gD"  '(magit-file-delete        :which-key "Delete this file")
  "gF"  '(magit-fetch              :which-key "Fetch")
  "gg"  '(magit-status             :which-key "Magit status")
  "gG"  '(magit-status-here        :which-key "Magit status here")
  "gL"  '(magit-log-buffer-file    :which-key "Log for this file")
  "gp"  '(diff-hl-show-hunk        :which-key "Preview hunk at point")
  "gr"  '(diff-hl-revert-hunk      :which-key "Revert hunk at point")
  "gR"  '(vc-revert                :which-key "Revert file")
  "gs"  '(diff-hl-stage-dwim       :which-key "Stage hunk at point")
  "gS"  '(magit-stage-buffer-file  :which-key "Stage this file")
  "gU"  '(magit-unstage-buffer-file :which-key "Unstage this file")

  "gc"  '(:ignore t :which-key "create")
  "gcb" '(magit-branch-and-checkout :which-key "Branch")
  "gcc" '(magit-commit-create      :which-key "Commit")
  "gcf" '(magit-commit-fixup       :which-key "Fixup")
  "gci" '(forge-create-issue       :which-key "Issue")
  "gcp" '(forge-create-pullreq     :which-key "Pull request")
  "gcr" '(magit-init               :which-key "Initialise repo")
  "gcR" '(magit-clone              :which-key "Clone repo")

  "gf"  '(:ignore t :which-key "find")
  "gfc" '(magit-show-commit        :which-key "Commit")
  "gff" '(magit-find-file          :which-key "File")
  "gfg" '(magit-find-git-config-file :which-key "Gitconfig file")
  "gfi" '(forge-visit-issue        :which-key "Issue")
  "gfp" '(forge-visit-pullreq      :which-key "Pull request")

  "gl"  '(:ignore t :which-key "list")
  "gli" '(forge-list-issues        :which-key "Issues")
  "gln" '(forge-list-notifications :which-key "Notifications")
  "glp" '(forge-list-pullreqs      :which-key "Pull requests")
  "glr" '(magit-list-repositories  :which-key "Repositories")
  "gls" '(magit-list-submodules    :which-key "Submodules")

  "go"  '(:ignore t :which-key "open in browser")
  "goc" '(forge-browse-commit      :which-key "Commit")
  "goi" '(forge-browse-issue       :which-key "Issue")
  "goI" '(forge-browse-issues      :which-key "Issues")
  "gop" '(forge-browse-pullreq     :which-key "Pull request")
  "goP" '(forge-browse-pullreqs    :which-key "Pull requests")
  "gor" '(forge-browse-remote      :which-key "Remote")

  ;;; SPC h --- help (borrowed map, named above)
  "h"   '(:keymap help-map :which-key "help")

  ;;; SPC i --- insert
  "i"   '(:ignore t :which-key "insert")
  "ie"  '(emoji-search             :which-key "Emoji")
  "ir"  '(consult-register         :which-key "From register")
  "iu"  '(insert-char              :which-key "Unicode character")
  "iy"  '(consult-yank-pop         :which-key "From kill ring")

  ;;; SPC m --- local leader
  ;;
  ;; `:ignore t' names the prefix WITHOUT touching the keymap, so this cannot
  ;; disturb the `my/local-leader' bindings at the bottom of this file no
  ;; matter which form runs first.  Before this line the popup showed the
  ;; anonymous "+prefix" here.
  "m"   '(:ignore t :which-key "local")

  ;;; SPC n --- notes
  "n"   '(:ignore t :which-key "notes")
  "na"  '(org-agenda               :which-key "Org agenda")
  "nc"  '(org-clock-in             :which-key "Clock in")
  "nC"  '(org-clock-cancel         :which-key "Cancel clock")
  "nf"  '(my/find-in-notes         :which-key "Find file in notes")
  "nl"  '(org-store-link           :which-key "Store link")
  "nm"  '(org-tags-view            :which-key "Tags search")
  "nn"  '(org-capture              :which-key "Org capture")
  "nN"  '(org-capture-goto-target  :which-key "Goto capture target")
  "no"  '(org-clock-goto           :which-key "Active org clock")
  "ns"  '(my/search-notes          :which-key "Search notes")
  "nS"  '(consult-org-agenda       :which-key "Search agenda headings")
  "nt"  '(org-todo-list            :which-key "Todo list")
  "nv"  '(org-search-view          :which-key "View search")

  ;;; SPC o --- open
  "o"   '(:ignore t :which-key "open")
  "o-"  '(dired-jump               :which-key "Dired")
  "oA"  '(org-agenda               :which-key "Org agenda")
  "ob"  '(browse-url-of-file       :which-key "Open in browser")
  "oe"  '(eshell                   :which-key "Eshell")
  "of"  '(make-frame               :which-key "New frame")
  "oF"  '(select-frame-by-name     :which-key "Select frame")
  "os"  '(shell                    :which-key "Shell")
  "oa"  '(:ignore t :which-key "org agenda")
  "oaa" '(org-agenda               :which-key "Agenda")
  "oam" '(org-tags-view            :which-key "Tags search")
  "oat" '(org-todo-list            :which-key "Todo list")
  "oav" '(org-search-view          :which-key "View search")

  ;;; SPC p --- project (borrowed map, named above)
  "p"   '(:keymap project-prefix-map :which-key "project")

  ;;; SPC q --- quit/session
  "q"   '(:ignore t :which-key "quit/session")
  "qf"  '(delete-frame             :which-key "Delete frame")
  "qF"  '(delete-other-frames      :which-key "Delete other frames")
  "qK"  '(save-buffers-kill-emacs  :which-key "Kill Emacs (and daemon)")
  "qq"  '(save-buffers-kill-terminal :which-key "Quit Emacs")
  "qQ"  '(evil-quit-all-with-error-code :which-key "Quit Emacs without saving")
  "qr"  '(restart-emacs            :which-key "Restart Emacs")

  ;;; SPC s --- search
  ;;
  ;; DEVIATION: `s l' and `s c' are avy here.  Doom's `s l'/`s L' are link-hint
  ;; and ffap-menu, neither of which is in this package set, and avy had no
  ;; leader key at all -- so the two free keys go to the tool that is present.
  "s"   '(:ignore t :which-key "search")
  "sb"  '(consult-line             :which-key "Search buffer")
  "sB"  '(consult-line-multi       :which-key "Search all open buffers")
  "sc"  '(avy-goto-char-timer      :which-key "Jump to character")
  "sd"  '(my/search-cwd            :which-key "Search current directory")
  "sf"  '(locate                   :which-key "Locate file")
  "si"  '(consult-imenu            :which-key "Jump to symbol")
  "sI"  '(consult-imenu-multi      :which-key "Jump to symbol in open buffers")
  "sj"  '(evil-show-jumps          :which-key "Jump list")
  "sl"  '(avy-goto-line            :which-key "Jump to line")
  "sm"  '(consult-bookmark         :which-key "Jump to bookmark")
  "sk"  '(consult-mark             :which-key "Jump to local mark")
  "sK"  '(consult-global-mark      :which-key "Jump to global mark")
  "so"  '(consult-outline          :which-key "Jump to heading")
  "sp"  '(consult-ripgrep          :which-key "Search project")
  "sr"  '(evil-show-marks          :which-key "Jump to mark")
  "ss"  '(consult-line             :which-key "Search buffer")
  "sS"  '(my/search-buffer-for-symbol-at-point :which-key "Search buffer for symbol")
  "st"  '(hl-todo-occur            :which-key "List TODO/FIXME")
  "su"  '(vundo                    :which-key "Undo history")

  ;;; SPC t --- toggle
  "t"   '(:ignore t :which-key "toggle")
  "tc"  '(global-display-fill-column-indicator-mode :which-key "Fill column indicator")
  "td"  '(diff-hl-mode             :which-key "Diff highlights")
  "tf"  '(flymake-mode             :which-key "Flymake")
  "tF"  '(toggle-frame-fullscreen  :which-key "Frame fullscreen")
  "th"  '(hl-line-mode             :which-key "Highlight current line")
  "tl"  '(display-line-numbers-mode :which-key "Line numbers")
  "tr"  '(read-only-mode           :which-key "Read-only mode")
  "ts"  '(flyspell-mode            :which-key "Spell checker")
  "tt"  '(toggle-truncate-lines    :which-key "Truncate lines")
  "tv"  '(visible-mode             :which-key "Visible mode")
  "tw"  '(visual-line-mode         :which-key "Soft line wrapping")

  ;;; SPC w --- window (borrowed map, named above)
  "w"   '(:keymap evil-window-map :which-key "window"))

;;;; The local leader
;;
;; `SPC m'.  Structurally global rather than mode-local -- see the note in
;; my-org.el: the general override map is an evil INTERCEPT map, so once `SPC'
;; resolves there `org-mode-map' is never consulted for the rest of the
;; sequence.  Everything below is therefore an org key that happens to be
;; reachable everywhere; org commands run outside an org buffer error clearly.
;;
;; Keys follow Doom's org localleader.  ONE DELIBERATE DIFFERENCE: Doom's
;; `SPC m r' is a refile SUB-PREFIX whose useful entries are all `+org/'
;; commands that do not exist here, so `SPC m r' stays bound directly to
;; `org-refile' as it already was.

(my/local-leader
  "#"   '(org-update-statistics-cookies :which-key "Update statistics cookies")
  "'"   '(org-edit-special          :which-key "Edit special")
  ","   '(org-switchb               :which-key "Switch org buffer")
  "."   '(consult-org-heading       :which-key "Goto heading")
  "/"   '(consult-org-agenda        :which-key "Goto agenda heading")
  "A"   '(org-archive-subtree-default :which-key "Archive subtree")
  "e"   '(org-export-dispatch       :which-key "Export dispatch")
  "h"   '(org-toggle-heading        :which-key "Toggle heading")
  "i"   '(org-toggle-item           :which-key "Toggle item")
  "n"   '(org-store-link            :which-key "Store link")
  "o"   '(org-set-property          :which-key "Set property")
  "q"   '(org-set-tags-command      :which-key "Set tags")
  "r"   '(org-refile                :which-key "Refile")
  "t"   '(org-todo                  :which-key "Todo state")
  "T"   '(org-todo-list             :which-key "Todo list")
  "x"   '(org-toggle-checkbox       :which-key "Toggle checkbox")

  "c"   '(:ignore t :which-key "clock")
  "cc"  '(org-clock-cancel          :which-key "Cancel clock")
  "cE"  '(org-set-effort            :which-key "Set effort")
  "ce"  '(org-clock-modify-effort-estimate :which-key "Modify effort estimate")
  "cg"  '(org-clock-goto            :which-key "Goto clock")
  "ci"  '(org-clock-in              :which-key "Clock in")
  "co"  '(org-clock-out             :which-key "Clock out")
  "cR"  '(org-clock-report          :which-key "Clock report")

  "d"   '(:ignore t :which-key "date/deadline")
  "dd"  '(org-deadline              :which-key "Deadline")
  "ds"  '(org-schedule              :which-key "Schedule")
  ;; The canonical names since org 9.7; `org-time-stamp' is a bare defalias
  ;; and, unlike the alias, only `org-timestamp' has a defun to autoload.
  "dt"  '(org-timestamp             :which-key "Timestamp")
  "dT"  '(org-timestamp-inactive    :which-key "Inactive timestamp")

  "l"   '(:ignore t :which-key "links")
  "ll"  '(org-insert-link           :which-key "Insert link")
  "ls"  '(org-store-link            :which-key "Store link")
  "lt"  '(org-toggle-link-display   :which-key "Toggle link display")

  "p"   '(:ignore t :which-key "priority")
  "pd"  '(org-priority-down         :which-key "Priority down")
  "pp"  '(org-priority              :which-key "Set priority")
  "pu"  '(org-priority-up           :which-key "Priority up")

  "s"   '(:ignore t :which-key "tree/subtree")
  "sa"  '(org-toggle-archive-tag    :which-key "Toggle archive tag")
  "sA"  '(org-archive-subtree-default :which-key "Archive subtree")
  "sb"  '(org-tree-to-indirect-buffer :which-key "Tree to indirect buffer")
  "sd"  '(org-cut-subtree           :which-key "Cut subtree")
  "sh"  '(org-promote-subtree       :which-key "Promote subtree")
  "sj"  '(org-move-subtree-down     :which-key "Move subtree down")
  "sk"  '(org-move-subtree-up       :which-key "Move subtree up")
  "sl"  '(org-demote-subtree        :which-key "Demote subtree")
  "sn"  '(org-narrow-to-subtree     :which-key "Narrow to subtree")
  "sN"  '(widen                     :which-key "Widen")
  "ss"  '(org-sparse-tree           :which-key "Sparse tree")
  "sS"  '(org-sort                  :which-key "Sort")

  ;; Google Calendar.  NOT a Doom key -- Doom's localleader `G' is unbound and
  ;; its `g' is a goto prefix.  Kept exactly where the phase-2 port put it so
  ;; nothing already in the fingers moves.
  "G"   '(:ignore t :which-key "gcal")
  "Gs"  '(org-gcal-sync             :which-key "Sync calendars")
  "Gf"  '(org-gcal-fetch            :which-key "Fetch calendars")
  "Gp"  '(org-gcal-post-at-point    :which-key "Post entry at point"))

(provide 'my-bindings)
;;; my-bindings.el ends here
