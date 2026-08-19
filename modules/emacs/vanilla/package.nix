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
