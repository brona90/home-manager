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

              # NOTE: org_gcal/gpg_private_key is deliberately NOT decrypted.
              # It was a passphrase-less key encrypting Doom's org-gcal token
              # plstore; Doom is retired and the current token store is a plain
              # 0600 file. The key is still in secrets.yaml -- removing it there
              # needs `sops unset`, and deleting it from each keyring is manual.
              # See modules/emacs/RETIRING-DOOM.md, step 3.

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
            # REMOVED, and worth knowing why rather than rediscovering it.
            #
            # This used to import a second key -- org_gcal/gpg_private_key,
            # 050C399D3A6B013DD2C93F899BC379782DFE1930 -- and mark it :6:
            # (ultimate) so gpg would encrypt to it with no prompt. Its only
            # job was Doom's org-gcal OAuth token plstore, which had to decrypt
            # unattended in a headless daemon with no frame to draw a pinentry
            # in.
            #
            # It was a passphrase-less, certify-capable key sitting ultimately
            # trusted in this keyring -- an always-unlocked CA for it -- and
            # the thing it protected was a refresh token whose own private key
            # sat unprotected at 0600 on the same disk. The current Emacs
            # stores that token as a plain 0600 file instead and is honest
            # about it; see the commentary in
            # modules/emacs/vanilla/config/lisp/my-secrets.el.
            #
            # This change stops the key being re-imported on every activation.
            # It does NOT remove it from keyrings it already reached, and it
            # does not touch secrets.yaml. Both are manual: see
            # modules/emacs/RETIRING-DOOM.md, step 3.
          '';
        };

      sessionVariables = {
        GITHUB_TOKEN_FILE = "${secretsDir}/github_token";
        DOCKERHUB_TOKEN_FILE = "${secretsDir}/dockerhub_token";
        CACHIX_TOKEN_FILE = "${secretsDir}/cachix_token";
        FLAKE_UPDATE_TOKEN_FILE = "${secretsDir}/flake_update_token";
        PORKBUN_API_KEY_FILE = "${secretsDir}/porkbun_api_key";
        PORKBUN_SECRET_KEY_FILE = "${secretsDir}/porkbun_secret_key";
        CLOUDFLARE_ORRERY_TOKEN_FILE = "${secretsDir}/cloudflare_orrery_token";
        CLOUDFLARE_TUNNEL_TOKEN_FILE = "${secretsDir}/cloudflare_tunnel_token";
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
        # orrery_token: Pages + DNS + Access on the fosterthecode.com zone (CI uses it).
        # tunnel_token: Cloudflare Tunnel:Edit only -- provisioning the warealien tunnel.
        "cloudflare/orrery_token" = {
          path = "${secretsDir}/cloudflare_orrery_token";
        };
        "cloudflare/tunnel_token" = {
          path = "${secretsDir}/cloudflare_tunnel_token";
        };
        "org_gcal/client_id" = {
          path = "${secretsDir}/org_gcal_client_id";
        };
        "org_gcal/client_secret" = {
          path = "${secretsDir}/org_gcal_client_secret";
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
      export CLOUDFLARE_ORRERY_TOKEN_FILE="${secretsDir}/cloudflare_orrery_token"
      export CLOUDFLARE_TUNNEL_TOKEN_FILE="${secretsDir}/cloudflare_tunnel_token"

      github-token() { cat "$GITHUB_TOKEN_FILE" 2>/dev/null || echo "Secret not available"; }
      dockerhub-token() { cat "$DOCKERHUB_TOKEN_FILE" 2>/dev/null || echo "Secret not available"; }
      cachix-token() { cat "$CACHIX_TOKEN_FILE" 2>/dev/null || echo "Secret not available"; }
      flake-update-token() { cat "$FLAKE_UPDATE_TOKEN_FILE" 2>/dev/null || echo "Secret not available"; }
      porkbun-api-key() { cat "$PORKBUN_API_KEY_FILE" 2>/dev/null || echo "Secret not available"; }
      porkbun-secret-key() { cat "$PORKBUN_SECRET_KEY_FILE" 2>/dev/null || echo "Secret not available"; }
      cloudflare-orrery-token() { cat "$CLOUDFLARE_ORRERY_TOKEN_FILE" 2>/dev/null || echo "Secret not available"; }
      cloudflare-tunnel-token() { cat "$CLOUDFLARE_TUNNEL_TOKEN_FILE" 2>/dev/null || echo "Secret not available"; }

      # `wrangler login` is the default auth path, and it writes a 23-scope
      # OAuth grant to ~/.config/.wrangler/config/default.toml in PLAINTEXT --
      # including connectivity:admin, secrets_store:write and
      # email_sending:write, plus an offline_access refresh token that keeps
      # minting access tokens until the grant is revoked server-side. That is
      # strictly broader than the least-privilege API tokens in sops, and it
      # silently supersedes them: the careful orrery/tunnel split stops being
      # the privilege boundary the moment someone runs `wrangler login`.
      #
      # This wrapper feeds wrangler the scoped orrery token instead.
      # CLOUDFLARE_API_TOKEN takes precedence over any stored OAuth grant, so
      # the wrapper wins even if a stale login is still on disk.
      #
      # Scoped to one invocation rather than exported: an exported
      # CLOUDFLARE_API_TOKEN is inherited by every child process for the life
      # of the shell and lands in core dumps and /proc, which trades a
      # 0600 file for a broader exposure.
      #
      # If a wrangler operation fails on permissions, that is the token being
      # correctly narrow -- widen the token deliberately, do not fall back to
      # `wrangler login`.
      wrangler() {
        if [ ! -s "$CLOUDFLARE_ORRERY_TOKEN_FILE" ]; then
          echo "wrangler: no decrypted token at $CLOUDFLARE_ORRERY_TOKEN_FILE" >&2
          echo "wrangler: run hms, or check sops-nix activation" >&2
          return 1
        fi
        if command -v wrangler >/dev/null 2>&1; then
          CLOUDFLARE_API_TOKEN="$(cat "$CLOUDFLARE_ORRERY_TOKEN_FILE")" command wrangler "$@"
        else
          CLOUDFLARE_API_TOKEN="$(cat "$CLOUDFLARE_ORRERY_TOKEN_FILE")" npx wrangler "$@"
        fi
      }

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
