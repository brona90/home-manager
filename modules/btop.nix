{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.my.btop;
in
{
  options.my.btop = {
    enable = mkEnableOption "btop configuration";
  };

  config = mkIf cfg.enable {
    programs.btop = {
      enable = true;
      settings = {
        color_theme = "Default";
        theme_background = false;
        vim_keys = true;
      };
    };

    xdg.configFile."btop/btop.conf".force = true;
  };
}
