# Common home-manager configuration shared across all systems
{
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

  # Locale settings (important for SSH sessions and special characters)
  home.sessionVariables = {
    LANG = "en_US.UTF-8";
    LC_ALL = "en_US.UTF-8";
  };

  # Common packages
  home.packages = with pkgs;
    [
      tree
      jq
      bat # syntax-highlighted cat
      bazel_7
      bazel-buildtools
      aspell
      aspellDicts.en
      cachix # Nix binary cache
    ]
    # Skip lilypond on macOS - it has build errors on aarch64-darwin
    ++ lib.optionals (!pkgs.stdenv.isDarwin) [lilypond];
}
