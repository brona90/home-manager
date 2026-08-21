{
  runCommand,
  emacs,
}: let
  # Base Emacs: pkgs.emacs (30.2) on EVERY platform, deliberately.
  #
  # emacs-overlay offers emacs-unstable (31.x), and on Linux it is cached. But
  # taking it only on Linux introduces a version skew across the fleet on day
  # one -- anything 31-only would build and then fail on the Macs, which is the
  # worst kind of bug to have while a config is still being written. And taking
  # it on darwin is not an option: emacs-overlay's hydraJobs cover x86_64-linux
  # and aarch64-linux ONLY, so emacs-unstable on either Mac is an uncached
  # source build (srcRepo = true, so autogen.sh + autoconf) -- on the Intel
  # Mac's 26.05 stdenv that is the least-tested build path in the tree.
  #
  # Emacs 31.1 releases 2026-08-24. Moving to it is a deliberate one-line
  # change here, made once, after the config is stable and the Intel Mac's
  # future is settled.
  baseEmacs = emacs;

  # The elisp tree as a store path. The module links a COPY of this into
  # $XDG_CONFIG_HOME/emacs with recursive = true; the store path itself is used
  # directly only by `nix run .#emacs-vanilla`, which is precisely the test
  # that early-init.el has redirected every writable path out of the config
  # directory.
  configDir = runCommand "emacs-vanilla-config" {} ''
    mkdir -p $out
    cp -r ${./config}/. $out/
  '';

  # Package set: an EXPLICIT list, deliberately NOT
  # emacsWithPackagesFromUsePackage.
  #
  # emacs-overlay's README: "Config files cannot contain unicode characters,
  # since they're being parsed in nix, which lacks unicode support." The elisp
  # here uses box-drawing section rules and the Doom config we are porting from
  # is full of them. Stripping characters to satisfy a build tool would be the
  # tail wagging the dog, and a silent mis-parse is worse than a manual list.
  #
  # Nothing here may fetch at runtime: early-init.el sets
  # package-enable-at-startup nil and neuters use-package's ensure function.
  withPkgs = baseEmacs.pkgs.withPackages (epkgs:
    with epkgs; [
      # -- infrastructure ---------------------------------------------------
      use-package # built in since 29; pinned so the version is explicit
      no-littering # keeps writable state out of the read-only config dir
      compat # hard dependency of the minad/oantolin packages

      # -- completion -------------------------------------------------------
      vertico
      orderless
      marginalia
      consult
      embark
      embark-consult
      corfu
      cape

      # -- modal editing ----------------------------------------------------
      evil
      evil-collection
      evil-surround
      general # for :keymaps 'override -- a prebuilt evil intercept map

      # -- org ---------------------------------------------------------------
      # org is not listed here, but it is NOT the bundled 9.7 either: org-gcal
      # depends on org, so the ELPA build (9.8.9) comes in transitively and
      # wins the load-path over Emacs 30.2's bundled copy. That is checked, not
      # assumed -- and it is the version we want, because the Doom daemon we
      # are porting from runs 9.8.7. Listing `org' explicitly would pin the
      # same thing twice and make the two disagree the day one moves.
      evil-org # org motions/folding under evil, from Doom's :lang org
      org-gcal # pulls org, oauth2-auto, request-deferred, persist

      # -- version control --------------------------------------------------
      magit
      forge
      diff-hl

      # -- editing / navigation ---------------------------------------------
      vundo # visualiser over built-in undo; no undo-tree needed
      avy
      envrc # per-buffer direnv, unlike direnv.el's global mutation
      ws-butler # trims only lines you touched

      # -- appearance -------------------------------------------------------
      doom-themes
      doom-modeline
      nerd-icons
      rainbow-delimiters
      hl-todo

      # -- language modes ---------------------------------------------------
      #
      # ONLY the modes Emacs 30.2 does not already ship. 30.2 has a -ts-mode
      # in-tree for bash, c, c++, cmake, csharp, css, dockerfile, elixir, go,
      # go-mod, heex, html, java, js, json, lua, php, python, ruby, rust, toml,
      # tsx, typescript and yaml, so none of those need a package -- they need
      # a grammar (below) and an `auto-mode-alist'/`major-mode-remap-alist'
      # entry (lisp/my-lang.el). It LACKS markdown, haskell, nix, fortran,
      # latex, commonlisp and elisp, which is exactly this list plus the
      # built-in non-ts modes.
      markdown-mode
      haskell-ts-mode # tree-sitter Haskell; calls derived-mode-add-parents
      nix-ts-mode #     tree-sitter Nix;     ditto -- see my-lang.el on eglot
      auctex #          LaTeX. Reaching it needs a shim; see my-lang.el
      sly #             Common Lisp REPL; the modern SLIME fork
      restclient #      .http scratch files, the curl-in-a-buffer workflow

      # -- tree-sitter grammars ---------------------------------------------
      #
      # An EXPLICIT list, not `withAllGrammars'. CLOSURE SIZES, measured with
      # `nix path-info -S' on this build:
      #
      #   these 17 grammars      57.0 MiB   (17 .so files)
      #   with-all-grammars     272.9 MiB   (284 .so files)
      #
      # The bundle derivation itself is a symlink farm and weighs nothing; all
      # of that is the individual grammar store paths in its closure. About
      # 20 MiB of the 57 is a glibc base that Emacs already carries, so the NET
      # effect here is ~+37 MiB against ~+253 MiB -- for ~90 grammars nothing in
      # this config can ever load. treesit only creates a parser for a language
      # some MODE asks for, so a grammar with no corresponding -ts-mode is dead
      # weight in the store, forever.
      #
      # DELIBERATELY ABSENT, and do not "complete" the list by adding them:
      # markdown, latex, commonlisp, elisp and fortran. There is no
      # markdown-ts-mode, latex-ts-mode, commonlisp-ts-mode, elisp-ts-mode or
      # fortran-ts-mode in Emacs 30.2 OR in the packages above -- markdown-mode,
      # AUCTeX, sly, lisp-mode and fortran-mode are all font-lock modes. Adding
      # those grammars would grow the closure and never create a parser.
      #
      # jsdoc is not a mode: javascript-ts-mode and typescript-ts-mode embed it
      # as a range parser for /** */ comments and warn without it.
      (treesit-grammars.with-grammars (g:
        with g; [
          tree-sitter-bash
          tree-sitter-dockerfile
          tree-sitter-go
          tree-sitter-gomod
          tree-sitter-haskell
          tree-sitter-java
          tree-sitter-javascript
          tree-sitter-jsdoc
          tree-sitter-json
          tree-sitter-lua
          tree-sitter-nix
          tree-sitter-python
          tree-sitter-rust
          tree-sitter-toml
          tree-sitter-tsx
          tree-sitter-typescript
          tree-sitter-yaml
        ]))
    ]);
in
  withPkgs.overrideAttrs (old: {
    passthru =
      (old.passthru or {})
      // {
        inherit configDir baseEmacs;
      };
    meta =
      (old.meta or {})
      // {
        description = "Hand-built vanilla Emacs (parallel to the Doom daily driver)";
      };
  })
