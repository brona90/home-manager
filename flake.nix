{
  description = "Reproducible Home Manager and NixOS configurations";

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

    doom-emacs = {
      url = "github:marienz/nix-doom-emacs-unstraightened";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, home-manager, nixos-wsl, doom-emacs, sops-nix, ... }:
    let
      # Read user configuration
      userConfig = import ./config.nix;

      allSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs allSystems;

      pkgsFor = system: import nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = [ doom-emacs.overlays.default ];
      };

      homeDirectoryFor = { system, username }:
        if nixpkgs.lib.hasInfix "darwin" system
        then "/Users/${username}"
        else "/home/${username}";

      mkHomeConfiguration = { system, username }:
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
            ./modules/sops.nix
            ./home/common.nix
          ]
          ++ (if isLinux then [ ./home/linux.nix ] else [ ./home/darwin.nix ])
          ++ [{
            home = {
              inherit username homeDirectory;
              stateVersion = "24.11";
            };

            my = {
              tmux = {
                enable = true;
                configDir = ./modules/tmux/tmux-config;
              };
              emacs = {
                enable = true;
                package = pkgs.emacsWithDoom {
                  doomDir = if isDarwin && builtins.pathExists ./modules/emacs/doom.d-darwin
                            then ./modules/emacs/doom.d-darwin
                            else ./modules/emacs/doom.d;
                  doomLocalDir = "~/.local/share/nix-doom";
                };
              };
              zsh.extraAliases.hms = ''home-manager switch --flake "$HOME/.config/home-manager#${username}@${system}"'';
            };
          }];
        };

      # Generate homeConfigurations from config.nix
      homeConfigs = builtins.foldl' (acc: user:
        acc // builtins.foldl' (inner: system:
          inner // { "${user.username}@${system}" = mkHomeConfiguration { inherit system; inherit (user) username; }; }
        ) {} user.systems
      ) {} userConfig.users;

      # Get first user's first system for defaults
      defaultUser = builtins.head userConfig.users;
      defaultUsername = defaultUser.username;

    in {
      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          nixos-wsl.nixosModules.default
          sops-nix.nixosModules.sops
          ./hosts/wsl/configuration.nix
        ];
      };

      homeConfigurations = homeConfigs;

      packages = forAllSystems (system:
        let
          pkgs = pkgsFor system;
          homeDirectory = homeDirectoryFor { inherit system; username = defaultUsername; };
          isLinux = !(nixpkgs.lib.hasInfix "darwin" system);
          configKey = "${defaultUsername}@${system}";
          hasConfig = builtins.hasAttr configKey homeConfigs;
        in
        (if hasConfig then {
          default = homeConfigs.${configKey}.activationPackage;
        } else {})
        // (if isLinux && hasConfig then {
          dockerImage = import ./lib/docker-image.nix {
            inherit pkgs homeDirectory;
            username = defaultUsername;
            homeConfiguration = homeConfigs.${configKey};
            imageName = "brona90/terminal";
          };
        } else {})
      );

      apps = forAllSystems (system:
        let
          pkgs = pkgsFor system;
          homeDirectory = homeDirectoryFor { inherit system; username = defaultUsername; };
          isLinux = !(nixpkgs.lib.hasInfix "darwin" system);
          configKey = "${defaultUsername}@${system}";
          hasConfig = builtins.hasAttr configKey homeConfigs;
        in
        (if hasConfig then {
          default = {
            type = "app";
            meta.description = "Activate home-manager configuration";
            program = toString (pkgs.writeShellScript "activate-home" ''
              echo "Activating home-manager configuration for ${system}..."
              home-manager switch --flake "$HOME/.config/home-manager#${defaultUsername}@${system}"
            '');
          };
        } else {})
        // (if isLinux && hasConfig then {
          docker-test = import ./lib/docker-test-app.nix { inherit pkgs homeDirectory; };
        } else {})
      );
    };
}
