{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.my.tmux;

  # Path to the helper binary in /nix/store. Phase 2 only references this when
  # useHelper = true; otherwise Nix laziness keeps it from being evaluated.
  helperBin = "${config.my.tmuxHelper.package}/bin/tmux-helper";

  experimentalConf = pkgs.writeText "tmux-experimental.conf" (
    import ./conf-experimental.nix {inherit helperBin;}
  );
in {
  options.my.tmux = {
    enable = lib.mkEnableOption "tmux configuration (gpakosz/.tmux)";

    configDir = lib.mkOption {
      type = lib.types.path;
      description = "Path to the tmux config directory containing .tmux.conf and .tmux.conf.local";
    };

    useHelper = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        When true, replaces the bundled gpakosz config with the Nix-generated
        experimental tmux.conf driven by the tmux-helper Go binary. Off by
        default until the rewrite reaches feature parity (Phase 9). For ad-hoc
        testing without flipping this flag, run `nix run .#tmux-experimental`
        which spins up a parallel tmux server on a separate socket.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [pkgs.perl];

    programs.tmux = {
      enable = true;
      terminal = "tmux-256color";
      extraConfig =
        if cfg.useHelper
        then ''
          source-file ${experimentalConf}
        ''
        else ''
          # UTF-8 and true color support
          set -g default-terminal "tmux-256color"
          set -ag terminal-overrides ",xterm-256color:RGB"
          set -ag terminal-overrides ",*256col*:Tc"

          # Ensure UTF-8
          set -q -g status-utf8 on
          setw -q -g utf8 on

          # Source the gpakosz config
          source-file ${cfg.configDir}/.tmux.conf
        '';
    };

    home.sessionVariables = {
      TMUX_CONF = "${cfg.configDir}/.tmux.conf";
      TMUX_CONF_LOCAL = "${cfg.configDir}/.tmux.conf.local";
      TMUX_PLUGIN_MANAGER_PATH = "$HOME/.tmux/plugins";
      # Read by `tmux-helper reload` so prefix-r knows what to source-file.
      TMUX_HELPER_CONF = "${experimentalConf}";
    };
  };
}
