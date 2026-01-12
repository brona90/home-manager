# Home Manager Configuration

A reproducible, cross-platform development environment using Nix and home-manager.

## Features

- **Cross-platform**: Works on Linux (x86_64, ARM64) and macOS (Intel, Apple Silicon)
- **Modular**: Each tool (vim, zsh, tmux, emacs, git) is a separate Nix flake
- **Reproducible**: Same configuration everywhere
- **Docker testing**: Test changes in isolation before applying (Linux only)
- **Automatic backup**: Bootstrap script backs up existing dotfiles before installation

## Tool Flakes

This configuration integrates these custom tool flakes:
- [nix-vim](https://github.com/brona90/nix-vim) - LazyVim with LSPs, formatters, linters
- [nix-zsh](https://github.com/brona90/nix-zsh) - oh-my-zsh with custom aliases
- [nix-tmux](https://github.com/brona90/nix-tmux) - tmux configuration
- [nix-emacs](https://github.com/brona90/nix-emacs) - Doom Emacs
- [nix-git](https://github.com/brona90/nix-git) - Git with aliases

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

The bootstrap script will:
1. Check Nix and flakes are installed
2. Detect your system architecture
3. **Backup existing dotfiles** to `~/.config/home-manager-backups/TIMESTAMP/`
4. Build and activate home-manager configuration

After installation completes:
```bash
# Reload your shell
source ~/.zshrc

# Or restart your terminal
```

### Manual Installation by Platform

If you prefer not to use the bootstrap script:

#### Linux (x86_64)
```bash
cd ~/.config/home-manager
home-manager switch --flake .#gfoster@x86_64-linux
```

#### Linux (ARM64)
```bash
home-manager switch --flake .#gfoster@aarch64-linux
```

#### macOS (Intel)
```bash
home-manager switch --flake .#gfoster@x86_64-darwin
```

#### macOS (Apple Silicon)
```bash
home-manager switch --flake .#gfoster@aarch64-darwin
```

## Available Tools

After installation, these tools are available:

- **Editor**: `vim`/`vi` (aliases to `lvim`), `emacs`, `lvim` (LazyVim with full IDE features)
- **Shell**: `zsh` with oh-my-zsh, starship prompt, syntax highlighting
- **Terminal**: `tmux` with custom configuration
- **Version Control**: `git` with custom aliases
- **Utilities**: `btop`, `tree`, `mise`, `direnv`
- **Language Support**: via `mise` - install Node, Python, Java, Go, Ruby, etc.

### Using Tools

```bash
# Launch LazyVim
lvim file.txt
vim file.txt   # Also launches lvim (aliased)

# Use Git aliases (defined in nix-git)
gs              # git status
ga              # git add -A
gcm "message"   # git commit -m
gps             # git push

# Install language runtimes with mise
mise use node@latest
mise use python@3.12
mise use java@21

# Use btop for system monitoring
btop
```

## Docker Testing (Linux only)

### Local Testing

Test the complete environment in Docker before applying to your system:

```bash
cd ~/.config/home-manager
nix run .#docker-test
```

### Pre-built Docker Image

You can also pull the pre-built Nix-enabled image from Docker Hub (automatically built on every commit):

```bash
# Pull and run the latest version
docker run -it --rm brona90/terminal:latest

# Or a specific date version
docker run -it --rm brona90/terminal:20260112

# With SSH keys mounted
docker run -it --rm \
  -v ~/.ssh:/home/gfoster/.ssh:ro \
  brona90/terminal:latest
```

**The container includes Nix**, so you can install additional packages:

```bash
# Inside the container
nix-shell -p nodejs python3 go    # Temporary shell with packages
nix-env -iA nixpkgs.ripgrep       # Install to profile
nix run nixpkgs#cowsay            # Run a package directly
```

Inside the container:
- All tools are available (`vim`, `lvim`, `emacs`, `tmux`, etc.)
- Starship prompt configured
- Colors match your terminal (xterm-256color with truecolor support)
- Use `mise` to install language runtimes
- Test changes in isolation

Exit with `exit` or Ctrl+D.

## Customization

### Change Username

Edit `flake.nix` and change:
```nix
username = "gfoster";  # Change to your username
```

Then rebuild:
```bash
home-manager switch --flake .#YOUR_USERNAME@$(uname -m)-$(uname -s | tr '[:upper:]' '[:lower:]')
```

### Add/Remove Tools

Edit the `home.packages` section in `flake.nix`:
```nix
home.packages = [
  nix-emacs.packages.${system}.default
  nix-vim.packages.${system}.default
  pkgs.yourPackageHere
  pkgs.ripgrep
  pkgs.fd
];
```

### Modify Shell Aliases

Aliases are defined in [nix-zsh](https://github.com/brona90/nix-zsh), or add custom ones in `flake.nix`:
```nix
shellAliases = zshConfig.aliases // {
  myalias = "my command";
  ll = "ls -la";
};
```

### Customize Starship Prompt

Edit the `programs.starship.settings` section in `flake.nix`:
```nix
programs.starship = {
  enable = true;
  settings = {
    # Your custom starship config
  };
};
```

## Platform Differences

The configuration automatically handles platform differences:

| Feature | Linux | macOS |
|---------|-------|-------|
| Home Directory | `/home/username` | `/Users/username` |
| `ls` colors flag | `--color=auto` | `-G` |
| Docker testing | ✅ | ❌ |
| Mise runtime libraries | Included (glibc, gcc, etc.) | Native macOS |

## Prerequisites

- [Nix](https://nixos.org/download.html) with flakes enabled
- Docker (optional, for testing on Linux)

### Install Nix

```bash
# Multi-user installation (recommended)
sh <(curl -L https://nixos.org/nix/install) --daemon
```

### Enable Flakes

The bootstrap script does this automatically, or manually add to `~/.config/nix/nix.conf`:
```
experimental-features = nix-command flakes
```

Then restart your terminal or Nix daemon.

## Updating

```bash
cd ~/.config/home-manager

# Update all flake inputs (vim, zsh, emacs, etc.)
nix flake update

# Apply updates
home-manager switch --flake .#gfoster@$(uname -m)-$(uname -s | tr '[:upper:]' '[:lower:]')

# Or use shorthand (Linux x86_64 only)
home-manager switch --flake .#gfoster
```

## Troubleshooting

### Aliases not working after installation

Reload your shell:
```bash
source ~/.zshrc
```

Or restart your terminal.

### Check if alias is loaded

```bash
type vim   # Should show: vim is an alias for lvim
type vi    # Should show: vi is an alias for lvim
```

### "command not found: home-manager"

After first installation, you need to reload your shell:
```bash
source ~/.zshrc
```

Or restart your terminal. The `home-manager` command comes from the home-manager package installed in your profile.

### Docker permissions on Linux

Ensure your user is in the `docker` group:
```bash
sudo usermod -aG docker $USER
```

Log out and back in for the change to take effect.

### macOS: Nix daemon not starting

```bash
sudo launchctl load /Library/LaunchDaemons/org.nixos.nix-daemon.plist
```

### Mise can't install tools in Docker

This is expected - the Docker image includes runtime dependencies (glibc, gcc, zlib), but some tools may need additional libraries. For full functionality, use mise on your host system, not in Docker.

### Restore backed up files

Your original dotfiles are in:
```bash
ls ~/.config/home-manager-backups/
```

To restore:
```bash
# Find your backup
ls -la ~/.config/home-manager-backups/

# Restore specific file
cp ~/.config/home-manager-backups/TIMESTAMP/.zshrc ~/.zshrc
```

## File Structure

```
~/.config/home-manager/
├── flake.nix           # Main configuration
├── flake.lock          # Locked dependency versions
├── bootstrap.sh        # Installation script
├── README.md           # This file
└── .gitignore          # Ignore build artifacts
```

## What Gets Installed

Home-manager creates symlinks from your home directory to the Nix store:

```bash
~/.zshrc -> /nix/store/...-hm_..zshrc
~/.zshenv -> /nix/store/...-hm_..zshenv
~/.config/git/config -> /nix/store/...
~/.config/starship.toml -> /nix/store/...
# etc.
```

Your home-manager profile is at:
```bash
~/.nix-profile/
```

## Development Workflow

1. Make changes to `flake.nix`
2. Test in Docker (Linux): `nix run .#docker-test`
3. Apply to your system: `home-manager switch --flake .`
4. Commit and push changes

## Contributing

This is a personal configuration, but feel free to fork and adapt for your needs!

## License

MIT

## Author

Gregory Foster ([@brona90](https://github.com/brona90))

## See Also

- [Nix Documentation](https://nixos.org/manual/nix/stable/)
- [Home Manager Manual](https://nix-community.github.io/home-manager/)
- [Nix Pills](https://nixos.org/guides/nix-pills/) - Learning Nix
