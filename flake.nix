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

    # A MELPA/ELPA snapshot fresher than the channel's, and the source of
    # the emacs-unstable* attributes when Emacs 31 is worth moving to.
    #
    # It arrived as a transitive input of nix-doom-emacs-unstraightened and was
    # promoted to a direct one so both could share a single node; that input is
    # gone and this one stayed, because pkgs.emacs.pkgs is where every package
    # in modules/emacs/vanilla/package.nix comes from.
    #
    # follows: emacs-overlay's own nixpkgs inputs are read ONLY by its
    # packages/lib/hydraJobs outputs. overlays.default is a plain
    # `final: prev:` taking everything from prev, so the follows target does
    # not change a byte of what gets built -- it exists purely to keep the lock
    # from gaining a third and fourth nixpkgs.
    #
    # It gets NO pinned counterpart for x86_64-darwin: emacs-overlay publishes
    # a single rolling branch with no 26.05 equivalent. See the guard in
    # `checks` for how that is kept honest.
    emacs-overlay = {
      url = "github:nix-community/emacs-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.nixpkgs-stable.follows = "nixpkgs";
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
    # commit, `nix flake check` on push). Installed into .git/hooks by
    # `nix run .#install-hooks`, which the devShell starts for you -- NOT from
    # the devShell shellHook directly. Evaluating this input is ~19s of the
    # ~42s the old devShell put on every `cd`; the linters were the other ~22s.
    # See lib/dev-shell.nix.
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
    sops-nix,
    claude-code,
    git-hooks,
    nixpkgs-mise,
    nixpkgs-darwin-intel,
    home-manager-darwin-intel,
    emacs-overlay,
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
          # Makes the overlay's MELPA/ELPA snapshot reachable as
          # pkgs.emacs.pkgs, which is the package set
          # modules/emacs/vanilla/package.nix draws its whole explicit list
          # from.
          emacs-overlay.overlays.default
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
    #
    # NOT referenced by devShells.default any more: it was ~19s of the ~42s of
    # evaluation the old devShell put on every `cd`, and the devShell sits on
    # the interactive path. It reaches .git/hooks through
    # `nix run .#install-hooks` instead -- see lib/dev-shell.nix.
    preCommitFor = system:
      git-hooks.lib.${system}.run {
        src = ./.;
        hooks = import ./lib/pre-commit-hooks.nix;
      };

    # Cheap staleness token for the installed hooks. It has to be computable
    # WITHOUT evaluating git-hooks.nix -- that is the whole point -- so it
    # hashes the files that actually determine what gets installed, rather than
    # the derivations they produce. A handful of hashFile calls on small files;
    # the devShell shellHook carries the result as a literal.
    #
    # The hook set and the lock the tools are resolved from were the original
    # two. The three script bodies are here because they were an oversight:
    # `install-hooks` writes lib/warm-direnv.sh and lib/link-pc-config.sh into
    # .git/hooks as store paths, and lib/install-hooks.sh decides what else
    # lands there, so editing any of them changes the installed hooks while
    # leaving the stamp -- and therefore every existing clone -- unmoved. The
    # bug that exposed this was a change to the hook BODIES with no change to
    # flake.lock. Hashing flake.nix instead is still wrong: it moves on every
    # unrelated edit and would force a reinstall each time.
    devHooksStamp =
      builtins.hashString "sha256"
      (builtins.hashFile "sha256" ./flake.lock
        + builtins.hashFile "sha256" ./lib/pre-commit-hooks.nix
        + builtins.hashFile "sha256" ./lib/install-hooks.sh
        + builtins.hashFile "sha256" ./lib/warm-direnv.sh
        + builtins.hashFile "sha256" ./lib/link-pc-config.sh);

    # One definition, two consumers: packages.lint-tools (what verify.sh and
    # ci.yml resolve, per the lint-tools-pinned guard) and the devShell -- which
    # reaches it INDIRECTLY, through .direnv/lint-tools, rather than naming the
    # derivation. Evaluating this set costs ~31s and the devShell is on the
    # `cd` path; see lib/dev-shell.nix.
    lintToolsFor = system: (pkgsFor system).callPackage ./lib/lint-tools.nix {};

    devShellFor = system:
      import ./lib/dev-shell.nix {
        pkgs = pkgsFor system;
        preCommit = preCommitFor system;
        lintTools = lintToolsFor system;
        hooksStamp = devHooksStamp;
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
            ./modules/dev-tools.nix
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
                  # The only Emacs, on every platform. Doom was retired here;
                  # see modules/emacs/vanilla/DESIGN.md for what this config
                  # is and modules/emacs/default.nix for what went with it.
                  package = pkgs.callPackage ./modules/emacs/vanilla/package.nix {};
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

          # The linters every gate in this repo runs, pinned to this flake's
          # nixpkgs. modules/emacs/vanilla/verify.sh and ci.yml's lint job
          # both resolve THIS derivation rather than `nix run nixpkgs#<tool>`,
          # which reads the runner's registry and silently gave the two
          # different versions of shellcheck (red CI, PR #21). Deliberately
          # NOT gated to one system: cross-machine agreement is the point.
          #
          # It is also what the devShell puts on PATH, indirectly: evaluating
          # this set costs ~31s, so `nix run .#install-hooks` materialises it
          # at .direnv/lint-tools (GC-rooted) and the shellHook adds that
          # directory, rather than the devShell naming the derivation and
          # paying for it on every `cd`. See lib/dev-shell.nix.
          lint-tools = lintToolsFor system;
        }
        # emacs-doctor is Linux-only (systemd/proc/WSLg); expose it only there
        # so darwin `nix flake check` doesn't try to build an unsupported pkg.
        // nixpkgs.lib.optionalAttrs isLinux {
          emacs-doctor = pkgs.callPackage ./modules/emacs-doctor/package.nix {};
          # Linux-gated for the same reason as emacs-doctor: `nix flake check`
          # runs under forAllSystems, and an ungated attribute makes it try to
          # BUILD this on darwin.
          emacs-vanilla = pkgs.callPackage ./modules/emacs/vanilla/package.nix {};
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
        # Pinned systems have no git-hooks.lib (see the devShells comment), so
        # naming the installer there would re-trigger the 26.11 throw.
        // nixpkgs.lib.optionalAttrs (!isPinned system) {
          # The expensive half of the old devShell shellHook, lifted out of the
          # `cd` path. devShells.default runs this itself when the installed
          # hooks are missing (foreground) or stale (background); it is exposed
          # as an app so it is also runnable by hand, which is the documented
          # recovery when either of those goes wrong.
          install-hooks = {
            type = "app";
            meta.description = "Install the pre-commit git hooks and the linter bundle into this clone";
            program = "${(devShellFor system).installHooks}/bin/install-hooks";
          };
        }
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

          # Throwaway foreground Emacs for trying a config change without an
          # `hms`, mirroring `nix run .#tmux-experimental`.
          #
          # --init-directory points at a READ-ONLY store path deliberately:
          # this run IS the test that early-init.el has redirected every
          # writable path (eln-cache, custom.el, auto-save, recentf, transient)
          # out of user-emacs-directory. If it tries to write into the store,
          # the redirect is incomplete -- fix early-init.el, do not make the
          # directory writable.
          #
          # No --daemon: it opens no server socket, so it cannot collide with
          # the running daemon.
          emacs-vanilla = let
            vanilla = pkgs.callPackage ./modules/emacs/vanilla/package.nix {};
          in {
            type = "app";
            meta.description = "Throwaway foreground Emacs from this flake, no daemon and no socket";
            program = "${pkgs.writeShellApplication {
              name = "emacs-vanilla";
              text = ''
                exec ${vanilla}/bin/emacs \
                  --init-directory=${vanilla.configDir} "$@"
              '';
            }}/bin/emacs-vanilla";
          };
        }
    );

    devShells = forAllSystems (
      system: let
        pkgs = pkgsFor system;
      in {
        # `direnv allow` (or `nix develop`) bootstraps the git hooks through
        # this shellHook and keeps them current -- but it does the expensive
        # part out of line, in `nix run .#install-hooks`. See lib/dev-shell.nix
        # for why, with the measurements: naming git-hooks.nix and the linters here cost ~42s
        # of evaluation on the first `cd` after every weekly flake.lock bump.
        #
        # Pinned systems get a bare shell. git-hooks.lib.<system> is built from
        # legacyPackages.<system> of the FOLLOWED (channel) nixpkgs, so merely
        # naming it for a dropped platform re-triggers the 26.11 throw no matter
        # which nixpkgs pkgsFor returned. The hooks are a contributor
        # convenience, not a build input, so the Intel Mac goes without.
        default =
          if isPinned system
          then pkgs.mkShell {}
          else (devShellFor system).shell;
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
          dev = devShellFor system;
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

          # 3. CI must actually start Emacs, and it must start a DAEMON.
          #
          #    `emacs --batch` does NOT load init.el at all, so a batch check
          #    reports success while having loaded nothing. That is how six
          #    leader keys reached master bound to void commands (PR #15) with
          #    every CI job green. modules/emacs/vanilla/verify.sh starts a
          #    real daemon from the store configDir and walks the actual
          #    leader keymap; ci.yml runs it in the build-home job.
          #
          #    This guard exists because the failure mode of a deleted gate is
          #    a GREEN CI, and this repo has already been bitten by exactly
          #    that shape: `build-home` carried a job-level
          #    `if: github.event_name == 'push'`, so it reported "skipping" on
          #    every pull request and no PR ever built the Linux closure
          #    (observed on PR #14). Hence (a) as well as (b) and (c).
          ci-emacs-gate =
            pkgs.runCommand "ci-emacs-gate" {
              nativeBuildInputs = [pkgs.yq-go];
              ciWorkflow = ./.github/workflows/ci.yml;
            } ''
              # (a) build-home must not be gated off for pull requests again.
              #     Its event-dependence lives in the matrix, not in a
              #     job-level `if` (which cannot see the matrix context and so
              #     can only skip the WHOLE job, Linux build included).
              yq -e '.jobs["build-home"] | has("if") | not' "$ciWorkflow" >/dev/null \
                || { echo 'GUARD: build-home has a job-level `if` again -- that is what made it skip on every PR (#14). Gate the matrix, not the job.'; exit 1; }

              # (b) exactly one build-home step runs the Emacs gate.
              yq -e '[.jobs["build-home"].steps[] | select((.run // "") | contains("modules/emacs/vanilla/verify.sh"))] | length == 1' "$ciWorkflow" >/dev/null \
                || { echo 'GUARD: no build-home step runs modules/emacs/vanilla/verify.sh -- the only CI step that starts Emacs is gone.'; exit 1; }

              # (c) nothing in ci.yml may run Emacs in batch mode. Comments are
              #     stripped first so the explanatory ones may say the word.
              if grep -vE '^[[:space:]]*#' "$ciWorkflow" | grep -q -- '--batch'; then
                echo 'GUARD: --batch does not load init.el; the Emacs gate must start a real daemon.'
                exit 1
              fi

              touch $out
            '';

          # 4. The linters must keep coming from this flake, not from the
          #    runner's flake registry.
          #
          #    `nix run nixpkgs#<tool>` resolves through the REGISTRY, which
          #    is a property of the machine running the command and not of
          #    this repo. verify.sh and ci.yml each did that, so the two ran
          #    whatever versions they each resolved. PR #21 went red on
          #    exactly that: shellcheck renumbered one finding (SC2329 in
          #    0.11, SC2317 in earlier releases), the file suppressed only
          #    the newer code, it passed locally on 0.11.0 and failed CI on
          #    an older one. Both now resolve packages.<system>.lint-tools.
          #
          #    Guarded because the failure mode is invisible until the day
          #    the two versions happen to disagree, which is to say: on
          #    somebody else's pull request.
          lint-tools-pinned =
            pkgs.runCommand "lint-tools-pinned" {
              nativeBuildInputs = [pkgs.yq-go];
              ciWorkflow = ./.github/workflows/ci.yml;
              verifySh = ./modules/emacs/vanilla/verify.sh;
            } ''
              # (a) no step of the lint job may resolve a tool from the
              #     registry. yq reads the parsed YAML, so the explanatory
              #     comments in ci.yml are excluded for free.
              yq -e '[.jobs.lint.steps[] | select((.run // "") | contains("nixpkgs#"))] | length == 0' "$ciWorkflow" >/dev/null \
                || { echo 'GUARD: a ci.yml lint step resolves a tool through nixpkgs# -- that is the runner registry, not this flake. Use .#lint-tools.'; exit 1; }

              # (b) nor may the emacs gate. Comments are stripped first so
              #     the paragraph explaining all this may name the thing.
              if grep -vE '^[[:space:]]*#' "$verifySh" | grep -q 'nixpkgs#'; then
                echo 'GUARD: verify.sh resolves a linter through nixpkgs# -- that is the runner registry, not this flake. Use $REPO#lint-tools.'
                exit 1
              fi

              # (c) and it must not reach for --impure again. This was the
              #     only --impure in the repo (`nix eval --impure --expr
              #     builtins.currentSystem`); `nix config show system`
              #     answers the same question from nix's settings. Kept in
              #     this guard rather than a new one because it is the same
              #     file and the same claim: what this gate runs is a
              #     function of the flake, not of the machine.
              if grep -vE '^[[:space:]]*#' "$verifySh" | grep -q -- '--impure'; then
                echo 'GUARD: verify.sh uses --impure. For the system double use `nix config show system`.'
                exit 1
              fi

              touch $out
            '';

          # 5. The devShell must stay off the expensive path, AND the hooks
          #    must still actually get installed. These two guards are a pair:
          #    either one alone can be satisfied by the bug the other catches.
          #
          #    History: devShells.default used to inherit git-hooks.nix's
          #    shellHook AND its enabledPackages. Between them that put ~56s of
          #    evaluation on every `cd` into the repo whenever flake.lock had
          #    moved -- which it does every week, unattended, via
          #    update-flake.yml. Measured cold `direnv export bash` was 55-58s
          #    here on a warm store, and over five minutes on one that also had
          #    to fetch.
          #
          #    Read off the devShell DERIVATION, not off lib/dev-shell.nix's
          #    `shellHook` attribute: the first cut of this guard inspected the
          #    latter, and a deliberate re-introduction of the regression --
          #    `mkShell { shellHook = shellHook + preCommit.shellHook; }` --
          #    sailed straight past it. A guard has to be shown failing.
          devshell-stays-light =
            pkgs.runCommand "devshell-stays-light" {
              # dev.shell is verbatim what devShells.default is on this
              # system (x86_64-linux is not pinned), and unlike `devShells` it
              # is in scope here -- outputs is a plain attrset, not rec.
              hookText = dev.shell.shellHook or "";
              # The other way back in is `buildInputs = pre-commit.enabledPackages`.
              inputPaths =
                builtins.concatStringsSep "\n"
                (map toString (
                  (dev.shell.buildInputs or [])
                  ++ (dev.shell.nativeBuildInputs or [])
                ));
              passAsFile = ["hookText" "inputPaths"];
            } ''
              # git-hooks.nix's installer is identifiable by the line it logs
              # when it rewrites a repo. If that text is in the shellHook, the
              # whole derivation is being evaluated on the `cd` path again.
              if grep -q 'git-hooks.nix: updating' "$hookTextPath"; then
                echo 'GUARD: devShells.default runs the git-hooks.nix installer again.'
                echo '       That is ~19s of evaluation on every `cd` after a flake.lock bump.'
                echo '       Hook installation belongs in `nix run .#install-hooks`; see lib/dev-shell.nix.'
                exit 1
              fi
              # Same argument for the linters, which are the other ~22s. They reach
              # PATH via .direnv/lint-tools, which install-hooks materialises.
              if grep -qE '/nix/store/[a-z0-9]{32}-(shellcheck|statix|deadnix|alejandra|pre-commit)' \
                   "$hookTextPath" "$inputPathsPath"; then
                echo 'GUARD: devShells.default pulls in a linter or pre-commit store path directly.'
                echo '       Use packages.lint-tools via .direnv/lint-tools instead.'
                exit 1
              fi
              touch $out
            '';

          # 6. ... and the counterweight: install-hooks must really run the
          #    upstream installer. A fast shell that quietly stopped writing
          #    .git/hooks/pre-commit would be a regression, not a fix.
          install-hooks-installs-hooks =
            pkgs.runCommand "install-hooks-installs-hooks" {
              installer = "${dev.gitHooksInstaller}/bin/hm-git-hooks-install";
              appText = builtins.readFile ./lib/install-hooks.sh;
              passAsFile = ["appText"];
            } ''
              # (a) the wrapped script really is git-hooks.nix's installer,
              #     not an empty stub left behind by an upstream API change.
              grep -q 'git-hooks.nix: updating' "$installer" \
                || { echo 'GUARD: hm-git-hooks-install no longer contains the git-hooks.nix installer.'; exit 1; }

              # (b) the app actually invokes it.
              grep -q '@GIT_HOOKS_INSTALLER@' "$appTextPath" \
                || { echo 'GUARD: lib/install-hooks.sh no longer invokes the git-hooks installer.'; exit 1; }

              # (c) and refuses to stamp success it did not achieve. Without
              #     this the devShell would believe the hooks were installed
              #     and never retry.
              grep -q 'was not installed' "$appTextPath" \
                || { echo 'GUARD: lib/install-hooks.sh no longer verifies that .git/hooks/pre-commit exists before stamping.'; exit 1; }

              # (d) and can still REPAIR a deleted hook. git-hooks.nix's
              #     installer converges on .pre-commit-config.yaml alone: with
              #     that symlink intact it returns without touching
              #     .git/hooks, so a deleted pre-commit hook is never restored
              #     and the devShell asks for a reinstall on every `cd`
              #     forever. Dropping the symlink first is the repair.
              grep -q 'rm -f "$repo/.pre-commit-config.yaml"' "$appTextPath" \
                || { echo 'GUARD: lib/install-hooks.sh cannot repair a deleted pre-commit hook -- it must clear .pre-commit-config.yaml first.'; exit 1; }

              # (e) the warm hooks must be rooted in the SHARED git dir, not
              #     under a per-worktree .direnv. .git/hooks is shared by every
              #     worktree, so a root that `direnv prune` or
              #     `git worktree remove` can take away is shorter-lived than
              #     the hook it protects -- and a collected script makes every
              #     `git checkout` in every worktree print an exec error.
              grep -qF 'gcroots="$hooks/.hm-gcroots"' "$appTextPath" \
                || { echo 'GUARD: install-hooks no longer roots the warm hooks in the shared git dir.'; exit 1; }
              grep -qF 'pin "@WARM_DIRENV_STORE@" "$gcroots/warm-direnv"' "$appTextPath" \
                || { echo 'GUARD: warm-direnv is no longer GC-rooted; one nix-collect-garbage breaks every git checkout.'; exit 1; }

              # (f) ... and the hooks must survive losing it anyway, WHILE
              #     something notices. Both halves or neither: an unguarded
              #     exec is noisy on every checkout, and a guarded one with no
              #     repair is a permanent silent no-op -- the "gate that can
              #     only pass" shape this repo keeps getting bitten by.
              grep -qF '[ -x @WARM_DIRENV@ ] || exit 0' "$appTextPath" \
                || { echo 'GUARD: the warm hooks exec a store path unguarded; a collected path errors on every checkout.'; exit 1; }
              grep -qF '.hm-gcroots/warm-direnv' ${./lib/dev-shell-hook.sh} \
                || { echo 'GUARD: the devShell no longer notices a collected warm-direnv, so the guarded exec would fail silently forever.'; exit 1; }

              # (g) a FRESH WORKTREE MUST BE ABLE TO COMMIT, AND BE LINTED.
              #
              #     .git/hooks belongs to the clone; .pre-commit-config.yaml
              #     does not, because the generated hook passes a relative
              #     --config. So `git worktree add` used to leave behind a
              #     worktree the shared pre-commit hook fires in with no config,
              #     and every commit in it died with "No .pre-commit-config.yaml
              #     file was found". This repo's workflow is entirely
              #     worktree-based, so that was every new branch.
              #
              #     Three parts, and all three are needed: record the config
              #     path in the shared git dir, root the linker that reads it,
              #     and actually call the linker from the shared hooks.
              grep -qF 'pin "$pc_config" "$gcroots/pre-commit-config"' "$appTextPath" \
                || { echo 'GUARD: install-hooks no longer records the pre-commit config in the shared git dir.'; \
                     echo '       Without it `git worktree add` produces a worktree that cannot commit.'; exit 1; }
              grep -qF 'pin "@LINK_PC_CONFIG_STORE@" "$gcroots/link-pc-config"' "$appTextPath" \
                || { echo 'GUARD: hm-link-pc-config is no longer GC-rooted.'; exit 1; }
              grep -qF 'if [ -x @LINK_PC_CONFIG@ ]; then @LINK_PC_CONFIG@ || true; fi' "$appTextPath" \
                || { echo 'GUARD: the shared post-checkout hook no longer links a new worktree its .pre-commit-config.yaml.'; \
                     echo '       That hook firing on `git worktree add` is the only moment the worktree can be fixed'; \
                     echo '       before its first commit is refused.'; exit 1; }
              grep -qF '.hm-gcroots/pre-commit-config' ${./lib/dev-shell-hook.sh} \
                || { echo 'GUARD: the devShell can no longer repair a worktree with no .pre-commit-config.yaml.'; exit 1; }

              # (g2) core.hooksPath must be cleared after the installer runs.
              #
              #     git-hooks.nix's last act is
              #       git config --local core.hooksPath "$common_dir/hooks"
              #     with $common_dir stripped of the working copy prefix. Run
              #     from the main checkout that stores the RELATIVE `.git/hooks`
              #     -- and in a linked worktree `.git` is a file, so that names
              #     nothing, git finds no hooks, and every commit in every
              #     worktree of the clone goes through UNLINTED in silence.
              #     Demonstrated, not deduced: a deliberately misformatted .nix
              #     file committed clean in a fresh worktree.
              #
              #     Which of the two broken states a clone is in depends only on
              #     whether install-hooks last ran from the main checkout
              #     (silently unlinted) or from a worktree (every commit
              #     refused). Neither is acceptable, and unsetting fixes both:
              #     git resolves hooks against the common dir on its own.
              #     Anchored to the start of a line on purpose. The first cut of
              #     this guard was a plain -F for the command text, and deleting
              #     the actual `git config` call did not fail it: the same
              #     string survives in the "Fix with: ..." advice this script
              #     prints when the unset fails. A guard a COMMENT can satisfy
              #     is not a guard, and this one was caught by being run against
              #     a tree with the invariant deliberately broken.
              grep -qE '^[[:space:]]*git config --local --unset-all core\.hooksPath' "$appTextPath" \
                || { echo 'GUARD: install-hooks no longer clears core.hooksPath after the git-hooks installer sets it.'; \
                     echo '       A relative core.hooksPath makes linked worktrees run NO hooks and commit unlinted.'; exit 1; }

              # (g3) ... and nothing may resolve the hooks directory through
              #     core.hooksPath alone, because that call FAILS in a linked
              #     worktree while the config is still relative -- which is the
              #     state of every clone that has not re-run install-hooks yet.
              #     All three scripts need the common-dir fallback.
              for f in ${./lib/install-hooks.sh} ${./lib/link-pc-config.sh} ${./lib/dev-shell-hook.sh}; do
                grep -qF 'path-format=absolute --git-common-dir' "$f" \
                  || { echo "GUARD: $f resolves the hooks directory without a common-dir fallback."; \
                       echo '       `--git-path hooks` fatals in a linked worktree when core.hooksPath is relative.'; exit 1; }
              done

              # (h) ... and it must be fixed by CONFIGURING the worktree, never
              #     by making the config optional. `pre-commit install
              #     --allow-missing-config` unblocks the commit by skipping
              #     every linter, and so does the PRE_COMMIT_ALLOW_NO_CONFIG
              #     escape hatch pre-commit advertises in that error. Both
              #     convert "this worktree is misconfigured" into "this worktree
              #     is not linted", silently. A blocked commit is recoverable; a
              #     quietly unlinted one is the gate that can only pass.
              if grep -q -- '--allow-missing-config' "$appTextPath" "$installer"; then
                echo 'GUARD: the pre-commit hook is being installed with --allow-missing-config.'
                echo '       That makes a worktree without a config commit UNLINTED instead of'
                echo '       being told it is misconfigured. Give the worktree a config instead;'
                echo '       see lib/link-pc-config.sh.'
                exit 1
              fi
              touch $out
            '';

          # 7. The background jobs must stay backgrounded. Closing the
          #    inherited descriptors is what makes them detach: direnv hands
          #    the .envrc an extra pipe on FD 3 and reads it to EOF, so a child
          #    that inherits FD 3 blocks the caller no matter how completely
          #    stdin/stdout/stderr are redirected. Measured: 9364ms without
          #    this line, 713ms with it. nohup, setsid and double-forking all
          #    made no difference, so "it looks detached" is not evidence.
          background-jobs-close-fds = pkgs.runCommand "background-jobs-close-fds" {} ''
            for f in ${./lib/dev-shell-hook.sh} ${./lib/warm-direnv.sh}; do
              grep -q 'exec 3>&- 4>&- 5>&- 6>&- 7>&- 8>&- 9>&-' "$f" \
                || { echo "GUARD: $f spawns a background job without closing inherited descriptors."; \
                     echo '       FD 3 is direnv'"'"'s capture pipe; leaving it open re-blocks the caller.'; exit 1; }
            done
            touch $out
          '';

          # 8. The shellHook is a hand-written shell script that mkShell will
          #    never lint for us, and it runs at an interactive prompt where a
          #    syntax error looks like a broken terminal. Lint it here, where
          #    nobody is waiting.
          devshell-hook-lint =
            pkgs.runCommand "devshell-hook-lint" {
              nativeBuildInputs = [pkgs.shellcheck];
            } ''
              cp ${./lib/dev-shell-hook.sh} hook.sh
              shellcheck --shell=bash hook.sh
              cp ${./lib/install-hooks.sh} install-hooks.sh
              shellcheck --shell=bash install-hooks.sh
              cp ${./lib/warm-direnv.sh} warm-direnv.sh
              shellcheck --shell=bash warm-direnv.sh
              cp ${./lib/link-pc-config.sh} link-pc-config.sh
              shellcheck --shell=bash link-pc-config.sh

              touch $out
            '';

          # 9. The specflow branch-policy hook must stay worktree-aware AND
          #    keep failing closed.
          #
          #    The hook decides whether a Bash tool call may commit or push,
          #    from nothing but the command string, before that command runs.
          #    Which directory a commit lands in therefore has to be inferred,
          #    and that inference has now been wrong in both directions.
          #
          #    It shipped reading the branch with a bare `git rev-parse` in
          #    the hook's OWN cwd -- the main checkout, normally sitting on
          #    master -- so every commit made in a worktree was blocked as if
          #    it were a commit on master. The first fix for that (PR #6,
          #    closed unmerged) resolved one directory and fell back to
          #    `|| true`, which turned every parse miss into a silent ALLOW:
          #    it let `cd <worktree> && cd <main> && git commit` and
          #    `cd <nonexistent> && git commit` put a commit on master.
          #
          #    A guard that only checked the worktree case would have passed
          #    on that second version. modules/claude-specflow/tests runs both
          #    directions -- 43 cases, and its own comment lists the eight
          #    deliberate breakages it was confirmed to catch, because a
          #    matrix nobody has ever seen fail proves nothing.
          branch-policy-hook =
            pkgs.runCommand "branch-policy-hook" {
              nativeBuildInputs = [pkgs.bash pkgs.git pkgs.jq];
            } ''
              export HOME="$TMPDIR"
              bash ${./modules/claude-specflow/tests/branch-policy-matrix.sh} \
                ${./modules/claude-specflow/templates/specflow/hooks/branch-policy.sh}

              touch $out
            '';
        })
    );
  };
}
