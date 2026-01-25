{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.my.emacs;

  # Wrapper script that connects to daemon or starts it
  emacsClientWrapper = pkgs.writeShellScriptBin "em" ''
    # Try to connect to existing daemon, start one if needed
    if ! ${cfg.package}/bin/emacsclient -n -e "(if (daemonp) t)" >/dev/null 2>&1; then
      echo "Starting Emacs daemon..."
      ${cfg.package}/bin/emacs --daemon
    fi

    # Connect to daemon
    if [ -t 0 ] && [ -z "$DISPLAY" ] && [ -z "$WAYLAND_DISPLAY" ]; then
      # Terminal mode (no GUI available)
      exec ${cfg.package}/bin/emacsclient -t "$@"
    else
      # GUI mode
      exec ${cfg.package}/bin/emacsclient -c "$@"
    fi
  '';

  # Terminal-only version
  emacsClientTerminal = pkgs.writeShellScriptBin "emt" ''
    # Try to connect to existing daemon, start one if needed
    if ! ${cfg.package}/bin/emacsclient -n -e "(if (daemonp) t)" >/dev/null 2>&1; then
      echo "Starting Emacs daemon..."
      ${cfg.package}/bin/emacs --daemon
    fi
    exec ${cfg.package}/bin/emacsclient -t "$@"
  '';

in
{
  options.my.emacs = {
    enable = mkEnableOption "Gregory's Doom Emacs configuration";

    package = mkOption {
      type = types.package;
      description = "The Doom Emacs package (built externally with nix-doom-emacs-unstraightened)";
    };

    daemon.enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Emacs daemon via systemd user service";
    };
  };

  config = mkIf cfg.enable {
    home.packages = [
      cfg.package
      pkgs.ispell
      emacsClientWrapper   # 'em' command
      emacsClientTerminal  # 'emt' command
    ];

    # Systemd user service for Emacs daemon
    services.emacs = mkIf cfg.daemon.enable {
      enable = true;
      package = cfg.package;
      defaultEditor = true;
      startWithUserSession = "graphical";
    };

    home.sessionVariables = mkMerge [
      {
        VISUAL = if cfg.daemon.enable then "emacsclient -c" else "emacs";
      }
      (mkIf cfg.daemon.enable {
        EDITOR = "emacsclient -t";
        ALTERNATE_EDITOR = "emacs -nw";
      })
      (mkIf (!cfg.daemon.enable) {
        EDITOR = "emacs -nw";
      })
    ];
  };
}
