{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.my.searxng;
  pkg = pkgs.callPackage ./package.nix {};
  cfgDir = "${config.home.homeDirectory}/.config/searxng";
in {
  options.my.searxng = {
    enable = lib.mkEnableOption "local SearXNG private web search + MCP server";
    port = lib.mkOption {
      type = lib.types.port;
      default = 8888;
      description = "Host port the SearXNG container listens on.";
    };
    image = lib.mkOption {
      type = lib.types.str;
      default = "searxng/searxng:latest";
    };
    dockerBin = lib.mkOption {
      type = lib.types.str;
      default = "/usr/bin/docker";
      description = "Path to the docker CLI (talks to the system daemon).";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [pkg];

    # Register the MCP server with Claude Code (merged into ~/.claude.json).
    my.claudeCode.mcpServers.searxng = {
      type = "stdio";
      command = "${pkg}/bin/searxng-mcp";
      env.SEARXNG_URL = "http://localhost:${toString cfg.port}";
    };

    # Render settings.yml with a generated secret_key (kept out of the repo). The
    # SearXNG container chowns this dir to its own uid on first start, so only render
    # while we still own it — the generated secret then persists in the file. (The
    # container rejects a read-only config mount, hence this approach.)
    home.activation.searxngSettings = lib.hm.dag.entryAfter ["writeBoundary"] ''
      cfgdir="${cfgDir}"
      ${pkgs.coreutils}/bin/mkdir -p "$cfgdir" 2>/dev/null || true
      if [ -w "$cfgdir" ]; then
        secret=$(${pkgs.gnugrep}/bin/grep -oP 'secret_key:\s*"\K[^"]+' "$cfgdir/settings.yml" 2>/dev/null || true)
        if [ -z "$secret" ] || [ "$secret" = "__SECRET__" ]; then
          secret=$(${pkgs.openssl}/bin/openssl rand -hex 32)
        fi
        ${pkgs.gnused}/bin/sed "s|__SECRET__|$secret|" ${./settings.yml} > "$cfgdir/settings.yml"
      else
        echo "searxng: ${cfgDir} is container-owned; leaving settings.yml as-is"
      fi
    '';

    systemd.user.services.searxng = {
      Unit = {
        Description = "SearXNG private web search (claude-kg companion)";
        After = ["network-online.target"];
      };
      Service = {
        Type = "exec";
        ExecStartPre = "-${cfg.dockerBin} rm -f searxng";
        ExecStart = ''
          ${cfg.dockerBin} run --rm --name searxng \
            -p ${toString cfg.port}:8080 \
            -v ${cfgDir}:/etc/searxng \
            -e SEARXNG_BASE_URL=http://localhost:${toString cfg.port}/ \
            --cap-drop ALL --cap-add CHOWN --cap-add SETGID --cap-add SETUID \
            ${cfg.image}
        '';
        ExecStop = "${cfg.dockerBin} stop searxng";
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install.WantedBy = ["default.target"];
    };
  };
}
