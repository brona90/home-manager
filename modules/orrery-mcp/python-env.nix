# The Python interpreter orrery-mcp.py runs under, with mcp 2.x from the Nix
# store instead of from uv's cache.
#
# WHY THIS EXISTS. The launcher used to end in `uv run --script', which reads
# the PEP 723 header of orrery-mcp.py (`dependencies = ["mcp[cli]>=2,<3"]') and
# RESOLVES it over the network into ~/.cache/uv on first launch. Measured
# 2026-09-02: 25s of silence on a cold cache while uv installed 36 packages, and
# the MCP client reports only "failed to connect", so nothing in the symptom
# names the cause. On a freshly built machine that cache is empty and the server
# does not start at all.
#
# It is also not reproducible, which is the worse half. `>=2,<3' is a range, and
# uv re-resolves it whenever the cache does not already hold an answer: this
# machine's ~/.cache/uv/environments-v2 has TWO environments for this one script
# (orrery-mcp-aa50fc4d81941017 and orrery-mcp-cc303519938e63af), holding mcp
# 2.0.0 and 2.1.1, cryptography 50.0.0 and 50.0.1. Which code ran depended on
# when the cache happened to be warmed. Pinning here replaces that with one
# answer that a rebuild reproduces.
#
# WHY NOT JUST python3.withPackages [ps.mcp], AS claude-kg AND searxng DO.
# nixpkgs' python3Packages.mcp is 1.29.0 and the server imports
# `mcp.server.mcpserver`, a module that only exists in mcp 2.x -- that is the
# whole reason this one server was on uv while the other three were not. So the
# two packages 2.x needs and nixpkgs does not have are defined below, and
# everything else in mcp 2.1.1's dependency list is already packaged:
# anyio 4.14.2, httpx2 2.9.1, jsonschema 4.26.0, opentelemetry-api 1.43.0,
# pydantic 2.13.4, pyjwt 2.13.0, python-multipart 0.0.32, sse-starlette 3.2.0,
# starlette 1.3.1, typing-inspection 0.4.3, uvicorn 0.51.0, and for the [cli]
# extra python-dotenv 1.2.2 and typer 0.25.1. Nothing had to be vendored or
# waived.
#
# packageOverrides rather than an overlay on pkgs: the override has to be
# visible to `withPackages`, and it is scoped to this module so nothing else in
# the configuration is rebuilt against a different mcp than nixpkgs ships.
{
  lib,
  python3,
  fetchPypi,
}: let
  # mcp and mcp-types are cut from one repository and version-locked to each
  # other (`mcp-types=={{ version }}` in mcp's own metadata), so one version
  # string governs both and they can never drift apart here.
  mcpVersion = "2.1.1";

  # Both projects take their version from git tags via uv-dynamic-versioning.
  # An sdist has no .git, so the build would fail resolving it; this is the
  # upstream-supported escape hatch, and it also fills the `{{ version }}`
  # template in mcp's dependency metadata hook.
  bypassVersion = ''
    export UV_DYNAMIC_VERSIONING_BYPASS=${mcpVersion}
  '';

  # `_prev' and not `prev': nothing below is built out of the package it
  # replaces. mcp 2.x is a different dependency set from nixpkgs' 1.29 (httpx
  # became httpx2, httpx-sse and pydantic-settings are gone, mcp-types and
  # opentelemetry-api are new), so an override that started from prev.mcp would
  # inherit 1.29-era inputs and test exclusions and have to unpick them all.
  overrides = final: _prev: {
    # Not in nixpkgs at all. Pure wire types: pydantic models and nothing else.
    mcp-types = final.buildPythonPackage {
      pname = "mcp-types";
      version = mcpVersion;
      pyproject = true;

      src = fetchPypi {
        pname = "mcp_types";
        version = mcpVersion;
        hash = "sha256-d9y+SPunPMpxpnPyZGpfA3oBe3oKB6yJzsERMCiJDto=";
      };

      preBuild = bypassVersion;

      build-system = [final.hatchling final.uv-dynamic-versioning];
      dependencies = [final.pydantic final.typing-extensions];
      pythonImportsCheck = ["mcp_types"];

      meta = {
        description = "Model Context Protocol wire types";
        homepage = "https://github.com/modelcontextprotocol/python-sdk";
        license = lib.licenses.mit;
      };
    };

    # nixpkgs has 1.29.0; this is 2.x. Written out rather than overriding the
    # nixpkgs derivation because 2.x is a different package underneath -- httpx
    # became httpx2, httpx-sse and pydantic-settings are gone, and mcp-types,
    # opentelemetry-api and typing-inspection are new -- so an overrideAttrs
    # would have to replace every field that matters anyway, while silently
    # keeping nixpkgs' 1.29-era test exclusions.
    mcp = final.buildPythonPackage {
      pname = "mcp";
      version = mcpVersion;
      pyproject = true;

      src = fetchPypi {
        pname = "mcp";
        version = mcpVersion;
        hash = "sha256-ULe6HrvhFwCOp73SiCNAQ+acILQD1oUdGWYebUMade8=";
      };

      preBuild = bypassVersion;

      build-system = [final.hatchling final.uv-dynamic-versioning];

      dependencies = [
        final.anyio
        final.httpx2
        final.jsonschema
        final.mcp-types
        final.opentelemetry-api
        final.pydantic
        final.pyjwt
        # pyjwt[crypto]: the extra is just this, and nixpkgs' pyjwt does not
        # pull it in by default.
        final.cryptography
        final.python-multipart
        final.sse-starlette
        final.starlette
        final.typing-extensions
        final.typing-inspection
        final.uvicorn
      ];

      optional-dependencies = {
        cli = [final.python-dotenv final.typer];
        rich = [final.rich];
      };

      # The import that made this whole file necessary: `mcp.server.mcpserver`
      # is the 2.x-only module orrery-mcp.py needs, so checking it here means a
      # version bump that removes or renames it fails the build rather than the
      # server.
      pythonImportsCheck = ["mcp" "mcp.server.mcpserver"];

      # The sdist ships the test suite, but running it here would pull in
      # pytest-examples, inline-snapshot, dirty-equals and trio, and the
      # network-touching cases are exactly the ones nixpkgs already disables for
      # 1.29. pythonImportsCheck above covers what this configuration uses.
      doCheck = false;

      meta = {
        description = "Official Python SDK for Model Context Protocol servers and clients";
        homepage = "https://github.com/modelcontextprotocol/python-sdk";
        license = lib.licenses.mit;
      };
    };
  };

  python = python3.override {
    self = python;
    packageOverrides = overrides;
  };
in
  python.withPackages (ps: [ps.mcp ps.mcp-types] ++ ps.mcp.optional-dependencies.cli)
