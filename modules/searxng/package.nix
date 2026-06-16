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

    meta = {
      description = "MCP server exposing local SearXNG web search to Claude Code";
      mainProgram = "searxng-mcp";
    };
  }
