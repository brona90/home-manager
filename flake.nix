{
  description = "Gregory's Home Manager configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-emacs.url = "github:brona90/nix-emacs";
    nix-vim.url = "github:brona90/nix-vim";
    nix-tmux.url = "github:brona90/nix-tmux";
    nix-zsh.url = "github:brona90/nix-zsh";
    nix-git.url = "github:brona90/nix-git";
  };

  outputs = { self, nixpkgs, home-manager, sops-nix, nix-emacs, nix-vim, nix-tmux, nix-zsh, nix-git, ... }:
    let
      # Define supported systems
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      
      # Helper to generate configs for each system
      forAllSystems = nixpkgs.lib.genAttrs systems;
      
      # Per-system package sets
      pkgsFor = system: import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      
      # Default username
      defaultUsername = "gfoster";
      
      # Detect home directory based on OS and username
      homeDirectoryFor = { system, username }:
        if nixpkgs.lib.hasInfix "darwin" system
        then "/Users/${username}"
        else "/home/${username}";
      
      # Create home configuration for a given system and username
      mkHomeConfiguration = { system, username ? defaultUsername }:
        let
          pkgs = pkgsFor system;
          lib = nixpkgs.lib;
          homeDirectory = homeDirectoryFor { inherit system username; };
          zshConfig = nix-zsh.lib.mkZshConfig pkgs;
          gitConfig = nix-git.lib.mkGitConfig pkgs;
          isDarwin = nixpkgs.lib.hasInfix "darwin" system;
          isLinux = !isDarwin;
        in
        home-manager.lib.homeManagerConfiguration {
          inherit pkgs;

          modules = [
            sops-nix.homeManagerModules.sops
            {
              home = {
                inherit username homeDirectory;
                stateVersion = "24.11";
              };

              programs.home-manager.enable = true;

              home.packages = [
                nix-vim.packages.${system}.default
                nix-tmux.packages.${system}.default
                nix-emacs.packages.${system}.default
                pkgs.btop
                pkgs.tree
              ] 
              # Only include these on Linux (gsettings/dconf are Linux-specific)
              ++ (if isLinux then [ 
                pkgs.gsettings-desktop-schemas
                pkgs.glib
                pkgs.dconf
              ] else []);

              programs.git = {
                enable = true;
                settings = {
                  user = {
                    name = gitConfig.userName;
                    email = gitConfig.userEmail;
                  };
                  alias = gitConfig.aliases;
                } // gitConfig.extraConfig;
                ignores = gitConfig.ignores;
              };

              xdg.configFile."git/config".force = true;
              xdg.configFile."git/ignore".force = true;
              xdg.configFile."btop/btop.conf".force = true;

              programs.zsh = {
                enable = true;
                enableCompletion = true;
                dotDir = "${homeDirectory}";
                shellAliases = zshConfig.aliases // {
                  nrs = "nixos-rebuild switch --flake .";
                  hms = "home-manager switch --flake .#${username}@${system}";
                  nfu = "nix flake update";
                  vim = "lvim";
                  vi = "lvim";
                } // (if isDarwin then {
                  # macOS-specific aliases
                  ls = "ls -G";
                } else {
                  # Linux-specific aliases
                  ls = "ls --color=auto";
                });
                oh-my-zsh = zshConfig.ohMyZsh;
                plugins = zshConfig.plugins;
                initContent = zshConfig.initExtra + ''
                  # Ensure starship is initialized
                  eval "$(${pkgs.starship}/bin/starship init zsh)"
                '' + (if isLinux then ''
                  # Set GSettings schema directory for Emacs (Linux only)
                  export GSETTINGS_SCHEMA_DIR="${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}/glib-2.0/schemas"
                '' else "");
                sessionVariables = zshConfig.sessionVariables;
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
                  git_branch.symbol = " ";
                  git_status = {
                    ahead = "⇡\${count}";
                    diverged = "⇕⇡\${ahead_count}⇣\${behind_count}";
                    behind = "⇣\${count}";
                  };
                  nix_shell = {
                    symbol = " ";
                    format = "via [$symbol$state]($style) ";
                  };
                };
              };

              programs.mise.enable = true;
              programs.direnv = {
                enable = true;
                nix-direnv.enable = true;
              };
              programs.btop = {
                enable = true;
                settings = {
                  color_theme = "Default";
                  theme_background = false;
                  vim_keys = true;
                };
              };

              home.sessionVariables = {
                EDITOR = "emacs -nw";
                VISUAL = "emacs -nw";
              };

              xdg.enable = true;
            }
          ];
        };
    in
    {
      # Home configurations for all systems
      homeConfigurations = {
        # Linux x86_64
        "gfoster@x86_64-linux" = mkHomeConfiguration { system = "x86_64-linux"; };
        
        # Linux ARM64
        "gfoster@aarch64-linux" = mkHomeConfiguration { system = "aarch64-linux"; };
        
        # macOS Intel
        "gfoster@x86_64-darwin" = mkHomeConfiguration { system = "x86_64-darwin"; };
        
        # macOS Apple Silicon
        "gfoster@aarch64-darwin" = mkHomeConfiguration { system = "aarch64-darwin"; };
        
        # Work Mac (different username)
        "888973@aarch64-darwin" = mkHomeConfiguration { system = "aarch64-darwin"; username = "888973"; };
        
        # Default (shorthand) configurations
        "gfoster" = mkHomeConfiguration { system = "x86_64-linux"; };
      };

      # Packages for all systems (uses default username)
      packages = forAllSystems (system:
        let
          pkgs = pkgsFor system;
          username = defaultUsername;
          homeDirectory = homeDirectoryFor { inherit system username; };
          isDarwin = nixpkgs.lib.hasInfix "darwin" system;
          isLinux = !isDarwin;
        in
        {
          default = self.homeConfigurations."${username}@${system}".activationPackage;
          
          # Docker image only for Linux systems
        } // (if isLinux then {
          dockerImage = 
            let
              homeConfig = self.homeConfigurations."${username}@${system}";
              activationPackage = homeConfig.activationPackage;
              homePath = "${activationPackage}/home-path";
              
              entrypoint = pkgs.writeShellScript "entrypoint.sh" ''
                export HOME=${homeDirectory}
                export USER=${username}
                
                # Create directories with proper permissions
                mkdir -p ~/.cache/oh-my-zsh/completions 2>/dev/null || true
                mkdir -p ~/.cache/starship 2>/dev/null || true
                mkdir -p ~/.local/share/nvim 2>/dev/null || true
                mkdir -p ~/.local/state/nvim 2>/dev/null || true
                mkdir -p ~/.config/tmux 2>/dev/null || true
                mkdir -p ~/.config/nvim 2>/dev/null || true
                mkdir -p ~/.zsh/plugins 2>/dev/null || true
                
                echo "Setting up home-manager environment..."
                if [ -d ${activationPackage}/home-files ]; then
                  ${pkgs.rsync}/bin/rsync -rL ${activationPackage}/home-files/ ~/ 2>/dev/null || \
                    cp -rL ${activationPackage}/home-files/. ~/ 2>/dev/null || true
                fi
                
                export PATH="${homePath}/bin:$PATH"
                export LD_LIBRARY_PATH="${pkgs.stdenv.cc.cc.lib}/lib:${pkgs.glibc}/lib:${pkgs.zlib}/lib:$LD_LIBRARY_PATH"
                
                if [ -f ${homePath}/etc/profile.d/hm-session-vars.sh ]; then
                  source ${homePath}/etc/profile.d/hm-session-vars.sh
                fi
                
                exec ${homePath}/bin/zsh
              '';
            in
            pkgs.dockerTools.buildLayeredImage {
              name = "brona90/terminal";
              tag = "latest";
              
              contents = [
                pkgs.bashInteractive
                pkgs.coreutils
                pkgs.findutils
                pkgs.gnugrep
                pkgs.gnused
                pkgs.gawk
                pkgs.less
                pkgs.which
                pkgs.ncurses
                pkgs.nix
                pkgs.cacert
                pkgs.rsync
                pkgs.gcc
                pkgs.glibc
                pkgs.zlib
                pkgs.stdenv.cc.cc.lib
                homePath
              ];
              
              extraCommands = ''
                mkdir -p home/${username}
                mkdir -p home/${username}/.config
                mkdir -p home/${username}/.local
                mkdir -p home/${username}/.cache
                mkdir -p etc
                mkdir -p tmp
                chmod 1777 tmp
                
                echo "${username}:x:1000:1000::${homeDirectory}:${homePath}/bin/zsh" > etc/passwd
                echo "${username}:x:1000:" > etc/group
                echo "root:x:0:0::/root:/bin/bash" >> etc/passwd
                echo "root:x:0:" >> etc/group
              '';
              
              config = {
                Cmd = [ "${entrypoint}" ];
                Env = [
                  "HOME=${homeDirectory}"
                  "USER=${username}"
                  "PATH=${homePath}/bin:/bin"
                  "NIX_PATH=nixpkgs=${pkgs.path}"
                  "EDITOR=emacs -nw"
                  "VISUAL=emacs -nw"
                  "LANG=C.UTF-8"
                  "LC_ALL=C.UTF-8"
                  "TERM=xterm-256color"
                  "COLORTERM=truecolor"
                ];
                WorkingDir = homeDirectory;
                User = username;
              };
            };
        } else {})
      );
      
      # Development shells for all systems
      devShells = forAllSystems (system:
        let
          pkgs = pkgsFor system;
        in
        {
          default = pkgs.mkShell {
            buildInputs = [
              pkgs.bazel_7
              pkgs.bazel-buildtools
            ];
            
            shellHook = ''
              echo "Bazel development environment"
              echo "Bazel version: $(bazel version | head -n1)"
              echo ""
              echo "Available commands:"
              echo "  bazel build //...     - Build all targets"
              echo "  bazel test //...      - Run all tests"
              echo "  buildifier -r .       - Format BUILD files"
            '';
          };
        }
      );
      
      # Apps for all systems
      apps = forAllSystems (system:
        let
          pkgs = pkgsFor system;
          username = defaultUsername;
          homeDirectory = homeDirectoryFor { inherit system username; };
          isDarwin = nixpkgs.lib.hasInfix "darwin" system;
          isLinux = !isDarwin;
        in
        {
          # Default app: activate home-manager
          default = {
            type = "app";
            program = toString (pkgs.writeShellScript "activate-home" ''
              echo "Activating home-manager configuration for ${system}..."
              home-manager switch --flake .#${username}@${system}
            '');
            meta = {
              description = "Activate home-manager configuration";
            };
          };
        } // (if isLinux then {
          # Docker test only available on Linux
          docker-test = {
            type = "app";
            program = toString (pkgs.writeShellScript "docker-test" ''
              set -e
              
              echo "Building Docker image..."
              rm -f result
              nix build .#dockerImage
              
              echo "Loading image into Docker..."
              docker load < result
              
              DOCKER_ARGS="-it --rm"
              DOCKER_ARGS="$DOCKER_ARGS --tmpfs ${homeDirectory}:exec,uid=1000,gid=1000,mode=0755"
              DOCKER_ARGS="$DOCKER_ARGS --tmpfs /tmp:exec,mode=1777"
              
              if [ -d "$HOME/.ssh" ]; then
                DOCKER_ARGS="$DOCKER_ARGS -v $HOME/.ssh:${homeDirectory}/.ssh:ro"
              fi
              
              if [ -n "$SSH_AUTH_SOCK" ]; then
                DOCKER_ARGS="$DOCKER_ARGS -v $SSH_AUTH_SOCK:/ssh-agent -e SSH_AUTH_SOCK=/ssh-agent"
              fi
              
              echo "Starting container..."
              docker run $DOCKER_ARGS brona90/terminal:latest
            '');
            meta = {
              description = "Build and test Docker image";
            };
          };
        } else {})
      );
    };
}
