{ config, lib, pkgs, ... }:

let
  cfg = config.my.btop;
in
{
  options.my.btop = {
    enable = lib.mkEnableOption "btop system monitor";

    updateMs = lib.mkOption {
      type = lib.types.int;
      default = 100;
      description = "Update time in milliseconds";
    };
  };

  config = lib.mkIf cfg.enable {
    programs.btop = {
      enable = true;
      settings = {
        color_theme = "Default";
        theme_background = false;
        vim_keys = true;
        update_ms = cfg.updateMs;
      };
    };

    xdg.configFile."btop/btop.conf".force = true;
  };
}
