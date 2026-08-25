{
  config,
  lib,
  pkgs,
  userConfig,
  ...
}: let
  cfg = config.my.zsh;
  inherit (userConfig.repo) cachixCache;
in {
  options.my.zsh = {
    enable = lib.mkEnableOption "zsh configuration with oh-my-zsh, starship, and mise";

    extraOhMyZshPlugins = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Additional oh-my-zsh plugins to enable";
    };

    extraAliases = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
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

        shellAliases =
          {
            # Basic
            df = "df -h";
            du = "du -h -d 2";
            ll = "ls -alh --color=auto";
            ls = "ls --color=auto";
            ":q" = "exit";
            less = "less -R";
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
            # Nix cleanup (nc = nix clean/collect)
            ncg = "nix-collect-garbage"; # basic garbage collection
            ncgd = "nix-collect-garbage -d"; # delete old generations + gc
            nco = "nix store optimise"; # deduplicate store
            nsc = "nix-collect-garbage -d && nix store optimise"; # store clean (full cleanup)

            # Docker (d = docker)
            dps = "docker ps";
            dpsa = "docker ps -a";
            di = "docker images";
            # Docker cleanup (dc = docker clean)
            dcp = "docker system prune -f"; # prune unused
            dcpa = "docker system prune -af"; # prune all unused images
            dcpv = "docker volume prune -f"; # prune volumes
            dcpb = "docker builder prune -f"; # prune build cache
            dca = "docker system prune -af --volumes && docker builder prune -af"; # clean all

            # Mise (m = mise)
            mcp = "mise prune -y"; # prune unused versions
            mcc = "mise cache clear"; # clear download cache
            mca = "mise prune -y && mise cache clear"; # clean all mise

            # Neovim/LazyVim (v = vim)
            vcc = "rm -rf ~/.local/share/nvim ~/.local/state/nvim ~/.cache/nvim"; # vim cache clean

            # General cache
            ccc = "rm -rf ~/.cache/*"; # cache clean (careful!)

            # WSL interop aliases (clip, explorer, cmd, powershell, notepad,
            # nrs) live in home/linux.nix, gated to the WSL machine.
          }
          # Editors -- only when the Nix-managed LazyVim wrapper exists
          // lib.optionalAttrs config.my.vim.enable {
            vim = "lvim";
            vi = "lvim";
          }
          // cfg.extraAliases;

        oh-my-zsh = {
          enable = true;
          plugins = ["git" "z"] ++ cfg.extraOhMyZshPlugins;
          extraConfig = ''
            # oh-my-zsh comes from the read-only Nix store; self-update can
            # never succeed, so disable it instead of letting it no-op.
            zstyle ':omz:update' mode disabled
            ENABLE_CORRECTION="true"
            COMPLETION_WAITING_DOTS="true"
          '';
        };

        plugins = [
          {
            name = "zsh-fast-syntax-highlighting";
            src = pkgs.zsh-fast-syntax-highlighting;
            file = "share/zsh/plugins/fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh";
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

          # Size of a path, in human units.
          # Uses `command du` deliberately: the interactive `du` alias adds
          # `-d 2`, which conflicts with `-s` and makes du exit without
          # printing anything. Bounded by a timeout so one slow path cannot
          # stall the whole report.
          _dd_size() {
            # printf, never echo: zsh's echo eats a lone "-" as an option
            # terminator and prints an empty line instead.
            local target="$1" limit="$2" out cache cache_dir key now cached_at age
            [ -n "$limit" ] || limit=8
            [ -e "$target" ] || { printf '%s\n' "-"; return 0; }

            cache_dir="$HOME/.cache/dev-disk"
            key=$(printf '%s' "$target" | command tr -c 'A-Za-z0-9' '_')
            cache="$cache_dir/$key"
            command mkdir -p "$cache_dir" 2>/dev/null

            # Fast path: measure directly if it fits in the budget.
            out=$(command timeout "$limit" du -shx "$target" 2>/dev/null | command cut -f1)
            if [ -n "$out" ]; then
              printf '%s' "$out" > "$cache" 2>/dev/null
              command rm -f "$cache.tmp" 2>/dev/null
              printf '%s\n' "$out"
              return 0
            fi

            # Too slow to measure inline. Serve the last known value and
            # refresh out of band.
            now=$(command date +%s)
            cached_at=0
            [ -f "$cache" ] && cached_at=$(command stat -c %Y "$cache" 2>/dev/null || echo 0)
            age=$(( now - cached_at ))

            # Refresh at most one du per target: with a cold cache, an
            # unguarded branch spawns another walk over the same tree on every
            # invocation and they pile up. The guard asks "is a du for this
            # target actually alive?" rather than using a .tmp sentinel, which
            # goes stale if its du is killed and wedges the target on
            # "measuring…" until the file ages out.
            if [ "$age" -gt 3600 ] && ! command pgrep -f "du -shx $target" >/dev/null 2>&1; then
              # The fd redirections are load-bearing, not tidiness: this runs
              # inside a $(...), and command substitution waits for every
              # process holding the pipe open - a backgrounded job included.
              # Without them the caller blocks on the very du walk this cache
              # exists to avoid.
              ( command du -shx "$target" 2>/dev/null | command cut -f1 > "$cache.tmp" \
                  && command mv "$cache.tmp" "$cache" ) >/dev/null 2>&1 </dev/null &!
            fi

            if [ -s "$cache" ]; then
              printf '%s' "$(command cat "$cache")"
              if [ "$age" -gt 3600 ]; then
                printf ' [%dh old, refreshing…]' "$(( age / 3600 ))"
              else
                printf ' [cached]'
              fi
              printf '\n'
            else
              printf '%s\n' "measuring in background…"
            fi
          }

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

            # All locals are declared once, here. Re-declaring an existing
            # local mid-function makes zsh echo `name=value` to stdout, which
            # is what leaked `rt_name=claude` / empty `cache_size` into the report.
            local nix_size nix_paths hm_gens
            local mise_install_size mise_cache_size mise_runtimes
            local rt rt_name rt_vers rt_size
            local nvim_data nvim_state nvim_cache
            local vemacs_config vemacs_cache vemacs_state
            local cache_info cache_size human_size general_cache_size

            echo ""
            echo "''${bold}📦 Development Tools Disk Usage''${nc}"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo ""

            # Nix store
            if [ -d /nix/store ]; then
              nix_size=$(_dd_size /nix/store 5)
              nix_paths=$(command ls /nix/store 2>/dev/null | command wc -l | tr -d ' ')
              echo "''${blue}❄  Nix Store''${nc}"
              echo "   Size:  ''${bold}$nix_size''${nc}"
              echo "   Paths: $nix_paths"
              echo "   Clean: ''${cyan}nsc''${nc}"
              echo ""
            fi

            # Home Manager generations
            if [ -d ~/.local/state/nix/profiles ]; then
              hm_gens=$(command ls -d ~/.local/state/nix/profiles/home-manager-*-link 2>/dev/null | command wc -l | tr -d ' ')
              echo "''${green}🏠 Home Manager''${nc}"
              echo "   Generations: $hm_gens"
              echo "   Clean: ''${cyan}ncgd''${nc} (deletes old generations)"
              echo ""
            fi

            # Docker
            if command -v docker &>/dev/null && docker info &>/dev/null; then
              echo "''${yellow}🐳 Docker''${nc}"
              docker system df 2>/dev/null | tail -n +2 | while IFS= read -r line; do
                echo "   $line"
              done
              echo "   Clean: ''${cyan}dca''${nc}"
              echo ""
            fi

            # Mise (runtime versions)
            if [ -d ~/.local/share/mise ]; then
              mise_install_size=$(_dd_size ~/.local/share/mise/installs)
              mise_cache_size=$(_dd_size ~/.local/share/mise/cache)
              mise_runtimes=$(command ls ~/.local/share/mise/installs 2>/dev/null | command wc -l | tr -d ' ')
              echo "''${red}🔧 Mise''${nc}"
              echo "   Installs: ''${bold}$mise_install_size''${nc} ($mise_runtimes runtimes)"
              echo "   Cache:    $mise_cache_size"
              if [ -d ~/.local/share/mise/installs ]; then
                for rt in ~/.local/share/mise/installs/*/; do
                  if [ -d "$rt" ]; then
                    rt_name=$(basename "$rt")
                    rt_vers=$(command ls "$rt" 2>/dev/null | command wc -l | tr -d ' ')
                    rt_size=$(_dd_size "$rt" 5)
                    echo "   - $rt_name: $rt_vers versions ($rt_size)"
                  fi
                done
              fi
              echo "   Clean: ''${cyan}mca''${nc}"
              echo ""
            fi

            # Emacs. There used to be a second block above this one for
            # ~/.local/share/nix-doom; it went with Doom. NOTE for anyone
            # wondering where the space went on a machine that has not been
            # cleaned since: that directory is not removed by `hms`, and
            # deleting it is a manual step -- see docs/doom-retirement.md.
            #
            # The .el files under ~/.config/emacs are store symlinks and cost
            # nothing; the caches beside them are real and do grow, eln-cache
            # in particular. Config is measured anyway: on a machine that has
            # not switched in a long time that path may still be the multi-GB
            # pre-Nix doomemacs checkout, which is exactly what wants seeing.
            # Such a tree also blows the inline du budget in _dd_size, so the
            # first run prints the background-measure message instead of a
            # number -- that is the helper working, not this block failing.
            if [ -d ~/.config/emacs ] || [ -d ~/.cache/emacs ] || [ -d ~/.local/state/emacs ]; then
              vemacs_config=$(_dd_size ~/.config/emacs)
              vemacs_cache=$(_dd_size ~/.cache/emacs)
              vemacs_state=$(_dd_size ~/.local/state/emacs)
              echo "''${magenta}🪶 Emacs''${nc}"
              echo "   Config: $vemacs_config"
              echo "   Cache:  ''${bold}$vemacs_cache''${nc}"
              echo "   State:  $vemacs_state"
              echo ""
            fi

            # Neovim/LazyVim
            if [ -d ~/.local/share/nvim ] || [ -d ~/.local/state/nvim ] || [ -d ~/.cache/nvim ]; then
              nvim_data=$(_dd_size ~/.local/share/nvim)
              nvim_state=$(_dd_size ~/.local/state/nvim)
              nvim_cache=$(_dd_size ~/.cache/nvim)
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
              if command grep -qF "${cachixCache}.cachix.org" ~/.config/nix/nix.conf 2>/dev/null; then
                echo "   Substituter: ''${green}Configured''${nc}"
              else
                echo "   Substituter: ''${yellow}Not configured''${nc} (run ''${cyan}cachix use ${cachixCache}''${nc})"
              fi
              # Try to get cache size from API (requires auth)
              if [ -f ~/.config/cachix/cachix.dhall ]; then
                cache_info=$(curl -s --max-time 5 "https://app.cachix.org/api/v1/cache/${cachixCache}" 2>/dev/null)
                if [ -n "$cache_info" ]; then
                  cache_size=$(echo "$cache_info" | jq -r '.size // empty' 2>/dev/null || echo "")
                  if [ -n "$cache_size" ]; then
                    # Convert bytes to human-readable (numfmt is GNU-only; awk is portable)
                    if command -v numfmt &>/dev/null; then
                      human_size=$(numfmt --to=iec-i --suffix=B "$cache_size" 2>/dev/null || echo "''${cache_size}B")
                    else
                      human_size=$(awk -v b="$cache_size" 'BEGIN{
                        if(b<1024) printf "%dB",b
                        else if(b<1048576) printf "%.1fKiB",b/1024
                        else if(b<1073741824) printf "%.1fMiB",b/1048576
                        else printf "%.1fGiB",b/1073741824
                      }')
                    fi
                    echo "   Size: ''${bold}$human_size''${nc}"
                  fi
                fi
              fi
              echo "   Push: ''${cyan}cachix push ${cachixCache} ./result''${nc}"
              echo "   Clean: Set retention at ''${cyan}https://app.cachix.org/cache/${cachixCache}''${nc} (Settings tab)"
              echo ""
            fi

            # General cache
            if [ -d ~/.cache ]; then
              general_cache_size=$(_dd_size ~/.cache 8)
              echo "''${cyan}💾 General Cache (~/.cache)''${nc}"
              echo "   Size: ''${bold}$general_cache_size''${nc}"
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
            if command -v docker &>/dev/null && docker info &>/dev/null; then
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

        # Drop /mnt/c entirely from interactive PATH. Each /mnt/c entry
        # costs a 9P-bridge stat() per command-name lookup, and zsh-fast-
        # syntax-highlighting probes the command hash on every keystroke
        # -- so even the few "kept" entries from the previous trim caused
        # per-keystroke typing lag. The .exes actually invoked from zsh
        # are surfaced via shellAliases above (clip, explorer, cmd,
        # powershell, notepad). Anything else can be run by absolute path
        # or aliased on demand.
        #
        # On Darwin, also re-source nix-daemon.sh from .zshenv. macOS
        # system updates periodically reset /etc/zshrc and /etc/zprofile,
        # wiping the nix-daemon sourcing the installer added there. The
        # nix-daemon script self-guards via __ETC_PROFILE_NIX_SOURCED, so
        # this is safe even when /etc/zshrc is intact.
        envExtra =
          ''
            path=( ''${path:#/mnt/c/*} )
          ''
          + lib.optionalString pkgs.stdenv.hostPlatform.isDarwin ''
            if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
              . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
            fi
          '';

        history = {
          path = "${config.xdg.stateHome}/zsh/history";
          size = 10000;
          save = 10000;
        };
      };

      starship = {
        enable = true;
        settings = {
          command_timeout = 500;
          scan_timeout = 10000;
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
        # Integration off because mise itself is uniquely slow on this WSL
        # host: profiled 2026-04-29, mise --version takes 4-7s and hook-env
        # takes 5s even with empty config. Other Nix-installed binaries
        # (gh 357ms, starship 74ms, ls 25ms) are fast, so it's mise-specific
        # not WSL-wide. MISE_DISABLE_DEFAULT_REGISTRIES helped --version
        # (4.7s -> 0.17s) but didn't help hook-env -- the per-prompt cost
        # is in mise's toolset diff logic, not configurable.
        # Strategy: globally-needed tools (node, python, gh, gcloud) live
        # in home.packages from nixpkgs (zero overhead). Mise stays as a
        # CLI for per-project version pinning via .mise.toml in repos,
        # activated through direnv's `use_mise` stdlib helper -- one-shot
        # cost on cd-into-project, not per-prompt.
        enableZshIntegration = false;
      };

      direnv = {
        enable = true;
        nix-direnv.enable = true;
        # On darwin, pkgs.direnv has doCheck=false applied via the overlay
        # in flake.nix's pkgsFor, since CI builds direnv from source and
        # its vendored zsh test suite hangs the macOS-14 runner.
        stdlib = ''
          use_mise() {
            eval "$(mise direnv)"
          }
        '';
      };
    };

    # Ensure XDG state directory for zsh history exists
    home.file.".local/state/zsh/.keep".text = "";

    # Force-overwrite .zshenv to prevent home-manager activation failure
    # when a stale manually-created .zshenv exists outside HM control.
    # Safe to remove once all machines have completed the migration to HM.
    home.file.".zshenv".force = true;
  };
}
