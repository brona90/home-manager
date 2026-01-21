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
          homeDirectory = homeDirectoryFor { inherit system username; };
          isDarwin = nixpkgs.lib.hasInfix "darwin" system;
          isLinux = !isDarwin;
        in
        {
          default = self.homeConfigurations."${username}@${system}".activationPackage;
        }
        // (
          if isLinux then
            {
              dockerImage =
                let
                  homeConfig = self.homeConfigurations."${username}@${system}";
                  activationPackage = homeConfig.activationPackage;
                  homePath = "${activationPackage}/home-path";

                  # Custom fakeNss with our user included
                  customNss = pkgs.symlinkJoin {
                    name = "custom-nss";
                    paths = [
                      (pkgs.writeTextDir "etc/passwd" ''
                        root:x:0:0:root:/root:/bin/bash
                        nobody:x:65534:65534:Nobody:/nonexistent:/usr/sbin/nologin
                        ${username}:x:1000:1000::${homeDirectory}:${homePath}/bin/zsh
                      '')
                      (pkgs.writeTextDir "etc/group" ''
                        root:x:0:
                        nobody:x:65534:
                        ${username}:x:1000:
                      '')
                      (pkgs.writeTextDir "etc/nsswitch.conf" ''
                        hosts: files dns
                      '')
                      (pkgs.runCommand "var-empty" { } ''
                        mkdir -p $out/var/empty
                      '')
                    ];
                  };

                  entrypoint = pkgs.writeShellScript "entrypoint.sh" ''
                    export HOME=${homeDirectory}
                    export USER=${username}

                    # Create directories with proper permissions
                    mkdir -p ~/.cache/oh-my-zsh/completions 2>/dev/null || true
                    mkdir -p ~/.cache/starship 2>/dev/null || true
                    mkdir -p ~/.local/share/nvim/lazy 2>/dev/null || true
                    mkdir -p ~/.local/state/nvim 2>/dev/null || true
                    mkdir -p ~/.config/tmux 2>/dev/null || true
                    mkdir -p ~/.config/nvim 2>/dev/null || true
                    mkdir -p ~/.config/zsh 2>/dev/null || true
                    mkdir -p ~/.zsh/plugins 2>/dev/null || true
                    mkdir -p ~/.tmux/plugins 2>/dev/null || true

                    echo "Setting up home-manager environment..."
                    if [ -d ${activationPackage}/home-files ]; then
                      ${pkgs.rsync}/bin/rsync -rL ${activationPackage}/home-files/ ~/ 2>/dev/null || \
                        cp -rL ${activationPackage}/home-files/. ~/ 2>/dev/null || true
                    fi

                    export PATH="${homePath}/bin:$PATH"
                    export LD_LIBRARY_PATH="${pkgs.stdenv.cc.cc.lib}/lib:${pkgs.glibc}/lib:${pkgs.zlib}/lib:$LD_LIBRARY_PATH"

                    # Set tmux plugin path to writable location
                    export TMUX_PLUGIN_MANAGER_PATH="$HOME/.tmux/plugins"

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
                    pkgs.iana-etc
                    pkgs.curl
                    pkgs.dnsutils
                    pkgs.iputils
                    customNss
                    homePath
                    activationPackage  # Include full activation package for home-files
                  ];

                  extraCommands = ''
                    mkdir -p home/${username}/.config
                    mkdir -p home/${username}/.local
                    mkdir -p home/${username}/.cache
                    mkdir -p tmp
                    chmod 1777 tmp
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
            }
          else
            { }
        )
      );

      apps = forAllSystems (system:
        let
          pkgs = pkgsFor system;
          username = defaultUsername;
          homeDirectory = homeDirectoryFor { inherit system username; };
          isDarwin = nixpkgs.lib.hasInfix "darwin" system;
          isLinux = !isDarwin;
        in
        {
          default = {
            type = "app";
            program = toString (
              pkgs.writeShellScript "activate-home" ''
                echo "Activating home-manager configuration for ${system}..."
                home-manager switch --flake '.#${username}@${system}'
              ''
            );
          };
        }
        // (
          if isLinux then
            {
              docker-test = {
                type = "app";
                program = toString (
                  pkgs.writeShellScript "docker-test" ''
                    set -e

                    echo "Building Docker image..."
                    rm -f result
                    nix build .#dockerImage

                    echo "Loading image into Docker..."
                    docker load < result

                    DOCKER_ARGS="-it --rm --network host"
                    DOCKER_ARGS="$DOCKER_ARGS --tmpfs ${homeDirectory}:exec,uid=1000,gid=1000,mode=0755"
                    DOCKER_ARGS="$DOCKER_ARGS --tmpfs /tmp:exec,mode=1777"

                    if [ -d "$HOME/.ssh" ]; then
                      DOCKER_ARGS="$DOCKER_ARGS -v $HOME/.ssh:${homeDirectory}/.ssh:ro"
                    fi

                    if [ -n "$SSH_AUTH_SOCK" ]; then
                      DOCKER_ARGS="$DOCKER_ARGS -v $SSH_AUTH_SOCK:/ssh-agent -e SSH_AUTH_SOCK=/ssh-agent"
                    fi

                    echo "Starting container (using host network for WSL compatibility)..."
                    docker run $DOCKER_ARGS brona90/terminal:latest
                  ''
                );
              };
            }
          else
            { }
        )
      );
    };
}
