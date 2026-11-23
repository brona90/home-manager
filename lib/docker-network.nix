# The user-defined docker network the claude-kg services run on, and the
# idempotent ExecStartPre that makes sure it exists.
#
# Why not the default bridge. On 2026-11-23 the `docker0` kernel interface had
# vanished while dockerd still believed in its `bridge` network: the running
# Qdrant and SearXNG containers were attached to a bridge that no longer
# existed, docker-proxy accepted connections and then sent the SYN to
# 172.17.0.x out of eth1, where it hung -- so the graph and search were dead
# from WSL and Windows alike, and any NEW container on the default bridge
# failed outright ("adding interface ... to bridge docker0 failed: Device does
# not exist"). The user-defined bridges on the same box (scottapp_default)
# survived. A dedicated network also stops these two sharing a segment with
# every other default-bridge container.
#
# Used by modules/claude-kg (Qdrant) and modules/searxng, which are separate
# modules that can be enabled independently, so each unit ensures the network
# itself. They usually start together, so two `create`s can race: the loser's
# create fails with "already exists", which is why the script re-inspects
# rather than trusting create's exit code. checks/service-binds.nix refuses a
# unit that falls back to the default bridge.
{
  pkgs,
  dockerBin,
}: rec {
  name = "claude-kg";
  ensure = pkgs.writeShellApplication {
    name = "docker-ensure-network-${name}";
    text = ''
      if ${dockerBin} network inspect ${name} >/dev/null 2>&1; then exit 0; fi
      if ${dockerBin} network create --driver bridge ${name} >/dev/null; then exit 0; fi
      # Lost a race with the other unit's create: fine if it exists now.
      ${dockerBin} network inspect ${name} >/dev/null
    '';
  };
}
