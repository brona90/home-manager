# SOPS secrets configuration
{ config, lib, pkgs, ... }:

let
  cfg = config.my.sops;
  secretsFile = ../secrets/secrets.yaml;
  secretsExist = builtins.pathExists secretsFile;
in
{
  options.my.sops = {
    enable = lib.mkEnableOption "sops-nix secrets management";

    ageKeyFile = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
      description = "Path to age private key";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.sops pkgs.age ];

    sops = {
      age.keyFile = cfg.ageKeyFile;
      defaultSopsFile = lib.mkIf secretsExist secretsFile;

      # Example secrets (uncomment when secrets.yaml exists):
      # secrets.github_token = {};
      # secrets.openai_api_key = {};
      # secrets."ssh/id_ed25519" = {
      #   path = "${config.home.homeDirectory}/.ssh/id_ed25519";
      #   mode = "0600";
      # };
    };
  };
}
