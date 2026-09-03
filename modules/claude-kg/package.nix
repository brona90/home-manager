{
  lib,
  stdenvNoCC,
  python3,
  makeWrapper,
  coreutils,
  util-linux,
  curl,
  jq,
  bash,
}: let
  # Pure Nix Python env — replaces the previous `uv run` PEP-723 scripts, so the
  # MCP server and helpers are fully reproducible with no network dep fetch.
  pyEnv = python3.withPackages (ps: [ps.mcp ps.httpx]);
in
  stdenvNoCC.mkDerivation {
    pname = "claude-kg";
    version = "1.0.0";
    src = ./src;
    nativeBuildInputs = [makeWrapper];

    installPhase = ''
      runHook preInstall
      mkdir -p $out/lib/claude-kg $out/bin
      cp *.py $out/lib/claude-kg/

      # Python entrypoints share one lib dir so cross-imports (capture_local ->
      # kg_server) resolve via PYTHONPATH.
      pybin() {
        makeWrapper ${pyEnv}/bin/python3 "$out/bin/$1" \
          --add-flags "$out/lib/claude-kg/$2" \
          --set PYTHONPATH "$out/lib/claude-kg"
      }
      pybin kg-server   kg_server.py
      pybin kg          kg_cli.py
      pybin kg-capture  capture_local.py
      pybin kg-seed     seed.py
      pybin kg-reembed  reembed.py

      # Shell helpers: the SessionEnd hook and the snapshot job.
      install -m755 capture_memory.sh "$out/bin/kg-capture-hook"
      install -m755 snapshot.sh       "$out/bin/kg-snapshot"
      patchShebangs "$out/bin/kg-capture-hook" "$out/bin/kg-snapshot"

      wrapProgram "$out/bin/kg-capture-hook" \
        --prefix PATH : ${lib.makeBinPath [coreutils util-linux python3 bash]} \
        --set-default KG_CAPTURE_BIN "$out/bin/kg-capture"
      wrapProgram "$out/bin/kg-snapshot" \
        --prefix PATH : ${lib.makeBinPath [coreutils curl jq python3 bash]}
      runHook postInstall
    '';

    # Exposed for checks/mcp-servers.nix, which asserts that the env named here
    # is in this server's runtime closure. Read rather than re-derived, so that
    # adding a package to pyEnv above cannot leave the guard checking an env
    # this package no longer uses.
    passthru.mcpDepsFrom = pyEnv;

    meta = {
      description = "Local knowledge-graph MCP server (Qdrant + Ollama) and helpers for Claude Code";
      mainProgram = "kg";
    };
  }
