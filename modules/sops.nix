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

  config = lib.mkIf (cfg.enable && secretsExist) {
    home = {
      packages = [ pkgs.sops pkgs.age ];

      activation.createSshDir = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
        mkdir -p "${config.home.homeDirectory}/.ssh"
        chmod 700 "${config.home.homeDirectory}/.ssh"
      '';

      sessionVariables = {
        GITHUB_TOKEN_FILE = config.sops.secrets.github_token.path;
        DOCKERHUB_TOKEN_FILE = config.sops.secrets.dockerhub_token.path;
      };
    };

    sops = {
      age.keyFile = cfg.ageKeyFile;
      defaultSopsFile = secretsFile;

      # Required on macOS: LaunchAgent needs PATH to find getconf
      environment.PATH = lib.mkForce "/usr/bin";

      secrets = {
        github_token = {};
        dockerhub_token = {};
        "ssh/id_rsa" = {
          path = "${config.home.homeDirectory}/.ssh/id_rsa";
          mode = "0600";
        };
        "ssh/id_rsa_pub" = {
          path = "${config.home.homeDirectory}/.ssh/id_rsa.pub";
          mode = "0644";
        };
      };
    };

    my.zsh.extraInitExtra = ''
      github-token() { cat "$GITHUB_TOKEN_FILE" 2>/dev/null || echo "Secret not available"; }
      dockerhub-token() { cat "$DOCKERHUB_TOKEN_FILE" 2>/dev/null || echo "Secret not available"; }
    '';
  };
}
