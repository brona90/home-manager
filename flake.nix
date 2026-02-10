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
      repoConfig = userConfig.repo;
      gitConfig = userConfig.git;

      allSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs allSystems;

      pkgsFor = system:
        let
          isDarwin = nixpkgs.lib.hasInfix "darwin" system;
          # Overlay to stub out lilypond on Darwin (fails to build with newer clang)
          lilypondOverlay = _: prev: nixpkgs.lib.optionalAttrs isDarwin {
            lilypond = prev.runCommand "lilypond-stub" {} ''
              mkdir -p $out/bin
              echo '#!/bin/sh' > $out/bin/lilypond
              echo 'echo "lilypond stub - install via brew on macOS"' >> $out/bin/lilypond
              chmod +x $out/bin/lilypond
            '';
          };
        in
        import nixpkgs {
          inherit system;
          config.allowUnfree = true;
          overlays = [
            lilypondOverlay
            doom-emacs.overlays.default
          ];
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
          extraSpecialArgs = { inherit gitConfig userConfig; };
          modules = [
            sops-nix.homeManagerModules.sops
            ./modules/zsh.nix
            ./modules/git.nix
            ./modules/gpg.nix
            ./modules/btop.nix
            ./modules/vim/default.nix
            ./modules/emacs/default.nix
            ./modules/tmux/default.nix
            ./modules/sops.nix
            ./modules/docker-terminal.nix
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
                  doomDir = ./modules/emacs/doom.d;
                  doomLocalDir = "~/.local/share/nix-doom";
                };
              };
              zsh.extraAliases.hms = ''home-manager switch --flake "$HOME/.config/home-manager#${username}@${system}" -b backup'';
            };
          }];
        };

      # Generate homeConfigurations from config.nix
      homeConfigs = builtins.foldl' (acc: user:
        acc // builtins.foldl' (inner: system:
          inner // { "${user.username}@${system}" = mkHomeConfiguration { inherit system; inherit (user) username; }; }
        ) {} user.systems
      ) {} userConfig.users;

      # Find the first user that supports a given system
      userForSystem = system:
        let
          matchingUsers = builtins.filter (user: builtins.elem system user.systems) userConfig.users;
        in
        if matchingUsers != []
        then builtins.head matchingUsers
        else null;

      # Docker image name from config
      dockerImageName = "${repoConfig.dockerHubUser}/terminal";

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
          user = userForSystem system;
          pkgs = pkgsFor system;
          isLinux = !(nixpkgs.lib.hasInfix "darwin" system);
        in
        if user != null then
          let
            username = user.username;
            homeDirectory = homeDirectoryFor { inherit system username; };
            configKey = "${username}@${system}";
          in
          {
            default = homeConfigs.${configKey}.activationPackage;
          }
          // (if isLinux then {
            dockerImage = import ./lib/docker-image.nix {
              inherit pkgs homeDirectory username;
              homeConfiguration = homeConfigs.${configKey};
              imageName = dockerImageName;
            };
          } else {})
        else {}
      );

      apps = forAllSystems (system:
        let
          user = userForSystem system;
          pkgs = pkgsFor system;
          isLinux = !(nixpkgs.lib.hasInfix "darwin" system);
        in
        if user != null then
          let
            username = user.username;
            homeDirectory = homeDirectoryFor { inherit system username; };
          in
          {
            default = {
              type = "app";
              meta.description = "Activate home-manager configuration";
              program = toString (pkgs.writeShellScript "activate-home" ''
                echo "Activating home-manager configuration for ${system}..."
                home-manager switch --flake "$HOME/.config/home-manager#${username}@${system}" -b backup
              '');
            };
          }
          // (if isLinux then {
            docker-test = import ./lib/docker-test-app.nix { inherit pkgs homeDirectory; };
          } else {})
        else {}
      );
    };
}
