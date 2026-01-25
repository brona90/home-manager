#!/usr/bin/env bash
set -euo pipefail

# Bootstrap script for Gregory's Nix environment
# Works on any system with Nix installed

REPO_URL="https://github.com/brona90/home-manager.git"
CONFIG_DIR="${HOME}/.config/home-manager"
NIX_CONF_DIR="${HOME}/.config/nix"
NIX_CONF="${NIX_CONF_DIR}/nix.conf"

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
  
  info "Nix found: $(nix --version)"
}

# Configure Nix with flakes and caches
configure_nix() {
  mkdir -p "$NIX_CONF_DIR"
  
  # Check if already fully configured
  if [ -f "$NIX_CONF" ] && grep -q "gfoster.cachix.org" "$NIX_CONF"; then
    info "Nix already configured with caches"
    return
  fi
  
  info "Configuring Nix with flakes and caches..."
  
  cat > "$NIX_CONF" << 'EOF'
# Enable flakes and new nix command
experimental-features = nix-command flakes

# Binary caches
substituters = https://cache.nixos.org https://nix-community.cachix.org https://emacs.cachix.org https://gfoster.cachix.org
trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs= emacs.cachix.org-1:b1SMJNLY/mZF6GxQE+eDBeps7WnkT0Po55TAyzwOxTY= gfoster.cachix.org-1:O73e1PtN7sjaB5xDnBO/UMJSfheJjqlt6l6howghGvw=

# Performance
max-jobs = auto
cores = 0
connect-timeout = 5
EOF
  
  info "Nix configured in $NIX_CONF"
}

# Check if home-manager is available
check_home_manager() {
  if command -v home-manager &>/dev/null; then
    return 0
  fi
  return 1
}

# Clone or update config repo
setup_config() {
  if [ -d "$CONFIG_DIR/.git" ]; then
    info "Config directory exists, pulling latest..."
    git -C "$CONFIG_DIR" pull --ff-only || warn "Pull failed, using existing config"
  else
    info "Cloning config repository..."
    mkdir -p "$(dirname "$CONFIG_DIR")"
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
  configure_nix
  setup_config
  
  cd "$CONFIG_DIR"
  
  info "Building and activating home-manager configuration..."
  if check_home_manager; then
    home-manager switch --flake ".#${config}"
  else
    # First run: use nix run to bootstrap home-manager
    nix run home-manager -- switch --flake ".#${config}"
  fi
  
  info "=== Bootstrap complete! ==="
  info "Restart your shell or run: exec zsh"
  info ""
  info "Commands available:"
  info "  hms  - Switch home-manager configuration"
  info "  nrs  - Switch NixOS configuration (NixOS only)"
  info "  nfu  - Update flake inputs"
  info "  em   - Open Emacs (via daemon)"
  info "  emt  - Open Emacs in terminal"
}

main "$@"
