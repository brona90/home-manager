# Example secrets file structure (NOT actual secrets)
# 
# After setting up .sops.yaml with your age key, create the real file:
#   sops secrets/secrets.yaml
#
# This will open $EDITOR with an encrypted file. Add secrets like:
#
# github_token: ghp_xxxxxxxxxxxxxxxxxxxx
# openai_api_key: sk-xxxxxxxxxxxxxxxxxxxx
# ssh:
#   id_ed25519: |
#     -----BEGIN OPENSSH PRIVATE KEY-----
#     ...
#     -----END OPENSSH PRIVATE KEY-----
#   id_ed25519_pub: ssh-ed25519 AAAA... user@host
#
# Save and close. The file will be encrypted automatically.
# You can then safely commit secrets/secrets.yaml to git.
