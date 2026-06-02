# Wrapper around Homebrew's `displayplacer` providing named resolution
# presets for common ultrawide / UHD monitors. The script resolves the
# main display's persistent ID at runtime (the one macOS reports as
# origin (0,0)), so presets target whatever the system currently treats
# as the primary screen — typically an external monitor when one is
# attached, otherwise the built-in.
#
# Usage:
#   dp list             — show all displays + available modes
#   dp uwqhd            — 3440x1440 (most common 21:9 ultrawide)
#   dp uwqhd 100        — 3440x1440 @ 100Hz
#   dp set 3840x1600 75 — arbitrary resolution
#
# Requires the Homebrew `displayplacer` cask (installed via home/darwin.nix).
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.my.displayplacer;

  dpScript = pkgs.writeShellApplication {
    name = "dp";
    text = ''
            # Locate the brew-installed binary (Apple Silicon vs Intel paths)
            DP=""
            for candidate in /opt/homebrew/bin/displayplacer /usr/local/bin/displayplacer; do
              if [[ -x "$candidate" ]]; then
                DP="$candidate"
                break
              fi
            done
            if [[ -z "$DP" ]] && command -v displayplacer >/dev/null 2>&1; then
              DP="$(command -v displayplacer)"
            fi
            if [[ -z "$DP" ]]; then
              echo "error: displayplacer not found." >&2
              echo "Install it via 'hms' (already wired in home/darwin.nix) or 'brew install displayplacer'." >&2
              exit 1
            fi

            # Find the main display's persistent screen ID (the one at origin 0,0).
            # head -n 1 sidesteps BSD awk re-running END after exit.
            _main_id() {
              "$DP" list | /usr/bin/awk '
                /^Persistent screen id:/ { id=$NF; main=0; next }
                /^Origin:.*main display/ { main=1 }
                /^$/ {
                  if (main && id != "") { print id; exit }
                  id=""; main=0
                }
              ' | /usr/bin/head -n 1
            }

            # Print supported resolutions for a given display id, deduped.
            _supported_res() {
              local id=$1
              "$DP" list | /usr/bin/awk -v id="$id" '
                /^Persistent screen id:/ { want=($NF==id); next }
                want && /^  mode/ {
                  for (i=1; i<=NF; i++) if ($i ~ /^res:/) print substr($i, 5)
                }
              ' | /usr/bin/sort -u
            }

            _set_main() {
              local res=$1 hz=$2 scaling=''${3:-off}
              local id
              id=$(_main_id)
              if [[ -z "$id" ]]; then
                echo "error: could not identify main display from 'displayplacer list'." >&2
                exit 1
              fi

              local hz_part="" hz_label="(any hz)"
              if [[ -n "$hz" ]]; then
                hz_part="hz:$hz "
                hz_label="@ ''${hz}Hz"
              fi

              echo "→ main display $id : ''${res} ''${hz_label} (scaling:$scaling)"

              # Try requested mode; if it fails and hz was specified, retry without
              # hz (built-in MBP panels report Hertz: N/A and reject any hz spec).
              if "$DP" "id:$id res:$res ''${hz_part}color_depth:8 scaling:$scaling origin:(0,0) degree:0" 2>/dev/null; then
                return 0
              fi
              if [[ -n "$hz_part" ]] \
                && "$DP" "id:$id res:$res color_depth:8 scaling:$scaling origin:(0,0) degree:0" 2>/dev/null; then
                echo "  (applied without hz — this display has no configurable refresh rate)"
                return 0
              fi

              echo "" >&2
              echo "Mode ''${res} not supported by this display. Supported resolutions:" >&2
              _supported_res "$id" | /usr/bin/sed 's/^/  /' >&2
              exit 1
            }

            _usage() {
              cat <<'EOF'
      Usage: dp <command> [hz]

      Identification:
        list                  Show all displays with persistent IDs + available modes

      Ultrawide presets (21:9 / 32:9):
        uwfhd                 2560 x 1080   (21:9 ultrawide FHD)
        uwqhd                 3440 x 1440   (21:9 ultrawide QHD — most common)
        uwqhd-plus            3840 x 1600   (21:9 LG 38" class)
        5k2k                  5120 x 2160   (21:9 5K2K)
        dqhd | super-uw       5120 x 1440   (32:9 dual-QHD super ultrawide)
        dwuxga                3840 x 1200   (32:10 dual-WUXGA)

      UHD / 16:9 presets:
        4k | uhd              3840 x 2160
        1440p | qhd           2560 x 1440
        1200p | wuxga         1920 x 1200
        1080p | fhd           1920 x 1080
        720p                  1280 x  720

      HiDPI variants (Retina-style — only on supported displays):
        4k-hidpi              3840 x 2160 scaled
        uwqhd-hidpi           3440 x 1440 scaled

      Custom:
        set WIDTHxHEIGHT [HZ]  Apply arbitrary resolution (HZ optional)

      Each preset accepts an optional refresh rate as the second arg. If
      omitted, displayplacer picks any matching mode (necessary for built-in
      laptop panels, which report Hertz: N/A). Examples:
        dp uwqhd 100          3440x1440 @ 100 Hz
        dp 4k 30              3840x2160 @ 30 Hz (useful over Remote Desktop)
      EOF
            }

            case "''${1:-}" in
              list) "$DP" list ;;

              # Ultrawide
              uwfhd)             _set_main 2560x1080 "''${2:-}" ;;
              uwqhd)             _set_main 3440x1440 "''${2:-}" ;;
              uwqhd-plus)        _set_main 3840x1600 "''${2:-}" ;;
              5k2k)              _set_main 5120x2160 "''${2:-}" ;;
              dqhd|super-uw)     _set_main 5120x1440 "''${2:-}" ;;
              dwuxga)            _set_main 3840x1200 "''${2:-}" ;;

              # 16:9
              4k|uhd)            _set_main 3840x2160 "''${2:-}" ;;
              1440p|qhd)         _set_main 2560x1440 "''${2:-}" ;;
              1200p|wuxga)       _set_main 1920x1200 "''${2:-}" ;;
              1080p|fhd)         _set_main 1920x1080 "''${2:-}" ;;
              720p)              _set_main 1280x720  "''${2:-}" ;;

              # HiDPI variants
              4k-hidpi)          _set_main 3840x2160 "''${2:-}" on ;;
              uwqhd-hidpi)       _set_main 3440x1440 "''${2:-}" on ;;

              set)
                if [[ -z "''${2:-}" ]]; then
                  echo "Usage: dp set WIDTHxHEIGHT [HZ]" >&2
                  exit 1
                fi
                _set_main "$2" "''${3:-}"
                ;;

              ""|--help|-h|help) _usage ;;

              *)
                echo "Unknown command: $1" >&2
                _usage
                exit 1
                ;;
            esac
    '';
  };
in {
  options.my.displayplacer.enable =
    lib.mkEnableOption "dp wrapper around Homebrew displayplacer with ultrawide/UHD presets";

  config = lib.mkIf cfg.enable {
    home.packages = [dpScript];
  };
}
