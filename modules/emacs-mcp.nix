{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.my.emacsMcp;

  # emacsclient must come from the same Emacs the daemon runs (the Doom
  # package) — pulling in vanilla pkgs.emacs would drag a second full
  # Emacs into the closure and risk version skew vs the daemon.  Fall
  # back to pkgs.emacs only when the emacs module is disabled.
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
  };
}
