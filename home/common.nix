# Common home-manager configuration shared across all systems
{ pkgs, ... }:

{
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
  home.packages = with pkgs; [
    tree
    bazel_7
    bazel-buildtools
    aspell
    aspellDicts.en
  ];
}
