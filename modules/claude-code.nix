{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.my.claudeCode;

  # Hoisted out of the enabledPlugins keys to keep an at-sign-prefixed plugin
  # marketplace string out of the raw file text. GitHub's mention parser
  # greedy-matches the substring at-cl* (the plugins-official user 404s, so it
  # falls back to the bot user id 81847) and pulls that bot into the repo's
  # contributors widget. Splitting the literal preserves the evaluated value
  # Claude Code reads while avoiding the raw-text mention match in this file.
  marketplace = "claude-plugins-official";

  # WHY THIS GUARD EXISTS. A survey of this machine on 2026-08-29 found 371 loose
  # scripts sitting directly in /home/gfoster -- aud1.sh through aud15.sh,
  # brief-diag.sh, basecheck.sh -- and 303 of the 313 shell scripts among them
  # carried no exec bit, i.e. each was written to be run once as `bash foo.sh'
  # and never again. Several cd into worktrees that have since been removed, so
  # they cannot even be re-run. Every one is an agent answering a question where
  # it stood instead of in a scratchpad, and the instruction not to do that has
  # been in CLAUDE.md the whole time: an instruction is advice the model may not
  # be holding at the moment it reaches for Write, and a hook is not.
  #
  # THE RULE, and why it can afford to be this blunt: a NON-HIDDEN FILE written
  # directly into the home root is debris. Dotfiles are configuration and are
  # never touched. Anything one directory down is a project and is never
  # touched. A directory is not a file. What is left is exactly the shape those
  # 371 share and almost nothing legitimate, which is what makes a hard refusal
  # cheap here rather than merely irritating -- the escape hatch below exists
  # for the remainder and has to be set deliberately, per call.
  #
  # WHAT IT CANNOT SEE, and why it does not pretend to. Write/Edit/NotebookEdit
  # declare a path, so checking one is exact and a refusal is never wrong. A
  # `cat > ~/x.sh' inside a Bash call declares nothing, and matching a regex
  # against arbitrary shell to find it is a false-positive machine that would
  # get itself disabled within a week. So the Bash half is a PostToolUse
  # DETECTOR that reports and does not refuse: block what can be proved, report
  # what can only be noticed, and never guess in the blocking direction.
  homeWriteGuard = pkgs.writeShellApplication {
    name = "claude-home-guard";
    # `Nix PATH is login-shell only' applies with full force here: a hook is
    # started by Claude Code with /usr/bin, not with this user's profile, so
    # every binary this script names has to be listed. runtimeInputs prefixes
    # rather than replaces PATH, so an invocation from inside a login shell
    # still behaves identically.
    runtimeInputs = [pkgs.jq pkgs.coreutils pkgs.findutils];
    text = ''
      set -u

      root=${lib.escapeShellArg config.home.homeDirectory}

      # Deliberate, per-call, and named in the refusal text so the way out is
      # discoverable from the error rather than from this file.
      if [ "''${CLAUDE_ALLOW_HOME_WRITE:-}" = "1" ]; then
        exit 0
      fi

      mode="guard"
      if [ "$#" -gt 0 ]; then
        mode="$1"
      fi

      if [ "$mode" = "detect" ]; then
        # No stamp file and no session state: "changed in the last minute" is a
        # good enough proxy for "this Bash call did it", and being occasionally
        # late is harmless for something that only ever prints.
        hits=$(find "$root" -maxdepth 1 -type f ! -name '.*' -mmin -1 -printf '%f\n' 2>/dev/null || true)
        if [ -n "$hits" ]; then
          printf 'claude-home-guard: these non-hidden files just appeared directly in %s:\n\n%s\n\nThat is where the 371 came from. Move them into the session scratchpad, or into the repo they serve with a name that says what they are, and remove them from the home root before finishing.\n' "$root" "$hits" >&2
          exit 2
        fi
        exit 0
      fi

      payload=$(cat)

      tool=$(printf '%s' "$payload" | jq -r '.tool_name // empty')
      case "$tool" in
        Write | Edit | NotebookEdit) : ;;
        *) exit 0 ;;
      esac

      path=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty')
      if [ -z "$path" ]; then
        exit 0
      fi

      # WSL paths only, deliberately. The Windows half of this machine reaches
      # Claude Code natively and would hand this rule backslashes, but it cannot
      # reach this hook at all yet: my.windowsBridge.files.claude-settings
      # claims exactly one key (`attribution'), so nothing here crosses to
      # C:\Users. Normalising for a caller that does not exist bought one
      # escaping bug per attempt -- a literal backslash has to survive Nix
      # indented-string escaping and the shell linter at once -- for a case no
      # test could exercise. When the bridge learns to carry hooks, the
      # separator conversion belongs here and gets a test with it.
      dir=$(dirname "$path")
      base=$(basename "$path")

      # Configuration, not debris. Never blocked.
      case "$base" in
        .*) exit 0 ;;
      esac

      if [ "$dir" = "$root" ]; then
        printf 'claude-home-guard: refusing to write %s\n\n%s is the home root, and a non-hidden file directly in it is scratch. Scratch belongs in the session scratchpad, or in the repo it serves under a name that says what it is. 371 files arrived this way before this hook existed; several of them cd into worktrees that no longer exist.\n\nIf this file genuinely belongs in the home root, re-run the call with CLAUDE_ALLOW_HOME_WRITE=1.\n' "$path" "$root" >&2
        exit 2
      fi

      exit 0
    '';
  };

  # The server itself: a pinned tarball with its node_modules fetched by Nix.
  # See modules/porkbun-mcp/package.nix for why this is not `npx -y' and not the
  # bare-fetchzip shape claude-powerline uses below.
  porkbunMcpServer = pkgs.callPackage ./porkbun-mcp/package.nix {};

  porkbunMcpWrapper = pkgs.writeShellApplication {
    name = "porkbun-mcp";
    # nodejs is still here even though the exec below is a wrapped bin: the
    # bin/porkbun-mcp symlink points at dist/index.js, whose `#!/usr/bin/env
    # node' shebang needs a node on PATH.
    runtimeInputs = [pkgs.nodejs pkgs.coreutils];
    text = ''
      api_key_file="${config.home.homeDirectory}/.config/sops-nix/secrets/porkbun_api_key"
      secret_key_file="${config.home.homeDirectory}/.config/sops-nix/secrets/porkbun_secret_key"
      if [ ! -r "$api_key_file" ] || [ ! -r "$secret_key_file" ]; then
        echo "porkbun-mcp: secret files missing or unreadable" >&2
        exit 1
      fi
      PORKBUN_API_KEY=$(cat "$api_key_file")
      PORKBUN_SECRET_API_KEY=$(cat "$secret_key_file")
      export PORKBUN_API_KEY PORKBUN_SECRET_API_KEY
      # A store path, resolved at build time. The two secrets above are already
      # in this process's environment when the exec happens, so what runs here
      # must be decided by this repository and not by whoever last published to
      # the npm registry.
      exec ${lib.getExe porkbunMcpServer} "$@"
    '';
  };

  # Serialize the MCP servers contributed via my.claudeCode.mcpServers (this module
  # sets porkbun; claude-kg/searxng/emacs modules add their own) for the activation
  # merge below. Claude Code reads user-scope servers only from ~/.claude.json — never
  # from settings.json — so we merge into that mutable runtime file on every switch,
  # which also refreshes Nix-store command paths on each rebuild.
  managedMcpServersFile =
    pkgs.writeText "claude-mcp-servers.json" (builtins.toJSON cfg.mcpServers);

  # claude-powerline ships fully bundled (no runtime npm dependencies), so we
  # pin the tarball and run it with node directly: the statusline re-runs on
  # every conversation update, where per-call npx resolution is too slow.
  claudePowerlineSrc = pkgs.fetchzip {
    url = "https://registry.npmjs.org/@owloops/claude-powerline/-/claude-powerline-1.27.0.tgz";
    hash = "sha256-0l30qqQyGxYl1W++jOutzrQA0eQ6eUg9LdFwV9RhC10=";
  };

  # Hand-written JSON rather than builtins.toJSON: claude-powerline renders
  # segments in JSON key order, and toJSON sorts attrset keys alphabetically,
  # which would scramble the segment order. Segment lineup mirrors the
  # previous shell statusline: user@host, cwd, git branch, model, context %,
  # 5h rate limit (block), 7d rate limit (weekly).
  claudePowerlineConfig = pkgs.writeText "claude-powerline.json" ''
    {
      "theme": "dark",
      "display": {
        "style": "powerline",
        "charset": "unicode",
        "lines": [
          {
            "segments": {
              "env": {"enabled": true, "variable": "CLAUDE_POWERLINE_HOST", "prefix": ""},
              "directory": {"enabled": true, "style": "fish"},
              "git": {"enabled": true},
              "model": {"enabled": true},
              "context": {"enabled": true, "percentageMode": "used", "displayStyle": "text"},
              "block": {"enabled": true, "displayStyle": "text"},
              "weekly": {"enabled": true, "displayStyle": "text"}
            }
          }
        ]
      }
    }
  '';

  statusLineScript = pkgs.writeShellApplication {
    name = "claude-statusline";
    runtimeInputs = [pkgs.nodejs pkgs.git pkgs.coreutils];
    text = ''
      # No built-in hostname segment; feed user@host through the env segment.
      CLAUDE_POWERLINE_HOST="$(whoami)@$(hostname -s)"
      export CLAUDE_POWERLINE_HOST
      exec node ${claudePowerlineSrc}/bin/claude-powerline \
        --config=${claudePowerlineConfig} "$@"
    '';
  };

  # Hook commands are contributed by other modules (claude-kg today), and the
  # right timeout is a property of the command, not of the event: the same
  # script runs several times slower when Claude Code is running natively on
  # Windows and reaches the hook through wsl.exe, which adds seconds of interop
  # overhead on top of the native runtime. A single per-event literal cannot
  # express that, so every contributed command carries its own budget. A bare
  # command string is still accepted and takes the event's default timeout,
  # which keeps every existing list-of-strings call site valid.
  hookCommandType = defaultTimeout:
    lib.types.coercedTo lib.types.str (command: {inherit command;})
    (lib.types.submodule {
      options = {
        command = lib.mkOption {
          type = lib.types.str;
          description = "Command line Claude Code executes for this hook.";
        };
        timeout = lib.mkOption {
          type = lib.types.ints.positive;
          default = defaultTimeout;
          description = ''
            Seconds Claude Code waits before killing the hook. Budget for the
            slowest caller rather than the measured one: a hook that takes N
            seconds natively takes roughly N plus 1 to 10 more when Claude Code
            runs on Windows and invokes it through wsl.exe.
          '';
        };
      };
    });

  # Every event renders its contributed commands the same way; only the list
  # and the default timeout baked into its type differ.
  hookEntries = commands:
    map (c: {
      type = "command";
      inherit (c) command timeout;
    })
    commands;

  settings = {
    # No agent attribution in commit messages or PR bodies (no
    # Co-Authored-By trailers, no "Generated with Claude Code" footers).
    attribution = {
      commit = "";
      pr = "";
    };
    statusLine = {
      type = "command";
      command = "${statusLineScript}/bin/claude-statusline";
    };
    enabledPlugins = {
      # Language servers for the languages in daily use (go-to-def, refs,
      # diagnostics). No first-party LSP exists for Nix/Fortran/Elisp/Bash.
      "lua-lsp@${marketplace}" = true;
      "pyright-lsp@${marketplace}" = true;
      "typescript-lsp@${marketplace}" = true;
      "gopls-lsp@${marketplace}" = true;
      # Claude-tooling authoring: this config builds MCP servers (claude-kg,
      # searxng, porkbun), agents/commands (specflow), and hooks constantly.
      "plugin-dev@${marketplace}" = true;
      "mcp-server-dev@${marketplace}" = true;
      "skill-creator@${marketplace}" = true;
      # hookify ships its own SessionStart/PreToolUse/PostToolUse/Stop/
      # UserPromptSubmit runners that execute in every session — enabled
      # deliberately, not as a default.
      "hookify@${marketplace}" = true;
    };
    # MCP servers are NOT set here — Claude Code ignores `mcpServers` in
    # settings.json. They are declared via my.claudeCode.mcpServers (by this and
    # other modules) and merged into ~/.claude.json by the activation script below.
    permissions = {
      allow = [
        "Bash(gh run view *)"
        "Bash(gh run list *)"
        "Bash(gh run watch *)"
        "Bash(gh pr view *)"
        "Bash(gh pr checks *)"
        "Bash(gh api *)"
        # emacs_eval is deliberately NOT allow-listed: it passes arbitrary
        # elisp to emacsclient --eval, which is an unguarded code-execution
        # path that bypasses every other permission gate.
        "mcp__emacs__emacs_show_diff"
      ];
    };
    hooks =
      {
        PermissionRequest = [
          {
            matcher = "Edit|Write";
            hooks = [
              {
                type = "command";
                # Write via temp file + mv in the same directory so input.json
                # appears atomically and readers never see a partial write.
                #
                # `-s $EMACS_SOCKET_NAME` when that is set, bare emacsclient
                # otherwise. A bare emacsclient resolves to whichever Emacs is
                # on PATH -- i.e. ALWAYS the daily driver -- so a Claude session
                # running inside a second daemon would fire its hook at the
                # wrong Emacs and show the diff there. Emacs does not export
                # EMACS_SOCKET_NAME to its subprocesses (it is read only by the
                # emacsclient binary), so the daemon's unit has to set it; where
                # it is unset this expands to nothing and behaviour is exactly
                # as before.
                command = "[ -n \"\${INSIDE_EMACS:-}\" ] || exit 0; d=\${XDG_RUNTIME_DIR:-/tmp}/claude-diff && mkdir -p \"$d\" && f=$d/input.json && t=$(mktemp \"$d/input.XXXXXX\") && cat > \"$t\" && mv \"$t\" \"$f\" && emacsclient \${EMACS_SOCKET_NAME:+-s \"$EMACS_SOCKET_NAME\"} --eval \"(claude-diff-from-hook \\\"$f\\\")\"";
                timeout = 10;
              }
            ];
          }
        ];
        # Exact, blocking, and only where the path is declared. See the
        # homeWriteGuard comment above for why the Bash case is a detector
        # instead and why the rule is allowed to be a flat refusal.
        PreToolUse = [
          {
            matcher = "Write|Edit|NotebookEdit";
            hooks = [
              {
                type = "command";
                command = "${homeWriteGuard}/bin/claude-home-guard";
                timeout = 5;
              }
            ];
          }
        ];
        PostToolUse = [
          {
            matcher = "Bash";
            hooks = [
              {
                type = "command";
                command = "${homeWriteGuard}/bin/claude-home-guard detect";
                timeout = 5;
              }
            ];
          }
          {
            matcher = "Edit|Write";
            hooks = [
              {
                type = "command";
                # Same socket handling as the PermissionRequest hook above --
                # the dismiss must reach the SAME Emacs that was asked to show
                # the diff, or the diff layout is left on screen forever.
                command = "[ -n \"\${INSIDE_EMACS:-}\" ] || exit 0; emacsclient \${EMACS_SOCKET_NAME:+-s \"$EMACS_SOCKET_NAME\"} --eval '(claude-diff-dismiss)'";
                timeout = 5;
              }
            ];
          }
        ];
      }
      // lib.optionalAttrs (cfg.sessionEndCommands != []) {
        # Run each contributed SessionEnd command (e.g. claude-kg auto-capture).
        SessionEnd = [{hooks = hookEntries cfg.sessionEndCommands;}];
      }
      // lib.optionalAttrs (cfg.sessionStartCommands != []) {
        # Contributed SessionStart commands (e.g. claude-kg recall primer). Each
        # command's stdout is injected into the new session's context.
        SessionStart = [{hooks = hookEntries cfg.sessionStartCommands;}];
      }
      // lib.optionalAttrs (cfg.userPromptSubmitCommands != []) {
        # Contributed UserPromptSubmit commands (e.g. claude-kg per-prompt recall).
        # Each command receives the prompt JSON on stdin and may inject context via stdout.
        UserPromptSubmit = [{hooks = hookEntries cfg.userPromptSubmitCommands;}];
      };
  };
in {
  options.my.claudeCode = {
    enable = lib.mkEnableOption "Claude Code settings and hooks";

    # Read by checks/claude-home-guard.nix so the guard's behavioural test
    # exercises the package activation installs rather than a rebuild of the
    # same source. Internal and read-only: this is an output of the module, not
    # a knob -- nothing outside the check set has any business setting it.
    homeWriteGuardPackage = lib.mkOption {
      type = lib.types.package;
      internal = true;
      readOnly = true;
      default = homeWriteGuard;
      description = "The built claude-home-guard hook, exposed for the flake checks.";
    };

    mcpServers = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = {};
      description = ''
        User-scope MCP servers to merge into ~/.claude.json on activation. Other
        modules contribute entries (e.g. claude-kg, searxng, emacs-mcp); this module
        adds porkbun.
      '';
    };

    sessionEndCommands = lib.mkOption {
      type = lib.types.listOf (hookCommandType 15);
      default = [];
      description = ''
        Commands run as Claude Code SessionEnd hooks (one hook each). An entry is
        either a bare command string, which gets the 15s default timeout, or an
        attrset carrying a command and its own timeout in seconds.
      '';
    };

    sessionStartCommands = lib.mkOption {
      type = lib.types.listOf (hookCommandType 15);
      default = [];
      description = ''
        Commands run as Claude Code SessionStart hooks (one hook each). Each
        command's stdout is injected into the new session's context. An entry is
        either a bare command string, which gets the 15s default timeout, or an
        attrset carrying a command and its own timeout in seconds. 15s is only
        safe for a hook that touches nothing but the local filesystem: the
        wsl.exe crossing alone has been measured to add 9s to a hook that takes
        under 7s natively, so anything that also talks to a service should state
        its own timeout.
      '';
    };

    userPromptSubmitCommands = lib.mkOption {
      type = lib.types.listOf (hookCommandType 45);
      default = [];
      description = ''
        Commands run as Claude Code UserPromptSubmit hooks (one hook each). Each
        receives the prompt JSON on stdin and may inject context via stdout. An
        entry is either a bare command string, which gets the 45s default
        timeout, or an attrset carrying a command and its own timeout in
        seconds. The default is generous because this event blocks every turn on
        work that may have to cold-start an embedding model.
      '';
    };

    claudeMdSections = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = ''
        Markdown sections contributed by modules; joined into the managed
        ~/.claude/CLAUDE.md (user-scope global instructions). Empty = file unmanaged.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # This module owns the porkbun DNS MCP server (its wrapper is defined above).
    my.claudeCode.mcpServers.porkbun = {
      type = "stdio";
      command = "${porkbunMcpWrapper}/bin/porkbun-mcp";
    };

    # The OTHER settings.json: the one Claude Code reads when it runs natively on
    # Windows against work that lives in WSL. Installed by
    # modules/windows-bridge.nix (a no-op anywhere there is no /mnt/c), declared
    # here because this module owns what Claude Code is configured to do.
    #
    # MERGED, not owned, and claiming exactly one key. Claude Code writes that
    # file itself, and the live copy proves it: an `autoMode.environment' block
    # it generated, an `enabledPlugins' entry that appeared by installing a
    # plugin, a statusLine pointing at a hand-maintained statusline-command.sh,
    # and PowerShell() permission rules that mean nothing on the WSL side.
    # Rendering the whole file from here would delete all of that on the next
    # `hms' -- and would make the plugin-installed-on-Windows-only problem worse
    # rather than better, by silently reverting every future plugin install. So
    # the flake claims the one key that is genuinely the same decision on both
    # sides and leaves the application everything else.
    #
    # `attribution' comes from the settings above BY REFERENCE, not by copy:
    # one definition in this repo, read by both files and by both guards. It
    # lives here rather than in windows-bridge.nix because empty attribution is
    # a Claude Code policy, not a Windows one.
    my.windowsBridge.files.claude-settings = {
      target = ".claude/settings.json";
      mode = "merge-json";
      text = builtins.toJSON {inherit (settings) attribution;};
    };

    home = {
      # The module that enables Claude Code also owns the CLI package
      # (previously duplicated in home/linux.nix and home/darwin.nix).
      packages = [pkgs.claude-code];

      file.".claude/settings.json".text = builtins.toJSON settings;

      # Assemble ~/.claude/CLAUDE.md (user-scope global instructions) from sections
      # contributed by modules (e.g. claude-kg, claude-specflow). Only managed when at
      # least one section is contributed, so the file is untouched on hosts with none.
      file.".claude/CLAUDE.md" = lib.mkIf (cfg.claudeMdSections != []) {
        text = lib.concatStringsSep "\n\n" cfg.claudeMdSections;
      };

      # Claude Code loads user-scope MCP servers only from ~/.claude.json (a mutable
      # runtime file), so we merge our managed set into it on activation instead of
      # owning the file. Unmanaged servers already present are preserved; ours win on
      # key conflict. Writes atomically via a temp file.
      activation.claudeMcpServers = lib.hm.dag.entryAfter ["writeBoundary"] ''
        cj="$HOME/.claude.json"
        ${pkgs.coreutils}/bin/test -e "$cj" || echo '{}' > "$cj"
        tmp="$(${pkgs.coreutils}/bin/mktemp "$HOME/.claude.json.XXXXXX")"
        if ${pkgs.jq}/bin/jq --slurpfile m ${managedMcpServersFile} \
             '.mcpServers = ((.mcpServers // {}) + $m[0])' "$cj" > "$tmp"; then
          $DRY_RUN_CMD ${pkgs.coreutils}/bin/mv "$tmp" "$cj"
          echo "claude-mcp: merged managed MCP servers into ~/.claude.json"
        else
          ${pkgs.coreutils}/bin/rm -f "$tmp"
          echo "claude-mcp: jq merge failed; ~/.claude.json left unchanged" >&2
        fi
      '';
    };
  };
}
