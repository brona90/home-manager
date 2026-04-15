{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.my.emacsMcp;

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
        --prefix PATH : ${lib.makeBinPath [pkgs.python3 pkgs.emacs]}
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
