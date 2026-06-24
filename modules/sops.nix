# SOPS secrets configuration
{
  config,
  lib,
  pkgs,
  userConfig,
  ...
}: let
  cfg = config.my.sops;
  secretsFile = ../secrets/secrets.yaml;
  secretsExist = builtins.pathExists secretsFile;
  inherit (pkgs.stdenv) isDarwin;
  secretsDir = "${config.home.homeDirectory}/.config/sops-nix/secrets";
in {
  options.my.sops = {
    enable = lib.mkEnableOption "sops-nix secrets management";

    ageKeyFile = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
      description = "Path to age private key";
    };

    sshKeyName = lib.mkOption {
      type = lib.types.str;
      default = "id_rsa";
      description = "Base name of the SSH key in secrets.yaml (e.g. id_ed25519). The SOPS YAML must have ssh.<sshKeyName> and ssh.<sshKeyName>_pub entries.";
    };
  };

  config = lib.mkIf (cfg.enable && secretsExist) {
    home = {
      packages = [pkgs.sops pkgs.age];

      activation =
        {
          createSshDir = lib.hm.dag.entryBefore ["checkLinkTargets"] ''
            mkdir -p "${config.home.homeDirectory}/.ssh"
            chmod 700 "${config.home.homeDirectory}/.ssh"
          '';
        }
        // lib.optionalAttrs isDarwin {
          # Manual decryption for Darwin only
          # On Darwin: LaunchAgent is blocked by AMFI/code signing, so this is required
          # On Linux: native sops-nix systemd service handles decryption
          decryptSopsSecrets = lib.hm.dag.entryAfter ["writeBoundary"] ''
            umask 077
            trap 'rm -f \
              "${secretsDir}/github_token.tmp" \
              "${secretsDir}/dockerhub_token.tmp" \
              "${secretsDir}/cachix_token.tmp" \
              "${secretsDir}/flake_update_token.tmp" \
              "${secretsDir}/porkbun_api_key.tmp" \
              "${secretsDir}/porkbun_secret_key.tmp" \
              "${secretsDir}/org_gcal_client_id.tmp" \
              "${secretsDir}/org_gcal_client_secret.tmp" \
              "${secretsDir}/org_gcal_gpg_private_key.tmp" \
              "${config.home.homeDirectory}/.ssh/${cfg.sshKeyName}.tmp" \
              "${config.home.homeDirectory}/.ssh/${cfg.sshKeyName}.pub.tmp" \
              "${secretsDir}/gpg_private_key.tmp" \
              "${secretsDir}/gpg_public_key.tmp"' EXIT
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

              # Decrypt flake_update_token (GitHub PAT for update-flake.yml CI)
              if ${pkgs.sops}/bin/sops -d --extract '["flake_update_token"]' "${secretsFile}" > "${secretsDir}/flake_update_token.tmp" 2>/dev/null; then
                chmod 0400 "${secretsDir}/flake_update_token.tmp"
                mv -f "${secretsDir}/flake_update_token.tmp" "${secretsDir}/flake_update_token"
              fi

              # Decrypt Porkbun API credentials
              if ${pkgs.sops}/bin/sops -d --extract '["porkbun"]["api_key"]' "${secretsFile}" > "${secretsDir}/porkbun_api_key.tmp" 2>/dev/null; then
                chmod 0400 "${secretsDir}/porkbun_api_key.tmp"
                mv -f "${secretsDir}/porkbun_api_key.tmp" "${secretsDir}/porkbun_api_key"
              fi

              if ${pkgs.sops}/bin/sops -d --extract '["porkbun"]["secret_key"]' "${secretsFile}" > "${secretsDir}/porkbun_secret_key.tmp" 2>/dev/null; then
                chmod 0400 "${secretsDir}/porkbun_secret_key.tmp"
                mv -f "${secretsDir}/porkbun_secret_key.tmp" "${secretsDir}/porkbun_secret_key"
              fi

              # Decrypt org-gcal OAuth credentials
              if ${pkgs.sops}/bin/sops -d --extract '["org_gcal"]["client_id"]' "${secretsFile}" > "${secretsDir}/org_gcal_client_id.tmp" 2>/dev/null; then
                chmod 0400 "${secretsDir}/org_gcal_client_id.tmp"
                mv -f "${secretsDir}/org_gcal_client_id.tmp" "${secretsDir}/org_gcal_client_id"
              fi

              if ${pkgs.sops}/bin/sops -d --extract '["org_gcal"]["client_secret"]' "${secretsFile}" > "${secretsDir}/org_gcal_client_secret.tmp" 2>/dev/null; then
                chmod 0400 "${secretsDir}/org_gcal_client_secret.tmp"
                mv -f "${secretsDir}/org_gcal_client_secret.tmp" "${secretsDir}/org_gcal_client_secret"
              fi

              if ${pkgs.sops}/bin/sops -d --extract '["org_gcal"]["gpg_private_key"]' "${secretsFile}" > "${secretsDir}/org_gcal_gpg_private_key.tmp" 2>/dev/null; then
                chmod 0600 "${secretsDir}/org_gcal_gpg_private_key.tmp"
                mv -f "${secretsDir}/org_gcal_gpg_private_key.tmp" "${secretsDir}/org_gcal_gpg_private_key"
              fi

              # Decrypt SSH keys - write directly, not via symlink
              if ${pkgs.sops}/bin/sops -d --extract '["ssh"]["${cfg.sshKeyName}"]' "${secretsFile}" > "${config.home.homeDirectory}/.ssh/${cfg.sshKeyName}.tmp" 2>/dev/null; then
                chmod 0600 "${config.home.homeDirectory}/.ssh/${cfg.sshKeyName}.tmp"
                mv -f "${config.home.homeDirectory}/.ssh/${cfg.sshKeyName}.tmp" "${config.home.homeDirectory}/.ssh/${cfg.sshKeyName}"
              fi

              if ${pkgs.sops}/bin/sops -d --extract '["ssh"]["${cfg.sshKeyName}_pub"]' "${secretsFile}" > "${config.home.homeDirectory}/.ssh/${cfg.sshKeyName}.pub.tmp" 2>/dev/null; then
                chmod 0644 "${config.home.homeDirectory}/.ssh/${cfg.sshKeyName}.pub.tmp"
                mv -f "${config.home.homeDirectory}/.ssh/${cfg.sshKeyName}.pub.tmp" "${config.home.homeDirectory}/.ssh/${cfg.sshKeyName}.pub"
              fi

              # Decrypt GPG keys
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

          importGpgKey = lib.hm.dag.entryAfter ["decryptSopsSecrets"] ''
            GPG_PRIVATE_KEY="${secretsDir}/gpg_private_key"
            if [ -f "$GPG_PRIVATE_KEY" ]; then
              export GNUPGHOME="${config.home.homeDirectory}/.gnupg"
              timeout 10 ${pkgs.gnupg}/bin/gpg --batch --pinentry-mode loopback --import "$GPG_PRIVATE_KEY" 2>/dev/null || true
            fi
          '';
        }
        // lib.optionalAttrs (!isDarwin) {
          importGpgKey = lib.hm.dag.entryAfter ["sops-nix"] ''
            export GNUPGHOME="${config.home.homeDirectory}/.gnupg"
            GPG_PRIVATE_KEY="${config.sops.secrets."gpg/private_key".path}"
            if [ -f "$GPG_PRIVATE_KEY" ]; then
              timeout 10 ${pkgs.gnupg}/bin/gpg --batch --pinentry-mode loopback --import "$GPG_PRIVATE_KEY" 2>/dev/null || true
            fi
            # Passphrase-less key that encrypts the org-gcal OAuth token store so it
            # decrypts with zero prompts (see modules/emacs plstore-encrypt-to).
            ORG_GCAL_KEY="${config.sops.secrets."org_gcal/gpg_private_key".path}"
            if [ -f "$ORG_GCAL_KEY" ]; then
              timeout 10 ${pkgs.gnupg}/bin/gpg --batch --pinentry-mode loopback --import "$ORG_GCAL_KEY" 2>/dev/null || true
              # Ownertrust :6: (ultimate) marks the key VALID so gpg encrypts to it
              # non-interactively (prompt-free token-store decryption). DELIBERATE
              # TRADEOFF: ultimate also makes it a trusted introducer, and the key is
              # passphrase-less + certify-capable — i.e. an always-unlocked CA for
              # THIS keyring. Accepted because nothing here verifies signatures against
              # ~/.gnupg (git signing uses the YubiKey key; nix doesn't use it), so the
              # blast radius is nil today. To fully close it later: regenerate as an
              # encryption-subkey-only key (no certify secret present), keeping :6: for
              # validity. Do NOT drop to :3: — that reintroduces the encryption prompt.
              echo "050C399D3A6B013DD2C93F899BC379782DFE1930:6:" | timeout 10 ${pkgs.gnupg}/bin/gpg --import-ownertrust 2>/dev/null || true
            fi
          '';
        };

      sessionVariables = {
        GITHUB_TOKEN_FILE = "${secretsDir}/github_token";
        DOCKERHUB_TOKEN_FILE = "${secretsDir}/dockerhub_token";
        CACHIX_TOKEN_FILE = "${secretsDir}/cachix_token";
        FLAKE_UPDATE_TOKEN_FILE = "${secretsDir}/flake_update_token";
        PORKBUN_API_KEY_FILE = "${secretsDir}/porkbun_api_key";
        PORKBUN_SECRET_KEY_FILE = "${secretsDir}/porkbun_secret_key";
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
        flake_update_token = {
          path = "${secretsDir}/flake_update_token";
        };
        "porkbun/api_key" = {
          path = "${secretsDir}/porkbun_api_key";
        };
        "porkbun/secret_key" = {
          path = "${secretsDir}/porkbun_secret_key";
        };
        "org_gcal/client_id" = {
          path = "${secretsDir}/org_gcal_client_id";
        };
        "org_gcal/client_secret" = {
          path = "${secretsDir}/org_gcal_client_secret";
        };
        "org_gcal/gpg_private_key" = {
          path = "${secretsDir}/org_gcal_gpg_private_key";
          mode = "0600";
        };
        "ssh/${cfg.sshKeyName}" = {
          path = "${config.home.homeDirectory}/.ssh/${cfg.sshKeyName}";
          mode = "0600";
        };
        "ssh/${cfg.sshKeyName}_pub" = {
          path = "${config.home.homeDirectory}/.ssh/${cfg.sshKeyName}.pub";
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
      export FLAKE_UPDATE_TOKEN_FILE="${secretsDir}/flake_update_token"
      export PORKBUN_API_KEY_FILE="${secretsDir}/porkbun_api_key"
      export PORKBUN_SECRET_KEY_FILE="${secretsDir}/porkbun_secret_key"

      github-token() { cat "$GITHUB_TOKEN_FILE" 2>/dev/null || echo "Secret not available"; }
      dockerhub-token() { cat "$DOCKERHUB_TOKEN_FILE" 2>/dev/null || echo "Secret not available"; }
      cachix-token() { cat "$CACHIX_TOKEN_FILE" 2>/dev/null || echo "Secret not available"; }
      flake-update-token() { cat "$FLAKE_UPDATE_TOKEN_FILE" 2>/dev/null || echo "Secret not available"; }
      porkbun-api-key() { cat "$PORKBUN_API_KEY_FILE" 2>/dev/null || echo "Secret not available"; }
      porkbun-secret-key() { cat "$PORKBUN_SECRET_KEY_FILE" 2>/dev/null || echo "Secret not available"; }

      # Authenticate cachix using stored token
      cachix-auth() {
        if [ -s "$CACHIX_TOKEN_FILE" ]; then
          cachix authtoken --stdin < "$CACHIX_TOKEN_FILE"
          echo "Cachix authenticated"
        else
          echo "Cachix token not available"
        fi
      }

      # Replay all GitHub Actions secrets/variables from sops-decrypted
      # files. GitHub secrets are write-only, so a deleted/recreated repo
      # loses them; this restores everything in one command.
      repo-secrets-restore() {
        local repo="''${1:-${userConfig.repo.owner}/${userConfig.repo.name}}"
        local rc=0
        for pair in \
          "CACHIX_AUTH_TOKEN:$CACHIX_TOKEN_FILE" \
          "DOCKERHUB_TOKEN:$DOCKERHUB_TOKEN_FILE" \
          "FLAKE_UPDATE_TOKEN:$FLAKE_UPDATE_TOKEN_FILE"; do
          local name="''${pair%%:*}" file="''${pair#*:}"
          if [ -s "$file" ]; then
            gh secret set "$name" --repo "$repo" < "$file" && echo "✓ $name" || rc=1
          else
            echo "✗ $name: no decrypted secret at $file" >&2; rc=1
          fi
        done
        gh variable set DOCKERHUB_USERNAME --repo "$repo" --body "${userConfig.repo.dockerHubUser}" && echo "✓ DOCKERHUB_USERNAME" || rc=1
        return $rc
      }
    '';
  };
}
