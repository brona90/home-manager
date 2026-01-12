#!/bin/bash
# Bootstrap home-manager installation

set -e

echo "Installing home-manager..."

# Check if Nix is installed
if ! command -v nix &> /dev/null; then
    echo "Error: Nix is not installed. Please install Nix first:"
    echo "  sh <(curl -L https://nixos.org/nix/install) --daemon"
    exit 1
fi

# Check if flakes are enabled
if ! nix flake --help &> /dev/null 2>&1; then
    echo "Enabling flakes..."
    mkdir -p ~/.config/nix
    echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
    echo "Flakes enabled! You may need to restart your terminal."
fi

# Detect system
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)

if [ "$OS" = "darwin" ]; then
    SYSTEM="${ARCH}-darwin"
else
    SYSTEM="${ARCH}-linux"
fi

echo "Detected system: $SYSTEM"

# Backup existing dotfiles that home-manager will manage
echo "Backing up existing dotfiles..."
BACKUP_DIR="$HOME/.config/home-manager-backups/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

for file in .zshrc .zshenv .gitconfig .tmux.conf; do
    if [ -f "$HOME/$file" ] || [ -L "$HOME/$file" ]; then
        echo "  Backing up ~/$file"
        cp -P "$HOME/$file" "$BACKUP_DIR/" 2>/dev/null || true
        # Remove the file after backing up so home-manager can manage it
        rm -f "$HOME/$file"
    fi
done

if [ "$(ls -A $BACKUP_DIR 2>/dev/null)" ]; then
    echo "✓ Backups saved to: $BACKUP_DIR"
else
    rmdir "$BACKUP_DIR" 2>/dev/null || true
    echo "  No existing files to backup"
fi
echo ""

# Build and activate home-manager configuration
cd ~/.config/home-manager

echo "Building home-manager configuration..."
nix build .#homeConfigurations.gfoster@${SYSTEM}.activationPackage

echo "Activating home-manager..."
./result/activate

echo ""
echo "✓ Home-manager installed and activated!"
echo ""
echo "Please restart your terminal or run:"
echo "  source ~/.zshrc"
echo ""
echo "Then you can use 'home-manager' command:"
echo "  home-manager switch --flake .#gfoster@${SYSTEM}"
