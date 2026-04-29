# Common home-manager configuration shared across all systems
{
  config,
  lib,
  pkgs,
  userConfig,
  ...
}: let
  cachixCache = userConfig.repo.cachixCache or "";
  cachixPublicKey = userConfig.repo.cachixPublicKey or "";
in {
  programs.home-manager.enable = true;
  xdg.enable = true;

  my = {
    zsh.enable = true;
    git.enable = true;
    git.signing.enable = true;
    gpg.enable = true;
    btop.enable = true;
    vim.enable = true;
    sops.enable = true;
    dockerTerminal.enable = true;
    emacsMcp.enable = true;
    claudeCode.enable = true;
  };

  # Manage ~/.config/nix/nix.conf declaratively.
  # Use extra-* variants so settings append to the system list and work
  # for non-root users even before trusted-users is configured.
  nix.package = pkgs.nix;

  nix.settings = {
    extra-experimental-features = ["nix-command" "flakes"];
    extra-substituters =
      [
        "https://nix-community.cachix.org"
        "https://emacs.cachix.org"
      ]
      ++ lib.optional (cachixCache != "") "https://${cachixCache}.cachix.org";
    extra-trusted-public-keys =
      [
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "emacs.cachix.org-1:b1SMJNLY/mZF6GxQE+eDBeps7WnkT0Po55TAyzwOxTY="
      ]
      ++ lib.optional (cachixPublicKey != "") cachixPublicKey;
  };

  home = {
    # Include user-local scripts/binaries on all machines
    sessionPath = ["${config.home.homeDirectory}/.local/bin"];

    # Locale settings (important for SSH sessions and special characters)
    sessionVariables = {
      LANG = "en_US.UTF-8";
      LC_ALL = "en_US.UTF-8";
    };

    # Common packages
    packages = with pkgs;
      [
        tree
        # Migrated from mise global config (formerly node-pinned by mise@latest);
        # nixpkgs is faster (zero hook-env cost) and reproducible via flake lock.
        jq
        fd
        bat # syntax-highlighted cat
        shellcheck
        watchexec
        imagemagick
        bazel_7
        bazel-buildtools
        aspell
        aspellDicts.en
        ispell
        eza # modern ls replacement (exa fork)
        cachix # Nix binary cache
        texlive.combined.scheme-medium
      ]
      # Skip lilypond on macOS - installed via Homebrew formula on Darwin (darwin.nix)
      ++ lib.optionals (!pkgs.stdenv.isDarwin) [lilypond];
    # calibre: GUI app — installed via Homebrew cask on macOS (darwin.nix);
    # Nix build broken on Linux (qtbase6-setup-hook missing qmake)
  };
}
