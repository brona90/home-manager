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

    installSystemWide = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        On macOS, install tmux-helper to /usr/local/bin via the
        `nix run .#tmux-helper-install` flake app for stable
        path-based fingerprinting by BeyondTrust EPM. Setting this
        true here is informational only; the actual copy is done
        out-of-band by the install app and requires sudo.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [cfg.package];
  };
}
