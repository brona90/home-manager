# Linux-specific home-manager configuration
{ config, lib, pkgs, ... }:

{
  home.packages = with pkgs; [
    gsettings-desktop-schemas
    glib
    dconf
  ];

  my.zsh.extraInitExtra = ''
    export GSETTINGS_SCHEMA_DIR="${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}/glib-2.0/schemas"
  '';
}
