{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.my.claudeCode;

  statusLineScript = pkgs.writeShellApplication {
    name = "claude-statusline";
    runtimeInputs = [pkgs.jq pkgs.git pkgs.coreutils];
    text = ''
      input=$(cat)

      user=$(whoami)
      host=$(hostname -s)
      cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd')
      model=$(echo "$input" | jq -r '.model.display_name // .model.id // "claude"')
      used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

      # Truncate cwd: collapse $HOME to ~, keep last 3 segments
      cwd_display="''${cwd/#$HOME/\~}"
      IFS='/' read -ra parts <<< "$cwd_display"
      if [ "''${#parts[@]}" -gt 4 ]; then
        cwd_display="...''${parts[-3]:+/''${parts[-3]}}''${parts[-2]:+/''${parts[-2]}}/''${parts[-1]}"
      fi

      # Git branch (skip optional locks to avoid blocking)
      branch=""
      if GIT_OPTIONAL_LOCKS=0 git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1; then
        branch=$(GIT_OPTIONAL_LOCKS=0 git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null \
          || GIT_OPTIONAL_LOCKS=0 git -C "$cwd" rev-parse --short HEAD 2>/dev/null || true)
      fi

      CYAN='\033[0;36m'
      GREEN='\033[0;32m'
      YELLOW='\033[1;33m'
      RED='\033[0;31m'
      RESET='\033[0m'

      out=""
      out+="$(printf "''${GREEN}%s@%s''${RESET}" "$user" "$host")"
      out+=" $(printf "''${CYAN}%s''${RESET}" "$cwd_display")"
      if [ -n "$branch" ]; then
        out+=" $(printf "''${YELLOW}(%s)''${RESET}" "$branch")"
      fi
      out+=" | $model"
      if [ -n "$used_pct" ]; then
        used_int=$(printf '%.0f' "$used_pct")
        if [ "$used_int" -ge 80 ]; then
          color="$RED"
        elif [ "$used_int" -ge 50 ]; then
          color="$YELLOW"
        else
          color="$GREEN"
        fi
        out+=" $(printf "🧠 ''${color}ctx:%d%%''${RESET}" "$used_int")"
      fi

      # 5-hour rate limit
      five_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
      if [ -n "$five_pct" ]; then
        five_int=$(printf '%.0f' "$five_pct")
        if [ "$five_int" -ge 80 ]; then
          color="$RED"
        elif [ "$five_int" -ge 50 ]; then
          color="$YELLOW"
        else
          color="$GREEN"
        fi
        out+=" $(printf "⚡ ''${color}5h:%d%%''${RESET}" "$five_int")"
      fi

      # 7-day rate limit
      week_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
      if [ -n "$week_pct" ]; then
        week_int=$(printf '%.0f' "$week_pct")
        if [ "$week_int" -ge 80 ]; then
          color="$RED"
        elif [ "$week_int" -ge 50 ]; then
          color="$YELLOW"
        else
          color="$GREEN"
        fi
        out+=" $(printf "📅 ''${color}7d:%d%%''${RESET}" "$week_int")"
      fi

      printf "%b\n" "$out"
    '';
  };

  settings = {
    statusLine = {
      type = "command";
      command = "${statusLineScript}/bin/claude-statusline";
    };
    enabledPlugins = {
      "lua-lsp@claude-plugins-official" = true;
      "pyright-lsp@claude-plugins-official" = true;
      "typescript-lsp@claude-plugins-official" = true;
    };
    permissions = {
      allow = [
        "Bash(gh run view *)"
        "Bash(gh run list *)"
        "Bash(gh run watch *)"
        "Bash(gh pr view *)"
        "Bash(gh pr checks *)"
        "Bash(gh api *)"
        "mcp__emacs__emacs_show_diff"
        "mcp__emacs__emacs_eval"
      ];
    };
    hooks = {
      PermissionRequest = [
        {
          matcher = "Edit|Write";
          hooks = [
            {
              type = "command";
              command = "[ -n \"\${INSIDE_EMACS:-}\" ] || exit 0; d=\${XDG_RUNTIME_DIR:-/tmp}/claude-diff && mkdir -p \"$d\" && f=$d/input.json && cat > \"$f\" && emacsclient --eval \"(claude-diff-from-hook \\\"$f\\\")\"";
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
    home.file.".claude/settings.json".text =
      builtins.toJSON settings;
  };
}
