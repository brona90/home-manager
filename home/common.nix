# Common home-manager configuration shared across all systems
{ config, lib, pkgs, ... }:

{
  programs.home-manager.enable = true;
  xdg.enable = true;

  my = {
    zsh.enable = true;
    git.enable = true;
    btop.enable = true;
    vim.enable = true;
    sops.enable = true;
  };

  # Common packages
  home.packages = with pkgs; [
    tree
    bazel_7
    bazel-buildtools
  ];
}
