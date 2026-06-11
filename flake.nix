{
  description = "Reproducible Home Manager and NixOS configurations";

  inputs = {
    # TEMPORARY PIN (2026-06-10): nixos-unstable (a799d3e3) carries nixpkgs
    # commit 04b2b505 which breaks the darwin emacs 30.2 build (C23 bool in
    # ObjC units; nixpkgs#529554, fixed by #529355 / 95e9e11e). This
    # nixpkgs-unstable rev contains the fix and has cached darwin binaries.
    # Revert to "github:NixOS/nixpkgs/nixos-unstable" once the channel
    # advances past 95e9e11e.
    nixpkgs.url = "github:NixOS/nixpkgs/8c3cede7ddc26bd659d2d383b5610efbd2c7a16e";

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

    # Always-current claude-code: nixpkgs lags npm by several patch releases,
    # so this flake (auto-bumped daily upstream) is the source of truth for
    # the CLI. Its overlay replaces pkgs.claude-code; `nfu` pulls the newest
    # pin each run. Prebuilt binaries available from claude-code.cachix.org.
    claude-code = {
      url = "github:sadjow/claude-code-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    nixpkgs,
    home-manager,
    nixos-wsl,
    doom-emacs,
    sops-nix,
    claude-code,
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

    # Setting programs.direnv.package alone isn't enough: something else in
    # the activation closure still pulls vanilla pkgs.direnv and runs its
    # zsh test suite, which hangs the macOS-14 CI runner. Overriding via
    # pkgsFor ensures every consumer of pkgs.direnv gets the patched build.
    skipDirenvChecksOnDarwin = _final: prev:
      nixpkgs.lib.optionalAttrs prev.stdenv.isDarwin {
        direnv = prev.direnv.overrideAttrs (_: {doCheck = false;});
      };

    pkgsFor = system:
      import nixpkgs {
        inherit system;
        config = {
          allowUnfree = true;
          # sbcl-2.6.3 is marked broken on darwin in the pinned nixpkgs.
          # It's pulled into the home-manager activation eval (transitively
          # via emacs lisp packages) so the eval refuses outright. "ignore"
          # lets eval proceed; if a subsequent build actually invokes sbcl
          # we'll surface the real failure there instead of at eval-time.
          problems.handlers.sbcl.broken = "ignore";
          # Suppress the per-eval x86_64-darwin deprecation warning from
          # nixpkgs (it fires on every flake check / hms on this Intel
          # Mac). The deprecation is acknowledged -- 26.05 is the last
          # release supporting x86_64-darwin -- and tracked separately
          # from CI noise.
          allowDeprecatedx86_64Darwin = true;
        };
        overlays = [
          doom-emacs.overlays.default
          claude-code.overlays.default
          skipDirenvChecksOnDarwin
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
            ./modules/tmux-helper/default.nix
            ./modules/sops.nix
            ./modules/docker-terminal.nix
            ./modules/emacs-mcp.nix
            ./modules/claude-code.nix
            ./home/common.nix
          ]
          ++ (
            if isLinux
            then [./home/linux.nix]
            else [
              ./home/darwin.nix
              ./modules/zscaler-bypass.nix
              ./modules/displayplacer.nix
              # Zscaler bypass routes only on corporate machines (user 888973)
              {my.zscalerBypass.enable = username == "888973";}
            ]
          )
          ++ [
            {
              home = {
                inherit username homeDirectory;
                stateVersion = "25.05";
              };

              my = {
                tmux.enable = true;
                tmux.theme.preset = "nord";
                tmuxHelper.enable = true;
                emacs = {
                  enable = true;
                  package = pkgs.emacsWithDoom {
                    doomDir = ./modules/emacs/doom.d;
                    doomLocalDir = "~/.local/share/nix-doom";
                  };
                };
                zsh.extraAliases.hms = ''home-manager switch --flake "$HOME/.config/home-manager#${username}@${system}" -b backup'';
                zsh.extraAliases.hmn = ''home-manager news --flake "$HOME/.config/home-manager#${username}@${system}"'';
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

    # All users that support a given system
    usersForSystem = system:
      builtins.filter (user: builtins.elem system user.systems) userConfig.users;

    # Find the first user that supports a given system.
    # CAVEAT: this head-pick is only safe for single-user contexts (CI's
    # packages.default, the Linux dockerImage). On shared systems like
    # aarch64-darwin (gfoster + 888973) it returns gfoster; use the
    # per-user packages."home-<username>" outputs or apps.default (which
    # resolves $USER at runtime) instead.
    userForSystem = system: let
      matchingUsers = usersForSystem system;
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

        # Per-user activation packages: every user on this system is
        # addressable as packages."home-<username>" regardless of the
        # userForSystem head-pick (e.g. .#home-888973 on aarch64-darwin).
        perUserPackages = builtins.listToAttrs (
          map (u: {
            name = "home-${u.username}";
            value = homeConfigs."${u.username}@${system}".activationPackage;
          }) (usersForSystem system)
        );
      in
        perUserPackages
        // {
          tmux-helper = pkgs.callPackage ./modules/tmux-helper/package.nix {};
        }
        // (
          if user != null
          then let
            inherit (user) username;
            homeDirectory = homeDirectoryFor {inherit system username;};
            configKey = "${username}@${system}";
          in
            {
              # Head-picked first matching user — kept for CI convenience.
              # On multi-user systems prefer packages."home-<username>".
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
                # CI variant: executable that streams the image tarball to
                # stdout for `./result | docker load` — no tar.gz in the
                # store, no layer-assembly scratch (runner disk pressure).
                dockerImageStream = import ./lib/docker-image.nix {
                  inherit pkgs homeDirectory username;
                  homeConfiguration = homeConfigs.${configKey};
                  imageName = dockerImageName;
                  stream = true;
                };
              }
              else {}
            )
          else {}
        )
    );

    apps = forAllSystems (
      system: let
        user = userForSystem system;
        pkgs = pkgsFor system;
        isLinux = !(nixpkgs.lib.hasInfix "darwin" system);
      in
        {
          # Resolves the invoking user at runtime, so the same `nix run`
          # activates the correct config on multi-user systems (e.g. both
          # gfoster and 888973 on aarch64-darwin) instead of head-picking.
          default = {
            type = "app";
            meta.description = "Activate home-manager configuration for the current user";
            program = "${pkgs.writeShellApplication {
              name = "activate-home";
              text = ''
                echo "Activating home-manager configuration for $USER@${system}..."
                home-manager switch --flake "$HOME/.config/home-manager#$USER@${system}" -b backup
              '';
            }}/bin/activate-home";
          };
        }
        // (
          if user != null && isLinux
          then {
            docker-test = import ./lib/docker-test-app.nix {
              inherit pkgs;
              homeDirectory = homeDirectoryFor {
                inherit system;
                inherit (user) username;
              };
              imageName = dockerImageName;
            };
          }
          else {}
        )
        // {
          tmux-helper-install = {
            type = "app";
            meta.description = "Install /usr/local/bin/tmux-helper for stable BT-fingerprintable path on macOS";
            program = "${import ./modules/tmux-helper/install-script.nix {
              inherit pkgs;
              helperPackage = pkgs.callPackage ./modules/tmux-helper/package.nix {};
            }}/bin/tmux-helper-install";
          };

          tmux-experimental = let
            helperPkg = pkgs.callPackage ./modules/tmux-helper/package.nix {};
            helperBin = "${helperPkg}/bin/tmux-helper";
            themesJson =
              pkgs.writeText "tmux-themes.json"
              (builtins.toJSON (import ./modules/tmux/themes.nix));
            confText = import ./modules/tmux/conf-experimental.nix {
              inherit helperBin;
              defaultThemePreset = "molokai";
            };
            conf = pkgs.writeText "tmux-experimental.conf" confText;
          in {
            type = "app";
            meta.description = "Experimental tmux server using tmux-helper (parallel to gpakosz daily driver)";
            program = "${pkgs.writeShellApplication {
              name = "tmux-experimental";
              runtimeInputs = [pkgs.tmux];
              text = ''
                export TMUX_HELPER_CONF=${conf}
                export TMUX_HELPER_THEMES=${themesJson}
                exec tmux -L experimental -f ${conf} new-session
              '';
            }}/bin/tmux-experimental";
          };

          update-vim-plugins = {
            type = "app";
            meta.description = "Fetch latest lazy.nvim + LazyVim versions and hashes for modules/vim/default.nix";
            program = "${pkgs.writeShellApplication {
              name = "update-vim-plugins";
              runtimeInputs = [pkgs.curl pkgs.jq pkgs.nix-prefetch-github];
              text = ''
                fetch_latest_tag() {
                  local owner="$1" repo="$2" tag
                  tag=$(curl -sL "https://api.github.com/repos/$owner/$repo/releases/latest" \
                    | jq -r '.tag_name')
                  if [ -z "$tag" ] || [ "$tag" = "null" ]; then
                    echo "error: failed to fetch release tag for $owner/$repo (got: '$tag')" >&2
                    return 1
                  fi
                  echo "$tag"
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
    );

    checks = forAllSystems (
      system: let
        pkgs = pkgsFor system;
      in {
        tmux-helper-build = pkgs.callPackage ./modules/tmux-helper/package.nix {};

        # Runs go vet across the helper sources. buildGoModule's checkPhase
        # already runs go test, but vet only fires for packages with _test.go
        # files; this check exercises every package regardless.
        tmux-helper-vet =
          pkgs.runCommand "tmux-helper-vet" {
            nativeBuildInputs = [pkgs.go];
          } ''
            export HOME=$TMPDIR
            export GOCACHE=$TMPDIR/go-build
            # Match package.nix: helper is built CGO_ENABLED=0, so vet (which
            # otherwise resolves runtime/cgo and demands gcc) must match.
            export CGO_ENABLED=0
            cp -r ${./modules/tmux-helper/src} src
            chmod -R u+w src
            cd src
            go vet ./...
            touch $out
          '';
      }
    );
  };
}
