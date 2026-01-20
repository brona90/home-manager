# Home Manager Configuration

A reproducible, cross-platform development environment using Nix and home-manager with local modules.

## Features

- **Cross-platform**: Works on Linux (x86_64, ARM64) and macOS (Intel, Apple Silicon)
- **Modular**: Each tool (vim, zsh, tmux, emacs, git, btop) is a local module
- **Reproducible**: Same configuration everywhere
- **Self-contained**: No external flake dependencies (except doom-emacs overlay)

## Modules

All configuration is in local modules under `modules/`:

| Module | Description |
|--------|-------------|
| `modules/zsh.nix` | Zsh with oh-my-zsh, syntax highlighting, history substring search |
| `modules/git.nix` | Git with aliases and global config |
| `modules/vim/` | LazyVim with LSPs, formatters, linters, pre-fetched plugins |
| `modules/emacs/` | Doom Emacs with bundled fonts |
| `modules/tmux/` | gpakosz/.tmux configuration |
| `modules/btop.nix` | btop system monitor |

## Quick Start

### First Time Installation

```bash
# Clone the repo
git clone https://github.com/brona90/home-manager.git ~/.config/home-manager
cd ~/.config/home-manager

# Run bootstrap script (backs up existing dotfiles and installs)
chmod +x bootstrap.sh
./bootstrap.sh
```

### Manual Installation

```bash
cd ~/.config/home-manager

# Linux (x86_64)
home-manager switch --flake '.#gfoster@x86_64-linux'

# Linux (ARM64)
home-manager switch --flake '.#gfoster@aarch64-linux'

# macOS (Intel)
home-manager switch --flake '.#gfoster@x86_64-darwin'

# macOS (Apple Silicon)
home-manager switch --flake '.#gfoster@aarch64-darwin'
```

## Available Tools

After installation:

- **Editor**: `vim`/`vi` → `lvim` (LazyVim), `emacs` (Doom Emacs)
- **Shell**: `zsh` with oh-my-zsh, starship prompt, syntax highlighting, history substring search
- **Terminal**: `tmux` with gpakosz config
- **Version Control**: `git` with aliases
- **Utilities**: `btop`, `tree`, `mise`, `direnv`

### Shell Aliases

```bash
# Nix
hms     # home-manager switch
nfu     # nix flake update

# Git
gs      # git status
ga      # git add -A
gpl     # git pull
gl      # git log --oneline --graph

# Editor
vim     # lvim
vi      # lvim
```

## Updating

```bash
cd ~/.config/home-manager

# Update flake inputs
nfu

# Apply updates
hms
```

## File Structure

```
~/.config/home-manager/
├── flake.nix              # Main configuration
├── flake.lock             # Locked dependency versions
├── modules/
│   ├── zsh.nix            # Zsh configuration
│   ├── git.nix            # Git configuration
│   ├── btop.nix           # btop configuration
│   ├── vim/
│   │   ├── default.nix    # LazyVim module
│   │   └── nvim-config/   # Neovim config files
│   ├── emacs/
│   │   ├── default.nix    # Doom Emacs module
│   │   └── doom.d/        # Doom config files
│   └── tmux/
│       ├── default.nix    # Tmux module
│       └── tmux-config/   # gpakosz tmux config
├── hosts/                 # Host-specific configurations
├── bootstrap.sh           # Installation script
└── README.md
```

## Customization

### Enable/Disable Modules

In `flake.nix`:

```nix
my.zsh.enable = true;
my.git.enable = true;
my.btop.enable = true;
my.vim.enable = true;
my.tmux.enable = true;
my.emacs.enable = true;
```

### Add Custom Aliases

In `flake.nix`:

```nix
my.zsh.extraAliases = {
  myalias = "my command";
};
```

### Add Extra Zsh Init

In `flake.nix`:

```nix
my.zsh.extraInitExtra = ''
  export MY_VAR="value"
'';
```

## Prerequisites

- [Nix](https://nixos.org/download.html) with flakes enabled

### Install Nix

```bash
sh <(curl -L https://nixos.org/nix/install) --daemon
```

### Enable Flakes

Add to `~/.config/nix/nix.conf`:

```
experimental-features = nix-command flakes
```

## Troubleshooting

### Aliases not working

Reload your shell:

```bash
exec zsh
```

### Existing files conflict

Back up and remove conflicting files:

```bash
mv ~/.config/nvim ~/.config/nvim.bak
mv ~/.config/zsh ~/.config/zsh.bak
hms
```

## License

MIT

## Author

Gregory Foster ([@brona90](https://github.com/brona90))
