# Home Manager Configuration

Reproducible, cross-platform development environment using Nix flakes.

## Quick Start

```bash
# Bootstrap on fresh system
curl -fsSL https://raw.githubusercontent.com/yourusername/home-manager/master/bootstrap.sh | bash

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
│   ├── emacs/
│   ├── vim/
│   └── tmux/
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

Uses Cachix for binary caching. Configure on fresh systems:

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
