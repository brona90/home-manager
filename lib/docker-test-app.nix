# Docker test app - runs the built image locally
#
# Usage: nix run .#docker-test

{ pkgs, homeDirectory, imageName ? "brona90/terminal", imageTag ? "latest" }:

{
  type = "app";
  meta.description = "Build and test Docker image locally";
  program = toString (pkgs.writeShellScript "docker-test" ''
    set -e
    echo "Building Docker image..."
    rm -f result
    nix build ~/.config/home-manager#dockerImage

    echo "Loading image into Docker..."
    docker load < result

    DOCKER_ARGS="-it --rm --network host"
    DOCKER_ARGS="$DOCKER_ARGS --tmpfs ${homeDirectory}:exec,uid=1000,gid=1000,mode=0755"
    DOCKER_ARGS="$DOCKER_ARGS --tmpfs /tmp:exec,mode=1777"

    [ -d "$HOME/.ssh" ] && DOCKER_ARGS="$DOCKER_ARGS -v $HOME/.ssh:${homeDirectory}/.ssh:ro"
    [ -n "$SSH_AUTH_SOCK" ] && DOCKER_ARGS="$DOCKER_ARGS -v $SSH_AUTH_SOCK:/ssh-agent -e SSH_AUTH_SOCK=/ssh-agent"

    echo "Starting container..."
    docker run $DOCKER_ARGS ${imageName}:${imageTag}
  '');
}
