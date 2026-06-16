# Host: gfoster's NixOS-WSL machine (x86_64-linux).
# Everything personal to this machine — distributed-build builders,
# GPG-to-Windows forwarding, Windows interop aliases — lives here.
# Selected via the users.*.hosts mapping in config.nix; other Linux
# users/systems inherit only the generic home/linux.nix profile.
{config, ...}: let
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
  my = {
    gpg.forwardToWindows = true;

    # Local AI infra lives on this box (Docker + Ollama): the claude-kg knowledge
    # graph and the SearXNG private-search MCP server, both managed declaratively.
    claudeKg.enable = true;
    searxng.enable = true;

    # Windows interop -- /mnt/c is dropped from PATH for zsh perf
    # (FSH command-existence checks per keystroke walk PATH and
    # stat each /mnt/c entry over the 9P bridge). Alias the few
    # .exes actually used so habit-typing keeps working.
    zsh.extraAliases = {
      clip = "/mnt/c/WINDOWS/system32/clip.exe";
      explorer = "/mnt/c/WINDOWS/explorer.exe";
      cmd = "/mnt/c/WINDOWS/system32/cmd.exe";
      powershell = "/mnt/c/WINDOWS/system32/WindowsPowerShell/v1.0/powershell.exe";
      notepad = "/mnt/c/WINDOWS/system32/notepad.exe";
      nrs = ''sudo /run/current-system/sw/bin/nixos-rebuild switch --flake "$HOME/.config/home-manager"'';
    };
  };

  home.file.".config/nix/machines".text = ''
    ssh-ng://gfoster@gregorys-macbook-pro.local?remote-program=${daemon}&ssh-key=${sshKey} x86_64-darwin - 4 1 big-parallel - ${personalHostKey}
    ssh-ng://888973@us-ntlcfv09mt.local?remote-program=${daemon}&ssh-key=${sshKey} aarch64-darwin - 4 2 big-parallel - ${corpHostKey}
  '';

  nix.settings = {
    builders = "@${config.home.homeDirectory}/.config/nix/machines";
    builders-use-substitutes = true;
  };
}
