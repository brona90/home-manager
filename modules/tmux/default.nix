{ config, lib, pkgs, ... }:

let
  cfg = config.my.tmux;
in
{
  options.my.tmux = {
    enable = lib.mkEnableOption "tmux configuration (gpakosz/.tmux)";

    configDir = lib.mkOption {
      type = lib.types.path;
      description = "Path to the tmux config directory containing .tmux.conf and .tmux.conf.local";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.perl ];

    programs.tmux = {
      enable = true;
      terminal = "tmux-256color";
      extraConfig = ''
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
    };
  };
}
