# Guard: every MCP server this flake registers must get its dependencies from Nix.
#
# WHY THIS GUARD EXISTS. modules/orrery-mcp.nix produces a store path, so it
# LOOKS declared. It is not: the launcher ends in `uv run --script', and uv
# resolves the script's PEP 723 dependencies over the network on first launch
# into ~/.cache/uv, a directory no flake owns. Measured 2026-09-02: on a cold
# cache the server answered nothing for 25s while uv installed 36 packages;
# warm, it answers in 6.8s. The MCP client reports only "failed to connect", so
# the symptom names nothing useful. On a fresh WSL instance that cache is empty,
# so the tool does not start at all.
#
# The hazard was already written down. Lines 11-17 of modules/orrery-mcp.nix
# state it exactly -- "the one MCP server on this machine whose Python deps are
# not fetched by Nix" -- and that comment has been true and inert for four
# months. Foresight was not the scarce ingredient here; a refusal was. A comment
# describes, a guard refuses.
#
# WHY THE GENERAL PROPERTY AND NOT `orrery-mcp' BY NAME. The choice was open,
# and the evidence closed it. Writing this guard turned up a SECOND server with
# the same defect that nobody had written a comment about: `porkbun' execs
# `npx -y @porkbunllc/mcp-server', which fetches an UNPINNED npm package from
# the network on every launch -- no version pin, no hash, arbitrary published
# code exec'd with the Porkbun API secrets already exported into its
# environment. A guard that named orrery-mcp would have passed straight over it.
# The same module pins @owloops/claude-powerline with fetchzip and a sha256
# precisely because per-call npx was too slow, so the technique was already in
# the file; it had just not been applied here.
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
# THIS GUARD IS CURRENTLY RED, ON PURPOSE. Two of the five declared servers do
# not satisfy it, and neither was fixed here -- packaging mcp 2.x is a real
# piece of work and pinning the porkbun tarball is a change to a module this
# branch does not own. It was not written to pass over that; it was written to
# stop it being invisible. `documentedImpure' below records what each one takes.
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
  };

  # Servers known to fetch dependencies at runtime. Membership here NEVER grants
  # a pass -- these names are absent from nixFetchedDeps above and are refused
  # like any other unlisted server. This attrset exists only so that the failure
  # message says something actionable instead of "unreviewed".
  documentedImpure = {
    orrery = "modules/orrery-mcp.nix execs `uv run --script', resolving the server's PEP 723 deps (mcp[cli]>=2,<3) over the network into ~/.cache/uv. nixpkgs' python3Packages.mcp is 1.29 and the script needs 2.x, so python3.withPackages cannot express it today; a fix means mcp 2.x in nixpkgs, or a hash-pinned fixed-output derivation holding the resolved wheel set. That the resolution is unpinned is not theoretical: this machine's uv cache holds TWO different resolutions of this one script (mcp 2.0.0 and 2.1.1, cryptography 50.0.0 and 50.0.1), so which code runs depends on when the cache was warmed";
    porkbun = "modules/claude-code.nix execs `npx -y @porkbunllc/mcp-server', fetching an unpinned npm package on every launch, with PORKBUN_API_KEY and PORKBUN_SECRET_API_KEY already exported into its environment. Fixable with the technique already used for claude-powerline in that same file: pkgs.fetchzip on a pinned registry tarball plus a hash, run with pkgs.nodejs directly";
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

  reasonFor = name:
    documentedImpure.${name}
    or "not reviewed. Say where its dependencies come from and add it to nixFetchedDeps in this file, or make them come from Nix";

  lines =
    (map (name: "GUARD: MCP server '${name}' does not have its dependencies fetched by Nix -- ${reasonFor name}.") refused)
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
