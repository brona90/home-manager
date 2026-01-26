# Home Manager Configuration

Reproducible, cross-platform development environment using Nix flakes.

## Quick Start

```bash
# Bootstrap on fresh system
curl -fsSL https://raw.githubusercontent.com/gfoster/home-manager/master/bootstrap.sh | bash

# Or if already have nix:
home-manager switch --flake "$HOME/.config/home-manager#gfoster@$(nix eval --impure --raw --expr 'builtins.currentSystem')"
```

## Commands

| Command | Description |
|---------|-------------|
| `hms`   | Home Manager switch (rebuild config) |
| `nrs`   | NixOS rebuild switch |
| `nfu`   | Nix flake update |
| `em`    | Emacs (GUI, uses daemon) |
| `emt`   | Emacs terminal |
| `lvim`  | LazyVim |
| `github-token` | Print GitHub token |
| `dockerhub-token` | Print Docker Hub token |

## Structure

```
.
├── flake.nix              # Main entry point
├── home/                  # Home Manager profiles
│   ├── common.nix         # Shared across all systems
│   ├── linux.nix          # Linux-specific
│   └── darwin.nix         # macOS-specific
├── hosts/                 # NixOS configurations
│   ├── common/            # Shared NixOS settings
│   └── wsl/               # WSL-specific config
├── modules/               # Reusable Home Manager modules
│   ├── zsh.nix
│   ├── git.nix
│   ├── btop.nix
│   ├── sops.nix           # Secrets management
│   ├── emacs/
│   ├── vim/
│   └── tmux/
├── secrets/               # Encrypted secrets (safe to commit)
│   └── secrets.yaml
├── lib/                   # Helper functions
│   ├── docker-image.nix
│   └── docker-test-app.nix
└── .github/workflows/     # CI/CD
    ├── ci.yml             # Main pipeline
    └── validate.yml       # Manual validation
```

## Supported Systems

- `x86_64-linux` (Debian WSL, NixOS WSL, Docker)
- `aarch64-linux` (Raspberry Pi, ARM servers)
- `x86_64-darwin` (Intel Mac)
- `aarch64-darwin` (Apple Silicon)

## New Machine Setup

### Existing age key (same key on all machines)

```bash
# 1. Install nix, clone repo
curl -fsSL https://raw.githubusercontent.com/gfoster/home-manager/master/bootstrap.sh | bash

# 2. Copy age key from existing machine (via Signal, password manager, etc)
mkdir -p ~/.config/sops/age
vim ~/.config/sops/age/keys.txt  # paste key
chmod 600 ~/.config/sops/age/keys.txt

# 3. Apply
cd ~/.config/home-manager
hms
```

### New age key (one key per machine)

```bash
# 1. On new machine: generate age key
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt
age-keygen -y ~/.config/sops/age/keys.txt
# Copy the public key (age1...)

# 2. On existing machine: add new key to .sops.yaml
cd ~/.config/home-manager
vim .sops.yaml  # add new public key

# 3. Re-encrypt secrets with new key
sops updatekeys secrets/secrets.yaml
git add -A
git commit -m "feat(sops): add <machine> age key"
git push

# 4. On new machine: pull and apply
git pull
hms
```

## Secrets Management

Uses [sops-nix](https://github.com/Mic92/sops-nix) with age encryption.

### Current secrets

- `github_token` - GitHub API token
- `dockerhub_token` - Docker Hub token
- `ssh/id_rsa` - SSH private key (synced to `~/.ssh/id_rsa`)
- `ssh/id_rsa_pub` - SSH public key (synced to `~/.ssh/id_rsa.pub`)

### Edit secrets

```bash
sops secrets/secrets.yaml
```

### Add new secret

1. Edit secrets file: `sops secrets/secrets.yaml`
2. Add to `modules/sops.nix`:
   ```nix
   sops.secrets.my_secret = {};
   ```
3. Access in shell: `cat $SOPS_SECRETS_DIR/my_secret`

### Security

- **Safe to commit:** `secrets/secrets.yaml` (encrypted), `.sops.yaml` (public keys only)
- **Never commit:** `~/.config/sops/age/keys.txt` (private key)
- If private key compromised: generate new key, re-encrypt secrets, revoke tokens

## Flake Updates

```bash
# Update all inputs (weekly/monthly)
nfu
nix flake check
hms
# Test, then commit
git add flake.lock
git commit -m "chore: update flake inputs"
git push

# Update single input (when adding new)
nix flake lock --update-input <name>
```

## CI Pipeline

```
lint (statix, deadnix)
  └─> check (nix flake check)
        ├─> docker-build → docker-test
        └─> validate-nixos
```

## Docker

```bash
# Build and test locally
nix run .#docker-test

# Pull from Docker Hub
docker run -it --rm brona90/terminal:latest
```

## Caches

Uses Cachix for binary caching.

```bash
# NixOS: Configured in hosts/common/default.nix

# Non-NixOS: Add to /etc/nix/nix.conf
extra-substituters = https://gfoster.cachix.org
extra-trusted-public-keys = gfoster.cachix.org-1:O73e1PtN7sjaB5xDnBO/UMJSfheJjqlt6l6howghGvw=
```

## Adding a New Module

1. Create `modules/mymodule.nix`:
```nix
{ config, lib, pkgs, ... }:
let cfg = config.my.mymodule;
in {
  options.my.mymodule = {
    enable = lib.mkEnableOption "my module";
  };
  config = lib.mkIf cfg.enable {
    # configuration here
  };
}
```

2. Import in `flake.nix` modules list
3. Enable in `home/common.nix`: `my.mymodule.enable = true;`

## Adding a New Host

1. Create `hosts/myhost/configuration.nix`
2. Add to `flake.nix` nixosConfigurations
3. Import `../common` for shared settings

## TODO

- [ ] Multi-machine deploy alias/script
