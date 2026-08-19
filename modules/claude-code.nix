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

  porkbunMcpWrapper = pkgs.writeShellApplication {
    name = "porkbun-mcp";
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
      exec npx -y @porkbunllc/mcp-server "$@"
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
                command = "[ -n \"\${INSIDE_EMACS:-}\" ] || exit 0; d=\${XDG_RUNTIME_DIR:-/tmp}/claude-diff && mkdir -p \"$d\" && f=$d/input.json && t=$(mktemp \"$d/input.XXXXXX\") && cat > \"$t\" && mv \"$t\" \"$f\" && emacsclient --eval \"(claude-diff-from-hook \\\"$f\\\")\"";
                timeout = 10;
              }
            ];
          }
        ];
        PostToolUse = [
          {
            matcher = "Edit|Write";
            hooks = [
              {
                type = "command";
                command = "[ -n \"\${INSIDE_EMACS:-}\" ] || exit 0; emacsclient --eval '(claude-diff-dismiss)'";
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
