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
    runtimeInputs = [pkg pkgs.jq pkgs.coreutils pkgs.git];
    text = ''
      # Claude Code names the trigger in .source: startup, resume, clear, compact
      # or fork. Only compact is worth skipping - it fires repeatedly inside one
      # long session, and re-running the whole kg round trip (6.8s natively,
      # 16.2s from Windows through wsl.exe) to re-inject text that is already in
      # context buys nothing. Every other value, including an unrecognised or
      # absent one, still gets the primer: staying silent when memory was wanted
      # is a worse failure than paying for it twice.
      #
      # This hook historically read no stdin at all, so the read is guarded -
      # run by hand on a terminal it must print the primer, not block on an
      # empty pipe until the hook timeout kills it.
      hook_source=""
      if [ ! -t 0 ]; then
        hook_source="$(jq -r '.source // empty' 2>/dev/null || true)"
      fi
      if [ "$hook_source" = "compact" ]; then exit 0; fi

      printf '## Knowledge graph (claude-kg) is ACTIVE for this session\n'
      printf 'Before non-trivial work, call kg_recall on the task topic; when you learn a durable, reusable fact, persist it with kg_upsert_entity / kg_add_observations and link with kg_relate. Do not re-derive what the graph already knows.\n\n'
      if stats="$(kg stats 2>/dev/null)"; then
        ents="$(printf '%s' "$stats" | jq -r '.entities // "?"')"
        rels="$(printf '%s' "$stats" | jq -r '.relations // "?"')"
        printf 'Graph: %s entities, %s relations.\n' "$ents" "$rels"
        # Seed the digest on the repository, not the working directory. Claude
        # Code on Windows starts in C:\Users\brona, so basename "$PWD" was
        # "brona" and the recall came back as generic facts about the user -
        # noise, injected into every session. Outside a repository there is no
        # meaningful key at all, so print the stats line and stop there.
        if root="$(git rev-parse --show-toplevel 2>/dev/null)" && [ -n "$root" ]; then
          proj="$(basename "$root")"
          digest="$(kg recall "$proj" 5 1 2>/dev/null \
            | jq -r '[.seeds[]? | "- " + .name + " (" + (.type // "?") + "): " + ((.observations[0].text // "") | .[0:160])] | .[0:5] | join("\n")' 2>/dev/null || true)"
          if [ -n "$digest" ]; then
            printf '\nPossibly relevant to "%s":\n%s\n' "$proj" "$digest"
          fi
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

  # Windows bridge for the SessionEnd capture hook. Claude Code running natively
  # on Windows reaches these hooks through `wsl.exe`, so its payload carries
  # Windows paths (C:\Users\...\transcript.jsonl) that kg-capture-hook cannot
  # stat — it would fail its `[ ! -f "$transcript" ]` guard and exit 0 silently,
  # leaving Windows sessions permanently uncaptured. Rewrite drive-letter paths
  # to their /mnt equivalents before handing the payload to the real hook.
  #
  # The read-side hooks (session-start, prompt-recall) need no such shim: they
  # only query Qdrant/Ollama and touch no caller-supplied path.
  kgCaptureHookWin = pkgs.writeShellApplication {
    name = "kg-capture-hook-win";
    # python3 only: kg-capture-hook is invoked by absolute store path, and
    # nothing here calls a coreutils binary by a bare name.
    runtimeInputs = [pkgs.python3];
    text = ''
      # chr(92) rather than a backslash literal: this Python is nested inside a
      # Nix indented string inside a shell single-quoted string, where escaping
      # a backslash correctly through all three layers is a standing hazard.
      python3 -c '
      import json, sys
      BS = chr(92)

      def to_wsl(p):
          if not isinstance(p, str) or len(p) < 3 or p[1] != ":":
              return p
          if not p[0].isalpha():
              return p
          rest = p[2:].replace(BS, "/").lstrip("/")
          return "/mnt/" + p[0].lower() + "/" + rest

      try:
          d = json.load(sys.stdin)
      except Exception:
          sys.exit(0)
      for k in ("transcript_path", "cwd"):
          if k in d:
              d[k] = to_wsl(d[k])
      json.dump(d, sys.stdout)
      ' | ${pkg}/bin/kg-capture-hook
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
    # kg, kg-server, kg-capture, kg-seed, kg-reembed, kg-snapshot come from pkg.
    # The three hook wrappers are installed into the profile as well, so they have
    # stable ~/.nix-profile/bin/ names: settings.json on this host is regenerated
    # on every switch and can safely reference /nix/store paths, but the Windows
    # host's hand-written settings.json cannot — a bare store path there would
    # dangle at the next rebuild.
    home.packages = [pkg kgSessionStartHook kgPromptRecallHook kgCaptureHookWin];

    # Register the MCP server, the SessionEnd capture hook, the read-side recall hooks,
    # and the graph's usage section for ~/.claude/CLAUDE.md with Claude Code.
    my.claudeCode = {
      mcpServers.claude-kg = {
        type = "stdio";
        command = "${pkg}/bin/kg-server";
      };
      # Deliberately modest: kg-capture-hook detaches the extraction with
      # setsid and returns, so the hook's own runtime is a JSON parse and a
      # stat, NOT the minutes the capture itself takes. The budget only has to
      # cover that plus the wsl.exe crossing when the caller is Windows.
      sessionEndCommands = [
        {
          command = "${pkg}/bin/kg-capture-hook";
          timeout = 30;
        }
      ];

      # Read side: prime each session with a recall, and recall per prompt.
      #
      # Both timeouts are budgeted for the slow path rather than the measured
      # one. The session-start hook takes 6.8s natively but 16.2s when Claude
      # Code runs on Windows and reaches it through wsl.exe, so the old 15s
      # default was truncating every Windows session outright. On top of that
      # crossing, either hook may cold-start Ollama's embed model and wait on
      # Qdrant, which costs tens of seconds more on the first call after a boot.
      # The ceiling is only ever reached by a slow backend, never by an absent
      # one: both hooks fail fast and inject nothing when Qdrant is not
      # listening.
      sessionStartCommands = [
        {
          command = "${kgSessionStartHook}/bin/kg-session-start-hook";
          timeout = 45;
        }
      ];
      # Higher than session-start: this one runs on every turn, so it is the
      # most likely of the three to be the call that pays the cold start.
      userPromptSubmitCommands = [
        {
          command = "${kgPromptRecallHook}/bin/kg-prompt-recall-hook";
          timeout = 60;
        }
      ];
      claudeMdSections = [(builtins.readFile ./claude-md-section.md)];
    };

    # Runtime data lives outside the nix store (mutable Qdrant volumes + logs).
    home.activation.claudeKgDirs = lib.hm.dag.entryAfter ["writeBoundary"] ''
      ${pkgs.coreutils}/bin/mkdir -p "${dataDir}/qdrant" "${dataDir}/snapshots"
    '';

    # systemd.user is Linux-only — home-manager errors if these are set on a
    # non-Linux host. Gate them so the module's cross-platform parts (the kg
    # CLI + MCP registration above) still work if it's ever enabled on a Mac.
    systemd.user = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
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
