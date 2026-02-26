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

  outputs = {
    nixpkgs,
    home-manager,
    nixos-wsl,
    doom-emacs,
    sops-nix,
    ...
  }: let
    # Read user configuration.
    # config.local.nix (gitignored) can override any key — typically used for
    # git identity (userName, userEmail, signingKey) on personal machines so
    # those values don't have to live in the committed config.nix.
    # See config.local.nix.example for the format.
    userConfig = let
      base = import ./config.nix;
      local =
        if builtins.pathExists ./config.local.nix
        then import ./config.local.nix
        else {};
    in
      base
      // {
        git = (base.git or {}) // (local.git or {});
      };
    repoConfig = userConfig.repo;
    gitConfig = userConfig.git;

    allSystems = ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"];
    forAllSystems = nixpkgs.lib.genAttrs allSystems;

    pkgsFor = system: let
      isDarwin = nixpkgs.lib.hasInfix "darwin" system;
      # Overlay to stub out lilypond on Darwin (fails to build with newer clang)
      lilypondOverlay = _: prev:
        nixpkgs.lib.optionalAttrs isDarwin {
          # lilypond fails to build on Darwin with newer clang; stub it out so
          # transitive dependents (e.g. Doom Emacs) can still build. The stub
          # exits 1 so any accidental runtime invocation fails loudly.
          lilypond = prev.runCommand "lilypond-stub" {} ''
            mkdir -p $out/bin
            echo '#!/bin/sh' > $out/bin/lilypond
            echo 'echo "lilypond is not available on macOS in this configuration" >&2' >> $out/bin/lilypond
            echo 'exit 1' >> $out/bin/lilypond
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

    homeDirectoryFor = {
      system,
      username,
    }:
      if nixpkgs.lib.hasInfix "darwin" system
      then "/Users/${username}"
      else "/home/${username}";

    mkHomeConfiguration = {
      system,
      username,
    }: let
      pkgs = pkgsFor system;
      homeDirectory = homeDirectoryFor {inherit system username;};
      isDarwin = nixpkgs.lib.hasInfix "darwin" system;
      isLinux = !isDarwin;
    in
      home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        extraSpecialArgs = {inherit gitConfig userConfig;};
        modules =
          [
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
          ++ (
            if isLinux
            then [./home/linux.nix]
            else [./home/darwin.nix]
          )
          ++ [
            {
              home = {
                inherit username homeDirectory;
                stateVersion = "25.05";
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
            }
          ];
      };

    # Generate homeConfigurations from config.nix
    homeConfigs =
      builtins.foldl' (
        acc: user:
          acc
          // builtins.foldl' (
            inner: system:
              inner
              // {
                "${user.username}@${system}" = mkHomeConfiguration {
                  inherit system;
                  inherit (user) username;
                };
              }
          ) {}
          user.systems
      ) {}
      userConfig.users;

    # Find the first user that supports a given system
    userForSystem = system: let
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
      specialArgs = {inherit userConfig gitConfig;};
      modules = [
        nixos-wsl.nixosModules.default
        sops-nix.nixosModules.sops
        ./hosts/wsl/configuration.nix
      ];
    };

    homeConfigurations = homeConfigs;

    packages = forAllSystems (
      system: let
        user = userForSystem system;
        pkgs = pkgsFor system;
        isLinux = !(nixpkgs.lib.hasInfix "darwin" system);
      in
        if user != null
        then let
          inherit (user) username;
          homeDirectory = homeDirectoryFor {inherit system username;};
          configKey = "${username}@${system}";
        in
          {
            default = homeConfigs.${configKey}.activationPackage;
          }
          // (
            if isLinux
            then {
              dockerImage = import ./lib/docker-image.nix {
                inherit pkgs homeDirectory username;
                homeConfiguration = homeConfigs.${configKey};
                imageName = dockerImageName;
              };
            }
            else {}
          )
        else {}
    );

    apps = forAllSystems (
      system: let
        user = userForSystem system;
        pkgs = pkgsFor system;
        isLinux = !(nixpkgs.lib.hasInfix "darwin" system);
      in
        if user != null
        then let
          inherit (user) username;
          homeDirectory = homeDirectoryFor {inherit system username;};
        in
          {
            default = {
              type = "app";
              meta.description = "Activate home-manager configuration";
              program = "${pkgs.writeShellApplication {
                name = "activate-home";
                text = ''
                  echo "Activating home-manager configuration for ${system}..."
                  home-manager switch --flake "$HOME/.config/home-manager#${username}@${system}" -b backup
                '';
              }}/bin/activate-home";
            };
          }
          // (
            if isLinux
            then {
              docker-test = import ./lib/docker-test-app.nix {
                inherit pkgs homeDirectory;
                imageName = dockerImageName;
              };
            }
            else {}
          )
          // {
            update-vim-plugins = {
              type = "app";
              meta.description = "Fetch latest lazy.nvim + LazyVim versions and hashes for modules/vim/default.nix";
              program = "${pkgs.writeShellApplication {
                name = "update-vim-plugins";
                runtimeInputs = [pkgs.curl pkgs.jq pkgs.nix-prefetch-github];
                text = ''
                  fetch_latest_tag() {
                    local owner="$1" repo="$2"
                    curl -sL "https://api.github.com/repos/$owner/$repo/releases/latest" \
                      | jq -r '.tag_name'
                  }

                  echo "Fetching latest versions..."
                  lazy_tag=$(fetch_latest_tag folke lazy.nvim)
                  lazyvim_tag=$(fetch_latest_tag LazyVim LazyVim)

                  echo "  lazy.nvim : $lazy_tag"
                  echo "  LazyVim   : $lazyvim_tag"
                  echo ""
                  echo "Computing hashes (this may take a moment)..."

                  lazy_sha=$(nix-prefetch-github folke lazy.nvim --rev "$lazy_tag" --json | jq -r '.hash')
                  lazyvim_sha=$(nix-prefetch-github LazyVim LazyVim --rev "$lazyvim_tag" --json | jq -r '.hash')

                  echo ""
                  echo "Update modules/vim/default.nix with:"
                  echo ""
                  echo "  lazyNvim = pkgs.fetchFromGitHub {"
                  echo "    owner = \"folke\";"
                  echo "    repo = \"lazy.nvim\";"
                  echo "    rev = \"$lazy_tag\"; # https://github.com/folke/lazy.nvim/releases"
                  echo "    sha256 = \"$lazy_sha\";"
                  echo "  };"
                  echo ""
                  echo "  lazyVimDistro = pkgs.fetchFromGitHub {"
                  echo "    owner = \"LazyVim\";"
                  echo "    repo = \"LazyVim\";"
                  echo "    rev = \"$lazyvim_tag\"; # https://github.com/LazyVim/LazyVim/releases"
                  echo "    sha256 = \"$lazyvim_sha\";"
                  echo "  };"
                '';
              }}/bin/update-vim-plugins";
            };
          }
        else {}
    );
  };
}
