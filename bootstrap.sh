#!/usr/bin/env bash
set -euo pipefail

# Bootstrap script for Gregory's Nix environment
# Works on any system with Nix installed

REPO_URL="https://github.com/brona90/home-manager.git"
CONFIG_DIR="${HOME}/.config/home-manager"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# Detect system
detect_system() {
  local arch=$(uname -m)
  local os=$(uname -s)
  
  case "$os" in
    Linux)
      case "$arch" in
        x86_64)  echo "x86_64-linux" ;;
        aarch64) echo "aarch64-linux" ;;
        *)       error "Unsupported architecture: $arch" ;;
      esac
      ;;
    Darwin)
      case "$arch" in
        x86_64)  echo "x86_64-darwin" ;;
        arm64)   echo "aarch64-darwin" ;;
        *)       error "Unsupported architecture: $arch" ;;
      esac
      ;;
    *)
      error "Unsupported OS: $os"
      ;;
  esac
}

# Check if Nix is installed
check_nix() {
  if ! command -v nix &>/dev/null; then
    error "Nix is not installed. Install it first:
    
    curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install"
  fi
  
  if ! nix --version 2>&1 | grep -q "nix"; then
    error "Nix installation appears broken"
  fi
  
  info "Nix found: $(nix --version)"
}

# Check if home-manager is available
check_home_manager() {
  if ! command -v home-manager &>/dev/null; then
    warn "home-manager not in PATH, will use nix run"
    return 1
  fi
  return 0
}

# Clone or update config repo
setup_config() {
  if [ -d "$CONFIG_DIR/.git" ]; then
    info "Config directory exists, pulling latest..."
    git -C "$CONFIG_DIR" pull --ff-only || warn "Pull failed, using existing config"
  else
    info "Cloning config repository..."
    git clone "$REPO_URL" "$CONFIG_DIR"
  fi
}

# Main bootstrap
main() {
  info "=== Nix Environment Bootstrap ==="
  
  local system=$(detect_system)
  local username=$(whoami)
  local config="${username}@${system}"
  
  info "Detected system: $system"
  info "Username: $username"
  info "Config: $config"
  
  check_nix
  setup_config
  
  cd "$CONFIG_DIR"
  
  info "Updating flake inputs..."
  nix flake update
  
  info "Building and activating home-manager configuration..."
  if check_home_manager; then
    home-manager switch --flake ".#${config}"
  else
    nix run home-manager -- switch --flake ".#${config}"
  fi
  
  info "=== Bootstrap complete! ==="
  info "Restart your shell or run: exec zsh"
  info ""
  info "Commands available:"
  info "  hms  - Switch home-manager configuration"
  info "  nfu  - Update flake inputs"
  info "  em   - Open Emacs (via daemon)"
  info "  emt  - Open Emacs in terminal"
}

main "$@"
