# Nix Configuration

A reproducible, cross-platform development environment using Nix flakes.

## Quick Start

```bash
# On any system with Nix installed:
curl -sL https://raw.githubusercontent.com/brona90/home-manager/master/bootstrap.sh | bash
```

Or manually:

```bash
git clone https://github.com/brona90/home-manager.git ~/.config/home-manager
cd ~/.config/home-manager
./bootstrap.sh
```

## Supported Platforms

| Platform | Config |
|----------|--------|
| Linux x86_64 | `gfoster@x86_64-linux` |
| Linux ARM64 | `gfoster@aarch64-linux` |
| macOS Intel | `gfoster@x86_64-darwin` |
| macOS Apple Silicon | `gfoster@aarch64-darwin` |
| NixOS WSL | `wsl-nixos` |

## Commands

After installation, these commands work on **any** platform:

```bash
hms   # Switch home-manager configuration
nfu   # Update flake inputs
em    # Open Emacs (connects to daemon, starts if needed)
emt   # Open Emacs in terminal mode
```

## What's Included

| Tool | Description |
|------|-------------|
| **zsh** | oh-my-zsh, starship prompt, syntax highlighting, vi mode |
| **emacs** | Doom Emacs with daemon mode |
| **vim** | LazyVim with LSPs, formatters, treesitter |
| **tmux** | gpakosz/.tmux configuration |
| **git** | Aliases and global config |
| **btop** | System monitor |

## Repository Structure

```
├── flake.nix           # Main flake (inputs, outputs, configs)
├── modules/            # Home Manager modules
│   ├── zsh.nix
│   ├── git.nix
│   ├── btop.nix
│   ├── vim/
│   ├── emacs/
│   └── tmux/
├── hosts/              # NixOS host configurations
│   └── wsl-nixos/
├── lib/                # Reusable Nix functions
│   └── docker-image.nix
└── .github/workflows/  # CI/CD
```

## Usage

### Home Manager (any system)

```bash
# After bootstrap, just use:
hms

# Or explicitly:
home-manager switch --flake ~/.config/home-manager#gfoster@x86_64-linux
```

### NixOS

```bash
sudo nixos-rebuild switch --flake ~/.config/home-manager#wsl-nixos
```

### Docker Image

```bash
# Build locally
nix build .#dockerImage
docker load < result
docker run -it --rm brona90/terminal:latest

# Or pull from Docker Hub
docker run -it --rm brona90/terminal:latest
```

## Adding a New Host

### For Home Manager (non-NixOS)

Add to `flake.nix`:

```nix
homeConfigurations = {
  # ... existing configs ...
  "myuser@x86_64-linux" = mkHomeConfiguration { 
    system = "x86_64-linux"; 
    username = "myuser"; 
  };
};
```

### For NixOS

1. Create `hosts/my-host/configuration.nix`
2. Add to `flake.nix`:

```nix
nixosConfigurations = {
  my-host = nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      ./hosts/my-host/configuration.nix
    ];
  };
};
```

## CI/CD

GitHub Actions automatically:
- Checks flake validity on every PR
- Builds home-manager and NixOS configs
- Builds and pushes Docker image on merge to master

## Prerequisites

Install Nix with flakes:

```bash
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

## License

MIT
