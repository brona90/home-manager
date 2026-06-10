# Docker test app - runs the built image locally
#
# Usage: nix run .#docker-test [-- FLAKE_REF]
#   FLAKE_REF defaults to $HOME/.config/home-manager
{
  pkgs,
  homeDirectory,
  imageName,
  imageTag ? "latest",
}: {
  type = "app";
  meta.description = "Build and test Docker image locally";
  program = "${pkgs.writeShellApplication {
    name = "docker-test";
    text = ''
      # Optional first argument: flake ref to build the image from
      # (defaults to the standard checkout location; pass a path to test
      # a fork or alternate checkout).
      FLAKE_REF="''${1:-$HOME/.config/home-manager}"

      # Build into a throwaway directory so no `result` symlink is left
      # in the caller's cwd.
      tmpdir=$(mktemp -d)
      trap 'rm -rf "$tmpdir"' EXIT

      echo "Building Docker image from $FLAKE_REF..."
      nix build "$FLAKE_REF#dockerImage" -o "$tmpdir/result"

      echo "Loading image into Docker..."
      docker load < "$tmpdir/result"

      DOCKER_ARGS=("-it" "--rm" "--network" "host")
      # uid/gid 1000 matches the user baked into the image
      # (lib/docker-image.nix), not the host user.
      DOCKER_ARGS+=("--tmpfs" "${homeDirectory}:exec,uid=1000,gid=1000,mode=0755")
      DOCKER_ARGS+=("--tmpfs" "/tmp:exec,mode=1777")

      [ -S "''${SSH_AUTH_SOCK:-}" ] && DOCKER_ARGS+=("-v" "$SSH_AUTH_SOCK:/ssh-agent" "-e" "SSH_AUTH_SOCK=/ssh-agent")

      echo "Starting container..."
      docker run "''${DOCKER_ARGS[@]}" "${imageName}:${imageTag}"
    '';
  }}/bin/docker-test";
}
