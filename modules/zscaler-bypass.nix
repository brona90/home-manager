# Installs a root LaunchDaemon that adds per-host /32 bypass routes via the
# physical interface (en0) for build registry traffic, overriding the broad
# CIDR routes that Zscaler injects via its utun tunnel.  Re-runs automatically
# whenever /private/var/run/resolv.conf changes (i.e. on any network event).
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.my.zscalerBypass;

  bypassScript = pkgs.writeShellApplication {
    name = "zscaler-bypass";
    text = ''
      # Only act when Zscaler tunnel process is running
      if ! /usr/bin/pgrep -x ZscalerTunnel > /dev/null 2>&1; then
        echo "Zscaler not active, nothing to do"
        exit 0
      fi

      # Dynamically find the physical gateway (first default route via en*).
      # || true: awk exits early, causing netstat SIGPIPE; pipefail would abort without it.
      GATEWAY=$(/usr/sbin/netstat -rn \
        | /usr/bin/awk '/^default[[:space:]].*en[0-9]/{print $2; exit}') || true
      if [[ -z "$GATEWAY" ]]; then
        echo "ERROR: no physical gateway found on en*" >&2
        exit 1
      fi

      echo "Zscaler active — bypassing via $GATEWAY"

      bypass() {
        local host=$1
        local ips
        ips=$(/usr/bin/dig +short A "$host" 2>/dev/null) || return 0
        while IFS= read -r ip; do
          [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue
          # Use if/then — avoids set -e triggering on && when route already exists
          if /sbin/route -q add -host "$ip" "$GATEWAY" 2>/dev/null; then
            echo "  $host -> $ip (added)"
          else
            echo "  $host -> $ip (already present)"
          fi
        done <<< "$ips"
      }

      ${lib.concatMapStringsSep "\n      " (h: "bypass ${lib.escapeShellArg h}") cfg.hosts}

      # Subnet routes — stable CIDR ranges that don't need DNS resolution
      bypass_net() {
        local net=$1
        if /sbin/route -q add -net "$net" "$GATEWAY" 2>/dev/null; then
          echo "  $net (added)"
        else
          echo "  $net (already present)"
        fi
      }

      ${lib.concatMapStringsSep "\n      " (n: "bypass_net ${lib.escapeShellArg n}") cfg.subnets}
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
      if [[ -f /Library/LaunchDaemons/com.home-manager.zscaler-bypass.plist ]]; then
        echo "Plist:  installed"
      else
        echo "Plist:  NOT installed — run hms"
      fi
      echo ""
      echo "=== Host routing ==="
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

      ${lib.concatMapStringsSep "\n      " (h: "check_host ${lib.escapeShellArg h}") cfg.hosts}

      echo ""
      echo "=== Subnet routes ==="
      check_net() {
        local net=$1 iface status
        # Pick a representative IP from the subnet (first host address)
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

      ${lib.concatMapStringsSep "\n      " (n: "check_net ${lib.escapeShellArg n}") cfg.subnets}
    '';
  };

  daemonLabel = "com.home-manager.zscaler-bypass";

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
    home.packages = [bypassScript statusScript];

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
