{
  description = "Gregory's Home Manager and NixOS configurations";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    doom-emacs = {
      url = "github:marienz/nix-doom-emacs-unstraightened";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, nixos-wsl, sops-nix, doom-emacs, ... }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;

      pkgsFor = system: import nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = [ doom-emacs.overlays.default ];
      };

      defaultUsername = "gfoster";

      homeDirectoryFor = { system, username }:
        if nixpkgs.lib.hasInfix "darwin" system
        then "/Users/${username}"
        else "/home/${username}";

      # Home Manager configuration builder
      mkHomeConfiguration = { system, username ? defaultUsername }:
        let
          pkgs = pkgsFor system;
          homeDirectory = homeDirectoryFor { inherit system username; };
          isDarwin = nixpkgs.lib.hasInfix "darwin" system;
          isLinux = !isDarwin;
        in
        home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [
            sops-nix.homeManagerModules.sops
            ./modules/zsh.nix
            ./modules/git.nix
            ./modules/btop.nix
            ./modules/vim/default.nix
            ./modules/emacs/default.nix
            ./modules/tmux/default.nix
            {
              home = {
                inherit username homeDirectory;
                stateVersion = "24.11";
              };

              programs.home-manager.enable = true;
              xdg.enable = true;

              # Enable modules
              my.zsh.enable = true;
              my.git.enable = true;
              my.btop.enable = true;
              my.vim.enable = true;
              my.tmux = {
                enable = true;
                configDir = ./modules/tmux/tmux-config;
              };
              my.emacs = {
                enable = true;
                package = pkgs.emacsWithDoom {
                  doomDir = if isDarwin && builtins.pathExists ./modules/emacs/doom.d-darwin
                            then ./modules/emacs/doom.d-darwin
                            else ./modules/emacs/doom.d;
                  doomLocalDir = "~/.local/share/nix-doom";
                };
              };

              # Platform-specific aliases (work from any directory)
              my.zsh.extraAliases = {
                hms = "home-manager switch --flake ~/.config/home-manager#${username}@${system}";
              } // (if isDarwin then { ls = "ls -G"; } else { });

              # Packages
              home.packages = with pkgs; [
                tree
                bazel_7
                bazel-buildtools
              ] ++ (if isLinux then [
                gsettings-desktop-schemas
                glib
                dconf
              ] else []);

              # Linux-only init
              my.zsh.extraInitExtra = if isLinux then ''
                export GSETTINGS_SCHEMA_DIR="${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}/glib-2.0/schemas"
              '' else "";
            }
          ];
        };

    in {
      # ──────────────────────────────────────────────────────────────
      # NixOS Configurations
      # ──────────────────────────────────────────────────────────────
      nixosConfigurations = {
        # Matches default NixOS-WSL hostname
        nixos = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            nixos-wsl.nixosModules.default
            ./hosts/wsl-nixos/configuration.nix
          ];
        };
      };

      # ──────────────────────────────────────────────────────────────
      # Home Manager Configurations
      # ──────────────────────────────────────────────────────────────
      homeConfigurations = {
        "gfoster@x86_64-linux"  = mkHomeConfiguration { system = "x86_64-linux"; };
        "gfoster@aarch64-linux" = mkHomeConfiguration { system = "aarch64-linux"; };
        "gfoster@x86_64-darwin" = mkHomeConfiguration { system = "x86_64-darwin"; };
        "gfoster@aarch64-darwin" = mkHomeConfiguration { system = "aarch64-darwin"; };
        "gfoster" = mkHomeConfiguration { system = "x86_64-linux"; };
        "888973@aarch64-darwin" = mkHomeConfiguration { system = "aarch64-darwin"; username = "888973"; };
      };

      # ──────────────────────────────────────────────────────────────
      # Packages
      # ──────────────────────────────────────────────────────────────
      packages = forAllSystems (system:
        let
          pkgs = pkgsFor system;
          username = defaultUsername;
          homeDirectory = homeDirectoryFor { inherit system username; };
          isLinux = !(nixpkgs.lib.hasInfix "darwin" system);
        in
        { default = self.homeConfigurations."${username}@${system}".activationPackage; }
        // (if isLinux then {
          dockerImage = import ./lib/docker-image.nix {
            inherit pkgs username homeDirectory;
            homeConfiguration = self.homeConfigurations."${username}@${system}";
            imageName = "brona90/terminal";
            imageTag = "latest";
          };
        } else {})
      );

      # ──────────────────────────────────────────────────────────────
      # Apps
      # ──────────────────────────────────────────────────────────────
      apps = forAllSystems (system:
        let
          pkgs = pkgsFor system;
          username = defaultUsername;
          homeDirectory = homeDirectoryFor { inherit system username; };
          isLinux = !(nixpkgs.lib.hasInfix "darwin" system);
        in
        {
          default = {
            type = "app";
            program = toString (pkgs.writeShellScript "activate-home" ''
              echo "Activating home-manager configuration for ${system}..."
              home-manager switch --flake ~/.config/home-manager#${username}@${system}
            '');
          };
        }
        // (if isLinux then {
          docker-test = {
            type = "app";
            program = toString (pkgs.writeShellScript "docker-test" ''
              set -e
              echo "Building Docker image..."
              rm -f result
              nix build ~/.config/home-manager#dockerImage

              echo "Loading image into Docker..."
              docker load < result

              DOCKER_ARGS="-it --rm --network host"
              DOCKER_ARGS="$DOCKER_ARGS --tmpfs ${homeDirectory}:exec,uid=1000,gid=1000,mode=0755"
              DOCKER_ARGS="$DOCKER_ARGS --tmpfs /tmp:exec,mode=1777"

              [ -d "$HOME/.ssh" ] && DOCKER_ARGS="$DOCKER_ARGS -v $HOME/.ssh:${homeDirectory}/.ssh:ro"
              [ -n "$SSH_AUTH_SOCK" ] && DOCKER_ARGS="$DOCKER_ARGS -v $SSH_AUTH_SOCK:/ssh-agent -e SSH_AUTH_SOCK=/ssh-agent"

              echo "Starting container..."
              docker run $DOCKER_ARGS brona90/terminal:latest
            '');
          };
        } else {})
      );
    };
}
