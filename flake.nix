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

    # Always-current claude-code: nixpkgs lags npm by several patch releases,
    # so this flake (auto-bumped daily upstream) is the source of truth for
    # the CLI. Its overlay replaces pkgs.claude-code; `nfu` pulls the newest
    # pin each run. Prebuilt binaries available from claude-code.cachix.org.
    claude-code = {
      url = "github:sadjow/claude-code-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Pre-commit / pre-push git hooks (statix/deadnix/alejandra/shellcheck on
    # commit, `nix flake check` on push). Installed into .git/hooks via the
    # devShell shellHook, which direnv (.envrc) loads automatically.
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # TEMPORARY (2026-06-27): pin mise on Darwin only. nixos-unstable's mise
    # 2026.6.11 fails its Rust test suite on the macOS CI runner
    # (oci::layer ...preserve_metadata_dir... panics), breaking the Darwin home
    # build. This is the last channel rev that built mise green (2026.6.0); see
    # pinMiseOnDarwin. Remove this input + the overlay once the channel's mise
    # builds on Darwin again. Linux tracks the channel (mise builds fine there).
    nixpkgs-mise.url = "github:NixOS/nixpkgs/8c3cede7ddc26bd659d2d383b5610efbd2c7a16e";

    # x86_64-darwin pin. Nixpkgs 26.11 dropped the platform outright:
    # legacyPackages.x86_64-darwin throws at the genAttrs level, so EVERY
    # output instantiated for it fails at eval -- packages, apps, checks and
    # devShells, not just the home configuration.
    #
    # config.allowDeprecatedx86_64Darwin = true is now a documented no-op. The
    # live value is the string "force", and that only skips the eval throw: the
    # x86_64 stdenv bootstrap files were deleted in nixpkgs#535508, so a forced
    # eval still dies in stdenv. nixpkgs-26.05-darwin is the last supporting
    # branch and is what upstream's own error message points at.
    #
    # HARD EXPIRY: 26.05 security support ends 2026-12-31. This pin buys the
    # Intel MacBook time, it does not solve anything.
    nixpkgs-darwin-intel.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";

    # Must move in lockstep with the pin above. home-manager master is written
    # against 26.11 and removed x86_64-darwin from its own flakeExposed list in
    # 1817fbe17; driving 26.05 pkgs with master's modules trips its
    # releaseMismatch warning and is explicitly unsupported.
    home-manager-darwin-intel = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs-darwin-intel";
    };
  };

  outputs = {
    nixpkgs,
    home-manager,
    nixos-wsl,
    doom-emacs,
    sops-nix,
    claude-code,
    git-hooks,
    nixpkgs-mise,
    nixpkgs-darwin-intel,
    home-manager-darwin-intel,
    ...
  }: let
    # Read user configuration.
    # config.local.nix (gitignored) is recursively merged over config.nix:
    # nested attribute sets merge key-by-key, so you only specify the leaves
    # you want to change; lists and scalar values REPLACE the base value
    # wholesale (recursiveUpdate semantics — no list concatenation, e.g.
    # overriding `users` replaces the whole list). Typical uses: git
    # identity, repo/cachix settings, a host module's Homebrew lists.
    # See config.local.nix.example for the format.
    userConfig = let
      base = import ./config.nix;
      local =
        if builtins.pathExists ./config.local.nix
        then import ./config.local.nix
        else {};
    in
      nixpkgs.lib.recursiveUpdate base local;
    repoConfig = userConfig.repo;
    gitConfig = userConfig.git;

    allSystems = ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"];
    forAllSystems = nixpkgs.lib.genAttrs allSystems;

    # Systems that cannot track the channel and are served by a pinned
    # nixpkgs instead. Single source of truth: pkgsFor, the home-manager
    # selection, the mise overlay and devShells all key off isPinned rather
    # than testing the system string themselves, so adding or retiring a
    # pinned platform is one edit here.
    pinnedSystems = ["x86_64-darwin"];
    isPinned = system: builtins.elem system pinnedSystems;

    nixpkgsFor = system:
      if isPinned system
      then nixpkgs-darwin-intel
      else nixpkgs;

    homeManagerFor = system:
      if isPinned system
      then home-manager-darwin-intel
      else home-manager;

    # Setting programs.direnv.package alone isn't enough: something else in
    # the activation closure still pulls vanilla pkgs.direnv and runs its
    # zsh test suite, which hangs the macOS-14 CI runner. Overriding via
    # pkgsFor ensures every consumer of pkgs.direnv gets the patched build.
    skipDirenvChecksOnDarwin = _final: prev:
      nixpkgs.lib.optionalAttrs prev.stdenv.hostPlatform.isDarwin {
        direnv = prev.direnv.overrideAttrs (_: {doCheck = false;});
      };

    # See the nixpkgs-mise input: source mise from a known-good rev on Darwin
    # only, sidestepping the failing test in the channel's current mise.
    #
    # Takes `system` so it can skip pinned platforms. Without that it fires on
    # prev.stdenv.hostPlatform.isDarwin for the pinned pkgs too and splices a THIRD nixpkgs
    # into that closure, to work around a channel bug 26.05 never had.
    pinMiseOnDarwin = system: _final: prev:
      nixpkgs.lib.optionalAttrs (prev.stdenv.hostPlatform.isDarwin && !(isPinned system)) {
        mise = nixpkgs-mise.legacyPackages.${prev.stdenv.hostPlatform.system}.mise;
      };

    pkgsFor = system:
      import (nixpkgsFor system) {
        inherit system;
        config =
          {
            allowUnfree = true;
            # sbcl is marked broken on darwin in nixpkgs-unstable.
            # It's pulled into the home-manager activation eval (transitively
            # via emacs lisp packages) so the eval refuses outright. "ignore"
            # lets eval proceed; if a subsequent build actually invokes sbcl
            # we'll surface the real failure there instead of at eval-time.
            # 26.05 ships pkgs/stdenv/generic/problems.nix as well, so this key
            # is portable across both nixpkgs rather than 26.11-only.
            problems.handlers.sbcl.broken = "ignore";
          }
          # Only meaningful on the pinned branch: 26.05 WARNS about the
          # x86_64-darwin deprecation and this silences it. On 26.11 the same
          # key does nothing whatsoever, so setting it there would be a comment
          # that lies.
          // nixpkgs.lib.optionalAttrs (isPinned system) {
            allowDeprecatedx86_64Darwin = true;
          };
        overlays = [
          doom-emacs.overlays.default
          claude-code.overlays.default
          skipDirenvChecksOnDarwin
          (pinMiseOnDarwin system)
        ];
      };

    # git-hooks.nix config: fast lint (statix/deadnix/alejandra/shellcheck) on
    # every commit. No pre-push `nix flake check`: it takes minutes and holds the
    # push connection open long enough that GitHub drops it (push times out). CI
    # runs `nix flake check` on every push to the remote, and input/nixpkgs bumps
    # are checked locally by hand before pushing (see the workflow notes).
    preCommitFor = system:
      git-hooks.lib.${system}.run {
        src = ./.;
        hooks = {
          statix.enable = true;
          deadnix.enable = true;
          alejandra.enable = true;
          shellcheck.enable = true;
        };
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
      # Host module name resolved from the users.*.hosts mapping in
      # config.nix; null means "generic platform profile only".
      host ? null,
    }: let
      pkgs = pkgsFor system;
      homeDirectory = homeDirectoryFor {inherit system username;};
      isDarwin = nixpkgs.lib.hasInfix "darwin" system;
      isLinux = !isDarwin;
    in
      (homeManagerFor system).lib.homeManagerConfiguration {
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
            ./modules/emacs-doctor/default.nix
            ./modules/tmux/default.nix
            ./modules/tmux-helper/default.nix
            ./modules/sops.nix
            ./modules/docker-terminal.nix
            ./modules/emacs-mcp.nix
            ./modules/claude-code.nix
            ./modules/claude-specflow.nix
            ./modules/claude-skills.nix
            ./modules/claude-kg/default.nix
            ./modules/searxng/default.nix
            ./modules/orrery-mcp.nix
            ./home/common.nix
          ]
          ++ (
            if isLinux
            then [./home/linux.nix]
            else [
              ./home/darwin.nix
              ./modules/zscaler-bypass.nix
              ./modules/displayplacer.nix
            ]
          )
          # Machine-specific layer (Homebrew lists, build farm, WSL interop,
          # Zscaler bypass, ...) — see the users.*.hosts mapping in config.nix.
          ++ nixpkgs.lib.optional (host != null) (./home/hosts + "/${host}.nix")
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
                emacsDoctor.enable = true;
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
                  host = (user.hosts or {}).${system} or null;
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
        # emacs-doctor is Linux-only (systemd/proc/WSLg); expose it only there
        # so darwin `nix flake check` doesn't try to build an unsupported pkg.
        // nixpkgs.lib.optionalAttrs isLinux {
          emacs-doctor = pkgs.callPackage ./modules/emacs-doctor/package.nix {};
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
                # Slim rescue-shell image: zsh + tmux + git + core CLI, no
                # home-manager closure (editors/LSPs). ~240MB vs multi-GB.
                # Usage: $(nix build .#dockerImageSlim --print-out-paths) | docker load
                dockerImageSlim = import ./lib/docker-image.nix {
                  inherit pkgs homeDirectory username;
                  profile = "slim";
                  imageName = "${dockerImageName}-slim";
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

    devShells = forAllSystems (
      system: let
        pkgs = pkgsFor system;
      in {
        # `direnv allow` (or `nix develop`) installs the git hooks via this
        # shellHook and keeps them current.
        #
        # Pinned systems get a bare shell. git-hooks.lib.<system> is built from
        # legacyPackages.<system> of the FOLLOWED (channel) nixpkgs, so merely
        # naming it for a dropped platform re-triggers the 26.11 throw no matter
        # which nixpkgs pkgsFor returned. The hooks are a contributor
        # convenience, not a build input, so the Intel Mac goes without.
        default =
          if isPinned system
          then pkgs.mkShell {}
          else
            pkgs.mkShell (let
              pre-commit = preCommitFor system;
            in {
              inherit (pre-commit) shellHook;
              buildInputs = pre-commit.enabledPackages;
            });
      }
    );

    checks = forAllSystems (
      system: let
        pkgs = pkgsFor system;
      in
        {
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
        # Regression guards for resolved review findings. Pure-eval +
        # trivial builds; defined once on x86_64-linux (the guarded content
        # is identical across systems). `nix flake check` fails if any
        # future change reintroduces these.
        // nixpkgs.lib.optionalAttrs (system == "x86_64-linux") (let
          user = userForSystem system;
          settingsText =
            homeConfigs."${user.username}@${system}".config.home.file.".claude/settings.json".text;
        in {
          # 1. Claude Code must never attribute itself in commits/PRs, and
          #    emacs_eval (arbitrary elisp = arbitrary shell) must never be
          #    auto-allowed.
          claude-settings-guards =
            pkgs.runCommand "claude-settings-guards" {
              nativeBuildInputs = [pkgs.jq];
              settings = settingsText;
              passAsFile = ["settings"];
            } ''
              jq -e '.attribution == {commit: "", pr: ""}' "$settingsPath" >/dev/null \
                || { echo 'GUARD: settings.json attribution must be {commit: "", pr: ""}'; exit 1; }
              jq -e '(.permissions.allow // []) | index("mcp__emacs__emacs_eval") == null' "$settingsPath" >/dev/null \
                || { echo 'GUARD: mcp__emacs__emacs_eval must not be auto-allowed'; exit 1; }
              touch $out
            '';

          # 2. The docker terminal must never bind-mount ~/.ssh (it holds the
          #    sops-decrypted private key); SSH is agent-forwarding only.
          docker-terminal-no-ssh-mount = pkgs.runCommand "docker-terminal-no-ssh-mount" {} ''
            if grep -q '\$HOME/\.ssh:' ${./modules/docker-terminal.nix} ${./lib/docker-test-app.nix}; then
              echo 'GUARD: ~/.ssh must not be bind-mounted into containers'
              exit 1
            fi
            touch $out
          '';
        })
    );
  };
}
