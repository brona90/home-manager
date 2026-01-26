#!/usr/bin/env bash
set -euo pipefail

# Bootstrap script for Nix Home Manager environment
# Works on any system with Nix installed

REPO_URL="https://github.com/brona90/home-manager.git"
CONFIG_DIR="${HOME}/.config/home-manager"
NIX_CONF_DIR="${HOME}/.config/nix"
NIX_CONF="${NIX_CONF_DIR}/nix.conf"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
prompt() { echo -e "${BLUE}[INPUT]${NC} $*"; }

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
  
  if [ -f "$NIX_CONF" ] && grep -q "gfoster.cachix.org" "$NIX_CONF"; then
    info "Nix already configured with caches"
    return
  fi
  
  info "Configuring Nix with flakes and caches..."
  
  cat > "$NIX_CONF" << 'EOF'
experimental-features = nix-command flakes
substituters = https://cache.nixos.org https://nix-community.cachix.org https://emacs.cachix.org https://gfoster.cachix.org
trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs= emacs.cachix.org-1:b1SMJNLY/mZF6GxQE+eDBeps7WnkT0Po55TAyzwOxTY= gfoster.cachix.org-1:O73e1PtN7sjaB5xDnBO/UMJSfheJjqlt6l6howghGvw=
max-jobs = auto
cores = 0
connect-timeout = 5
EOF
  
  info "Nix configured in $NIX_CONF"
}

# Check if home-manager is available
check_home_manager() {
  command -v home-manager &>/dev/null
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

# Check if user exists in config.nix
user_exists() {
  local username="$1"
  local system="$2"
  
  if [ ! -f "$CONFIG_DIR/config.nix" ]; then
    return 1
  fi
  
  # Check if username@system combo exists
  grep -q "username = \"${username}\"" "$CONFIG_DIR/config.nix" && \
  grep -q "\"${system}\"" "$CONFIG_DIR/config.nix"
}

# Add user to config.nix
add_user() {
  local username="$1"
  local system="$2"
  local config_file="$CONFIG_DIR/config.nix"
  
  info "Adding ${username}@${system} to config.nix..."
  
  # Check if user exists but needs system added
  if grep -q "username = \"${username}\"" "$config_file"; then
    # User exists, check if system needs to be added
    # This is a simple check - might need manual edit for complex cases
    warn "User ${username} exists. Please verify ${system} is in their systems list."
    warn "Edit $config_file if needed."
    return
  fi
  
  # Add new user entry before the closing bracket
  # Find the line with "];" and insert before it
  local new_entry="    { username = \"${username}\"; systems = [ \"${system}\" ]; }"
  
  # Use sed to insert new user
  if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS sed
    sed -i '' "/^  \];$/i\\
${new_entry}
" "$config_file"
  else
    # GNU sed
    sed -i "/^  \];$/i\\${new_entry}" "$config_file"
  fi
  
  info "Added ${username}@${system} to config.nix"
  info "Don't forget to commit this change!"
}

# Setup sops age key
setup_sops() {
  local age_dir="${HOME}/.config/sops/age"
  local age_key="${age_dir}/keys.txt"
  
  if [ -f "$age_key" ]; then
    info "Age key already exists at $age_key"
    return
  fi
  
  prompt "Do you want to set up sops secrets? (y/n)"
  read -r setup_sops
  
  if [[ "$setup_sops" != "y" ]]; then
    warn "Skipping sops setup. Secrets will not be available."
    warn "Run 'age-keygen -o $age_key' later to set up."
    return
  fi
  
  prompt "Do you have an existing age key to copy? (y/n)"
  read -r has_key
  
  if [[ "$has_key" == "y" ]]; then
    mkdir -p "$age_dir"
    prompt "Paste your age private key (starts with AGE-SECRET-KEY-), then press Enter twice:"
    local key=""
    while IFS= read -r line; do
      [[ -z "$line" ]] && break
      key+="$line"$'\n'
    done
    echo -n "$key" > "$age_key"
    chmod 600 "$age_key"
    info "Age key saved to $age_key"
  else
    info "Generating new age key..."
    mkdir -p "$age_dir"
    nix run nixpkgs#age -- -keygen -o "$age_key"
    chmod 600 "$age_key"
    info "Age key generated at $age_key"
    
    local pubkey=$(nix run nixpkgs#age -- -keygen -y "$age_key")
    warn "Your public key (add to .sops.yaml on a machine that has secrets):"
    echo "$pubkey"
    warn ""
    warn "On a machine with existing secrets, run:"
    warn "  1. Add public key to .sops.yaml"
    warn "  2. sops updatekeys secrets/secrets.yaml"
    warn "  3. git commit and push"
    warn "Then pull here and run hms again."
  fi
}

# Main bootstrap
main() {
  info "=== Nix Home Manager Bootstrap ==="
  
  local system=$(detect_system)
  local default_username=$(whoami)
  
  info "Detected system: $system"
  
  prompt "Enter username [$default_username]:"
  read -r username
  username="${username:-$default_username}"
  
  local config="${username}@${system}"
  info "Will configure: $config"
  
  check_nix
  configure_nix
  setup_config
  
  cd "$CONFIG_DIR"
  
  # Check/add user to config.nix
  if ! user_exists "$username" "$system"; then
    add_user "$username" "$system"
  else
    info "User $config already in config.nix"
  fi
  
  # Setup sops
  setup_sops
  
  info "Building and activating home-manager configuration..."
  if check_home_manager; then
    home-manager switch --flake ".#${config}" -b backup
  else
    nix run home-manager -- switch --flake ".#${config}" -b backup
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
