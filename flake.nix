{
  description = "Gregory's Home Manager configuration (module-based)";

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

    # Only external flake needed: doom-emacs overlay
    doom-emacs = {
      url = "github:marienz/nix-doom-emacs-unstraightened";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      sops-nix,
      doom-emacs,
      ...
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      forAllSystems = nixpkgs.lib.genAttrs systems;

      pkgsFor = system:
        import nixpkgs {
          inherit system;
          config.allowUnfree = true;
          overlays = [ doom-emacs.overlays.default ];
        };

      defaultUsername = "gfoster";

      homeDirectoryFor = { system, username }:
        if nixpkgs.lib.hasInfix "darwin" system
        then "/Users/${username}"
        else "/home/${username}";

      mkHomeConfiguration = { system, username ? defaultUsername }:
        let
          pkgs = pkgsFor system;
          lib = nixpkgs.lib;
          homeDirectory = homeDirectoryFor { inherit system username; };
          isDarwin = lib.hasInfix "darwin" system;
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

              # Enable all our custom modules
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

              # Platform-specific aliases
              my.zsh.extraAliases = {
                hms = "home-manager switch --flake '.#${username}@${system}'";
              } // (if isDarwin then { ls = "ls -G"; } else { });

              # Linux-only packages
              home.packages = [
                pkgs.tree
                pkgs.bazel_7
                pkgs.bazel-buildtools
              ] ++ (if isLinux then [
                pkgs.gsettings-desktop-schemas
                pkgs.glib
                pkgs.dconf
              ] else []);

              # Linux-only init
              my.zsh.extraInitExtra = if isLinux then ''
                # Set GSettings schema directory for Emacs
                export GSETTINGS_SCHEMA_DIR="${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}/glib-2.0/schemas"
              '' else "";

              xdg.enable = true;
            }
          ];
        };
    in
    {
      homeConfigurations = {
        "gfoster@x86_64-linux" = mkHomeConfiguration { system = "x86_64-linux"; };
        "gfoster@aarch64-linux" = mkHomeConfiguration { system = "aarch64-linux"; };
        "gfoster@x86_64-darwin" = mkHomeConfiguration { system = "x86_64-darwin"; };
        "gfoster@aarch64-darwin" = mkHomeConfiguration { system = "aarch64-darwin"; };
        "888973@aarch64-darwin" = mkHomeConfiguration {
          system = "aarch64-darwin";
          username = "888973";
        };
        "gfoster" = mkHomeConfiguration { system = "x86_64-linux"; };
      };

      packages = forAllSystems (system:
        let
          pkgs = pkgsFor system;
          username = defaultUsername;
        in
        {
          default = self.homeConfigurations."${username}@${system}".activationPackage;
        }
      );

      apps = forAllSystems (system:
        let
          pkgs = pkgsFor system;
          username = defaultUsername;
        in
        {
          default = {
            type = "app";
            program = toString (
              pkgs.writeShellScript "activate-home" ''
                echo "Activating home-manager configuration for ${system}..."
                home-manager switch --flake .#${username}@${system}
              ''
            );
          };
        }
      );
    };
}
