{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.my.tmuxHelper;
in {
  options.my.tmuxHelper = {
    enable = lib.mkEnableOption "tmux-helper Go binary (companion to my.tmux)";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./package.nix {};
      defaultText = lib.literalExpression "pkgs.callPackage ./package.nix {}";
      description = "The tmux-helper package to install.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [cfg.package];
  };
}
