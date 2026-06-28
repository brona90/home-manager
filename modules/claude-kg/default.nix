{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.my.claudeKg;
  pkg = pkgs.callPackage ./package.nix {};
  dataDir = "${config.home.homeDirectory}/.local/share/claude-kg";

  # Read side of memory (the write side is the kg-capture SessionEnd hook below).
  # SessionStart: inject a graph summary + a recall seeded on the repo name, plus a
  # standing directive. Degrades silently if Qdrant is offline.
  kgSessionStartHook = pkgs.writeShellApplication {
    name = "kg-session-start-hook";
    runtimeInputs = [pkg pkgs.jq pkgs.coreutils];
    text = ''
      proj="$(basename "$PWD")"
      printf '## Knowledge graph (claude-kg) is ACTIVE for this session\n'
      printf 'Before non-trivial work, call kg_recall on the task topic; when you learn a durable, reusable fact, persist it with kg_upsert_entity / kg_add_observations and link with kg_relate. Do not re-derive what the graph already knows.\n\n'
      if stats="$(kg stats 2>/dev/null)"; then
        ents="$(printf '%s' "$stats" | jq -r '.entities // "?"')"
        rels="$(printf '%s' "$stats" | jq -r '.relations // "?"')"
        printf 'Graph: %s entities, %s relations.\n' "$ents" "$rels"
        digest="$(kg recall "$proj" 5 1 2>/dev/null \
          | jq -r '[.seeds[]? | "- " + .name + " (" + (.type // "?") + "): " + ((.observations[0].text // "") | .[0:160])] | .[0:5] | join("\n")' 2>/dev/null || true)"
        if [ -n "$digest" ]; then
          printf '\nPossibly relevant to "%s":\n%s\n' "$proj" "$digest"
        fi
      else
        printf '(kg offline: Qdrant not reachable. Recall unavailable until it is started.)\n'
      fi
    '';
  };

  # UserPromptSubmit: recall on the actual prompt text and inject a compact digest, so
  # relevant prior memory is in context every turn regardless of tool-call behaviour.
  # Skips slash commands and very short prompts to limit noise/cost.
  kgPromptRecallHook = pkgs.writeShellApplication {
    name = "kg-prompt-recall-hook";
    runtimeInputs = [pkg pkgs.jq pkgs.coreutils];
    text = ''
      input="$(cat)"
      prompt="$(printf '%s' "$input" | jq -r '.prompt // empty')"
      if [ -z "$prompt" ]; then exit 0; fi
      case "$prompt" in
        /*) exit 0 ;;
      esac
      if [ "''${#prompt}" -lt 12 ]; then exit 0; fi
      digest="$(kg recall "$prompt" 5 1 2>/dev/null \
        | jq -r '[.seeds[]? | "- " + .name + ": " + ((.observations[0].text // "") | .[0:200])] | .[0:4] | join("\n")' 2>/dev/null || true)"
      if [ -z "$digest" ]; then exit 0; fi
      printf '<knowledge-graph recall: prior memory relevant to this prompt>\n%s\n</knowledge-graph>\n' "$digest"
    '';
  };
in {
  options.my.claudeKg = {
    enable = lib.mkEnableOption "claude-kg local knowledge-graph MCP server + Qdrant";
    image = lib.mkOption {
      type = lib.types.str;
      default = "qdrant/qdrant:latest";
    };
    dockerBin = lib.mkOption {
      type = lib.types.str;
      default = "/usr/bin/docker";
      description = "Path to the docker CLI (talks to the system daemon).";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [pkg]; # kg, kg-server, kg-capture, kg-seed, kg-reembed, kg-snapshot

    # Register the MCP server, the SessionEnd capture hook, the read-side recall hooks,
    # and the graph's usage section for ~/.claude/CLAUDE.md with Claude Code.
    my.claudeCode = {
      mcpServers.claude-kg = {
        type = "stdio";
        command = "${pkg}/bin/kg-server";
      };
      sessionEndCommands = ["${pkg}/bin/kg-capture-hook"];

      # Read side: prime each session with a recall, and recall per prompt.
      sessionStartCommands = ["${kgSessionStartHook}/bin/kg-session-start-hook"];
      userPromptSubmitCommands = ["${kgPromptRecallHook}/bin/kg-prompt-recall-hook"];
      claudeMdSections = [(builtins.readFile ./claude-md-section.md)];
    };

    # Runtime data lives outside the nix store (mutable Qdrant volumes + logs).
    home.activation.claudeKgDirs = lib.hm.dag.entryAfter ["writeBoundary"] ''
      ${pkgs.coreutils}/bin/mkdir -p "${dataDir}/qdrant" "${dataDir}/snapshots"
    '';

    # systemd.user is Linux-only — home-manager errors if these are set on a
    # non-Linux host. Gate them so the module's cross-platform parts (the kg
    # CLI + MCP registration above) still work if it's ever enabled on a Mac.
    systemd.user = lib.mkIf pkgs.stdenv.isLinux {
      services.qdrant = {
        Unit = {
          Description = "Qdrant vector DB for claude-kg";
          After = ["network-online.target"];
        };
        Service = {
          Type = "exec";
          ExecStartPre = "-${cfg.dockerBin} rm -f claude-kg-qdrant";
          ExecStart = ''
            ${cfg.dockerBin} run --rm --name claude-kg-qdrant \
              -p 6333:6333 -p 6334:6334 \
              -v ${dataDir}/qdrant:/qdrant/storage \
              -v ${dataDir}/snapshots:/qdrant/snapshots \
              -e QDRANT__TELEMETRY_DISABLED=true \
              ${cfg.image}
          '';
          ExecStop = "${cfg.dockerBin} stop claude-kg-qdrant";
          Restart = "on-failure";
          RestartSec = 5;
        };
        Install.WantedBy = ["default.target"];
      };

      # Daily snapshot of all collections (replaces the old crontab entry).
      services.kg-snapshot = {
        Unit.Description = "claude-kg Qdrant snapshot + prune";
        Service = {
          Type = "oneshot";
          Environment = "CLAUDE_KG_DATA_DIR=${dataDir}";
          ExecStart = "${pkg}/bin/kg-snapshot";
        };
      };
      timers.kg-snapshot = {
        Unit.Description = "Daily claude-kg snapshot";
        Timer = {
          OnCalendar = "*-*-* 03:17:00";
          Persistent = true;
        };
        Install.WantedBy = ["timers.target"];
      };
    };
  };
}
