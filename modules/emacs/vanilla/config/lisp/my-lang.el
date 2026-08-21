;;; my-lang.el --- languages: modes, tree-sitter, eglot -*- lexical-binding: t; -*-

;;; Commentary:

;; Phase 3b.  What makes this file long is not the number of languages, it is
;; that NONE of the usual shortcuts are available here.  Three facts from
;; early-init.el decide almost every line below, and all three were measured in
;; a live daemon rather than assumed:
;;
;;   1. `package-enable-at-startup' is nil, so package.el NEVER activates and no
;;      package autoload file is ever loaded.  In a running daemon
;;      `package-alist' is literally VOID.  A packaged mode is therefore
;;      reachable ONLY through a `use-package' autoload keyword, and -- the part
;;      that bites -- the `auto-mode-alist' entries those packages register in
;;      their own autoload files NEVER REGISTER EITHER.  So every extension is
;;      spelled out with `:mode' here.  Nothing is inherited.
;;
;;   2. `use-package' derives the autoload FILE from the use-package NAME.
;;      `(use-package foo :mode ("\\.x\\'" . bar-mode))' emits
;;      (autoload (quote bar-mode) "foo").  If `bar-mode' does not live in
;;      foo.el that autoload resolves, loads the wrong file, and fails at
;;      find-file time with "failed to define function".  Every form below is
;;      named for the FILE, not for the language.
;;
;;   3. `major-mode-remap-alist' targets get NO autoload stub from anything.
;;      `:mode' only stubs the symbol it puts in `auto-mode-alist'; the remap
;;      table is consulted by `set-auto-mode' AFTER that and calls its target
;;      directly.  So each remap target below also appears in a `:commands' or
;;      `:autoload' list.  A remap to a void function fails as a raw
;;      "void-function" on find-file.
;;
;; WHY REMAP AT ALL, when `:mode' could name the -ts-mode directly?  Because
;; `major-mode-remap-alist' is the documented, user-level override and it keeps
;; the ONE behaviour we actually want from the built-in entries -- see the
;; `sh-mode' note below, where the built-in mode function is what decides
;; whether tree-sitter is appropriate at all.  Where there is no such subtlety,
;; `:mode' is used directly because it is one fewer indirection to debug.
;;
;; MEASURED, and the reason three of the remaps look wrong until you check:
;; `major-mode-remap-alist' is looked up with `assq' on the LITERAL symbol that
;; `auto-mode-alist' produced.  It does not chase aliases.  So
;;
;;   (js-mode        . js-ts-mode)   does NOTHING -- .js maps to the ALIAS
;;                                   `javascript-mode', not to `js-mode'
;;   (json-mode      . json-ts-mode) does NOTHING -- .json maps to `js-json-mode'
;;   (toml-mode      . toml-ts-mode) does NOTHING -- .toml maps to `conf-toml-mode'
;;
;; `major-mode-remap-defaults' at startup in this build contains ONLY the
;; LaTeX/TeX entries.  No tree-sitter remapping is free; all of it is here.
;;
;; NOT COVERED, deliberately: C, C++, CMake, Fortran and LaTeX get a mode but no
;; `eglot-ensure', because clangd, cmake-language-server, fortls and texlab are
;; not installed.  Hooking eglot where there is no server produces a failed
;; connection on every find-file, which trains you to ignore eglot errors.

;;; Code:

(require 'use-package)

;;;; ---------------------------------------------------------------------
;;;; Modes reached directly by extension
;;;; ---------------------------------------------------------------------

;; Every one of these is a BUILT-IN Emacs 30.2 tree-sitter mode.  "Built in"
;; does not mean "bound" and it does not mean "registered": the `:mode' forms
;; are what emit the autoload stub AND put the extension in `auto-mode-alist'
;; ahead of whatever was there.  `add-to-list' PREPENDS, which is what makes
;; these win over the built-in entries rather than merely duplicate them.

;; .ts / .tsx.  Both modes live in typescript-ts-mode.el; naming the form after
;; the file rather than after `typescript' is rule 2 above.
(use-package typescript-ts-mode
  :mode (("\\.ts\\'"  . typescript-ts-mode)
         ("\\.mts\\'" . typescript-ts-mode)
         ("\\.cts\\'" . typescript-ts-mode)
         ("\\.tsx\\'" . tsx-ts-mode)))

;; .mjs and .cjs have NO `auto-mode-alist' entry ANYWHERE in Emacs 30.2 --
;; measured: they open in `fundamental-mode'.  That is not a tree-sitter
;; problem, it is a missing-entry problem, and it is invisible until someone
;; opens an ESM config file and gets no highlighting at all.
;;
;; Plain .js is NOT here: it is handled by the `javascript-mode' remap below,
;; because the built-in entry already exists and prepending a second one for
;; the same extension makes two sources of truth for one file type.
(use-package js
  :mode (("\\.mjs\\'" . js-ts-mode)
         ("\\.cjs\\'" . js-ts-mode))
  ;; Remap targets from the section below.  Both live in js.el.
  :autoload (js-ts-mode js-json-mode))

(use-package yaml-ts-mode
  :mode (("\\.ya?ml\\'" . yaml-ts-mode)
         ;; Not a YAML extension as far as Emacs is concerned, but these are
         ;; YAML and nothing else knows it.
         ("\\.sops\\.ya?ml\\'" . yaml-ts-mode)))

;; go.mod is the trap in this file.  By DEFAULT it opens in `m2-mode' --
;; Modula-2 -- because files.el matches "\\.mod\\'" and nothing later overrides
;; it.  The explicit entry here wins only because `add-to-list' prepends.
(use-package go-ts-mode
  :mode (("\\.go\\'"      . go-ts-mode)
         ("/go\\.mod\\'"  . go-mod-ts-mode)
         ("/go\\.work\\'" . go-work-ts-mode)))

(use-package rust-ts-mode  :mode ("\\.rs\\'"   . rust-ts-mode))
(use-package lua-ts-mode   :mode ("\\.lua\\'"  . lua-ts-mode))
(use-package java-ts-mode  :mode ("\\.java\\'" . java-ts-mode))

;; Dockerfile, Dockerfile.foo and foo.dockerfile are all in use; none of the
;; three is matched by either of the other two patterns.
(use-package dockerfile-ts-mode
  :mode (("/Dockerfile\\'"   . dockerfile-ts-mode)
         ("/Dockerfile\\."   . dockerfile-ts-mode)
         ("\\.dockerfile\\'" . dockerfile-ts-mode)))

;; -- packaged modes (from package.nix) ---------------------------------------

;; haskell-ts-mode calls `derived-mode-add-parents' to declare itself a child of
;; haskell-mode; nix-ts-mode does NOT.  That asymmetry decides the eglot section
;; below and it is measured, not assumed -- see the comment there.
(use-package nix-ts-mode     :mode ("\\.nix\\'" . nix-ts-mode))
(use-package haskell-ts-mode :mode ("\\.hs\\'"  . haskell-ts-mode))

;; markdown-mode is NOT a tree-sitter mode and there is no markdown-ts-mode in
;; Emacs 30.2 or in the package set, which is why package.nix ships no markdown
;; grammar.  `treesit-parser-list' in a .md buffer is expected to be nil; that
;; is correct, not a missing grammar.
;;
;; gfm-mode for README.md specifically: GitHub Flavoured Markdown is what those
;; files actually are, and the two differ on tables and on line breaks.
(use-package markdown-mode
  :mode (("\\.md\\'"        . markdown-mode)
         ("\\.markdown\\'"  . markdown-mode)
         ("/README\\.md\\'" . gfm-mode))
  :init (setq markdown-fontify-code-blocks-natively t))

;; .http scratch buffers -- curl-in-a-buffer.  The FILE is restclient.el and
;; the mode is `restclient-mode'; naming the form `restclient' is what makes
;; the emitted autoload point at the right file.
(use-package restclient
  :mode ("\\.http\\'" . restclient-mode)
  :commands (restclient-mode))

;; Common Lisp.  `lisp-mode' is built in and already owns .lisp/.asd, so there
;; is nothing to add to `auto-mode-alist'; what is missing is sly itself, whose
;; entry points carry no reachable autoload here.  Deliberately NOT hooked into
;; `lisp-mode-hook': `sly-editing-mode' is useful, but starting a Lisp on every
;; .lisp visit is not, and `sbcl' is not assumed present.
(use-package sly
  :commands (sly sly-connect sly-mode sly-editing-mode)
  :init (setq inferior-lisp-program "sbcl"))

;;;; ---------------------------------------------------------------------
;;;; major-mode-remap-alist
;;;; ---------------------------------------------------------------------

;; `add-to-list' rather than `setq': `major-mode-remap-alist' is a user option
;; other code may already have written to, and a `setq' here would silently
;; drop whatever it found.  Prepending is also what makes each of these WIN.

;; sh.  (sh-mode . bash-ts-mode) looks dangerous -- .zsh, .csh and .ksh all map
;; to `sh-mode' too, and none of them is bash.  It is SAFE, and only because
;; Emacs 30 ships an advice, `sh--redirect-bash-ts-mode', on `bash-ts-mode'
;; that inspects the guessed shell and hands straight back to `sh-mode' unless
;; it is bash or sh.  MEASURED: a .zsh file under this remap lands in `sh-mode'
;; with no parser, and a .sh file lands in `bash-ts-mode' with one.
;;
;; If that advice is ever dropped upstream this remap becomes a bug, so the
;; gate asserts BOTH halves.
(add-to-list 'major-mode-remap-alist '(sh-mode . bash-ts-mode))

;; python.  `python-mode' here is Emacs's own, from python.el -- not the
;; long-dead python-mode.el package.
(add-to-list 'major-mode-remap-alist '(python-mode . python-ts-mode))

;; javascript-mode, NOT js-mode.  files.el maps .js to the ALIAS
;; `javascript-mode' and the remap lookup is an `assq' on that literal symbol.
;; (js-mode . js-ts-mode) is the form every blog post gives and it does nothing.
(add-to-list 'major-mode-remap-alist '(javascript-mode . js-ts-mode))

;; .json -> `js-json-mode' (js.el), not `json-mode' (a package that is not
;; installed).  Same alias-shaped trap as above.
(add-to-list 'major-mode-remap-alist '(js-json-mode . json-ts-mode))

;; .toml -> `conf-toml-mode' (conf-mode.el).  There is no `toml-mode' built in.
(add-to-list 'major-mode-remap-alist '(conf-toml-mode . toml-ts-mode))

;; Autoload stubs for the remap TARGETS above.  Rule 3 in the commentary:
;; `:mode' stubbed the symbols that went into `auto-mode-alist', and these are
;; not those.  Each form is named for the file the target actually lives in.
(use-package sh-script    :autoload (bash-ts-mode))
(use-package python       :autoload (python-ts-mode))
(use-package json-ts-mode :autoload (json-ts-mode))
(use-package toml-ts-mode :autoload (toml-ts-mode))
;; js-ts-mode and js-json-mode are covered by the `js' form above.

;;;; ---------------------------------------------------------------------
;;;; AUCTeX
;;;; ---------------------------------------------------------------------

;; AUCTeX CANNOT be reached by autoloading `LaTeX-mode', and four variants were
;; measured before this shim was written.  Emacs's own dumped loaddefs ships
;; BOTH
;;
;;   (defalias 'LaTeX-mode #'latex-mode)          ; from tex-mode.el
;;   ... and a `major-mode-remap-defaults' entry pointing at it
;;
;; and `autoload' DOES NOTHING when the symbol is already fboundp.  So every
;; deferred route -- :mode on `LaTeX-mode', :commands, a bare autoload form, a
;; remap entry -- silently resolves to the BUILT-IN `latex-mode' and looks like
;; AUCTeX simply not being installed.
;;
;; A shim under OUR OWN name is the only deferred route that works, because
;; `my/LaTeX-mode' is a symbol nothing else has defined: the `require' runs
;; first, latex.el redefines `LaTeX-mode' for real, and only then is it called.
;;
;; DO NOT "simplify" this to (use-package tex :mode ("\\.tex\\'" . TeX-latex-mode)).
;; That is rule 2 in the commentary: use-package would emit
;; (autoload 'TeX-latex-mode "tex") for a function that lives in latex.el.
(defun my/LaTeX-mode ()
  "Load AUCTeX, then hand off to its `LaTeX-mode'.
Named ours so that nothing has predefined it -- see the commentary above."
  (interactive)
  (require 'tex-site nil t)
  (require 'latex)
  (LaTeX-mode))

(use-package tex
  :mode (("\\.tex\\'" . my/LaTeX-mode)
         ("\\.ltx\\'" . my/LaTeX-mode)
         ("\\.sty\\'" . my/LaTeX-mode)
         ("\\.cls\\'" . my/LaTeX-mode))
  :init
  (setq TeX-auto-save t
        TeX-parse-self t
        TeX-electric-sub-and-superscript t
        ;; A daemon serves many projects; never guess the master file.
        TeX-master nil))

;;;; ---------------------------------------------------------------------
;;;; eglot
;;;; ---------------------------------------------------------------------

;; eglot in 30.2 ships 52 `eglot-server-programs' entries and they cover almost
;; every language in this file.  Re-declaring a covered one would be a second
;; source of truth that drifts from eglot's the first time upstream changes a
;; server's argv -- so there are exactly THREE additions here, and each has a
;; reason that is not "completeness".  The third is here because the gate found
;; it after this file was written, which is what the gate is for.
;;
;; `with-eval-after-load' rather than a use-package `:config': eglot is already
;; declared in init.el with `:commands', and a `:config' here would mean a
;; SECOND `use-package eglot' form, i.e. one more place to look.
(with-eval-after-load 'eglot
  ;; 1. THE GAP.  toml-ts-mode is the one mode in this file with no entry at
  ;;    all.  taplo is installed; "lsp stdio" is its LSP subcommand, not a
  ;;    generic pair of flags.
  (add-to-list 'eglot-server-programs
               '(toml-ts-mode . ("taplo" "lsp" "stdio")))

  ;; 2. THE AMBIGUITY.  Python is the ONLY language here where TWO installed
  ;;    servers match eglot's own entry: pyright-langserver AND ruff are both
  ;;    on PATH, so `M-x eglot' PROMPTS while `eglot-ensure' silently takes
  ;;    whichever comes first.  An interactive prompt on every Python file, and
  ;;    a different server depending on how the session was started, is worse
  ;;    than picking one.  `add-to-list' prepends, so this wins the `assoc'
  ;;    without removing eglot's own entry.
  ;;
  ;;    pyright for types, deliberately: ruff is a linter/formatter and is
  ;;    better used through its own tooling than as the type-checking LSP.
  (add-to-list 'eglot-server-programs
               '((python-mode python-ts-mode) . ("pyright-langserver" "--stdio")))

  ;; 3. THE ONE THAT WAS ASSUMED AND WAS WRONG.  The design for this file said
  ;;    nix-ts-mode and haskell-ts-mode BOTH call `derived-mode-add-parents',
  ;;    so eglot's existing `nix-mode'/`haskell-mode' entries would match both
  ;;    and no entry of our own was needed.  The gate disagreed.  Measured in a
  ;;    daemon on this exact build:
  ;;
  ;;      haskell-ts-mode 1.3.5          extra-parents (haskell-mode)
  ;;                                     eglot -> haskell-language-server-wrapper
  ;;      nix-ts-mode 20260705.1600      extra-parents NIL, parent prog-mode
  ;;                                     eglot -> NOTHING
  ;;
  ;;    So haskell needs nothing and nix needs this line.  Without it every .nix
  ;;    buffer runs `eglot-ensure' against an empty contact and errors, which is
  ;;    the precise failure the "no hook without a server" rule exists to avoid.
  ;;
  ;;    eglot's own nix entry keys on `nix-mode' ALONE and its contact is a
  ;;    FUNCTION that picks among ("nil" "rnix-lsp" "nixd") and PROMPTS when
  ;;    more than one is on PATH.  `nil' -- the executable is genuinely called
  ;;    that -- is the only one of the three installed here, so naming it
  ;;    directly is both unambiguous and one less interactive prompt.
  ;;
  ;;    DELETE THIS if nix-ts-mode ever gains a `derived-mode-add-parents' call:
  ;;    the gate asserts every eglot-hooked mode resolves to a contact, so it
  ;;    will keep telling you the truth either way.
  (add-to-list 'eglot-server-programs '(nix-ts-mode . ("nil"))))

;; NOTHING is added for haskell-ts-mode: `derived-mode-add-parents' makes
;; eglot's existing `haskell-mode' entry fire, and duplicating it here would
;; pin an argv that upstream is free to change.

;; -- eglot-ensure, and ONLY where a server is actually installed -------------
;;
;; Checked against ~/.nix-profile/bin, not against what would be nice:
;;
;;   installed  bash-language-server, pyright-langserver, ruff,
;;              typescript-language-server, vscode-json-language-server, taplo,
;;              yaml-language-server, gopls, rust-analyzer, lua-language-server,
;;              jdtls, nil, haskell-language-server-wrapper, docker-langserver,
;;              marksman
;;   ABSENT     clangd, cmake-language-server, fortls, texlab, nixd
;;
;; The absent four are why c-ts-mode, c++-ts-mode, cmake-ts-mode, fortran-mode
;; and LaTeX get no hook.  `eglot-ensure' with no server logs a connection
;; failure on EVERY find-file, and a config that cries wolf on every file visit
;; is how real eglot errors end up ignored.  Install the server, then add the
;; hook -- in that order.
(dolist (hook '(bash-ts-mode-hook
                python-ts-mode-hook
                js-ts-mode-hook
                typescript-ts-mode-hook
                tsx-ts-mode-hook
                json-ts-mode-hook
                toml-ts-mode-hook
                yaml-ts-mode-hook
                go-ts-mode-hook
                go-mod-ts-mode-hook
                rust-ts-mode-hook
                lua-ts-mode-hook
                java-ts-mode-hook
                nix-ts-mode-hook
                haskell-ts-mode-hook
                dockerfile-ts-mode-hook
                markdown-mode-hook))
  (add-hook hook #'eglot-ensure))

;; eldoc in an eglot buffer defaults to echoing ONE line, and most servers put
;; the signature on line one and the type on line two.  3 is the smallest value
;; that stops the useful half being cut off.
(setq eldoc-echo-area-use-multiline-p 3)

(provide 'my-lang)
;;; my-lang.el ends here
