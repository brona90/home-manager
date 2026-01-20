{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modules.zsh;
in
{
  options.modules.zsh = {
    enable = mkEnableOption "Gregory's zsh configuration";

    extraOhMyZshPlugins = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Additional oh-my-zsh plugins to enable";
      example = [ "docker" "kubectl" ];
    };

    extraAliases = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "Additional shell aliases";
    };

    extraInitContent = mkOption {
      type = types.lines;
      default = "";
      description = "Additional zsh init content";
    };
  };

  config = mkIf cfg.enable {
    programs.zsh = {
      enable = true;
      enableCompletion = true;

      shellAliases = {
        # Human friendly numbers and colors
        df = "df -h";
        du = "du -h -d 2";
        ll = "ls -alh --color=auto";

        # Mimic vim functions
        ":q" = "exit";

        # Git Aliases
        gs = "git status";
        gco = "git checkout";
        ga = "git add -A";
        gm = "git merge";
        gr = "git remote -v";
        gl = "git log --oneline --graph";
        gf = "git fetch";
        gd = "git diff";
        gb = "git branch";
        gpl = "git pull";
        gnb = "git checkout -b";

        # Common shell functions
        less = "less -r";
        tf = "tail -f";
        l = "less";
        lh = "ls -alt | head";
        screen = "TERM=screen screen";
        cl = "clear";

        # Tar
        gz = "tar -zcvf";

        # Kill aliases
        ka9 = "killall -9";
        k9 = "kill -9";

        # Nix/Home-manager shortcuts
        nfu = "nix flake update";
        vim = "lvim";
        vi = "lvim";
      } // cfg.extraAliases;

      oh-my-zsh = {
        enable = true;
        plugins = [
          "git"
          "z"
          "direnv"
        ] ++ cfg.extraOhMyZshPlugins;
        extraConfig = ''
          # Update settings
          zstyle ':omz:update' mode auto

          # Enable command auto-correction
          ENABLE_CORRECTION="true"

          # Completion waiting dots
          COMPLETION_WAITING_DOTS="true"
        '';
      };

      plugins = [
        {
          name = "zsh-syntax-highlighting";
          src = pkgs.zsh-syntax-highlighting;
          file = "share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh";
        }
        {
          name = "zsh-history-substring-search";
          src = pkgs.zsh-history-substring-search;
          file = "share/zsh-history-substring-search/zsh-history-substring-search.zsh";
        }
      ];

      initContent = ''
        # Enable vi mode
        bindkey -v
        export KEYTIMEOUT=1

        # History substring search highlighting
        # Use typeset -g to ensure these are global and visible to the plugin
        typeset -g HISTORY_SUBSTRING_SEARCH_HIGHLIGHT_FOUND='bg=green,fg=white,bold'
        typeset -g HISTORY_SUBSTRING_SEARCH_HIGHLIGHT_NOT_FOUND='bg=red,fg=white,bold'
        typeset -g HISTORY_SUBSTRING_SEARCH_FUZZY=1
        typeset -g HISTORY_SUBSTRING_SEARCH_ENSURE_UNIQUE=1

        # History substring search keybindings
        # Arrow keys
        bindkey '^[[A' history-substring-search-up
        bindkey '^[[B' history-substring-search-down
        # Vi mode k/j
        bindkey -M vicmd 'k' history-substring-search-up
        bindkey -M vicmd 'j' history-substring-search-down
        # Also bind for vi insert mode (Ctrl+P/N)
        bindkey -M viins '^P' history-substring-search-up
        bindkey -M viins '^N' history-substring-search-down

        # Environment variables
        export EDITOR='emacs -nw'

        ${cfg.extraInitContent}
      '';

      sessionVariables = {
        EDITOR = "emacs -nw";
      };
    };

    programs.starship = {
      enable = true;
      settings = {
        add_newline = true;
        character = {
          success_symbol = "[>](bold green)";
          error_symbol = "[>](bold red)";
          vimcmd_symbol = "[<](bold green)";
          vimcmd_replace_one_symbol = "[<](bold purple)";
          vimcmd_replace_symbol = "[<](bold purple)";
          vimcmd_visual_symbol = "[<](bold yellow)";
        };
        directory = {
          truncation_length = 3;
          truncate_to_repo = true;
        };
        git_status = {
          ahead = "⇡\${count}";
          diverged = "⇕⇡\${ahead_count}⇣\${behind_count}";
          behind = "⇣\${count}";
        };
        nix_shell = {
          format = "via [$symbol$state]($style) ";
        };
      };
    };

    programs.mise = {
      enable = true;
      enableZshIntegration = true;
    };

    programs.direnv = {
      enable = true;
      nix-direnv.enable = true;
    };
  };
}
