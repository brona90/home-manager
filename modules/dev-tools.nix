# Developer toolchain: compilers, formatters, linters and the CLI utilities
# the rest of this configuration assumes are on PATH.
#
# This module exists because of what it is NOT.  Until LazyVim was removed,
# every package below was a `home.packages` entry inside
# `modules/vim/default.nix`, where it sat as one of *neovim's* dependencies --
# the Nix-side replacement for mason.nvim, feeding conform.nvim and nvim-lint.
# Deleting that module without rehoming them would have taken `rg`, `fzf`, the
# compiler toolchain, every formatter and every linter out of the profile as a
# side effect of removing an editor.  Nothing here is neovim-specific and
# nothing here was added by the removal: this is the same set, relocated.
#
# Language servers deliberately do NOT live here.  They moved to
# `modules/emacs/default.nix`, next to the config that hooks them:
# `modules/emacs/vanilla/config/lisp/my-lang.el` enumerates exactly which
# servers must be on PATH for its `eglot-ensure' hook list, and a list split
# across two modules is a list that drifts.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.my.devTools;
in {
  options.my.devTools = {
    # NOT safe to turn off to slim a profile, despite reading like it is.
    # Emacs needs cmake and a C compiler from this list at RUNTIME -- vterm
    # compiles its module on first use and treesit compiles grammars -- so
    # disabling this while my.emacs.enable is true gives a working build and a
    # broken editor. Drop individual packages instead.
    enable = lib.mkEnableOption "developer toolchain (compilers, formatters, linters, CLI utilities)";
  };

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs;
      [
        # -- CLI utilities with named consumers elsewhere in this repo ------
        # ripgrep: `consult-ripgrep' throughout
        #          modules/emacs/vanilla/config/lisp/my-bindings.el
        # fzf:     the tmux popup pickers (`prefix s/w/./P'), which shell out
        #          to it -- see modules/tmux/conf-experimental.nix
        ripgrep
        fzf
        curl
        wget
        unzip
        gnutar
        gzip
        # fd, tree, shellcheck and bat are in home/common.nix; git comes from
        # programs.git in modules/git.nix.  Not repeated here.

        # -- Build toolchain -------------------------------------------------
        # Emacs needs these at *runtime*, not just to build: vterm compiles its
        # module with cmake, and treesit compiles grammars with a C compiler.
        gnumake
        cmake
        pkg-config
        sqlite
        tree-sitter
        ast-grep

        # -- Formatters ------------------------------------------------------
        # alejandra is also in .#lint-tools (lib/lint-tools.nix), which is what
        # the git hooks and CI resolve.  This copy is for running it by hand;
        # the gate does not depend on it.
        alejandra
        stylua
        black
        isort
        prettier
        gofumpt
        shfmt

        # -- Linters ---------------------------------------------------------
        pylint
        eslint
        markdownlint-cli
        yamllint

        # -- Debuggers -------------------------------------------------------
        python3Packages.debugpy
        delve

        # -- Git-adjacent ----------------------------------------------------
        lazygit
        delta
      ]
      ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [
        # gcc on Linux only: Darwin gets clang from the Xcode command line
        # tools, and adding gcc there fights the SDK rather than helping.
        gcc
        # X11 and Wayland clipboard bridges.  macOS has pbcopy/pbpaste.
        xclip
        wl-clipboard
        # Fontconfig picks fonts up from home.packages on Linux.  Darwin does
        # NOT -- CoreText only sees ~/Library/Fonts -- so the Mac installs this
        # same font by symlinking it there itself, in home/darwin.nix.  Listing
        # it in home.packages on Darwin was decorative.
        #
        # The consumer is `my/font-family' in
        # modules/emacs/vanilla/config/init.el, which asks for the family by
        # name ("VictorMono Nerd Font").  Nothing asserts that the name it asks
        # for is the family either installer provides; if Emacs ever comes up
        # with fallback glyphs, check that pairing first.
        nerd-fonts.victor-mono
      ];
  };
}
