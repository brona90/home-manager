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

# Enable flakes if not already enabled
enable_flakes() {
  mkdir -p "$NIX_CONF_DIR"
  
  if [ -f "$NIX_CONF" ] && grep -q "experimental-features.*flakes" "$NIX_CONF"; then
    info "Flakes already enabled"
    return
  fi
  
  info "Enabling flakes..."
  
  if [ -f "$NIX_CONF" ]; then
    # Append to existing config
    echo "" >> "$NIX_CONF"
    echo "# Enable flakes and new nix command" >> "$NIX_CONF"
    echo "experimental-features = nix-command flakes" >> "$NIX_CONF"
  else
    # Create new config
    cat > "$NIX_CONF" << 'EOF'
# Enable flakes and new nix command
experimental-features = nix-command flakes
EOF
  fi
  
  info "Flakes enabled in $NIX_CONF"
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
  enable_flakes
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
