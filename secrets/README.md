# Example secrets file structure (NOT actual secrets)
#
# After setting up .sops.yaml with your age key, create the real file:
#   sops secrets/secrets.yaml
#
# This will open $EDITOR (set to 'emt' by sops.nix). Add secrets like:
#
# Required keys (used by modules/sops.nix):
#
# github_token: ghp_xxxxxxxxxxxxxxxxxxxx
# dockerhub_token: dckr_pat_xxxxxxxxxxxxxxxxxxxx
# cachix_token: your-cachix-auth-token
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
#
# Save and close. The file will be encrypted automatically.
# You can then safely commit secrets/secrets.yaml to git.
#
# To add a new machine's age key:
#   1. Generate a key: age-keygen -o ~/.config/sops/age/keys.txt
#   2. Add the public key to .sops.yaml
#   3. Re-encrypt: sops updatekeys secrets/secrets.yaml
