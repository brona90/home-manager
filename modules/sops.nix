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
      packages = [ pkgs.sops pkgs.age pkgs.gnupg ];

      activation = {
        createSshDir = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
          mkdir -p "${config.home.homeDirectory}/.ssh"
          chmod 700 "${config.home.homeDirectory}/.ssh"
        '';

        decryptSopsSecrets = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        # On WSL, systemd user services don't work, so decrypt secrets manually
        if [ -f "${cfg.ageKeyFile}" ]; then
          export SOPS_AGE_KEY_FILE="${cfg.ageKeyFile}"
          
          # Create secrets directory  
          SECRETS_DIR="${config.home.homeDirectory}/.config/sops-nix/secrets"
          mkdir -p "$SECRETS_DIR"
          chmod 700 "$SECRETS_DIR"
          
          # Decrypt github_token
          if ${pkgs.sops}/bin/sops -d --extract '["github_token"]' "${secretsFile}" > "$SECRETS_DIR/github_token.tmp" 2>/dev/null; then
            chmod 0400 "$SECRETS_DIR/github_token.tmp"
            mv -f "$SECRETS_DIR/github_token.tmp" "$SECRETS_DIR/github_token"
          fi
          
          # Decrypt dockerhub_token
          if ${pkgs.sops}/bin/sops -d --extract '["dockerhub_token"]' "${secretsFile}" > "$SECRETS_DIR/dockerhub_token.tmp" 2>/dev/null; then
            chmod 0400 "$SECRETS_DIR/dockerhub_token.tmp"
            mv -f "$SECRETS_DIR/dockerhub_token.tmp" "$SECRETS_DIR/dockerhub_token"
          fi
          
          # Decrypt SSH keys
          if ${pkgs.sops}/bin/sops -d --extract '["ssh"]["id_rsa"]' "${secretsFile}" > "${config.home.homeDirectory}/.ssh/id_rsa.tmp" 2>/dev/null; then
            chmod 0600 "${config.home.homeDirectory}/.ssh/id_rsa.tmp"
            mv -f "${config.home.homeDirectory}/.ssh/id_rsa.tmp" "${config.home.homeDirectory}/.ssh/id_rsa"
          fi
          
          if ${pkgs.sops}/bin/sops -d --extract '["ssh"]["id_rsa_pub"]' "${secretsFile}" > "${config.home.homeDirectory}/.ssh/id_rsa.pub.tmp" 2>/dev/null; then
            chmod 0644 "${config.home.homeDirectory}/.ssh/id_rsa.pub.tmp"
            mv -f "${config.home.homeDirectory}/.ssh/id_rsa.pub.tmp" "${config.home.homeDirectory}/.ssh/id_rsa.pub"
          fi
          
          # Decrypt GPG keys
          if ${pkgs.sops}/bin/sops -d --extract '["gpg"]["private_key"]' "${secretsFile}" > "$SECRETS_DIR/gpg_private_key.tmp" 2>/dev/null; then
            chmod 0600 "$SECRETS_DIR/gpg_private_key.tmp"
            mv -f "$SECRETS_DIR/gpg_private_key.tmp" "$SECRETS_DIR/gpg_private_key"
          fi
          
          if ${pkgs.sops}/bin/sops -d --extract '["gpg"]["public_key"]' "${secretsFile}" > "$SECRETS_DIR/gpg_public_key.tmp" 2>/dev/null; then
            chmod 0644 "$SECRETS_DIR/gpg_public_key.tmp"
            mv -f "$SECRETS_DIR/gpg_public_key.tmp" "$SECRETS_DIR/gpg_public_key"
          fi
        fi
        '';

        importGpgKey = lib.hm.dag.entryAfter [ "decryptSopsSecrets" ] ''
          if [ -f "${config.sops.secrets."gpg/private_key".path}" ]; then
            export GNUPGHOME="${config.home.homeDirectory}/.gnupg"
            ${pkgs.gnupg}/bin/gpg --batch --import "${config.sops.secrets."gpg/private_key".path}" 2>/dev/null || true
          fi
        '';
      };

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
        github_token = {
          path = "${config.home.homeDirectory}/.config/sops-nix/secrets/github_token";
        };
        dockerhub_token = {
          path = "${config.home.homeDirectory}/.config/sops-nix/secrets/dockerhub_token";
        };
        "ssh/id_rsa" = {
          path = "${config.home.homeDirectory}/.ssh/id_rsa";
          mode = "0600";
        };
        "ssh/id_rsa_pub" = {
          path = "${config.home.homeDirectory}/.ssh/id_rsa.pub";
          mode = "0644";
        };
        "gpg/private_key" = {
          path = "${config.home.homeDirectory}/.config/sops-nix/secrets/gpg_private_key";
          mode = "0600";
        };
        "gpg/public_key" = {
          path = "${config.home.homeDirectory}/.config/sops-nix/secrets/gpg_public_key";
          mode = "0644";
        };
      };
    };

    programs.gpg = {
      enable = true;
      homedir = "${config.home.homeDirectory}/.gnupg";
    };

    my.zsh.extraInitExtra = ''
      # GPG needs TTY for pinentry
      export GPG_TTY=$(tty)

      # SOPS editor - use emt which handles daemon startup
      export SOPS_EDITOR="emt"

      github-token() { cat "$GITHUB_TOKEN_FILE" 2>/dev/null || echo "Secret not available"; }
      dockerhub-token() { cat "$DOCKERHUB_TOKEN_FILE" 2>/dev/null || echo "Secret not available"; }
    '';
  };
}
