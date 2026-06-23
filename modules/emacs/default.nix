{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.my.emacs;

  # Bring up a daemon if none is answering. On Linux the daemon is owned by the
  # systemd user unit, so we start *that* rather than spawning a raw `emacs
  # --daemon`: two daemons racing for the same server socket deadlocks the unit
  # into a crash loop (the standalone one squats the socket, `--fg-daemon` can
  # never bind it, Restart=on-failure relaunches forever, pegging a core).
  # `emacs --daemon` stays only as the fallback for hosts without the unit
  # (e.g. macOS, or daemon.enable = false). After starting, wait for the socket
  # to accept connections since Doom can take several seconds to load.
  ensureDaemon = ''
    if ! ${cfg.package}/bin/emacsclient -n -e "(if (daemonp) t)" >/dev/null 2>&1; then
      echo "Starting Emacs daemon..."
      ${
      if pkgs.stdenv.isLinux
      then "systemctl --user start emacs 2>/dev/null || ${cfg.package}/bin/emacs --daemon || true"
      else "${cfg.package}/bin/emacs --daemon || true"
    }
      for _ in $(seq 1 100); do
        ${cfg.package}/bin/emacsclient -n -e t >/dev/null 2>&1 && break
        sleep 0.1
      done
    fi
  '';

  emacsClientWrapper = pkgs.writeShellApplication {
    name = "em";
    text = ''
      ${ensureDaemon}
      if [ -t 0 ] && [ -z "''${DISPLAY:-}" ] && [ -z "''${WAYLAND_DISPLAY:-}" ]; then
        exec ${cfg.package}/bin/emacsclient -t "$@"
      else
        exec ${cfg.package}/bin/emacsclient -c "$@"
      fi
    '';
  };

  emacsClientTerminal = pkgs.writeShellApplication {
    name = "emt";
    text = ''
      ${ensureDaemon}
      exec ${cfg.package}/bin/emacsclient -t "$@"
    '';
  };
in {
  options.my.emacs = {
    enable = lib.mkEnableOption "Doom Emacs configuration with nix-doom-emacs-unstraightened";

    package = lib.mkOption {
      type = lib.types.package;
      description = "The Doom Emacs package (built externally with nix-doom-emacs-unstraightened)";
    };

    daemon.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Emacs daemon via systemd user service";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages =
      [
        cfg.package
        pkgs.ispell
        pkgs.typescript-language-server
        pkgs.pyright
        pkgs.gopls
        pkgs.jdt-language-server
        emacsClientWrapper
        emacsClientTerminal
      ]
      # sbcl is gated to Linux: the ECL bootstrap segfaults on macOS
      # (upstream nixpkgs issue with SBCL 2.6.3). Installed via Homebrew
      # on Darwin instead (see home/darwin.nix).
      ++ lib.optional pkgs.stdenv.isLinux pkgs.sbcl
      # haskell-language-server is gated to Linux: cache.nixos.org has been
      # delivering the darwin closure at byte-trickle speed (multiple CI runs
      # blew the 60min cap copying this single path), and the user doesn't
      # write Haskell on the corporate Mac. Linux runs build it from cache
      # in seconds.
      ++ lib.optional pkgs.stdenv.isLinux pkgs.haskell-language-server;

    services.emacs = lib.mkIf cfg.daemon.enable {
      enable = true;
      inherit (cfg) package;
      # true = WantedBy default.target (any user session, works in headless WSL).
      # "graphical" = WantedBy graphical-session.target (display server required).
      startWithUserSession =
        if pkgs.stdenv.isLinux
        then true
        else "graphical";
    };

    # Harden the systemd-managed daemon against the socket-squat deadlock:
    #   - ExecStartPre clears a stale server socket so a clean (re)start always
    #     wins the socket path (`%t` = $XDG_RUNTIME_DIR, e.g. /run/user/1000).
    #   - StartLimitBurst/RestartSec bound the restart loop: if it fails 3x in
    #     60s it stops in `failed` state (visible) instead of relaunching every
    #     ~100ms and burning a CPU core indefinitely.
    systemd.user.services.emacs = lib.mkIf (cfg.daemon.enable && pkgs.stdenv.isLinux) {
      Service = {
        ExecStartPre = "-${pkgs.coreutils}/bin/rm -f %t/emacs/server";
        RestartSec = 5;
      };
      Unit = {
        StartLimitIntervalSec = 60;
        StartLimitBurst = 3;
      };
    };

    home.sessionVariables = {
      EDITOR =
        if cfg.daemon.enable
        then "emacsclient -t --alternate-editor 'emacs -nw'"
        else "emacs -nw";
      VISUAL =
        if cfg.daemon.enable
        then "emacsclient -c --alternate-editor emacs"
        else "emacs";
    };
  };
}
