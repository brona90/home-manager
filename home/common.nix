# Common home-manager configuration shared across all systems
{ config, lib, pkgs, ... }:

{
  programs.home-manager.enable = true;
  xdg.enable = true;

  # Enable modules
  my.zsh.enable = true;
  my.git.enable = true;
  my.btop.enable = true;
  my.vim.enable = true;
  my.sops.enable = true;

  # Common packages
  home.packages = with pkgs; [
    tree
    bazel_7
    bazel-buildtools
  ];
}
