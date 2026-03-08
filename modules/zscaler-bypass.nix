# Installs a root LaunchDaemon that adds per-host /32 and per-subnet routes via
# the physical interface (en0) for build registry traffic, overriding the broad
# CIDR routes that Zscaler injects via its utun tunnel.  Re-runs automatically
# whenever /private/var/run/resolv.conf changes (i.e. on any network event).
#
# Runtime route management (no hms required):
#   zscaler-routes add host example.com
#   zscaler-routes add subnet 10.0.0.0/8
#   zscaler-routes remove example.com
#   zscaler-routes list / search <pattern> / apply
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.my.zscalerBypass;

  daemonLabel = "com.home-manager.zscaler-bypass";

  # Shell expression for the user's mutable extra-routes config file
  confExpr = ''"''${XDG_CONFIG_HOME:-$HOME/.config}/zscaler-bypass/extra.conf"'';

  # Built-in entries as individual echo calls (safe for any hostname/CIDR value)
  builtinEchos = lib.concatStringsSep "\n" (
    map (h: "echo ${lib.escapeShellArg "  host ${h}"}") cfg.hosts
    ++ map (n: "echo ${lib.escapeShellArg "  subnet ${n}"}") cfg.subnets
  );

  # Shared shell functions used by both bypass and status scripts
  bypassFunctions = ''
    bypass() {
      local host=$1
      local ips
      ips=$(/usr/bin/dig +short A "$host" 2>/dev/null) || return 0
      while IFS= read -r ip; do
        [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue
        if /sbin/route -q add -host "$ip" "$GATEWAY" 2>/dev/null; then
          echo "  $host -> $ip (added)"
        else
          echo "  $host -> $ip (already present)"
        fi
      done <<< "$ips"
    }

    bypass_net() {
      local net=$1
      if /sbin/route -q add -net "$net" "$GATEWAY" 2>/dev/null; then
        echo "  $net (added)"
      else
        echo "  $net (already present)"
      fi
    }
  '';

  # Shell snippet that processes extra.conf entries (reused in bypass + status)
  processExtraConf = type: ''
    CONF=${confExpr}
    if [[ -f "$CONF" ]]; then
      while IFS= read -r _line; do
        [[ "$_line" =~ ^[[:space:]]*# || -z "$_line" ]] && continue
        _type="''${_line%% *}"
        _entry="''${_line#* }"
        case "$_type" in
          host)   ${type} "$_entry" ;;
          subnet) ${type}_net "$_entry" ;;
        esac
      done < "$CONF"
    fi
  '';

  bypassScript = pkgs.writeShellApplication {
    name = "zscaler-bypass";
    text = ''
      # Only act when Zscaler tunnel process is running
      if ! /usr/bin/pgrep -x ZscalerTunnel > /dev/null 2>&1; then
        echo "Zscaler not active, nothing to do"
        exit 0
      fi

      # Dynamically find the physical gateway (first default route via en*).
      # || true: awk exits early causing netstat SIGPIPE; pipefail would abort without it.
      GATEWAY=$(/usr/sbin/netstat -rn \
        | /usr/bin/awk '/^default[[:space:]].*en[0-9]/{print $2; exit}') || true
      if [[ -z "$GATEWAY" ]]; then
        echo "ERROR: no physical gateway found on en*" >&2
        exit 1
      fi

      echo "Zscaler active — bypassing via $GATEWAY"

      ${bypassFunctions}

      # Built-in hosts
      ${lib.concatMapStringsSep "\n      " (h: "bypass ${lib.escapeShellArg h}") cfg.hosts}

      # Built-in subnets
      ${lib.concatMapStringsSep "\n      " (n: "bypass_net ${lib.escapeShellArg n}") cfg.subnets}

      # User-defined extra routes
      ${processExtraConf "bypass"}
    '';
  };

  statusScript = pkgs.writeShellApplication {
    name = "zscaler-status";
    text = ''
      echo "=== Zscaler ==="
      if /usr/bin/pgrep -x ZscalerTunnel > /dev/null 2>&1; then
        echo "ZscalerTunnel: ACTIVE (pid $(/usr/bin/pgrep -x ZscalerTunnel))"
      else
        echo "ZscalerTunnel: not running"
      fi

      echo ""
      echo "=== Bypass daemon ==="
      if [[ -f /Library/LaunchDaemons/${daemonLabel}.plist ]]; then
        echo "Plist:  installed"
      else
        echo "Plist:  NOT installed — run hms"
      fi

      check_host() {
        local host=$1 ip iface status
        ip=$(/usr/bin/dig +short A "$host" 2>/dev/null \
          | /usr/bin/grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
        if [[ -z "$ip" ]]; then
          printf "  %-45s (DNS failed)\n" "$host"
          return
        fi
        iface=$(/sbin/route get "$ip" 2>/dev/null \
          | /usr/bin/awk '/interface:/{print $2}') || true
        if [[ "$iface" == en* ]]; then
          status="BYPASSED ($iface)"
        else
          status="via Zscaler ($iface)"
        fi
        printf "  %-45s %-16s %s\n" "$host" "$ip" "$status"
      }

      check_net() {
        local net=$1 iface status
        local sample
        sample=$(echo "$net" | /usr/bin/awk -F'[./]' '{print $1"."$2"."$3"."$4+1}')
        iface=$(/sbin/route get "$sample" 2>/dev/null \
          | /usr/bin/awk '/interface:/{print $2}') || true
        if [[ "$iface" == en* ]]; then
          status="BYPASSED ($iface)"
        else
          status="via Zscaler ($iface)"
        fi
        printf "  %-45s %s\n" "$net" "$status"
      }

      echo ""
      echo "=== Host routing ==="
      ${lib.concatMapStringsSep "\n      " (h: "check_host ${lib.escapeShellArg h}") cfg.hosts}

      echo ""
      echo "=== Subnet routes ==="
      ${lib.concatMapStringsSep "\n      " (n: "check_net ${lib.escapeShellArg n}") cfg.subnets}

      # User-defined entries from extra.conf
      CONF=${confExpr}
      if [[ -f "$CONF" ]] && /usr/bin/grep -qvE "^[[:space:]]*#|^[[:space:]]*$" "$CONF" 2>/dev/null; then
        echo ""
        echo "=== User-defined routes ==="
        while IFS= read -r _line; do
          [[ "$_line" =~ ^[[:space:]]*# || -z "$_line" ]] && continue
          _type="''${_line%% *}"
          _entry="''${_line#* }"
          case "$_type" in
            host)   check_host "$_entry" ;;
            subnet) check_net "$_entry" ;;
          esac
        done < "$CONF"
      fi
    '';
  };

  routesScript = pkgs.writeShellApplication {
    name = "zscaler-routes";
    text = ''
            CONF=${confExpr}

            _ensure_conf() {
              /bin/mkdir -p "$(/usr/bin/dirname "$CONF")"
              [[ -f "$CONF" ]] || /usr/bin/touch "$CONF"
            }

            # Re-run the daemon as root so it picks up config changes immediately
            _apply() {
              if /usr/bin/pgrep -x ZscalerTunnel > /dev/null 2>&1; then
                echo "Applying routes via daemon..."
                /usr/bin/sudo /bin/launchctl kickstart -k "system/${daemonLabel}"
              fi
            }

            _usage() {
              cat << 'EOF'
      Usage: zscaler-routes <command> [args]

        list [host|subnet]          List all bypass entries (built-in + user-defined)
        add host <hostname>         Add a hostname bypass and apply immediately
        add subnet <cidr>           Add a CIDR subnet bypass and apply immediately
        remove <entry>              Remove a user-defined bypass entry
        search <pattern>            Search all entries (case-insensitive)
        apply                       Re-apply all routes via daemon
      EOF
              exit 0
            }

            case "''${1:-}" in
              list)
                _filter="''${2:-}"
                echo "Built-in:"
                if [[ -n "$_filter" ]]; then
                  { ${builtinEchos}; } | /usr/bin/grep "^  $_filter " || echo "  (none)"
                else
                  ${builtinEchos}
                fi
                echo ""
                echo "User-defined ($CONF):"
                if [[ -f "$CONF" ]] && /usr/bin/grep -qvE "^[[:space:]]*#|^[[:space:]]*$" "$CONF" 2>/dev/null; then
                  if [[ -n "$_filter" ]]; then
                    /usr/bin/grep -vE "^[[:space:]]*#|^[[:space:]]*$" "$CONF" \
                      | /usr/bin/grep "^$_filter " | /usr/bin/sed 's/^/  /' || echo "  (none)"
                  else
                    /usr/bin/grep -vE "^[[:space:]]*#|^[[:space:]]*$" "$CONF" \
                      | /usr/bin/sed 's/^/  /'
                  fi
                else
                  echo "  (none)"
                fi
                ;;

              add)
                _type="''${2:-}"
                _entry="''${3:-}"
                [[ "$_type" == "host" || "$_type" == "subnet" ]] \
                  || { echo "Error: type must be 'host' or 'subnet'"; exit 1; }
                [[ -n "$_entry" ]] || { echo "Error: entry value required"; exit 1; }
                _ensure_conf
                if /usr/bin/grep -qxF "$_type $_entry" "$CONF" 2>/dev/null; then
                  echo "$_type $_entry is already configured"
                else
                  printf '%s %s\n' "$_type" "$_entry" >> "$CONF"
                  echo "Added: $_type $_entry"
                  _apply
                fi
                ;;

              remove)
                _entry="''${2:-}"
                [[ -n "$_entry" ]] || { echo "Error: entry required"; exit 1; }
                _ensure_conf
                if /usr/bin/grep -qxF "host $_entry" "$CONF" 2>/dev/null; then
                  _line_type="host"
                elif /usr/bin/grep -qxF "subnet $_entry" "$CONF" 2>/dev/null; then
                  _line_type="subnet"
                else
                  echo "Not found in user-defined routes: $_entry"
                  echo "(Built-in routes can only be changed in home-manager config)"
                  exit 1
                fi
                _tmp=$(/usr/bin/mktemp)
                { /usr/bin/grep -vxF "host $_entry" "$CONF" || true; } \
                  | { /usr/bin/grep -vxF "subnet $_entry" || true; } > "$_tmp"
                /bin/mv "$_tmp" "$CONF"
                echo "Removed: $_entry"
                case "$_line_type" in
                  subnet)
                    /usr/bin/sudo /sbin/route -q delete -net "$_entry" 2>/dev/null \
                      && echo "Kernel route deleted" \
                      || echo "Note: kernel route will clear on next network event"
                    ;;
                  host)
                    echo "Note: host routes will clear on next network event"
                    ;;
                esac
                ;;

              search)
                _pattern="''${2:-}"
                [[ -n "$_pattern" ]] || { echo "Error: search pattern required"; exit 1; }
                echo "Built-in:"
                { ${builtinEchos}; } | /usr/bin/grep -i "$_pattern" || echo "  (no matches)"
                echo ""
                echo "User-defined:"
                if [[ -f "$CONF" ]]; then
                  /usr/bin/grep -ivE "^[[:space:]]*#|^[[:space:]]*$" "$CONF" \
                    | /usr/bin/grep -i "$_pattern" | /usr/bin/sed 's/^/  /' \
                    || echo "  (no matches)"
                else
                  echo "  (no matches)"
                fi
                ;;

              apply)
                _apply
                ;;

              "" | --help | -h)
                _usage
                ;;

              *)
                echo "Unknown command: ''${1}"
                _usage
                ;;
            esac
    '';
  };

  plist = pkgs.writeText "${daemonLabel}.plist" ''
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>Label</key>
      <string>${daemonLabel}</string>
      <key>ProgramArguments</key>
      <array>
        <string>${bypassScript}/bin/zscaler-bypass</string>
      </array>
      <key>RunAtLoad</key>
      <true/>
      <key>WatchPaths</key>
      <array>
        <string>/private/var/run/resolv.conf</string>
      </array>
    </dict>
    </plist>
  '';
in {
  options.my.zscalerBypass = {
    enable = lib.mkEnableOption "Zscaler bypass routes for build registry traffic";

    hosts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "cache.nixos.org"
        "nix-community.cachix.org"
        "gfoster.cachix.org"
        # github.com / api.github.com / codeload.github.com covered by subnets (140.82.112.0/20)
        "objects.githubusercontent.com"
        "raw.githubusercontent.com"
        "registry.npmjs.org"
        "crates.io"
        "static.crates.io"
        "index.crates.io"
        "pypi.org"
        "files.pythonhosted.org"
      ];
      description = "Hostnames whose resolved IPs get direct /32 routes bypassing Zscaler";
    };

    subnets = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        # GitHub's IP range — github.com/api.github.com/codeload rotate within this /20
        "140.82.112.0/20"
      ];
      description = "CIDR subnets to bypass Zscaler for via direct network routes";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [bypassScript statusScript routesScript];

    home.activation.zscalerBypass = lib.hm.dag.entryAfter ["writeBoundary"] ''
      _label="${daemonLabel}"
      _dest="/Library/LaunchDaemons/$_label.plist"
      _src="${plist}"

      # Install/update only when the plist has changed
      if ! diff -q "$_src" "$_dest" &>/dev/null; then
        $DRY_RUN_CMD /usr/bin/sudo /bin/launchctl bootout "system/$_label" 2>/dev/null || true
        $DRY_RUN_CMD /usr/bin/sudo /bin/cp -f "$_src" "$_dest"
        $DRY_RUN_CMD /usr/bin/sudo /bin/chmod 644 "$_dest"
        $DRY_RUN_CMD /usr/bin/sudo /usr/sbin/chown root:wheel "$_dest"
        $DRY_RUN_CMD /usr/bin/sudo /bin/launchctl bootstrap system "$_dest"
      fi
    '';
  };
}
