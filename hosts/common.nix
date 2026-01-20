# Common configuration shared across all machines
{ config, lib, pkgs, ... }:

{
  # Enable our custom modules
  my.zsh.enable = true;
  my.git.enable = true;
  my.btop.enable = true;
  my.vim.enable = true;
  # my.tmux.enable = true;  # Uncomment after setting configDir
  # my.emacs.enable = true; # Uncomment after setting package

  # Common packages
  home.packages = with pkgs; [
    tree
    bazel_7
    bazel-buildtools
  ];

  # XDG directories
  xdg.enable = true;

  # Session variables
  home.sessionVariables = {
    EDITOR = "emacs -nw";
    VISUAL = "emacs -nw";
  };
}
