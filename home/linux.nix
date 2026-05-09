# Linux-specific home-manager configuration
{
  config,
  pkgs,
  ...
}: let
  # Distributed-build targets. Lives in user nix.conf because this is a
  # standalone (non-NixOS) home-manager install -- we can't manage
  # /etc/nix/nix.conf declaratively, but trusted-users (which gfoster is,
  # set in /etc/nix/nix.conf manually) can override `builders` from their
  # own ~/.config/nix/nix.conf. The daemon merges them at request time.
  #
  # remote-program absolute path is required because the Macs run a
  # customized zsh (nohashdirs, empty $path array) where bare-command PATH
  # lookup silently fails in non-interactive SSH sessions -- ssh-ng's
  # default `nix-daemon --stdio` would otherwise hit `command not found`.
  #
  # ssh-key points at the sops-decrypted RSA key (mode 600, gfoster-owned;
  # the daemon's spawned ssh runs as gfoster on this standalone setup).
  sshKey = "${config.home.homeDirectory}/.config/sops-nix/secrets/ssh/id_rsa";
  daemon = "/nix/var/nix/profiles/default/bin/nix-daemon";
  # base64 of "ssh-ed25519 <key>" for each Mac, pinned here so the daemon
  # can verify the host without /root/.ssh/known_hosts.
  personalHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUhCNlR2OGJrUm9FeFdzL1Y2NDJNNm1vUzljR0NSOVRhZTlkajYvTENhQ0E=";
  corpHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUVuVjQvSG1YZ1dQajA2Ui83M1hnMUVtaVIwSjdxUXJ0ajRTLzJMdjRKZmM=";
in {
  home.packages = with pkgs; [
    gsettings-desktop-schemas
    glib
    dconf
    claude-code # Anthropic Claude CLI
  ];

  my.gpg.forwardToWindows = true;

  my.zsh.extraInitExtra = ''
    # Only set GSETTINGS_SCHEMA_DIR when a display server is present
    if [[ -n "''${DISPLAY:-}''${WAYLAND_DISPLAY:-}" ]]; then
      export GSETTINGS_SCHEMA_DIR="${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}/glib-2.0/schemas"
    fi
  '';

  home.file.".config/nix/machines".text = ''
    ssh-ng://gfoster@gregorys-macbook-pro.local?remote-program=${daemon}&ssh-key=${sshKey} x86_64-darwin - 4 1 big-parallel - ${personalHostKey}
    ssh-ng://888973@us-ntlcfv09mt.local?remote-program=${daemon}&ssh-key=${sshKey} aarch64-darwin - 4 2 big-parallel - ${corpHostKey}
  '';

  nix.settings = {
    builders = "@${config.home.homeDirectory}/.config/nix/machines";
    builders-use-substitutes = true;
  };
}
