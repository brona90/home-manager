# Linux-specific home-manager configuration
{pkgs, ...}: {
  home.packages = with pkgs; [
    gsettings-desktop-schemas
    glib
    dconf
  ];

  my.zsh.extraInitExtra = ''
    # Only set GSETTINGS_SCHEMA_DIR when a display server is present
    if [[ -n "''${DISPLAY:-}''${WAYLAND_DISPLAY:-}" ]]; then
      export GSETTINGS_SCHEMA_DIR="${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}/glib-2.0/schemas"
    fi
  '';
}
