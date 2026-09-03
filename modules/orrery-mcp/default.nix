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
# Its Python deps DO come from Nix, like every other MCP server here. That was
# not always true: this module used to exec `uv run --script', which resolved
# the script's PEP 723 header over the network into ~/.cache/uv on first launch,
# because nixpkgs' python3Packages.mcp is 1.29 and the server imports
# `mcp.server.mcpserver`, a 2.x-only module. ./python-env.nix now packages mcp
# 2.1.1 (and its unpackaged companion mcp-types) from hash-pinned sdists, so the
# interpreter below arrives with the imports already satisfied and the launcher
# never reaches the network. That file has the full argument; the short version
# is that the uv path was not merely slow but non-reproducible -- `>=2,<3' got
# re-resolved per cache miss, and this machine ended up holding two different
# answers for the same script.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.my.orreryMcp;

  # Nothing here talks to a daemon: orrery's build and CLI are `emacs -Q
  # --batch`, so ANY Emacs works and reading `my.emacs.package` is purely about
  # closure size -- reuse an Emacs that is already in the closure instead of
  # adding a second one.
  #
  # This used to be flagged as a deliberate exception, because `package` was
  # always Doom while emacs-mcp.nix and emacs-doctor/default.nix had to follow
  # `primaryPackage`. There is one Emacs now, so all three read the same
  # option and the exception is only worth knowing if a second one comes back:
  # THIS is the site that would stay on `package` while the other two follow
  # the primary.
  emacsPackage =
    if config.my.emacs.enable
    then config.my.emacs.package
    else pkgs.emacs;

  # mcp 2.x from the Nix store, replacing the uv resolve. See ./python-env.nix.
  pyEnv = pkgs.callPackage ./python-env.nix {};

  launcher = pkgs.writeShellApplication {
    name = "orrery-mcp";
    # Claude Code runs natively on Windows here and reaches this through
    # `wsl.exe`, which starts it with no login shell and therefore none of the
    # user's PATH. Every command the server shells out to has to be named here:
    # `make build` on the read path, and bin/orrery -> emacs + git on the write
    # path. runtimeInputs is prefixed onto PATH rather than replacing it, so an
    # inherited PATH (when launched from inside WSL) still passes through.
    #
    # pkgs.uv is deliberately NOT here any more. It was only ever on this list
    # to resolve the server's Python deps at launch, and leaving it would leave
    # the fallback that made that possible.
    runtimeInputs = [
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
      # The interpreter is invoked directly, so the server file's mode does not
      # matter (it is 0644 in the working copy) and its `#!/usr/bin/env -S uv
      # run --script` shebang is inert -- the same arrangement claude-kg uses
      # for the uv shebangs still sitting in its sources. The PEP 723
      # `dependencies` header stays in the file for anyone running it outside
      # Nix; nothing here reads it.
      exec ${pyEnv}/bin/python3 "$script"
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
