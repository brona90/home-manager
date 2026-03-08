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

      # Dynamically find the physical gateway (first default route via en*)
      GATEWAY=$(/usr/sbin/netstat -rn \
        | /usr/bin/awk '/^default[[:space:]].*en[0-9]/{print $2; exit}')
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
          /sbin/route -q add -host "$ip" "$GATEWAY" 2>/dev/null \
            && echo "  $host -> $ip"
        done <<< "$ips"
      }

      ${lib.concatMapStringsSep "\n      " (h: "bypass ${lib.escapeShellArg h}") cfg.hosts}
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
      <key>StandardOutPath</key>
      <string>/var/log/zscaler-bypass.log</string>
      <key>StandardErrorPath</key>
      <string>/var/log/zscaler-bypass.log</string>
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
        "github.com"
        "api.github.com"
        "objects.githubusercontent.com"
        "raw.githubusercontent.com"
        "codeload.github.com"
        "registry.npmjs.org"
        "crates.io"
        "static.crates.io"
        "index.crates.io"
        "pypi.org"
        "files.pythonhosted.org"
      ];
      description = "Hostnames whose resolved IPs get direct /32 routes bypassing Zscaler";
    };
  };

  config = lib.mkIf cfg.enable {
    # Make the script available in $PATH for manual invocation
    home.packages = [bypassScript];

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
