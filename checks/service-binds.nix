# Guards on what the docker-backed user services expose and what they run.
#
# Review finding #5 (2026-11), confirmed live: Qdrant (6333/6334) and SearXNG
# (8888) were published with bare `-p HOST:CONTAINER`, which Docker binds on
# 0.0.0.0 and [::]. Neither service authenticates, and under WSL mirrored
# networking the distro's wildcard address is the Windows host's LAN address
# too -- so the knowledge graph was readable and deletable from the network.
# Every real client is local (kg-server, the hooks, the searxng MCP server,
# cloudflared at 127.0.0.1), so loopback is the whole requirement.
#
# NOTE for anyone editing these builders: stdenv runs them under
# `set -eu -o pipefail`; every grep that may legitimately not match is in an
# `if` or ends in `|| true` (see checks/ollama.nix).
#
# Inputs, passed by checks/default.nix. Nothing in this file reads flake.nix's
# scope; if it is not in this list, it is not available here.
#   pkgs  -- `pkgsFor system` for the system being checked.
#   units -- attrset of name -> the rendered systemd user unit, taken from the
#            BUILT home configuration, so the guard reads the ExecStart that
#            activation would install and not a module's source text.
#
# Paths are relative to THIS file, so anything at the repo root reads `../`.
{
  pkgs,
  units,
}: let
  # One "<name>\t<ExecStart on a single line>" record per unit. Backslash
  # continuations are flattened here so the shell sees plain words. Every
  # record ends in a newline: `read` drops an unterminated last line, which
  # would silently exempt whichever unit sorts last. home-manager's unit type
  # normalises ExecStart to a LIST of strings, so it is joined first.
  execStarts =
    builtins.concatStringsSep ""
    (pkgs.lib.mapAttrsToList (
        name: u:
          name
          + "\t"
          + builtins.replaceStrings ["\\\n" "\n"] [" " " "]
          (builtins.concatStringsSep " " (pkgs.lib.toList (u.Service.ExecStart or [])))
          + "\n"
      )
      units);
in {
  # Every published port is bound to 127.0.0.1 or [::1]; nothing uses the
  # host network namespace or --publish-all. Also refuses a unit with NO
  # publish at all: that would mean the flag moved to a form this parser does
  # not read, and the guard would otherwise pass having checked nothing.
  services-bind-loopback-only =
    pkgs.runCommand "services-bind-loopback-only" {
      inherit execStarts;
      passAsFile = ["execStarts"];
    } ''
      fail=0
      while IFS=$'\t' read -r name cmd; do
        [ -n "$name" ] || continue
        set -f
        # shellcheck disable=SC2086 # word-splitting the flattened command is the point
        set -- $cmd
        set +f
        published=0
        while [ $# -gt 0 ]; do
          spec=""
          case "$1" in
            -p | --publish) spec="''${2:-}"; shift ;;
            --publish=* | -p=*) spec="''${1#*=}" ;;
            -p?*) spec="''${1#-p}" ;;
            -P | --publish-all)
              echo "GUARD: $name uses $1, which publishes every exposed port on all interfaces."
              fail=1 ;;
            --network | --net)
              if [ "''${2:-}" = host ]; then
                echo "GUARD: $name runs with --network host, which exposes every port it listens on."
                fail=1
              fi
              shift ;;
            --network=host | --net=host)
              echo "GUARD: $name runs with $1, which exposes every port it listens on."
              fail=1 ;;
          esac
          if [ -n "$spec" ]; then
            published=$((published + 1))
            case "$spec" in
              127.0.0.1:*:* | '[::1]':*:*) ;;
              *)
                echo "GUARD: $name publishes '$spec', which is not bound to 127.0.0.1 or [::1]."
                echo '       A bare HOST:CONTAINER (or 0.0.0.0 / [::]) binds every interface,'
                echo '       and under WSL mirrored networking that includes the LAN.'
                echo '       Neither Qdrant nor SearXNG authenticates; publish on loopback.'
                fail=1 ;;
            esac
          fi
          shift
        done
        if [ "$published" -eq 0 ]; then
          echo "GUARD: found no -p/--publish in $name's ExecStart; the guard cannot vouch for it."
          fail=1
        fi
      done < "$execStartsPath"
      [ "$fail" -eq 0 ] || exit 1
      touch $out
    '';

  # Every image these units run is pinned by digest. A floating tag means the
  # running version is whatever the daemon last pulled -- recorded nowhere,
  # different per machine, and not bisectable when a storage format changes.
  services-images-pinned =
    pkgs.runCommand "services-images-pinned" {
      inherit execStarts;
      passAsFile = ["execStarts"];
    } ''
      fail=0
      while IFS=$'\t' read -r name cmd; do
        [ -n "$name" ] || continue
        if ! printf '%s\n' "$cmd" | grep -Eq '[^[:space:]]+@sha256:[0-9a-f]{64}([[:space:]]|$)'; then
          echo "GUARD: $name does not run an image pinned by @sha256 digest."
          echo '       Pin the digest that is running: docker inspect <container> | RepoDigests.'
          fail=1
        fi
      done < "$execStartsPath"
      [ "$fail" -eq 0 ] || exit 1
      touch $out
    '';
}
