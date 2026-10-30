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

    # Every entrypoint must at least import under pyEnv, or this package does not
    # build. Without that, the failure surfaces only at run time. In 2026-10 a
    # flake.lock bump moved nixpkgs' python mcp from 1.x to 2.x, which removed
    # mcp.server.fastmcp. This package still built and home-manager switched,
    # and then kg-server, the `kg' CLI and every recall hook died on their first
    # import. checks/mcp-servers.nix now starts the server as well. This check is
    # the cheaper half: it fails `nix build' and `hms' themselves, and it also
    # covers the CLI and capture entrypoints, which no MCP handshake reaches.
    #
    # seed.py and smoke_test.py are left out on purpose: they WRITE to the
    # graph at import time (they are scripts with no main guard). Both import
    # nothing beyond kg_server, which is checked here.
    #
    # SSL_CERT_FILE is unset because stdenv points it at /no-cert-file.crt, and
    # kg_server builds its httpx.Client at import time. httpx loads that file
    # eagerly, so the import dies with FileNotFoundError, a failure no real
    # machine has. Unset, httpx falls back to certifi, which is what happens
    # outside the sandbox.
    doInstallCheck = true;
    installCheckPhase = ''
      runHook preInstallCheck
      HOME="$TMPDIR" env -u SSL_CERT_FILE -u NIX_SSL_CERT_FILE PYTHONPATH="$out/lib/claude-kg" ${pyEnv}/bin/python3 -c \
        'import asyncio, kg_server, kg_cli, capture_local, reembed; print("claude-kg: entrypoints import; MCP tools registered:", len(asyncio.run(kg_server.mcp.list_tools())))'
      runHook postInstallCheck
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
