# macOS-specific configuration
{ config, lib, pkgs, ... }:

{
  # macOS-specific aliases
  my.zsh.extraAliases = {
    ls = "ls -G";
  };
}
