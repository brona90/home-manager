{ config, lib, pkgs, userConfig, ... }:

let
  cfg = config.my.dockerTerminal;
  repoConfig = userConfig.repo;
  homeDir = config.home.homeDirectory;
  username = config.home.username;
  
  terminalScript = pkgs.writeShellScriptBin "terminal" ''
    IMAGE="''${DOCKER_TERMINAL_IMAGE:-${repoConfig.dockerHubUser}/terminal:latest}"
    MODE="ephemeral"
    WORKSPACE=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
      case $1 in
        -p|--persistent)
          MODE="persistent"
          shift
          ;;
        -w|--workspace)
          MODE="workspace"
          WORKSPACE="''${2:-$PWD}"
          shift 2
          ;;
        -h|--help)
          cat << HELP
Usage: terminal [OPTIONS]

Run the Home Manager environment in Docker

OPTIONS:
  -p, --persistent     Persistent home directory (survives container restarts)
  -w, --workspace DIR  Mount DIR as workspace (default: current directory)
  -h, --help          Show this help

MODES:
  Ephemeral (default): Clean environment each run, SSH keys mounted read-only
  Persistent:          Home directory persists in ~/.local/share/docker-terminal
  Workspace:           Mount a directory for project work

ENVIRONMENT:
  DOCKER_TERMINAL_IMAGE  Override image (default: ${repoConfig.dockerHubUser}/terminal:latest)

EXAMPLES:
  terminal                    # Ephemeral session
  terminal -p                 # Persistent session
  terminal -w ~/projects/foo  # Work on specific project
  terminal -w .               # Work in current directory
HELP
          exit 0
          ;;
        *)
          echo "Unknown option: $1"
          echo "Run 'terminal --help' for usage"
          exit 1
          ;;
      esac
    done
    
    # Base Docker args
    DOCKER_ARGS="-it --rm --network host"
    
    # Configure based on mode
    case "$MODE" in
      ephemeral)
        # Tmpfs home - nothing persists
        DOCKER_ARGS="$DOCKER_ARGS --tmpfs ${homeDir}:exec,uid=$(id -u),gid=$(id -g),mode=0755"
        DOCKER_ARGS="$DOCKER_ARGS --tmpfs /tmp:exec,mode=1777"
        ;;
        
      persistent)
        # Persistent home directory
        PERSIST_DIR="$HOME/.local/share/docker-terminal"
        mkdir -p "$PERSIST_DIR"
        DOCKER_ARGS="$DOCKER_ARGS -v $PERSIST_DIR:${homeDir}"
        DOCKER_ARGS="$DOCKER_ARGS --tmpfs /tmp:exec,mode=1777"
        echo "Using persistent home: $PERSIST_DIR"
        ;;
        
      workspace)
        # Ephemeral home + mounted workspace
        DOCKER_ARGS="$DOCKER_ARGS --tmpfs ${homeDir}:exec,uid=$(id -u),gid=$(id -g),mode=0755"
        DOCKER_ARGS="$DOCKER_ARGS --tmpfs /tmp:exec,mode=1777"
        DOCKER_ARGS="$DOCKER_ARGS -v $WORKSPACE:/workspace -w /workspace"
        echo "Workspace: $WORKSPACE -> /workspace"
        ;;
    esac
    
    # Mount SSH keys (read-only) - all modes
    if [ -d "$HOME/.ssh" ]; then
      DOCKER_ARGS="$DOCKER_ARGS -v $HOME/.ssh:${homeDir}/.ssh:ro"
    fi
    
    # Forward SSH agent - all modes
    if [ -n "$SSH_AUTH_SOCK" ]; then
      DOCKER_ARGS="$DOCKER_ARGS -v $SSH_AUTH_SOCK:/ssh-agent -e SSH_AUTH_SOCK=/ssh-agent"
    fi
    
    # Run the container
    exec docker run $DOCKER_ARGS "$IMAGE"
  '';

in
{
  options.my.dockerTerminal = {
    enable = lib.mkEnableOption "Docker terminal wrapper for Home Manager image";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ terminalScript ];
    
    my.zsh.extraAliases = {
      # Quick aliases for common modes
      term-clean = "terminal";                    # Ephemeral
      term-persist = "terminal --persistent";     # Persistent
      term-here = "terminal --workspace .";       # Current directory
    };
  };
}
