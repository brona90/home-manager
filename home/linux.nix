# Linux-specific home-manager configuration (platform-generic).
# Machine-specific config (WSL interop, build farm, GPG forwarding)
# lives in home/hosts/ — see the users.*.hosts mapping in config.nix.
{pkgs, ...}: {
  my.zsh.extraInitExtra = ''
    # Only set GSETTINGS_SCHEMA_DIR when a display server is present
    if [[ -n "''${DISPLAY:-}''${WAYLAND_DISPLAY:-}" ]]; then
      export GSETTINGS_SCHEMA_DIR="${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}/glib-2.0/schemas"
    fi
  '';

  home.packages = with pkgs; [
    gsettings-desktop-schemas
    glib
    dconf
  ];
}
