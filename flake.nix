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
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      
      username = "gfoster";
      homeDirectory = "/home/${username}";
      
      zshConfig = nix-zsh.lib.mkZshConfig pkgs;
      gitConfig = nix-git.lib.mkGitConfig pkgs;
    in
    {
      homeConfigurations.${username} = home-manager.lib.homeManagerConfiguration {
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
              nix-emacs.packages.${system}.default
              nix-vim.packages.${system}.default
              nix-tmux.packages.${system}.default
              # REMOVED: nix-git.packages.${system}.default
              # Using programs.git instead to avoid conflict
              pkgs.btop
              pkgs.tree
            ];

            programs.git = {
              enable = true;
              # Fix deprecated options (use settings instead)
              settings = {
                user = {
                  name = gitConfig.userName;
                  email = gitConfig.userEmail;
                };
                alias = gitConfig.aliases;
              } // gitConfig.extraConfig;
              ignores = gitConfig.ignores;
            };

            # Force overwrite existing config files
            xdg.configFile."git/config".force = true;
            xdg.configFile."git/ignore".force = true;
            xdg.configFile."btop/btop.conf".force = true;

            programs.zsh = {
              enable = true;
              enableCompletion = true;
              # Fix deprecated option
              dotDir = "${homeDirectory}";  # Or use: "${config.xdg.configHome}/zsh" for new behavior
              shellAliases = zshConfig.aliases // {
                nrs = "nixos-rebuild switch --flake .";
                hms = "home-manager switch --flake .";
                nfu = "nix flake update";
                vim = "lvim";
                vi = "lvim";
              };
              oh-my-zsh = zshConfig.ohMyZsh;
              plugins = zshConfig.plugins;
              # Fix deprecated option
              initContent = zshConfig.initExtra + ''
                # Ensure starship is initialized
                eval "$(${pkgs.starship}/bin/starship init zsh)"
              '';
              sessionVariables = zshConfig.sessionVariables;
            };

            programs.starship = {
              enable = true;
              settings = {
                add_newline = true;
                character = {
                  success_symbol = "[➜](bold green)";
                  error_symbol = "[➜](bold red)";
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

            # sops configuration FULLY DISABLED until setup is complete
            # Uncomment the entire block below after completing sops setup steps
            /*
            sops = {
              age.keyFile = "${homeDirectory}/.config/sops/age/keys.txt";
              defaultSopsFile = ./secrets/ssh.yaml;
              
              secrets = {
                ssh_private_key = {
                  path = "${homeDirectory}/.ssh/id_ed25519";
                  mode = "0600";
                };
              };
            };

            home.file.".ssh/id_ed25519.pub".text = ''
              ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIYourActualPublicKeyHere gfoster@laptop
            '';

            home.file.".ssh/config".text = ''
              Host *
                AddKeysToAgent yes
                IdentityFile ~/.ssh/id_ed25519
            '';
            */
          }
        ];
      };

      packages.${system} = {
        default = self.homeConfigurations.${username}.activationPackage;
        
        # Docker image for testing with home-manager activated
        dockerImage = 
          let
            homeConfig = self.homeConfigurations.${username};
            activationPackage = homeConfig.activationPackage;
            homePath = "${activationPackage}/home-path";
            
            # Create an entrypoint script that sets up the environment
            entrypoint = pkgs.writeShellScript "entrypoint.sh" ''
              export HOME=/home/${username}
              export USER=${username}
              
              # Ensure cache directories are writable
              mkdir -p ~/.cache/oh-my-zsh/completions
              mkdir -p ~/.cache/starship
              mkdir -p ~/.local/share
              mkdir -p ~/.local/share/nvim
              mkdir -p ~/.local/state
              mkdir -p ~/.local/state/nvim
              mkdir -p ~/.config/tmux
              mkdir -p ~/.config/nvim
              mkdir -p ~/.zsh/plugins
              
              # Copy home-manager configuration files to home directory
              echo "Setting up home-manager environment..."
              if [ -d ${activationPackage}/home-files ]; then
                # Use rsync or cp with -L to follow symlinks
                ${pkgs.rsync}/bin/rsync -rL ${activationPackage}/home-files/ ~/ 2>/dev/null || \
                  cp -rL ${activationPackage}/home-files/. ~/ 2>/dev/null || true
              fi
              
              # Set up PATH and environment (ensure home-path/bin is first)
              export PATH="${homePath}/bin:$PATH"
              
              # Set up library paths for mise-installed tools
              export LD_LIBRARY_PATH="${pkgs.stdenv.cc.cc.lib}/lib:${pkgs.glibc}/lib:${pkgs.zlib}/lib:$LD_LIBRARY_PATH"
              
              # Source home-manager session variables if available
              if [ -f ${homePath}/etc/profile.d/hm-session-vars.sh ]; then
                source ${homePath}/etc/profile.d/hm-session-vars.sh
              fi
              
              # Start zsh (which will load .zshrc with all the aliases)
              exec ${homePath}/bin/zsh
            '';
          in
          pkgs.dockerTools.buildLayeredImage {
            name = "home-manager-test";
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
              pkgs.ncurses  # Provides clear, tput, etc.
              pkgs.nix
              pkgs.cacert
              pkgs.rsync  # For copying home-files with symlinks
              # Runtime dependencies for mise-installed tools
              pkgs.gcc
              pkgs.glibc
              pkgs.zlib
              pkgs.stdenv.cc.cc.lib  # libstdc++
              # Include all the packages from home-manager
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
              
              echo "${username}:x:1000:1000::/home/${username}:${homePath}/bin/zsh" > etc/passwd
              echo "${username}:x:1000:" > etc/group
              echo "root:x:0:0::/root:/bin/bash" >> etc/passwd
              echo "root:x:0:" >> etc/group
            '';
            
            config = {
              Cmd = [ "${entrypoint}" ];
              Env = [
                "HOME=/home/${username}"
                "USER=${username}"
                "PATH=${homePath}/bin:/bin"
                "NIX_PATH=nixpkgs=${pkgs.path}"
                "EDITOR=emacs -nw"
                "VISUAL=emacs -nw"
                "LANG=C.UTF-8"
                "LC_ALL=C.UTF-8"
                "TERM=xterm-256color"  # Force 256 color support
                "COLORTERM=truecolor"  # Enable true color if terminal supports it
              ];
              WorkingDir = "/home/${username}";
              User = "${username}";
            };
          };
      };
      
      # App to build and load docker image
      apps.${system}.docker-test = {
        type = "app";
        program = toString (pkgs.writeShellScript "docker-test" ''
          set -e
          
          echo "Building Docker image..."
          # Remove old result symlink to force rebuild
          rm -f result
          nix build .#dockerImage
          
          echo "Loading image into Docker..."
          docker load < result
          
          # Prepare docker run arguments
          DOCKER_ARGS="-it --rm"
          
          # Mount the entire home directory as tmpfs to make it writable
          # This allows us to copy home-manager files and create any needed directories
          DOCKER_ARGS="$DOCKER_ARGS --tmpfs /home/${username}:exec,uid=1000,gid=1000,mode=0755"
          
          # Also make /tmp writable
          DOCKER_ARGS="$DOCKER_ARGS --tmpfs /tmp:exec,mode=1777"
          
          # Mount SSH keys if they exist
          if [ -d "$HOME/.ssh" ]; then
            DOCKER_ARGS="$DOCKER_ARGS -v $HOME/.ssh:/home/${username}/.ssh:ro"
          fi
          
          # Forward SSH agent if available
          if [ -n "$SSH_AUTH_SOCK" ]; then
            DOCKER_ARGS="$DOCKER_ARGS -v $SSH_AUTH_SOCK:/ssh-agent -e SSH_AUTH_SOCK=/ssh-agent"
          fi
          
          echo "Starting container..."
          docker run $DOCKER_ARGS home-manager-test:latest
        '');
      };
    };
}