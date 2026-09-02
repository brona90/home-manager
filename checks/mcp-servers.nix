# Guard: every MCP server this flake registers must get its dependencies from Nix.
#
# WHY THIS GUARD EXISTS. modules/orrery-mcp produced a store path, so it LOOKED
# declared. It was not: the launcher ended in `uv run --script', and uv resolved
# the script's PEP 723 dependencies over the network on first launch into
# ~/.cache/uv, a directory no flake owns. Measured 2026-09-02: on a cold cache
# the server answered nothing for 25s while uv installed 36 packages; warm, it
# answered in 6.8s. The MCP client reports only "failed to connect", so the
# symptom named nothing useful. On a fresh WSL instance that cache is empty, so
# the tool did not start at all.
#
# The hazard was already written down. The head comment of modules/orrery-mcp
# stated it exactly -- "the one MCP server on this machine whose Python deps are
# not fetched by Nix" -- and that comment had been true and inert for four
# months. Foresight was not the scarce ingredient here; a refusal was. A comment
# describes, a guard refuses.
#
# WHY THE GENERAL PROPERTY AND NOT `orrery-mcp' BY NAME. The choice was open,
# and the evidence closed it. Writing this guard turned up a SECOND server with
# the same defect that nobody had written a comment about: `porkbun' exec'd
# `npx -y @porkbunllc/mcp-server', fetching an UNPINNED npm package from the
# network on every launch -- no version pin, no hash, arbitrary published code
# exec'd with the Porkbun API secrets already exported into its environment. A
# guard that named orrery-mcp would have passed straight over it. The same
# module pins @owloops/claude-powerline with fetchzip and a sha256 precisely
# because per-call npx was too slow, so the technique was already in the file;
# it had just not been applied here.
#
# ALLOWLIST, NOT DENYLIST. The list below names the servers whose dependencies
# are known to come from Nix, and every declared server not on it is REFUSED.
# The alternative -- a list of banned fetchers (uv, npx, pip, pipx, ...) -- is
# open-ended, and fails silently for the sixth server that reaches for a
# seventh tool. Refusing by default means a server added later is caught on the
# day it is added, by an author who still has the context to say where its deps
# come from, rather than by whoever is next to boot a clean machine. Adding an
# entry here is the deliberate act; forgetting to is not a way through.
#
# THIS GUARD LANDED RED AND IS NOW GREEN. When it was written, two of the five
# declared servers failed it and neither was fixed in that commit; the entry it
# carried for each of them said what a fix would take. Both fixes have since
# landed -- modules/orrery-mcp/python-env.nix packages mcp 2.1.1 and mcp-types
# from hash-pinned sdists, and modules/porkbun-mcp/package.nix builds
# @porkbunllc/mcp-server 0.22.1 from a pinned tarball with a committed
# package-lock.json -- so the "known offender" table that held their reasons is
# gone with them. Do not reintroduce it as a place to park a new offender: an
# entry that explains why a server is exempt is an exemption, whatever it is
# called. The failure text below tells an author what to do instead.
#
# Inputs, passed by checks/default.nix. Nothing in this file reads flake.nix's
# scope; if it is not in this list, it is not available here.
#   lib        -- nixpkgs.lib.
#   pkgs       -- `pkgsFor system' for the system being checked.
#   mcpServers -- the EVALUATED my.claudeCode.mcpServers attrset from the home
#                 configuration: every server activation actually merges into
#                 ~/.claude.json, whichever module contributed it. Read from the
#                 built value rather than by grepping modules/, so a server
#                 contributed by a module nobody thought to grep is still
#                 covered -- which is how porkbun turned up.
{
  lib,
  pkgs,
  mcpServers,
}: let
  # THE ALLOWLIST. Server name -> how its dependencies reach the store. The
  # string is not decoration: it is the claim being made, and it has to name a
  # mechanism a reader can go and check.
  nixFetchedDeps = {
    claude-kg = "modules/claude-kg/package.nix: python3.withPackages [mcp httpx], wrapped so that interpreter is exec'd directly (the `uv run' shebangs still in src/*.py are inert -- makeWrapper never fires them)";
    searxng = "modules/searxng/package.nix: python3.withPackages [mcp httpx], wrapped the same way";
    emacs = "modules/emacs-mcp.nix: Python standard library only, no third-party imports; patchShebangs pins it to pkgs.python3";
    orrery = "modules/orrery-mcp/python-env.nix: python3.withPackages over a packageOverrides scope carrying mcp 2.1.1 and mcp-types 2.1.1, both fetchPypi sdists with a hash (nixpkgs' mcp is 1.29 and the server needs the 2.x-only mcp.server.mcpserver). The launcher execs that interpreter directly, so the PEP 723 header and the uv shebang in orrery-mcp.py are inert -- pkgs.uv is no longer even on its PATH";
    porkbun = "modules/porkbun-mcp/package.nix: buildNpmPackage over a pinned registry tarball (fetchzip + hash) with a committed package-lock.json and an npmDepsHash, so @modelcontextprotocol/sdk and zod come from the store; modules/claude-code.nix execs the resulting store path instead of `npx -y'";
  };

  declared = builtins.attrNames mcpServers;
  allowed = builtins.attrNames nixFetchedDeps;

  # Declared but not allowlisted. This is the refusal.
  refused = lib.subtractLists allowed declared;

  # An allowlist entry for a server no module declares any more. Left unchecked,
  # the list rots into a set of claims about things that do not exist, and the
  # next author reads it as evidence.
  stale = lib.subtractLists declared allowed;

  # Independent of the allowlist, and automatic: a command that is not a store
  # path cannot have been built by this flake at all, whatever anyone claims
  # about it. Catches a server pointed at ~/bin or at a bare name on PATH.
  notStorePath =
    builtins.filter
    (name: !(lib.hasPrefix builtins.storeDir (mcpServers.${name}.command or "")))
    declared;

  # One message for every refusal, because there is now exactly one thing to do
  # about one: name the mechanism, or build one. modules/porkbun-mcp/package.nix
  # (npm, buildNpmPackage) and modules/orrery-mcp/python-env.nix (Python,
  # withPackages over pinned sdists) are the two worked examples in this repo of
  # doing the second, and both started as entries in a table of known offenders.
  reason = "not reviewed. Say where its dependencies come from and add it to nixFetchedDeps in this file, or make them come from Nix -- see modules/porkbun-mcp/package.nix for the npm shape and modules/orrery-mcp/python-env.nix for the Python one";

  lines =
    (map (name: "GUARD: MCP server '${name}' does not have its dependencies fetched by Nix -- ${reason}.") refused)
    ++ (map (name: "GUARD: MCP server '${name}' command is not a ${builtins.storeDir} path: ${mcpServers.${name}.command or "<none>"}") notStorePath)
    ++ (map (name: "GUARD: nixFetchedDeps lists '${name}', which no module declares any more -- drop the entry.") stale);

  report = lib.concatStringsSep "\n" lines;
in {
  mcp-servers-deps-from-nix =
    pkgs.runCommand "mcp-servers-deps-from-nix" {
      inherit report;
      passAsFile = ["report"];
      # Recorded in the derivation so `nix derivation show' says which servers
      # were examined even on the runs where the guard passes and prints nothing.
      checkedServers = lib.concatStringsSep " " declared;
    } ''
      if [ -s "$reportPath" ]; then
        cat "$reportPath"
        echo
        echo "An MCP server whose deps are fetched at runtime does not start on a machine"
        echo "with a cold cache -- which is every freshly built machine. See the header of"
        echo "checks/mcp-servers.nix for why this is refused rather than commented."
        exit 1
      fi
      touch $out
    '';
}
