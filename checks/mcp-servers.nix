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
# THE ENTRY IS TESTED, NOT JUST WRITTEN. Each allowlist entry names the
# DERIVATION that supplies that server's dependencies, and the guard asserts
# that derivation is in the runtime closure of the command the server is
# actually registered with. That is a positive assertion about a mechanism, not
# a prohibition on a tool: it stays an allowlist, and it does not have to
# enumerate uv, npx, pip, pipx and whatever is invented next.
#
# It exists because the prose-only form had a hole, found by mutation and not by
# reading. Revert modules/claude-code.nix to `npx -y @porkbunllc/mcp-server' and
# leave porkbun's allowlist line untouched, and the old guard passed: it checked
# that a sentence existed, never that the sentence was still true. With the
# derivation named, that revert drops porkbun-mcp-server out of the wrapper's
# closure and the guard fails on its own, without anyone having to remember to
# edit this file at the same time as the module.
#
# WHAT IT DOES NOT PROVE, stated plainly so nobody reads more into a pass than
# is there. Closure membership is necessary, not sufficient. A launcher that
# puts the supplier on runtimeInputs and then execs `uv run' anyway -- a
# half-finished migration, which is a plausible way to write this bug -- has the
# supplier in its closure and still resolves over the network, and this guard
# passes it. Measured, not assumed: a probe built exactly that launcher and the
# supplier was IN. What would close it is executing each server in the build
# sandbox (which has no network and no ~/.cache) and requiring an `initialize'
# response; both porkbun and orrery already answer that under a stripped
# environment. That is a bigger check with its own risks -- claude-kg and
# searxng talk to Qdrant and SearXNG -- so it is named here as the next step
# rather than half-built.
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
  # THE ALLOWLIST. Server name -> { package; how; }.
  #
  # `how' is the prose claim, and it has to name a mechanism a reader can go and
  # check. `package' is the same claim in a form the guard can TEST: the
  # derivation that supplies that server's dependencies. Every entry is checked
  # against the server's real runtime closure below, so an entry cannot outlive
  # the arrangement it describes.
  #
  # WHY BOTH, AND WHY THE DERIVATION MATTERS. Until this was added the entry was
  # prose alone, which meant the guard only checked that SOMEBODY HAD WRITTEN A
  # SENTENCE. Mutation-testing found the hole: revert modules/claude-code.nix to
  # `npx -y @porkbunllc/mcp-server' but leave porkbun's line here, and the guard
  # passed. The sentence was still there; it had merely stopped being true.
  # Naming the derivation closes that, because reverting the exec line drops
  # porkbun-mcp-server out of the wrapper's closure and the assertion fails on
  # its own, with nobody having to remember to edit this file.
  #
  # These are read from the modules, not re-derived from a copy of their
  # expressions -- see the mcpDepsFrom passthru in claude-kg/package.nix and
  # searxng/package.nix. A second copy of `python3.withPackages [mcp httpx]'
  # here would drift the moment either package gained a dependency, and would
  # then fail for a reason unrelated to the property being protected.
  nixFetchedDeps = {
    claude-kg = {
      package = (pkgs.callPackage ../modules/claude-kg/package.nix {}).mcpDepsFrom;
      how = "modules/claude-kg/package.nix: python3.withPackages [mcp httpx], wrapped so that interpreter is exec'd directly (the `uv run' shebangs still in src/*.py are inert -- makeWrapper never fires them)";
    };
    searxng = {
      package = (pkgs.callPackage ../modules/searxng/package.nix {}).mcpDepsFrom;
      how = "modules/searxng/package.nix: python3.withPackages [mcp httpx], wrapped the same way";
    };
    emacs = {
      # The honest supplier for a standard-library-only server is the
      # interpreter itself, and this entry is correspondingly WEAK: pkgs.python3
      # is in the closure of almost anything, so its presence proves little. It
      # is not a special case and not an exemption -- the assertion is true, it
      # just carries less information than the other four. A server that grew a
      # third-party import would need a real env here, and the honest way to
      # find that out is to read the source, which is what `how' points at.
      package = pkgs.python3;
      how = "modules/emacs-mcp.nix: Python standard library only, no third-party imports; patchShebangs pins it to pkgs.python3";
    };
    orrery = {
      package = pkgs.callPackage ../modules/orrery-mcp/python-env.nix {};
      how = "modules/orrery-mcp/python-env.nix: python3.withPackages over a packageOverrides scope carrying mcp 2.1.1 and mcp-types 2.1.1, both fetchPypi sdists with a hash (nixpkgs' mcp is 1.29 and the server needs the 2.x-only mcp.server.mcpserver). The launcher execs that interpreter directly, so the PEP 723 header and the uv shebang in orrery-mcp.py are inert -- pkgs.uv is no longer even on its PATH";
    };
    porkbun = {
      package = pkgs.callPackage ../modules/porkbun-mcp/package.nix {};
      how = "modules/porkbun-mcp/package.nix: buildNpmPackage over a pinned registry tarball (fetchzip + hash) with a committed package-lock.json and an npmDepsHash, so @modelcontextprotocol/sdk and zod come from the store; modules/claude-code.nix execs the resulting store path instead of `npx -y'";
    };
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

  # THE CLOSURE ASSERTION. Everything above is decided at evaluation time from
  # names; this part cannot be, because "is X reachable from Y" is a fact about
  # built store paths. It runs for servers that are declared, allowlisted, and
  # whose command is a store path -- the other cases have already failed above,
  # and feeding a non-store path to closureInfo would abort the evaluation with
  # a Nix error instead of the guard's own message.
  #
  # pkgs.closureInfo, not `nix-store --query --requisites': the build sandbox
  # has no access to the Nix database, so the query form cannot work inside a
  # check. closureInfo is computed by Nix outside the sandbox and handed in as a
  # store-paths file, which is the sandbox-safe equivalent. The registered
  # command path is passed as the root as-is -- it is a file inside a store
  # path, which closureInfo accepts, so no string surgery is needed to recover
  # the store root and the string context that makes Nix build it stays intact.
  #
  # WHAT THIS PROVES, EXACTLY: that the derivation the allowlist names is
  # reachable from the command that gets registered. That is necessary for the
  # deps to come from Nix, and it is not sufficient -- see the residual noted in
  # the header. Do not read a pass here as "this server cannot reach the
  # network".
  checkable =
    builtins.filter
    (name: !(builtins.elem name notStorePath))
    (lib.intersectLists declared allowed);

  closureChecks =
    map (name: {
      inherit name;
      command = mcpServers.${name}.command;
      supplier = "${nixFetchedDeps.${name}.package}";
      closure = pkgs.closureInfo {rootPaths = [mcpServers.${name}.command];};
      how = nixFetchedDeps.${name}.how;
    })
    checkable;

  # The failure text, built as a NIX string and never as shell source. This is
  # not fussiness. The first version of this block interpolated `how' into
  # `echo "..."', and `how' is written in this repo's house style, which quotes
  # `like this' -- with a BACKTICK. Two of those in double quotes opened a
  # command substitution that swallowed three whole stanzas, so the emacs,
  # orrery and porkbun assertions silently never ran and the guard passed a
  # mutation it was built to catch. It looked green and was checking two servers
  # out of five. printf with lib.escapeShellArg keeps prose prose; the counter
  # below is the belt to this braces.
  closureMessage = c: ''
    GUARD: MCP server '${c.name}' names a dependency supplier that is NOT in its
           runtime closure, so the claim in nixFetchedDeps is no longer true.
             server command:   ${c.command}
             claimed supplier: ${c.supplier}
             the claim:        ${c.how}
           Either the module stopped using that derivation -- a revert to npx, uv
           or pip looks exactly like this -- or the entry was never true.
  '';

  # One shell block per checkable server. Written out at eval time rather than
  # looped over at build time so that each server's paths are visible in
  # `nix derivation show', the same reason checkedServers is recorded below.
  closureScript =
    lib.concatMapStringsSep "\n" (c: ''
      ran=$((ran + 1))
      if ! grep -qxF -- ${lib.escapeShellArg c.supplier} ${c.closure}/store-paths; then
        printf '%s' ${lib.escapeShellArg (closureMessage c)} >&2
        failed=1
      fi
    '')
    closureChecks;
in {
  mcp-servers-deps-from-nix =
    pkgs.runCommand "mcp-servers-deps-from-nix" {
      inherit report;
      passAsFile = ["report"];
      # Recorded in the derivation so `nix derivation show' says which servers
      # were examined even on the runs where the guard passes and prints nothing.
      checkedServers = lib.concatStringsSep " " declared;
      closureCheckedServers = lib.concatStringsSep " " (map (c: c.name) closureChecks);
    } ''
      failed=
      ran=0

      if [ -s "$reportPath" ]; then
        cat "$reportPath" >&2
        failed=1
      fi

      # The closure assertions. Appended rather than folded into $report because
      # they are decided here, at build time, from the store-paths files.
      ${closureScript}

      # Did every assertion actually execute? A guard that silently checks fewer
      # things than it claims is worse than no guard, because it reports the
      # same green. This counter exists because that happened here: a backtick
      # in one entry's prose commented three assertions out of the generated
      # script, and nothing said so. Compared against the count fixed at
      # evaluation time, so the two can only agree if every block ran.
      if [ "$ran" -ne ${toString (builtins.length closureChecks)} ]; then
        {
          echo "GUARD: internal error -- $ran of ${toString (builtins.length closureChecks)} closure assertions executed."
          echo "       The generated script is malformed; do not trust a pass from it."
        } >&2
        failed=1
      fi

      if [ -n "$failed" ]; then
        {
          echo
          echo "An MCP server whose deps are fetched at runtime does not start on a machine"
          echo "with a cold cache -- which is every freshly built machine. See the header of"
          echo "checks/mcp-servers.nix for why this is refused rather than commented."
        } >&2
        exit 1
      fi
      touch $out
    '';
}
