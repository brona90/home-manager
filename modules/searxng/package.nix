{
  python3,
  stdenvNoCC,
  makeWrapper,
}: let
  pyEnv = python3.withPackages (ps: [ps.mcp ps.httpx]);
in
  stdenvNoCC.mkDerivation {
    pname = "searxng-mcp";
    version = "1.0.0";
    src = ./src;
    nativeBuildInputs = [makeWrapper];

    installPhase = ''
      runHook preInstall
      mkdir -p $out/lib/searxng $out/bin
      cp search_server.py $out/lib/searxng/
      makeWrapper ${pyEnv}/bin/python3 "$out/bin/searxng-mcp" \
        --add-flags "$out/lib/searxng/search_server.py" \
        --set PYTHONPATH "$out/lib/searxng"
      runHook postInstall
    '';

    # Exposed for checks/mcp-servers.nix, which asserts that the env named here
    # is in this server's runtime closure. Read rather than re-derived: if the
    # guard rebuilt `python3.withPackages [mcp httpx]' from its own copy of that
    # expression, adding a package to pyEnv above would leave the guard checking
    # an env this package no longer uses, and it would fail for a reason that
    # has nothing to do with the property it exists to protect.
    passthru.mcpDepsFrom = pyEnv;

    meta = {
      description = "MCP server exposing local SearXNG web search to Claude Code";
      mainProgram = "searxng-mcp";
    };
  }
