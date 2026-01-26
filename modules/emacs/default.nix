{ config, lib, pkgs, ... }:

let
  cfg = config.my.emacs;

  emacsClientWrapper = pkgs.writeShellScriptBin "em" ''
    if ! ${cfg.package}/bin/emacsclient -n -e "(if (daemonp) t)" >/dev/null 2>&1; then
      echo "Starting Emacs daemon..."
      ${cfg.package}/bin/emacs --daemon
    fi

    if [ -t 0 ] && [ -z "$DISPLAY" ] && [ -z "$WAYLAND_DISPLAY" ]; then
      exec ${cfg.package}/bin/emacsclient -t "$@"
    else
      exec ${cfg.package}/bin/emacsclient -c "$@"
    fi
  '';

  emacsClientTerminal = pkgs.writeShellScriptBin "emt" ''
    if ! ${cfg.package}/bin/emacsclient -n -e "(if (daemonp) t)" >/dev/null 2>&1; then
      echo "Starting Emacs daemon..."
      ${cfg.package}/bin/emacs --daemon
    fi
    exec ${cfg.package}/bin/emacsclient -t "$@"
  '';

in
{
  options.my.emacs = {
    enable = lib.mkEnableOption "Gregory's Doom Emacs configuration";

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
    home.packages = [
      cfg.package
      pkgs.ispell
      emacsClientWrapper
      emacsClientTerminal
    ];

    services.emacs = lib.mkIf cfg.daemon.enable {
      enable = true;
      inherit (cfg) package;
      defaultEditor = true;
      startWithUserSession = "graphical";
    };

    home.sessionVariables = lib.mkIf (!cfg.daemon.enable) {
      EDITOR = "emacs -nw";
      VISUAL = "emacs";
    };
  };
}
