{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.my.claudeKg;
  pkg = pkgs.callPackage ./package.nix {};
  dataDir = "${config.home.homeDirectory}/.local/share/claude-kg";

  # Shared preamble for BOTH read-side hooks.
  #
  # Why this exists. Recall needs two backends -- Qdrant for the vectors and
  # Ollama for the query embedding -- and until this was written the hooks
  # noticed neither. kg_server.py's httpx client has a 120s timeout, sized for
  # a legitimate cold model load, and kg-prompt-recall-hook wrapped the whole
  # round trip in `2>/dev/null ... || true` and then treated an empty result as
  # "nothing relevant". Three silencers on one line. MEASURED against this box:
  #
  #   embedder live               6.4s, 693 bytes of recall, exit 0
  #   OLLAMA_URL -> refused port  123.5s, ZERO bytes, exit 0
  #   OLLAMA_URL -> black hole    124.7s, ZERO bytes, exit 0
  #
  # Note the refused port hangs just as long as the black hole: under WSL2 a
  # connection to an unbound localhost port is not refused promptly, so "it
  # will fail fast because nothing is listening" is false here. Both failures
  # were indistinguishable from success, and both cost more than the hook's
  # entire Claude Code budget -- so on a rebuilt WSL with no Ollama, every
  # prompt paid a full minute of dead wait and got nothing, silently.
  #
  # `kg stats` cannot stand in for this check: it only counts Qdrant points,
  # and the "embed_model" it reports is the configured env var echoed back,
  # never a probe result. It returns exit 0 with the embedder unreachable
  # (verified).
  #
  # So: classify the embedder in probeTimeout seconds before spending anything,
  # and keep the three states that used to collapse into one distinct --
  # unreachable, up-but-missing-the-model, and a real error from recall itself.
  # Sets: ollama_url, embed_model, embed_state (ok|unreachable|model-missing),
  # embed_detail.
  embedProbe = ''
    ollama_url="''${OLLAMA_URL:-${cfg.ollamaUrl}}"
    ollama_url="''${ollama_url%/}"
    embed_model="''${EMBED_MODEL:-${cfg.embedModel}}"
    embed_state=ok
    embed_detail=""
    probe_out=""
    # --connect-timeout AND --max-time: a black-holed address never completes
    # the handshake, an overloaded one connects and then stalls. Both must be
    # bounded or the probe becomes the thing it was added to prevent.
    if ! probe_out="$(curl -sS --connect-timeout ${toString cfg.probeTimeout} \
      --max-time ${toString cfg.probeTimeout} "$ollama_url/api/tags" 2>&1)"; then
      embed_state=unreachable
      embed_detail="$probe_out"
    elif ! printf '%s' "$probe_out" | jq -e . >/dev/null 2>&1; then
      embed_state=unreachable
      embed_detail="non-JSON response from $ollama_url/api/tags (something else owns that port?)"
    elif ! printf '%s' "$probe_out" \
      | jq -e --arg m "''${embed_model%%:*}" 'any(.models[]?.name; startswith($m))' >/dev/null 2>&1; then
      embed_state=model-missing
    fi
  '';

  # Read side of memory (the write side is the kg-capture SessionEnd hook below).
  # SessionStart: inject a graph summary + a recall seeded on the repo name, plus a
  # standing directive.
  kgSessionStartHook = pkgs.writeShellApplication {
    name = "kg-session-start-hook";
    runtimeInputs = [pkg pkgs.jq pkgs.coreutils pkgs.git pkgs.curl];
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

      ${embedProbe}

      printf '## Knowledge graph (claude-kg) is ACTIVE for this session\n'
      printf 'Before non-trivial work, call kg_recall on the task topic; when you learn a durable, reusable fact, persist it with kg_upsert_entity / kg_add_observations and link with kg_relate. Do not re-derive what the graph already knows.\n\n'

      # This hook must exit 0 to have its stdout injected at all: a non-zero
      # SessionStart hook gets its stdout DISCARDED, which would throw away the
      # primer along with the warning. So the degraded-state report goes on
      # stdout, phrased as an instruction to surface it -- that is the channel
      # that actually reaches the user for this event. The per-prompt hook,
      # which has no primer to protect, uses stderr + a non-zero exit instead.
      case "$embed_state" in
        unreachable)
          printf 'DEGRADED: the knowledge-graph embedder is NOT REACHABLE at %s (%s).\n' \
            "$ollama_url" "''${embed_detail:-no response}"
          printf 'Semantic recall and kg_recall/kg_search are unavailable this session; only exact lookups will work.\n'
          printf 'TELL THE USER this, in your first reply, and that the fix is: systemctl --user start ollama\n\n'
          ;;
        model-missing)
          printf 'DEGRADED: the embedder at %s is running but has no "%s" model, so nothing can be embedded.\n' \
            "$ollama_url" "$embed_model"
          printf 'TELL THE USER this, in your first reply, and that the fix is: ollama pull %s\n\n' "$embed_model"
          ;;
      esac

      if stats="$(kg stats 2>/dev/null)"; then
        ents="$(printf '%s' "$stats" | jq -r '.entities // "?"')"
        rels="$(printf '%s' "$stats" | jq -r '.relations // "?"')"
        printf 'Graph: %s entities, %s relations.\n' "$ents" "$rels"
      else
        printf 'DEGRADED: Qdrant is not reachable, so the graph itself is offline.\n'
        printf 'TELL THE USER this, in your first reply, and that the fix is: systemctl --user start qdrant\n'
        exit 0
      fi

      # No embedder means no query vector, so skip the recall rather than spend
      # the hook budget proving it again.
      if [ "$embed_state" != "ok" ]; then exit 0; fi

      # Seed the digest on the repository, not the working directory. Claude
      # Code on Windows starts in C:\Users\brona, so basename "$PWD" was
      # "brona" and the recall came back as generic facts about the user -
      # noise, injected into every session. Outside a repository there is no
      # meaningful key at all, so print the stats line and stop there.
      if root="$(git rev-parse --show-toplevel 2>/dev/null)" && [ -n "$root" ]; then
        proj="$(basename "$root")"
        # `recall_rc=$?` on its own line, NOT `kg recall | jq` -- a pipeline
        # reports the exit code of its LAST command, so piping straight into jq
        # would report jq's success and discard kg's failure. That defect is
        # exactly what made this hook unable to tell a dead backend from an
        # empty graph.
        recall_rc=0
        recall_raw="$(timeout ${toString cfg.recallTimeoutSessionStart} \
          kg recall "$proj" 5 1 2>/tmp/kg-session-start-err.$$)" || recall_rc=$?
        if [ "$recall_rc" -ne 0 ]; then
          if [ "$recall_rc" -eq 124 ]; then
            printf 'DEGRADED: recall timed out after %ss even though the embedder answered.\n' \
              '${toString cfg.recallTimeoutSessionStart}'
          else
            printf 'DEGRADED: recall failed (kg recall exited %s): %s\n' \
              "$recall_rc" "$(head -c 300 /tmp/kg-session-start-err.$$ | tr '\n' ' ')"
          fi
          printf 'TELL THE USER the graph read path is broken.\n'
          rm -f /tmp/kg-session-start-err.$$
          exit 0
        fi
        rm -f /tmp/kg-session-start-err.$$
        digest="$(printf '%s' "$recall_raw" \
          | jq -r '[.seeds[]? | "- " + .name + " (" + (.type // "?") + "): " + ((.observations[0].text // "") | .[0:160])] | .[0:5] | join("\n")' 2>/dev/null || true)"
        if [ -n "$digest" ]; then
          printf '\nPossibly relevant to "%s":\n%s\n' "$proj" "$digest"
        fi
      fi
    '';
  };

  # UserPromptSubmit: recall on the actual prompt text and inject a compact digest, so
  # relevant prior memory is in context every turn regardless of tool-call behaviour.
  # Skips slash commands and very short prompts to limit noise/cost.
  kgPromptRecallHook = pkgs.writeShellApplication {
    name = "kg-prompt-recall-hook";
    runtimeInputs = [pkg pkgs.jq pkgs.coreutils pkgs.curl];
    text = ''
      input="$(cat)"
      prompt="$(printf '%s' "$input" | jq -r '.prompt // empty')"
      if [ -z "$prompt" ]; then exit 0; fi
      case "$prompt" in
        /*) exit 0 ;;
      esac
      if [ "''${#prompt}" -lt 12 ]; then exit 0; fi

      ${embedProbe}

      # Exit 1, NOT 2. For UserPromptSubmit, Claude Code treats exit 2 as
      # "block this prompt" -- a dead embedder must never stop the user from
      # working. Any other non-zero exit is a non-blocking error whose stderr
      # is surfaced to the user, which is precisely the wanted behaviour: the
      # turn proceeds without recall, and the user is told why instead of
      # silently losing a minute per prompt.
      case "$embed_state" in
        unreachable)
          printf 'claude-kg: embedder UNREACHABLE at %s (probed for %ss) - no knowledge-graph recall this turn. Fix: systemctl --user start ollama. [%s]\n' \
            "$ollama_url" '${toString cfg.probeTimeout}' "''${embed_detail:-no response}" >&2
          exit 1
          ;;
        model-missing)
          printf 'claude-kg: embedder at %s is up but has no "%s" model - no recall this turn. Fix: ollama pull %s\n' \
            "$ollama_url" "$embed_model" "$embed_model" >&2
          exit 1
          ;;
      esac

      # Bounded, and the exit code is read from the command itself rather than
      # from the tail of a pipeline. `timeout` caps the case the probe cannot
      # catch: an embedder that accepts the connection and then stalls.
      recall_rc=0
      recall_raw="$(timeout ${toString cfg.recallTimeoutPrompt} \
        kg recall "$prompt" 5 1 2>/tmp/kg-prompt-recall-err.$$)" || recall_rc=$?
      if [ "$recall_rc" -ne 0 ]; then
        if [ "$recall_rc" -eq 124 ]; then
          printf 'claude-kg: recall timed out after %ss with the embedder answering - no recall this turn.\n' \
            '${toString cfg.recallTimeoutPrompt}' >&2
        else
          printf 'claude-kg: recall FAILED (kg recall exited %s) - no recall this turn: %s\n' \
            "$recall_rc" "$(head -c 300 /tmp/kg-prompt-recall-err.$$ | tr '\n' ' ')" >&2
        fi
        rm -f /tmp/kg-prompt-recall-err.$$
        exit 1
      fi
      rm -f /tmp/kg-prompt-recall-err.$$

      digest="$(printf '%s' "$recall_raw" \
        | jq -r '[.seeds[]? | "- " + .name + ": " + ((.observations[0].text // "") | .[0:200])] | .[0:4] | join("\n")' 2>/dev/null || true)"
      # The one state that is legitimately silent: both backends answered and
      # the graph simply holds nothing relevant to this prompt. Distinct from
      # every branch above, all of which now say something.
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

    # Read by checks/ollama.nix so the guard inspects the script activation
    # actually installs, rather than a rebuild of the same source that could
    # drift from it. Internal and read-only: this is an OUTPUT of the module,
    # not a knob -- nothing outside the check set has any business setting it.
    # Same pattern as my.claudeCode.homeWriteGuardPackage.
    promptRecallHookPackage = lib.mkOption {
      type = lib.types.package;
      internal = true;
      readOnly = true;
      default = kgPromptRecallHook;
      description = "The built kg-prompt-recall-hook, exposed for the flake checks.";
    };
    image = lib.mkOption {
      type = lib.types.str;
      default = "qdrant/qdrant:latest";
    };
    dockerBin = lib.mkOption {
      type = lib.types.str;
      default = "/usr/bin/docker";
      description = "Path to the docker CLI (talks to the system daemon).";
    };

    # These four exist so the read-side hooks agree with kg_server.py about
    # where the embedder is and what it is called, without either side having
    # to hardcode it twice. Both hooks still honour the OLLAMA_URL / EMBED_MODEL
    # environment variables over these defaults -- that override is how the
    # failure modes above were measured, and how they can be re-measured.
    ollamaUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://localhost:11434";
      description = "Default embedder endpoint the read-side hooks probe. Overridden by $OLLAMA_URL.";
    };
    embedModel = lib.mkOption {
      type = lib.types.str;
      default = "nomic-embed-text";
      description = "Default embedding model the read-side hooks require. Overridden by $EMBED_MODEL.";
    };
    probeTimeout = lib.mkOption {
      type = lib.types.ints.positive;
      default = 2;
      description = ''
        Seconds the read-side hooks will spend deciding whether the embedder is
        alive, before doing anything expensive. Deliberately far below the hook
        budgets: the whole point is that an absent backend costs ~2s and says
        so, rather than 123s and silence.
      '';
    };
    recallTimeoutPrompt = lib.mkOption {
      type = lib.types.ints.positive;
      default = 45;
      description = ''
        Hard ceiling on a single UserPromptSubmit recall, in seconds. Must stay
        BELOW the 60s hook timeout: whichever fires first wins, and this one
        produces a message the user can read while Claude Code's produces a
        silent kill.
      '';
    };
    recallTimeoutSessionStart = lib.mkOption {
      type = lib.types.ints.positive;
      default = 30;
      description = ''
        Hard ceiling on the SessionStart recall, in seconds. Below the 45s hook
        timeout for the same reason as recallTimeoutPrompt, and lower than it
        because this hook has already spent budget on `kg stats`.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # kg, kg-server, kg-capture, kg-seed, kg-reembed, kg-snapshot come from pkg.
    # The three hook wrappers are installed into the profile as well, so they have
    # stable ~/.nix-profile/bin/ names: settings.json on this host is regenerated
    # on every switch and can safely reference /nix/store paths, but the Windows
    # one is merged rather than rewritten — a bare store path there would dangle
    # at the next rebuild. That is what the windowsProfileBin field on each
    # contributed hook below takes, and checks/windows-bridge.nix fails the build
    # if a store path reaches the Windows fragment anyway.
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
          # The Windows caller gets the shim, not the hook itself: see
          # kgCaptureHookWin above for what it rewrites and why. This line is
          # also what finally gives that wrapper a consumer inside the flake --
          # until now it was built here and referenced only from a hand-written
          # line in the Windows settings.json, so nothing in this repository
          # recorded that it was needed.
          windowsProfileBin = "kg-capture-hook-win";
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
      #
      # These ceilings are now only ever reached by a genuinely SLOW backend.
      # An absent one is caught by the probe in ~probeTimeout seconds and
      # reported; a stalled one is caught by the inner `timeout`, which is set
      # below each of these numbers so the failure is a message rather than a
      # kill.
      sessionStartCommands = [
        {
          command = "${kgSessionStartHook}/bin/kg-session-start-hook";
          # No shim needed: the read-side hooks touch no caller-supplied path,
          # so the Windows caller runs the same program under the same name.
          windowsProfileBin = "kg-session-start-hook";
          timeout = 45;
        }
      ];
      # Higher than session-start: this one runs on every turn, so it is the
      # most likely of the three to be the call that pays the cold start.
      userPromptSubmitCommands = [
        {
          command = "${kgPromptRecallHook}/bin/kg-prompt-recall-hook";
          windowsProfileBin = "kg-prompt-recall-hook";
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
