# @porkbunllc/mcp-server, built from a pinned tarball with its node_modules
# fetched by Nix.
#
# WHY THIS EXISTS. modules/claude-code.nix used to launch this server with
# `npx -y @porkbunllc/mcp-server'. That resolves `latest' from the npm registry
# on EVERY launch, unpinned and unhashed, and the wrapper has already read
# ~/.config/sops-nix/secrets/porkbun_{api,secret}_key and exported them as
# PORKBUN_API_KEY / PORKBUN_SECRET_API_KEY by the time it execs. Whoever can
# publish a version of that package -- the maintainer, anyone who takes over the
# account, anyone who compromises the registry entry -- gets arbitrary code
# execution on this machine holding live Porkbun API credentials. Those
# credentials edit DNS for every domain in that account: an A record can be
# repointed at an attacker's host, an MX record can take delivery of the mail,
# and an ACME DNS-01 TXT record issues a publicly trusted certificate for the
# name. There is no review step between `npm publish' and that, and no record
# afterwards of which bytes ran.
#
# WHY NOT THE claude-powerline SHAPE. modules/claude-code.nix pins
# @owloops/claude-powerline with a bare fetchzip and runs it with node, and that
# is the right shape there because claude-powerline ships fully bundled -- its
# dist has no runtime imports left to resolve. This package does not:
# dist/index.js imports @modelcontextprotocol/sdk and zod, so a fetchzip alone
# would leave a tree that still needs a node_modules from somewhere. Hence
# buildNpmPackage, which is the same idea one level down: package-lock.json
# pins every transitive version and integrity hash, and npmDepsHash pins the
# whole fetched set.
#
# THE LOCKFILE IS OURS, NOT UPSTREAM'S. The published tarball ships no
# package-lock.json (its `files' list is dist/README/LICENSE), so the
# package-lock.json beside this file was generated once from the tarball's own
# package.json with `npm install --package-lock-only' and committed. It is what
# turns two caret ranges into exact versions; regenerate it deliberately when
# bumping `version', never as a side effect. devDependencies (typescript,
# @types/node) are stripped below because dist/ ships prebuilt -- there is
# nothing here to compile -- and the lockfile was generated from the same
# stripped package.json, so `npm ci' sees a consistent pair.
{
  lib,
  buildNpmPackage,
  fetchzip,
  jq,
  nodejs,
}: let
  version = "0.22.1";
in
  buildNpmPackage {
    pname = "porkbun-mcp-server";
    inherit version;

    # fetchzip, not fetchurl: buildNpmPackage wants an unpacked source tree, and
    # stripRoot drops the npm tarball's `package/' wrapper directory.
    src = fetchzip {
      url = "https://registry.npmjs.org/@porkbunllc/mcp-server/-/mcp-server-${version}.tgz";
      hash = "sha256-SHcNROQvqe5/gb0okEjw9kW7zBe6V4wDHNDSZ4mKo60=";
    };

    inherit nodejs;

    # ${jq}/bin/jq by store path rather than nativeBuildInputs: postPatch runs
    # in the npm-deps fixed-output derivation too, and that one is built with a
    # minimal stdenv that does not inherit this derivation's build inputs. With
    # jq only on nativeBuildInputs the FOD dies with `jq: command not found'.
    postPatch = ''
      ${jq}/bin/jq 'del(.devDependencies)' package.json > package.json.stripped
      mv package.json.stripped package.json
      cp ${./package-lock.json} package-lock.json
    '';

    npmDepsHash = "sha256-LgiV/vN5DlUvP1RcLocFiTMD9H0GeYU/M4adAE73kcs=";

    # dist/ is published prebuilt and there is no `build' script worth running
    # (it is `tsc', whose compiler was just stripped out with devDependencies).
    dontNpmBuild = true;

    meta = {
      description = "Porkbun MCP server: the Porkbun v3 DNS/domain API as MCP tools";
      homepage = "https://porkbun.com/mcp";
      license = lib.licenses.mit;
      mainProgram = "porkbun-mcp";
    };
  }
