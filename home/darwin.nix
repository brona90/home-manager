# macOS-specific home-manager configuration
{ config, lib, pkgs, ... }:

{
  my.zsh.extraAliases = {
    ls = "ls -G";  # macOS ls uses -G for color
  };
}
