# Linux-specific configuration
{ config, lib, pkgs, ... }:

{
  # Linux-specific packages
  home.packages = with pkgs; [
    gsettings-desktop-schemas
    glib
    dconf
  ];

  # Linux-specific zsh settings
  my.zsh.extraInitExtra = ''
    # Set GSettings schema directory for Emacs (Linux only)
    export GSETTINGS_SCHEMA_DIR="${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}/glib-2.0/schemas"
  '';

  # Linux-specific aliases
  my.zsh.extraAliases = {
    ls = "ls --color=auto";
  };
}
