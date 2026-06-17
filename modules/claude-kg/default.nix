{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.my.claudeKg;
  pkg = pkgs.callPackage ./package.nix {};
  dataDir = "${config.home.homeDirectory}/.local/share/claude-kg";
in {
  options.my.claudeKg = {
    enable = lib.mkEnableOption "claude-kg local knowledge-graph MCP server + Qdrant";
    image = lib.mkOption {
      type = lib.types.str;
      default = "qdrant/qdrant:latest";
    };
    dockerBin = lib.mkOption {
      type = lib.types.str;
      default = "/usr/bin/docker";
      description = "Path to the docker CLI (talks to the system daemon).";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [pkg]; # kg, kg-server, kg-capture, kg-seed, kg-reembed, kg-snapshot

    # Register the MCP server + the SessionEnd capture hook with Claude Code.
    my.claudeCode.mcpServers.claude-kg = {
      type = "stdio";
      command = "${pkg}/bin/kg-server";
    };
    my.claudeCode.sessionEndCommands = ["${pkg}/bin/kg-capture-hook"];

    # Runtime data lives outside the nix store (mutable Qdrant volumes + logs).
    home.activation.claudeKgDirs = lib.hm.dag.entryAfter ["writeBoundary"] ''
      ${pkgs.coreutils}/bin/mkdir -p "${dataDir}/qdrant" "${dataDir}/snapshots"
    '';

    systemd.user = {
      services.qdrant = {
        Unit = {
          Description = "Qdrant vector DB for claude-kg";
          After = ["network-online.target"];
        };
        Service = {
          Type = "exec";
          ExecStartPre = "-${cfg.dockerBin} rm -f claude-kg-qdrant";
          ExecStart = ''
            ${cfg.dockerBin} run --rm --name claude-kg-qdrant \
              -p 6333:6333 -p 6334:6334 \
              -v ${dataDir}/qdrant:/qdrant/storage \
              -v ${dataDir}/snapshots:/qdrant/snapshots \
              -e QDRANT__TELEMETRY_DISABLED=true \
              ${cfg.image}
          '';
          ExecStop = "${cfg.dockerBin} stop claude-kg-qdrant";
          Restart = "on-failure";
          RestartSec = 5;
        };
        Install.WantedBy = ["default.target"];
      };

      # Daily snapshot of all collections (replaces the old crontab entry).
      services.kg-snapshot = {
        Unit.Description = "claude-kg Qdrant snapshot + prune";
        Service = {
          Type = "oneshot";
          Environment = "CLAUDE_KG_DATA_DIR=${dataDir}";
          ExecStart = "${pkg}/bin/kg-snapshot";
        };
      };
      timers.kg-snapshot = {
        Unit.Description = "Daily claude-kg snapshot";
        Timer = {
          OnCalendar = "*-*-* 03:17:00";
          Persistent = true;
        };
        Install.WantedBy = ["timers.target"];
      };
    };
  };
}
