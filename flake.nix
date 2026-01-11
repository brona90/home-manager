{
  description = "Gregory's Home Manager configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Your custom flakes
    nix-emacs.url = "github:brona90/nix-emacs";
    nix-vim.url = "github:brona90/nix-vim";
    nix-tmux.url = "github:brona90/nix-tmux";
  };

  outputs = { self, nixpkgs, home-manager, nix-emacs, nix-vim, nix-tmux, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      
      username = "gfoster";
      homeDirectory = "/home/${username}";
    in
    {
      homeConfigurations.${username} = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;

        modules = [
          {
            home = {
              inherit username homeDirectory;
              stateVersion = "24.11";
            };

            # Let Home Manager manage itself
            programs.home-manager.enable = true;

            # Core packages from your custom flakes
            home.packages = with pkgs; [
              # Your custom editor/terminal setups
              nix-emacs.packages.${system}.default
              nix-vim.packages.${system}.default
              nix-tmux.packages.${system}.default

              # System tools
              btop
              git
              tree
              
              # Shell
              zsh
              starship
              
              # Development tools
              mise
            ];

            # Git configuration
            programs.git = {
              enable = true;
              userName = "Gregory Foster";
              userEmail = "brona90@gmail.com";
              extraConfig = {
                init.defaultBranch = "main";
                core.editor = "nvim";
                pull.rebase = false;
              };
            };

            # Zsh configuration
            programs.zsh = {
              enable = true;
              enableCompletion = true;
              autosuggestion.enable = true;
              syntaxHighlighting.enable = true;
              
              shellAliases = {
                # Nix helpers
                nrs = "nixos-rebuild switch --flake .";
                hms = "home-manager switch --flake .";
                nfu = "nix flake update";
                
                # Git shortcuts
                gs = "git status";
                ga = "git add";
                gc = "git commit";
                gp = "git push";
                gl = "git log --oneline --graph";
                
                # Common commands
                ls = "ls --color=auto";
                ll = "ls -lah";
                ".." = "cd ..";
                "..." = "cd ../..";
              };
              
              initExtra = ''
                # Custom prompt with starship
                eval "$(starship init zsh)"
                
                # Mise activation
                eval "$(mise activate zsh)"
              '';
            };

            # Starship prompt configuration
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
                
                git_branch = {
                  symbol = " ";
                };
                
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

            # Btop configuration
            programs.btop = {
              enable = true;
              settings = {
                color_theme = "Default";
                theme_background = false;
                vim_keys = true;
              };
            };

            # Home Manager settings
            home.sessionVariables = {
              EDITOR = "${nix-emacs.packages.${system}.default}/bin/emacs";
              VISUAL = "${nix-emacs.packages.${system}.default}/bin/emacs";
            };

            # XDG directories
            xdg.enable = true;
          }
        ];
      };

      # Provide packages for other systems
      packages.${system}.default = self.homeConfigurations.${username}.activationPackage;
    };
}