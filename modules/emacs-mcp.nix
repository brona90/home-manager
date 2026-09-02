{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.my.emacsMcp;

  # emacsclient must come from the same Emacs the daemon on the DEFAULT
  # socket runs.  Pulling in a bare pkgs.emacs would drag a second full Emacs
  # into the closure and risk version skew vs the daemon.  Fall back to
  # pkgs.emacs only when the emacs module is disabled.
  #
  # This used to read `my.emacs.primaryPackage`, which existed to resolve a
  # two-flavour `my.emacs.flavor` enum; there is one Emacs now and `package`
  # IS the one on the default socket.  If a second Emacs is ever added back,
  # this is one of the three call sites that has to follow the primary one --
  # the others are modules/emacs-doctor/default.nix and modules/orrery-mcp/default.nix
  # (which deliberately does not).
  emacsPackage =
    if config.my.emacs.enable
    then config.my.emacs.package
    else pkgs.emacs;

  # Wrap the Python MCP server as a derivation on $PATH.
  # No external Python deps — stdlib only.
  mcpServer = pkgs.stdenv.mkDerivation {
    pname = "emacs-mcp-server";
    version = "1.0.0";
    src = ./emacs-mcp-server.py;
    dontUnpack = true;
    installPhase = ''
      mkdir -p $out/bin
      cp $src $out/bin/emacs-mcp-server
      chmod +x $out/bin/emacs-mcp-server
      patchShebangs $out/bin/emacs-mcp-server
    '';
    buildInputs = [pkgs.python3];
    nativeBuildInputs = [pkgs.makeWrapper];
    postFixup = ''
      wrapProgram $out/bin/emacs-mcp-server \
        --prefix PATH : ${lib.makeBinPath [pkgs.python3 emacsPackage]}
    '';
    meta.description = "MCP server exposing Emacs functions to Claude Code via emacsclient";
  };
in {
  options.my.emacsMcp = {
    enable = lib.mkEnableOption "MCP server for Claude Code ↔ Emacs integration";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [mcpServer];

    # Register as a user-scope MCP server with Claude Code (merged into ~/.claude.json).
    my.claudeCode.mcpServers.emacs = {
      type = "stdio";
      command = "${mcpServer}/bin/emacs-mcp-server";
    };
  };
}
