# Common home-manager configuration shared across all systems
{
  config,
  lib,
  pkgs,
  ...
}: {
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
        jq
        bat # syntax-highlighted cat
        bazel_7
        bazel-buildtools
        aspell
        aspellDicts.en
        cachix # Nix binary cache
        claude-code # Anthropic Claude CLI
      ]
      # Skip lilypond on macOS - it has build errors on aarch64-darwin
      ++ lib.optionals (!pkgs.stdenv.isDarwin) [lilypond];
  };
}
