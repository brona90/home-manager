# Example secrets file structure (NOT actual secrets)
#
# After setting up .sops.yaml with your age key, create the real file:
#   sops secrets/secrets.yaml
#
# This will open $EDITOR (set to 'emt' by sops.nix). Add secrets like:
#
# Keys used by modules/sops.nix. Each one is decrypted only if present, so a
# fork can omit any of them:
#
# github_token: ghp_xxxxxxxxxxxxxxxxxxxx
# dockerhub_token: dckr_pat_xxxxxxxxxxxxxxxxxxxx
# cachix_token: your-cachix-auth-token
# flake_update_token: github_pat_xxxx   # fine-grained PAT for update-flake.yml
#                                       # (contents + pull-requests: write)
# porkbun:
#   api_key: pk1_xxxxxxxxxxxxxxxxxxxx
#   secret_key: sk1_xxxxxxxxxxxxxxxxxxxx
# ssh:
#   id_rsa: |                    # key name must match my.sops.sshKeyName (default: id_rsa)
#     -----BEGIN OPENSSH PRIVATE KEY-----
#     ...
#     -----END OPENSSH PRIVATE KEY-----
#   id_rsa_pub: ssh-ed25519 AAAA... user@host
# gpg:
#   private_key: |
#     -----BEGIN PGP PRIVATE KEY BLOCK-----
#     ...
#     -----END PGP PRIVATE KEY BLOCK-----
#   public_key: |
#     -----BEGIN PGP PUBLIC KEY BLOCK-----
#     ...
#     -----END PGP PUBLIC KEY BLOCK-----
# org_gcal:                      # Google Calendar sync. Both keys are read by
#   client_id: xxxxxxxx.apps.googleusercontent.com    # Emacs on every host.
#   client_secret: GOCSPX-xxxxxxxxxxxxxxxx
#
# NOTE: this file also still carries org_gcal/gpg_private_key, and nothing
# reads it. It was a passphrase-less key encrypting Doom's OAuth token
# plstore; Doom is retired and the token store is a plain 0600 file now.
# Nothing decrypts or imports it any more, but removing it from secrets.yaml
# needs `sops unset` (a hand edit corrupts the file's MAC) and deleting it
# from each keyring is manual. Both steps are written up in
# modules/emacs/RETIRING-DOOM.md.
#
# Save and close. The file will be encrypted automatically.
# You can then safely commit secrets/secrets.yaml to git.
#
# To add a new machine's age key:
#   1. Generate a key: age-keygen -o ~/.config/sops/age/keys.txt
#   2. Add the public key to .sops.yaml
#   3. Re-encrypt: sops updatekeys secrets/secrets.yaml
