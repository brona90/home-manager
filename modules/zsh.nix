{ config, lib, pkgs, ... }:

let
  cfg = config.my.zsh;
in
{
  options.my.zsh = {
    enable = lib.mkEnableOption "Gregory's zsh configuration";

    extraOhMyZshPlugins = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional oh-my-zsh plugins to enable";
    };

    extraAliases = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Additional shell aliases";
    };

    extraInitExtra = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Additional zsh init commands";
    };
  };

  config = lib.mkIf cfg.enable {
    programs = {
      zsh = {
        enable = true;
        enableCompletion = true;
        dotDir = "${config.xdg.configHome}/zsh";

        shellAliases = {
          df = "df -h";
          du = "du -h -d 2";
          ll = "ls -alh --color=auto";
          ls = "ls --color=auto";
          ":q" = "exit";
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
          less = "less -r";
          tf = "tail -f";
          l = "less";
          lh = "ls -alt | head";
          screen = "TERM=screen screen";
          cl = "clear";
          gz = "tar -zcvf";
          ka9 = "killall -9";
          k9 = "kill -9";
          nrs = ''sudo nixos-rebuild switch --flake "$HOME/.config/home-manager"'';
          nfu = "nix flake update";
          vim = "lvim";
          vi = "lvim";
        } // cfg.extraAliases;

        oh-my-zsh = {
          enable = true;
          plugins = [ "git" "z" "direnv" ] ++ cfg.extraOhMyZshPlugins;
          extraConfig = ''
            zstyle ':omz:update' mode auto
            ENABLE_CORRECTION="true"
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
          setopt extendedglob
          bindkey -v
          export KEYTIMEOUT=1

          typeset -g HISTORY_SUBSTRING_SEARCH_HIGHLIGHT_FOUND='bg=green,fg=white,bold'
          typeset -g HISTORY_SUBSTRING_SEARCH_HIGHLIGHT_NOT_FOUND='bg=red,fg=white,bold'
          typeset -g HISTORY_SUBSTRING_SEARCH_FUZZY=1
          typeset -g HISTORY_SUBSTRING_SEARCH_ENSURE_UNIQUE=1

          bindkey '^[[A' history-substring-search-up
          bindkey '^[[B' history-substring-search-down
          bindkey '^[OA' history-substring-search-up
          bindkey '^[OB' history-substring-search-down

          bindkey -M viins '^[[A' history-substring-search-up
          bindkey -M viins '^[[B' history-substring-search-down
          bindkey -M viins '^[OA' history-substring-search-up
          bindkey -M viins '^[OB' history-substring-search-down
          bindkey -M viins '^P' history-substring-search-up
          bindkey -M viins '^N' history-substring-search-down

          bindkey -M vicmd 'k' history-substring-search-up
          bindkey -M vicmd 'j' history-substring-search-down
          bindkey -M vicmd '^[[A' history-substring-search-up
          bindkey -M vicmd '^[[B' history-substring-search-down
          bindkey -M vicmd '^[OA' history-substring-search-up
          bindkey -M vicmd '^[OB' history-substring-search-down

          ${cfg.extraInitExtra}
        '';

        history = {
          path = "$HOME/.zsh_history";
          size = 10000;
          save = 10000;
        };
      };

      starship = {
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
          nix_shell.format = "via [$symbol$state]($style) ";
        };
      };

      mise = {
        enable = true;
        enableZshIntegration = true;
      };

      direnv = {
        enable = true;
        nix-direnv.enable = true;
      };
    };
  };
}
