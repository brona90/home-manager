{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.my.tmux;
in
{
  options.my.tmux = {
    enable = mkEnableOption "Gregory's tmux configuration (gpakosz/.tmux)";

    configDir = mkOption {
      type = types.path;
      description = "Path to the tmux config directory containing .tmux.conf and .tmux.conf.local";
    };
  };

  config = mkIf cfg.enable {
    home.packages = [
      pkgs.perl  # Required for tmux plugins
    ];

    programs.tmux = {
      enable = true;
      extraConfig = ''
        # Source the gpakosz config
        source-file ${cfg.configDir}/.tmux.conf
      '';
    };

    # Set TMUX_CONF environment variable for the config to find itself
    # Set TMUX_PLUGIN_MANAGER_PATH to writable location (not Nix store)
    home.sessionVariables = {
      TMUX_CONF = "${cfg.configDir}/.tmux.conf";
      TMUX_CONF_LOCAL = "${cfg.configDir}/.tmux.conf.local";
      TMUX_PLUGIN_MANAGER_PATH = "$HOME/.tmux/plugins";
    };
  };
}
