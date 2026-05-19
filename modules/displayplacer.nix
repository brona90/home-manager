# Wrapper around Homebrew's `displayplacer` providing named resolution
# presets for common ultrawide / UHD monitors. The script resolves the
# external (non-built-in) display's persistent ID at runtime, so presets
# work regardless of which monitor is connected.
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

      # Find the first non-built-in display's persistent screen ID
      _external_id() {
        "$DP" list | /usr/bin/awk '
          /^Persistent screen id:/ { id=$NF; type=""; next }
          /^Type:/                 { type=tolower($0) }
          /^$/ {
            if (id != "" && type !~ /built-?in/) { print id; exit }
            id=""; type=""
          }
          END {
            if (id != "" && type !~ /built-?in/) print id
          }
        '
      }

      _set_external() {
        local res=$1 hz=''${2:-60} scaling=''${3:-off}
        local id
        id=$(_external_id)
        if [[ -z "$id" ]]; then
          echo "error: no external display detected. Connect the monitor and try again." >&2
          exit 1
        fi
        echo "→ external display $id : ''${res} @ ''${hz}Hz (scaling:$scaling)"
        "$DP" "id:$id res:$res hz:$hz color_depth:8 scaling:$scaling origin:(0,0) degree:0"
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
  set WIDTHxHEIGHT [HZ]  Apply arbitrary resolution (HZ defaults to 60)

Each preset accepts an optional refresh rate as the second arg, e.g.:
  dp uwqhd 100          3440x1440 @ 100 Hz
  dp 4k 30              3840x2160 @ 30 Hz (useful over Remote Desktop)
EOF
      }

      case "''${1:-}" in
        list) "$DP" list ;;

        # Ultrawide
        uwfhd)             _set_external 2560x1080 "''${2:-60}" ;;
        uwqhd)             _set_external 3440x1440 "''${2:-60}" ;;
        uwqhd-plus)        _set_external 3840x1600 "''${2:-60}" ;;
        5k2k)              _set_external 5120x2160 "''${2:-60}" ;;
        dqhd|super-uw)     _set_external 5120x1440 "''${2:-60}" ;;
        dwuxga)            _set_external 3840x1200 "''${2:-60}" ;;

        # 16:9
        4k|uhd)            _set_external 3840x2160 "''${2:-60}" ;;
        1440p|qhd)         _set_external 2560x1440 "''${2:-60}" ;;
        1200p|wuxga)       _set_external 1920x1200 "''${2:-60}" ;;
        1080p|fhd)         _set_external 1920x1080 "''${2:-60}" ;;
        720p)              _set_external 1280x720  "''${2:-60}" ;;

        # HiDPI variants
        4k-hidpi)          _set_external 3840x2160 "''${2:-60}" on ;;
        uwqhd-hidpi)       _set_external 3440x1440 "''${2:-60}" on ;;

        set)
          if [[ -z "''${2:-}" ]]; then
            echo "Usage: dp set WIDTHxHEIGHT [HZ]" >&2
            exit 1
          fi
          _set_external "$2" "''${3:-60}"
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
