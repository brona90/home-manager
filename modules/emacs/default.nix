{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.my.emacs;

  emacsClientWrapper = pkgs.writeShellApplication {
    name = "em";
    text = ''
      if ! ${cfg.package}/bin/emacsclient -n -e "(if (daemonp) t)" >/dev/null 2>&1; then
        echo "Starting Emacs daemon..."
        # || true: daemon start may fail if another instance just raced us here;
        # emacsclient below will connect to whichever daemon won.
        ${cfg.package}/bin/emacs --daemon || true
      fi

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
      if ! ${cfg.package}/bin/emacsclient -n -e "(if (daemonp) t)" >/dev/null 2>&1; then
        echo "Starting Emacs daemon..."
        ${cfg.package}/bin/emacs --daemon || true
      fi
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
    home.packages = [
      cfg.package
      pkgs.ispell
      pkgs.typescript-language-server
      pkgs.pyright
      emacsClientWrapper
      emacsClientTerminal
    ];

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
