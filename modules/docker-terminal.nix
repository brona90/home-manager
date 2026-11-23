{
  config,
  lib,
  pkgs,
  userConfig,
  ...
}: let
  cfg = config.my.dockerTerminal;
  repoConfig = userConfig.repo;
  inherit (config.home) homeDirectory;

  # Must match the uid/gid baked into the image (lib/docker-image.nix
  # defaults). Host ids ($(id -u)) diverge on macOS (501) and would leave
  # the container user unable to write $HOME.
  imageUid = 1000;
  imageGid = 1000;

  terminalScript = pkgs.writeShellApplication {
    name = "terminal";
    text = ''
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
                WORKSPACE="$(cd "''${2:-$PWD}" && pwd)"
                # `shift 2` with no directory argument would fail under
                # set -e; consume the optional argument only if present.
                shift
                if [[ $# -gt 0 ]]; then shift; fi
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
        Ephemeral (default): Clean environment each run
        Persistent:          Home directory persists in ~/.local/share/docker-terminal
                             (owned by uid 1000, the image user)
        Workspace:           Mount a directory for project work

      SSH: the host SSH agent is forwarded when SSH_AUTH_SOCK is set;
      private keys are never mounted into the container.

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

          # Base Docker args. Default bridge networking: the container gets
          # outbound network but does NOT share the host's namespace, so it
          # cannot reach the host's loopback-only services (Qdrant, SearXNG,
          # Ollama, the scottapp databases -- none of which authenticate) and
          # anything it listens on stays inside it. SSH agent forwarding does
          # not need host networking: it is the socket bind-mount below.
          # my.dockerTerminal.hostNetwork opts back into --network host.
          DOCKER_ARGS=("-it" "--rm")
          ${lib.optionalString cfg.hostNetwork ''DOCKER_ARGS+=("--network" "host")''}

          # Configure based on mode
          case "$MODE" in
            ephemeral)
              # Tmpfs home - nothing persists. Owned by the image user
              # (uid ${toString imageUid}), not the host user.
              DOCKER_ARGS+=("--tmpfs" "${homeDirectory}:exec,uid=${toString imageUid},gid=${toString imageGid},mode=0755")
              DOCKER_ARGS+=("--tmpfs" "/tmp:exec,mode=1777")
              ;;

            persistent)
              # Persistent home directory. Files created inside the
              # container are owned by the image user (uid ${toString imageUid}), so the
              # persist dir on the host ends up uid-${toString imageUid}-owned too.
              PERSIST_DIR="''${XDG_DATA_HOME:-$HOME/.local/share}/docker-terminal"
              mkdir -p "$PERSIST_DIR"
              DOCKER_ARGS+=("-v" "$PERSIST_DIR:${homeDirectory}")
              DOCKER_ARGS+=("--tmpfs" "/tmp:exec,mode=1777")
              echo "Using persistent home: $PERSIST_DIR (files owned by uid ${toString imageUid} inside the container)"
              ;;

            workspace)
              # Ephemeral home + mounted workspace
              DOCKER_ARGS+=("--tmpfs" "${homeDirectory}:exec,uid=${toString imageUid},gid=${toString imageGid},mode=0755")
              DOCKER_ARGS+=("--tmpfs" "/tmp:exec,mode=1777")
              DOCKER_ARGS+=("-v" "$WORKSPACE:/workspace" "-w" "/workspace")
              echo "Workspace: $WORKSPACE -> /workspace"
              ;;
          esac

          # SSH access is via agent forwarding only. ~/.ssh is deliberately
          # NOT bind-mounted: it contains the sops-decrypted private key,
          # which must never be exposed inside the container.

          # Forward SSH agent - all modes
          if [ -S "''${SSH_AUTH_SOCK:-}" ]; then
            DOCKER_ARGS+=("-v" "$SSH_AUTH_SOCK:/ssh-agent" "-e" "SSH_AUTH_SOCK=/ssh-agent")
          fi

          # Run the container
          exec docker run "''${DOCKER_ARGS[@]}" "$IMAGE"
    '';
  };
in {
  options.my.dockerTerminal = {
    enable = lib.mkEnableOption "Docker terminal wrapper for Home Manager image";
    hostNetwork = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Run the terminal container with `--network host`, sharing the host's
        network namespace. Off by default: it gives the container every
        loopback-only service on the host (none of which authenticate) and
        lets it bind host ports. Turn on only when a session genuinely needs
        to talk to a host-local service.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [terminalScript];

    my.zsh.extraAliases = {
      # Quick aliases for common modes
      term-clean = "terminal"; # Ephemeral
      term-persist = "terminal --persistent"; # Persistent
      term-here = "terminal --workspace ."; # Current directory
    };
  };
}
