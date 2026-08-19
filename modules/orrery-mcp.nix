# Orrery MCP server -- the conversational surface of the Orrery dashboard.
#
# Unlike claude-kg/searxng/emacs-mcp, this module deliberately does NOT vendor
# the server source into this repo. Orrery's MCP server shells out to Orrery's
# own bin/orrery for every write and parses Orrery's own dist/ for every read,
# precisely so that filing from a conversation and filing from the terminal
# cannot disagree. A copy of the .py here would be a second implementation that
# drifts from the CLI it is required to agree with, so this module ships a
# launcher pointed at the working copy instead.
#
# It also cannot use the pure-Nix python env the other MCP modules use:
# nixpkgs' python3Packages.mcp is 1.29 and the server imports
# `mcp.server.mcpserver`, which only exists in mcp 2.x. The script declares its
# dependencies inline (PEP 723) and uv resolves them on first launch -- the one
# MCP server on this machine whose Python deps are not fetched by Nix. The
# interpreter is still pinned to the Nix python below, so uv never downloads
# a CPython of its own.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.my.orreryMcp;

  # Same reasoning as emacs-mcp.nix: reuse the Doom Emacs package when the
  # emacs module is on rather than pulling pkgs.emacs in as well, which would
  # put a second full Emacs in the closure. Orrery's build and CLI are
  # `emacs -Q --batch`, so any Emacs works -- this is purely about closure size.
  emacsPackage =
    if config.my.emacs.enable
    then config.my.emacs.package
    else pkgs.emacs;

  launcher = pkgs.writeShellApplication {
    name = "orrery-mcp";
    # Claude Code runs natively on Windows here and reaches this through
    # `wsl.exe`, which starts it with no login shell and therefore none of the
    # user's PATH. Every command the server shells out to has to be named here:
    # `make build` on the read path, and bin/orrery -> emacs + git on the write
    # path. runtimeInputs is prefixed onto PATH rather than replacing it, so an
    # inherited PATH (when launched from inside WSL) still passes through.
    runtimeInputs = [
      pkgs.uv
      pkgs.gnumake
      pkgs.git
      pkgs.coreutils
      emacsPackage
    ];
    text = ''
      root="''${ORRERY_ROOT:-${cfg.root}}"
      script="$root/mcp-server/orrery-mcp.py"
      if [ ! -f "$script" ]; then
        echo "orrery-mcp: no server at $script -- set ORRERY_ROOT to the Orrery working copy" >&2
        exit 1
      fi
      # Exported, not just resolved: the server re-reads ORRERY_ROOT itself and
      # would otherwise fall back to the script's own parent directory.
      export ORRERY_ROOT="$root"
      # The server file is mode 0644 in the working copy, so its `uv run
      # --script` shebang cannot fire; invoking uv explicitly is what makes the
      # launcher independent of that bit.
      exec uv run --python ${pkgs.python3}/bin/python3 --script "$script"
    '';
  };
in {
  options.my.orreryMcp = {
    enable = lib.mkEnableOption "MCP server exposing the Orrery dashboard to Claude Code";

    root = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/orrery";
      description = ''
        Path to the Orrery working copy. The launcher runs the MCP server from
        <root>/mcp-server and the server shells out to <root>/bin/orrery.
        ORRERY_ROOT in the environment overrides this at launch.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # On PATH as well as registered below. Claude Code running natively on
    # Windows cannot use a /nix/store path that changes on every rebuild, so
    # its hand-registered entry points at ~/.nix-profile/bin/orrery-mcp --
    # the same stable profile path claude-kg is registered under on that side.
    home.packages = [launcher];

    # Register as a user-scope MCP server with Claude Code (merged into ~/.claude.json).
    my.claudeCode.mcpServers.orrery = {
      type = "stdio";
      command = "${launcher}/bin/orrery-mcp";
    };
  };
}
