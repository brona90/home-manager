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
    mcpServers = {
      porkbun = {
        command = "${porkbunMcpWrapper}/bin/porkbun-mcp";
      };
    };
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
  };
}
