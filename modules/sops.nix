# SOPS secrets configuration
{ config, lib, pkgs, ... }:

let
  cfg = config.my.sops;
  secretsFile = ../secrets/secrets.yaml;
  secretsExist = builtins.pathExists secretsFile;
  inherit (pkgs.stdenv) isDarwin;
  secretsDir = "${config.home.homeDirectory}/.config/sops-nix/secrets";
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

      activation = {
        createSshDir = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
          mkdir -p "${config.home.homeDirectory}/.ssh"
          chmod 700 "${config.home.homeDirectory}/.ssh"
        '';
      } // lib.optionalAttrs isDarwin {
        # Manual decryption for Darwin only
        # On Darwin: LaunchAgent is blocked by AMFI/code signing, so this is required
        # On Linux: native sops-nix systemd service handles decryption
        decryptSopsSecrets = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          if [ -f "${cfg.ageKeyFile}" ]; then
            export SOPS_AGE_KEY_FILE="${cfg.ageKeyFile}"
            
            # Create secrets directory  
            mkdir -p "${secretsDir}"
            chmod 700 "${secretsDir}"
            
            # Decrypt github_token
            if ${pkgs.sops}/bin/sops -d --extract '["github_token"]' "${secretsFile}" > "${secretsDir}/github_token.tmp" 2>/dev/null; then
              chmod 0400 "${secretsDir}/github_token.tmp"
              mv -f "${secretsDir}/github_token.tmp" "${secretsDir}/github_token"
            fi
            
            # Decrypt dockerhub_token
            if ${pkgs.sops}/bin/sops -d --extract '["dockerhub_token"]' "${secretsFile}" > "${secretsDir}/dockerhub_token.tmp" 2>/dev/null; then
              chmod 0400 "${secretsDir}/dockerhub_token.tmp"
              mv -f "${secretsDir}/dockerhub_token.tmp" "${secretsDir}/dockerhub_token"
            fi
            
            # Decrypt cachix_token
            if ${pkgs.sops}/bin/sops -d --extract '["cachix_token"]' "${secretsFile}" > "${secretsDir}/cachix_token.tmp" 2>/dev/null; then
              chmod 0400 "${secretsDir}/cachix_token.tmp"
              mv -f "${secretsDir}/cachix_token.tmp" "${secretsDir}/cachix_token"
            fi
            
            # Decrypt SSH keys - write directly, not via symlink
            if ${pkgs.sops}/bin/sops -d --extract '["ssh"]["id_rsa"]' "${secretsFile}" > "${config.home.homeDirectory}/.ssh/id_rsa.tmp" 2>/dev/null; then
              chmod 0600 "${config.home.homeDirectory}/.ssh/id_rsa.tmp"
              mv -f "${config.home.homeDirectory}/.ssh/id_rsa.tmp" "${config.home.homeDirectory}/.ssh/id_rsa"
            fi
            
            if ${pkgs.sops}/bin/sops -d --extract '["ssh"]["id_rsa_pub"]' "${secretsFile}" > "${config.home.homeDirectory}/.ssh/id_rsa.pub.tmp" 2>/dev/null; then
              chmod 0644 "${config.home.homeDirectory}/.ssh/id_rsa.pub.tmp"
              mv -f "${config.home.homeDirectory}/.ssh/id_rsa.pub.tmp" "${config.home.homeDirectory}/.ssh/id_rsa.pub"
            fi
            
            # Decrypt GPG keys
            mkdir -p "${secretsDir}"
            if ${pkgs.sops}/bin/sops -d --extract '["gpg"]["private_key"]' "${secretsFile}" > "${secretsDir}/gpg_private_key.tmp" 2>/dev/null; then
              chmod 0600 "${secretsDir}/gpg_private_key.tmp"
              mv -f "${secretsDir}/gpg_private_key.tmp" "${secretsDir}/gpg_private_key"
            fi
            
            if ${pkgs.sops}/bin/sops -d --extract '["gpg"]["public_key"]' "${secretsFile}" > "${secretsDir}/gpg_public_key.tmp" 2>/dev/null; then
              chmod 0644 "${secretsDir}/gpg_public_key.tmp"
              mv -f "${secretsDir}/gpg_public_key.tmp" "${secretsDir}/gpg_public_key"
            fi
          else
            echo "Warning: Age key file not found at ${cfg.ageKeyFile}"
            echo "Secrets will not be decrypted. Run: age-keygen -o ${cfg.ageKeyFile}"
          fi
        '';

        importGpgKey = lib.hm.dag.entryAfter [ "decryptSopsSecrets" ] ''
          GPG_PRIVATE_KEY="${secretsDir}/gpg_private_key"
          if [ -f "$GPG_PRIVATE_KEY" ]; then
            export GNUPGHOME="${config.home.homeDirectory}/.gnupg"
            ${pkgs.gnupg}/bin/gpg --batch --import "$GPG_PRIVATE_KEY" 2>/dev/null || true
          fi
        '';
      };

      sessionVariables = {
        GITHUB_TOKEN_FILE = "${secretsDir}/github_token";
        DOCKERHUB_TOKEN_FILE = "${secretsDir}/dockerhub_token";
        CACHIX_TOKEN_FILE = "${secretsDir}/cachix_token";
      };
    };

    # Only use native sops-nix on Linux where systemd works
    # On Darwin, the LaunchAgent is blocked by AMFI code signing
    sops = lib.mkIf (!isDarwin) {
      age.keyFile = cfg.ageKeyFile;
      defaultSopsFile = secretsFile;

      secrets = {
        github_token = {
          path = "${secretsDir}/github_token";
        };
        dockerhub_token = {
          path = "${secretsDir}/dockerhub_token";
        };
        cachix_token = {
          path = "${secretsDir}/cachix_token";
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
          path = "${secretsDir}/gpg_private_key";
          mode = "0600";
        };
        "gpg/public_key" = {
          path = "${secretsDir}/gpg_public_key";
          mode = "0644";
        };
      };
    };

    my.zsh.extraInitExtra = ''
      # SOPS editor - use emt which handles daemon startup
      export SOPS_EDITOR="emt"

      # Secret file paths (home.sessionVariables doesn't auto-load in zsh)
      export GITHUB_TOKEN_FILE="${secretsDir}/github_token"
      export DOCKERHUB_TOKEN_FILE="${secretsDir}/dockerhub_token"
      export CACHIX_TOKEN_FILE="${secretsDir}/cachix_token"

      github-token() { cat "$GITHUB_TOKEN_FILE" 2>/dev/null || echo "Secret not available"; }
      dockerhub-token() { cat "$DOCKERHUB_TOKEN_FILE" 2>/dev/null || echo "Secret not available"; }
      cachix-token() { cat "$CACHIX_TOKEN_FILE" 2>/dev/null || echo "Secret not available"; }
      
      # Authenticate cachix using stored token
      cachix-auth() {
        local token
        token=$(cat "$CACHIX_TOKEN_FILE" 2>/dev/null)
        if [ -n "$token" ]; then
          echo "$token" | cachix authtoken --stdin
          echo "Cachix authenticated"
        else
          echo "Cachix token not available"
        fi
      }
    '';
  };
}
