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
    # Pinned by digest for the same reason as my.claudeKg.image: `:latest`
    # means the running version is whatever was last pulled, recorded nowhere.
    # This is the image that was running when the pin was taken (2026-11-23,
    # `docker inspect searxng`). checks/service-binds.nix enforces the pin.
    image = lib.mkOption {
      type = lib.types.str;
      default = "searxng/searxng@sha256:3cb8eba87bb347613fab9dfe87d448c21300b8f0648295c93b85f4246e93ae73";
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
      # The only server here whose env has to cross with it, and therefore the
      # one that made windowsMcpEnvArgs necessary: SEARXNG_URL is read by the
      # server process, which runs in WSL, so it cannot be set on the wsl.exe
      # side of the boundary. localhost is WSL's localhost -- the container this
      # module runs is not reachable from Windows by that name -- so crossing is
      # what makes a Windows session's web search hit this instance instead of
      # having no search tool at all. Not a secret: a port number.
      windowsProfileBin = "searxng-mcp";
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
        # 0600: the file carries secret_key, which signs SearXNG's session
        # cookies. A plain `> settings.yml` created it 0644 under the default
        # umask, and on an existing file `>` keeps whatever mode it already
        # had -- so write a fresh file under umask 077 and rename it over the
        # old one. The container chowns the directory to its own uid on start
        # (with CAP_CHOWN, kept below), and 0600 for that owner is all it needs.
        (
          umask 077
          ${pkgs.gnused}/bin/sed "s|__SECRET__|$secret|" ${./settings.yml} > "$cfgdir/settings.yml.tmp"
        )
        ${pkgs.coreutils}/bin/chmod 0600 "$cfgdir/settings.yml.tmp"
        ${pkgs.coreutils}/bin/mv -f "$cfgdir/settings.yml.tmp" "$cfgdir/settings.yml"
      else
        echo "searxng: ${cfgDir} is container-owned; leaving settings.yml as-is"
      fi
    '';

    # systemd.user is Linux-only — home-manager errors if set on a non-Linux
    # host. Gate it so the module's cross-platform parts (MCP registration,
    # settings render) still work if it's ever enabled on a Mac.
    systemd.user.services.searxng = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
      Unit = {
        Description = "SearXNG private web search (claude-kg companion)";
        After = ["network-online.target"];
      };
      Service = {
        Type = "exec";
        ExecStartPre = "-${cfg.dockerBin} rm -f searxng";
        # Loopback only -- same reasoning as the Qdrant unit in
        # modules/claude-kg: a bare `-p 8888:8080` publishes on 0.0.0.0 and
        # [::], which under WSL mirrored networking is the LAN as well, and
        # SearXNG has no auth. Its clients are the MCP server (in WSL, at
        # localhost, which resolves to 127.0.0.1 here) and cloudflared (in
        # WSL, at 127.0.0.1:8888, behind Cloudflare Access).
        # checks/service-binds.nix enforces this.
        ExecStart = ''
          ${cfg.dockerBin} run --rm --name searxng \
            -p 127.0.0.1:${toString cfg.port}:8080 \
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
