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

  # uv runs the PEP-723 self-contained MCP servers under ~/claude-kg and ~/searxng.
  uv = "${config.home.homeDirectory}/.local/bin/uv";

  # MCP servers Claude Code should load at USER scope. Claude reads these only from
  # ~/.claude.json — never from settings.json — and that file is a mutable runtime
  # store we can't own with home.file. So an activation script (below) merges this
  # set into ~/.claude.json on every switch, which also refreshes Nix-store command
  # paths (porkbun) on each rebuild.
  managedMcpServers = {
    # Local knowledge-graph shared memory (Qdrant + local Ollama embeddings).
    claude-kg = {
      type = "stdio";
      command = uv;
      args = ["run" "--quiet" "${config.home.homeDirectory}/claude-kg/kg_server.py"];
    };
    # Private web search via a local SearXNG instance.
    searxng = {
      type = "stdio";
      command = uv;
      args = ["run" "--quiet" "${config.home.homeDirectory}/searxng/search_server.py"];
      env = {SEARXNG_URL = "http://localhost:8888";};
    };
    # Emacs integration; binary from the user nix profile (stable path across rebuilds).
    emacs = {
      type = "stdio";
      command = "${config.home.homeDirectory}/.nix-profile/bin/emacs-mcp-server";
    };
    # Porkbun DNS. API credential setup is a later task; the server command is wired now.
    porkbun = {
      type = "stdio";
      command = "${porkbunMcpWrapper}/bin/porkbun-mcp";
    };
  };
  managedMcpServersFile =
    pkgs.writeText "claude-mcp-servers.json" (builtins.toJSON managedMcpServers);

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
      "lua-lsp@${marketplace}" = true;
      "pyright-lsp@${marketplace}" = true;
      "typescript-lsp@${marketplace}" = true;
    };
    # MCP servers are NOT configured here — Claude Code ignores `mcpServers` in
    # settings.json. They are merged into ~/.claude.json by the claudeMcpServers
    # activation script (see managedMcpServers above).
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
    hooks = {
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
      # At session end, distill durable facts from the transcript into the
      # claude-kg knowledge graph (local Ollama backend by default; free, no agent).
      SessionEnd = [
        {
          hooks = [
            {
              type = "command";
              command = "${config.home.homeDirectory}/claude-kg/hooks/capture_memory.sh";
              timeout = 15;
            }
          ];
        }
      ];
    };
  };
in {
  options.my.claudeCode = {
    enable = lib.mkEnableOption "Claude Code settings and hooks";
  };

  config = lib.mkIf cfg.enable {
    # The module that enables Claude Code also owns the CLI package
    # (previously duplicated in home/linux.nix and home/darwin.nix).
    home.packages = [pkgs.claude-code];

    home.file.".claude/settings.json".text =
      builtins.toJSON settings;

    # Claude Code loads user-scope MCP servers only from ~/.claude.json (a mutable
    # runtime file), so we merge our managed set into it on activation instead of
    # owning the file. Unmanaged servers already present are preserved; ours win on
    # key conflict. Writes atomically via a temp file.
    home.activation.claudeMcpServers = lib.hm.dag.entryAfter ["writeBoundary"] ''
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
}
