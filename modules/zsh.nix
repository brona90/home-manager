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
        dotDir = ".config/zsh";

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

          # Mise (m = mise)
          mcp = "mise prune -y";                                # prune unused versions
          mcc = "mise cache clear";                             # clear download cache
          mca = "mise prune -y && mise cache clear";            # clean all mise

          # Neovim/LazyVim (v = vim)
          vcc = "rm -rf ~/.local/share/nvim ~/.local/state/nvim ~/.cache/nvim"; # vim cache clean

          # General cache
          ccc = "rm -rf ~/.cache/*";                            # cache clean (careful!)

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
            _dev-disk-inner | less -R
          }

          _dev-disk-inner() {
            local blue='\033[0;34m'
            local green='\033[0;32m'
            local yellow='\033[1;33m'
            local red='\033[0;31m'
            local cyan='\033[0;36m'
            local magenta='\033[0;35m'
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
              echo "   Clean: ''${cyan}nsc''${nc}"
              echo ""
            fi

            # Home Manager generations
            if [ -d ~/.local/state/nix/profiles ]; then
              local hm_gens=$(ls ~/.local/state/nix/profiles/home-manager-*-link 2>/dev/null | wc -l | tr -d ' ')
              echo "''${green}🏠 Home Manager''${nc}"
              echo "   Generations: $hm_gens"
              echo "   Clean: ''${cyan}ncgd''${nc} (deletes old generations)"
              echo ""
            fi

            # Docker
            if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
              echo "''${yellow}🐳 Docker''${nc}"
              docker system df 2>/dev/null | tail -n +2 | while read line; do
                echo "   $line"
              done
              echo "   Clean: ''${cyan}dca''${nc}"
              echo ""
            fi

            # Mise (runtime versions)
            if [ -d ~/.local/share/mise ]; then
              local mise_install_size=$(du -sh ~/.local/share/mise/installs 2>/dev/null | cut -f1 || echo "0")
              local mise_cache_size=$(du -sh ~/.local/share/mise/cache 2>/dev/null | cut -f1 || echo "0")
              local mise_runtimes=$(ls ~/.local/share/mise/installs 2>/dev/null | wc -l | tr -d ' ')
              echo "''${red}🔧 Mise''${nc}"
              echo "   Installs: ''${bold}$mise_install_size''${nc} ($mise_runtimes runtimes)"
              echo "   Cache:    $mise_cache_size"
              if [ -d ~/.local/share/mise/installs ]; then
                for rt in ~/.local/share/mise/installs/*/; do
                  if [ -d "$rt" ]; then
                    local rt_name=$(basename "$rt")
                    local rt_vers=$(ls "$rt" 2>/dev/null | wc -l | tr -d ' ')
                    local rt_size=$(du -sh "$rt" 2>/dev/null | cut -f1)
                    echo "   - $rt_name: $rt_vers versions ($rt_size)"
                  fi
                done
              fi
              echo "   Clean: ''${cyan}mca''${nc}"
              echo ""
            fi

            # Doom Emacs
            if [ -d ~/.local/share/nix-doom ]; then
              local doom_size=$(du -sh ~/.local/share/nix-doom 2>/dev/null | cut -f1)
              echo "''${magenta}👿 Doom Emacs''${nc}"
              echo "   Size: ''${bold}$doom_size''${nc}"
              echo ""
            fi

            # Neovim/LazyVim
            local nvim_total=0
            if [ -d ~/.local/share/nvim ] || [ -d ~/.local/state/nvim ] || [ -d ~/.cache/nvim ]; then
              local nvim_data=$(du -sh ~/.local/share/nvim 2>/dev/null | cut -f1 || echo "0")
              local nvim_state=$(du -sh ~/.local/state/nvim 2>/dev/null | cut -f1 || echo "0")
              local nvim_cache=$(du -sh ~/.cache/nvim 2>/dev/null | cut -f1 || echo "0")
              echo "''${green}📝 Neovim/LazyVim''${nc}"
              echo "   Data:  $nvim_data"
              echo "   State: $nvim_state"
              echo "   Cache: $nvim_cache"
              echo "   Clean: ''${cyan}vcc''${nc}"
              echo ""
            fi

            # Cachix
            if command -v cachix &>/dev/null; then
              echo "''${cyan}☁️  Cachix Cache''${nc}"
              if [ -f ~/.config/cachix/cachix.dhall ]; then
                echo "   Auth: ''${green}Authenticated''${nc}"
              else
                echo "   Auth: ''${yellow}Not authenticated''${nc} (run ''${cyan}cachix-auth''${nc})"
              fi
              # Check if cache is configured in nix.conf
              if grep -q "gfoster.cachix.org" ~/.config/nix/nix.conf 2>/dev/null; then
                echo "   Substituter: ''${green}Configured''${nc}"
              else
                echo "   Substituter: ''${yellow}Not configured''${nc} (run ''${cyan}cachix use gfoster''${nc})"
              fi
              # Try to get cache size from API (requires auth)
              if [ -f ~/.config/cachix/cachix.dhall ]; then
                local cache_info
                cache_info=$(curl -s "https://app.cachix.org/api/v1/cache/gfoster" 2>/dev/null)
                if [ -n "$cache_info" ]; then
                  local cache_size
                  cache_size=$(echo "$cache_info" | grep -oP '"size":\s*\K[0-9]+' 2>/dev/null || echo "")
                  if [ -n "$cache_size" ]; then
                    # Convert bytes to human readable
                    local human_size
                    human_size=$(numfmt --to=iec-i --suffix=B "$cache_size" 2>/dev/null || echo "$cache_size bytes")
                    echo "   Size: ''${bold}$human_size''${nc}"
                  fi
                fi
              fi
              echo "   Push: ''${cyan}cachix push gfoster ./result''${nc}"
              echo "   Clean: Set retention at ''${cyan}https://app.cachix.org/cache/gfoster''${nc} (Settings tab)"
              echo ""
            fi

            # General cache
            if [ -d ~/.cache ]; then
              local cache_size=$(du -sh ~/.cache 2>/dev/null | cut -f1)
              echo "''${cyan}💾 General Cache (~/.cache)''${nc}"
              echo "   Size: ''${bold}$cache_size''${nc}"
              echo "   Clean: ''${cyan}ccc''${nc} (careful!)"
              echo ""
            fi

            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "''${bold}Quick cleanup commands:''${nc}"
            echo "  nsc  - Nix store clean (gc + optimise)"
            echo "  dca  - Docker clean all"
            echo "  mca  - Mise clean all (prune + cache)"
            echo "  vcc  - Neovim cache clean"
            echo "  ccc  - Clear ~/.cache (careful!)"
            echo ""
            echo "''${bold}Full cleanup:''${nc}"
            echo "  dev-clean  - Interactive cleanup of everything"
            echo ""
          }

          # Interactive full cleanup
          dev-clean() {
            local blue='\033[0;34m'
            local green='\033[0;32m'
            local yellow='\033[1;33m'
            local red='\033[0;31m'
            local nc='\033[0m'
            local bold='\033[1m'

            echo ""
            echo "''${bold}🧹 Development Environment Cleanup''${nc}"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo ""

            # Nix
            echo -n "''${blue}❄  Clean Nix store?''${nc} (nix-collect-garbage -d && nix store optimise) [y/N] "
            read -r yn
            if [[ "$yn" =~ ^[Yy]$ ]]; then
              echo "   Running nix-collect-garbage -d..."
              nix-collect-garbage -d
              echo "   Running nix store optimise..."
              nix store optimise
              echo "   ''${green}✓ Done''${nc}"
            fi
            echo ""

            # Docker
            if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
              echo -n "''${yellow}🐳 Clean Docker?''${nc} (system prune + volumes + builder) [y/N] "
              read -r yn
              if [[ "$yn" =~ ^[Yy]$ ]]; then
                docker system prune -af --volumes
                docker builder prune -af
                echo "   ''${green}✓ Done''${nc}"
              fi
              echo ""
            fi

            # Mise
            if command -v mise &>/dev/null; then
              echo -n "''${red}🔧 Clean Mise?''${nc} (prune unused + clear cache) [y/N] "
              read -r yn
              if [[ "$yn" =~ ^[Yy]$ ]]; then
                mise prune -y
                mise cache clear
                echo "   ''${green}✓ Done''${nc}"
              fi
              echo ""
            fi

            # Neovim
            if [ -d ~/.local/share/nvim ] || [ -d ~/.cache/nvim ]; then
              echo -n "''${green}📝 Clean Neovim/LazyVim cache?''${nc} [y/N] "
              read -r yn
              if [[ "$yn" =~ ^[Yy]$ ]]; then
                rm -rf ~/.local/share/nvim ~/.local/state/nvim ~/.cache/nvim
                echo "   ''${green}✓ Done''${nc} (plugins will reinstall on next launch)"
              fi
              echo ""
            fi

            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "''${green}✓ Cleanup complete!''${nc}"
            echo ""
            echo "Run ''${bold}dev-disk''${nc} to see current usage."
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

    # Force overwrite files that may exist from manual configuration
    home.file.".zshenv".force = true;
  };
}
