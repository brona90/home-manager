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
          # Basic
          df = "df -h";
          du = "du -h -d 2";
          ll = "ls -alh --color=auto";
          ls = "ls --color=auto";
          ":q" = "exit";
          less = "less -r";
          tf = "tail -f";
          l = "less";
          lh = "ls -alt | head";
          screen = "TERM=screen screen";
          cl = "clear";
          gz = "tar -zcvf";
          ka9 = "killall -9";
          k9 = "kill -9";

          # Git (g = git)
          gs = "git status";
          gco = "git checkout";
          ga = "git add -A";
          gm = "git merge";
          gr = "git remote -v";
          gl = "git log --graph --format='%C(yellow)%h%Creset %s %C(cyan)<%ae>%Creset %C(green)(%cr)%Creset%C(auto)%d%Creset'";
          gla = "git log --graph --all --format='%C(yellow)%h%Creset %s %C(cyan)<%ae>%Creset %C(green)(%cr)%Creset%C(auto)%d%Creset'";
          gf = "git fetch";
          gd = "git diff";
          gb = "git branch";
          gpl = "git pull";
          gnb = "git checkout -b";

          # Nix (n = nix)
          nfu = "nix flake update";
          nrs = ''sudo nixos-rebuild switch --flake "$HOME/.config/home-manager"'';
          # Nix cleanup (nc = nix clean/collect)
          ncg = "nix-collect-garbage";                          # basic garbage collection
          ncgd = "nix-collect-garbage -d";                      # delete old generations + gc
          nco = "nix store optimise";                           # deduplicate store
          nsc = "nix-collect-garbage -d && nix store optimise"; # store clean (full cleanup)

          # Docker (d = docker)
          dps = "docker ps";
          dpsa = "docker ps -a";
          di = "docker images";
          # Docker cleanup (dc = docker clean)
          dcp = "docker system prune -f";                       # prune unused
          dcpa = "docker system prune -af";                     # prune all unused images
          dcpv = "docker volume prune -f";                      # prune volumes
          dcpb = "docker builder prune -f";                     # prune build cache
          dca = "docker system prune -af --volumes && docker builder prune -af";  # clean all

          # Editors
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

          # Dev disk usage - pretty print disk usage for dev tools
          dev-disk() {
            local blue='\033[0;34m'
            local green='\033[0;32m'
            local yellow='\033[1;33m'
            local red='\033[0;31m'
            local nc='\033[0m'
            local bold='\033[1m'

            echo ""
            echo "''${bold}📦 Development Tools Disk Usage''${nc}"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo ""

            # Nix store
            if [ -d /nix/store ]; then
              local nix_size=$(du -sh /nix/store 2>/dev/null | cut -f1)
              local nix_paths=$(ls /nix/store 2>/dev/null | wc -l | tr -d ' ')
              echo "''${blue}❄  Nix Store''${nc}"
              echo "   Size:  ''${bold}$nix_size''${nc}"
              echo "   Paths: $nix_paths"
              echo ""
            fi

            # Home Manager generations
            if [ -d ~/.local/state/nix/profiles ]; then
              local hm_gens=$(ls ~/.local/state/nix/profiles/home-manager-*-link 2>/dev/null | wc -l | tr -d ' ')
              echo "''${green}🏠 Home Manager''${nc}"
              echo "   Generations: $hm_gens"
              echo ""
            fi

            # Docker
            if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
              echo "''${yellow}🐳 Docker''${nc}"
              docker system df 2>/dev/null | tail -n +2 | while read line; do
                echo "   $line"
              done
              echo ""
            fi

            # Mise (runtime versions)
            if [ -d ~/.local/share/mise/installs ]; then
              local mise_size=$(du -sh ~/.local/share/mise/installs 2>/dev/null | cut -f1)
              local mise_runtimes=$(ls ~/.local/share/mise/installs 2>/dev/null | wc -l | tr -d ' ')
              echo "''${red}🔧 Mise Runtimes''${nc}"
              echo "   Size:     ''${bold}$mise_size''${nc}"
              echo "   Runtimes: $mise_runtimes"
              if [ -d ~/.local/share/mise/installs ]; then
                for rt in ~/.local/share/mise/installs/*/; do
                  if [ -d "$rt" ]; then
                    local rt_name=$(basename "$rt")
                    local rt_vers=$(ls "$rt" 2>/dev/null | wc -l | tr -d ' ')
                    echo "   - $rt_name: $rt_vers versions"
                  fi
                done
              fi
              echo ""
            fi

            # Doom Emacs
            if [ -d ~/.local/share/nix-doom ]; then
              local doom_size=$(du -sh ~/.local/share/nix-doom 2>/dev/null | cut -f1)
              echo "''${blue}👿 Doom Emacs''${nc}"
              echo "   Size: ''${bold}$doom_size''${nc}"
              echo ""
            fi

            # Neovim/LazyVim
            if [ -d ~/.local/share/nvim ]; then
              local nvim_size=$(du -sh ~/.local/share/nvim 2>/dev/null | cut -f1)
              echo "''${green}📝 Neovim/LazyVim''${nc}"
              echo "   Size: ''${bold}$nvim_size''${nc}"
              echo ""
            fi

            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "''${bold}Cleanup commands:''${nc}"
            echo "  nsc   - Nix store clean (gc + optimise)"
            echo "  dca   - Docker clean all"
            echo ""
          }

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
