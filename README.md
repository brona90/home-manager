# Home Manager Configuration

Reproducible, cross-platform development environment using Nix flakes.

## Quick Start

```bash
# Bootstrap on fresh system (interactive - prompts for username)
curl -fsSL https://raw.githubusercontent.com/brona90/home-manager/master/bootstrap.sh | bash

# Or if already have nix and repo cloned:
home-manager switch --flake "$HOME/.config/home-manager#USERNAME@SYSTEM" -b backup
```

## Forking This Repo

1. Fork on GitHub
2. Update `REPO_URL` in `bootstrap.sh` to your fork
3. Run bootstrap - it will prompt for your username and add you to `config.nix`
4. Commit and push your changes

Or manually edit `config.nix`:

```nix
{
  users = [
    { username = "yourusername"; systems = [ "x86_64-linux" ]; }
  ];
}
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
├── config.nix             # User configuration (edit this!)
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

- `x86_64-linux` (Debian, Ubuntu, NixOS, WSL)
- `aarch64-linux` (Raspberry Pi, ARM servers)
- `x86_64-darwin` (Intel Mac)
- `aarch64-darwin` (Apple Silicon Mac)

## Adding Yourself (for forks)

Edit `config.nix`:

```nix
{
  users = [
    { username = "alice"; systems = [ "x86_64-linux" "aarch64-darwin" ]; }
  ];
}
```

Then run:
```bash
hms
```

## New Machine Setup

### Option 1: Same age key (share secrets across machines)

```bash
# 1. Run bootstrap
curl -fsSL https://raw.githubusercontent.com/.../bootstrap.sh | bash

# 2. When prompted for sops setup, paste your existing age key
# (copy from ~/.config/sops/age/keys.txt on existing machine)

# 3. Done! Secrets will decrypt automatically
```

### Option 2: New age key (per-machine keys)

```bash
# 1. On new machine: run bootstrap, choose to generate new key
curl -fsSL https://raw.githubusercontent.com/.../bootstrap.sh | bash

# 2. Bootstrap will show your public key (age1...)

# 3. On existing machine with secrets:
cd ~/.config/home-manager
vim .sops.yaml  # Add new public key
sops updatekeys secrets/secrets.yaml
git add -A && git commit -m "feat(sops): add <machine> key" && git push

# 4. On new machine:
cd ~/.config/home-manager
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

### Security

- **Safe to commit:** `secrets/secrets.yaml` (encrypted), `.sops.yaml` (public keys)
- **Never commit:** `~/.config/sops/age/keys.txt` (private key)

## Flake Updates

```bash
# Update all inputs (weekly/monthly)
nfu
nix flake check
hms
git add flake.lock
git commit -m "chore: update flake inputs"
git push

# Update single input
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

Uses Cachix for binary caching. Bootstrap configures this automatically.

Manual setup:
```bash
# Add to ~/.config/nix/nix.conf or /etc/nix/nix.conf
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

## TODO

- [ ] Multi-machine deploy alias/script
