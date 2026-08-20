{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.my.emacs;

  # The flavor that is NOT the daily driver, or null. Deliberately symmetric:
  # when `flavor` flips to "vanilla", Doom does not disappear -- it becomes the
  # one on a named socket. A bad day is then `emacsclient -s doom`, not a
  # rollback.
  secondary =
    if !cfg.vanilla.enable
    then null
    else if cfg.flavor == "doom"
    then {
      name = "vanilla";
      inherit (cfg.vanilla) serverName package;
      # Vanilla must be told where its config is; Doom bakes --init-directory
      # into its own wrapper and would ignore this.
      extraArgs = ["--init-directory=${config.xdg.configHome}/emacs"];
    }
    else {
      name = "doom";
      serverName = "doom";
      inherit (cfg) package;
      extraArgs = [];
    };

  secondaryName =
    if secondary != null
    then secondary.name
    else "unused";

  # Bring up a daemon if none is answering. On Linux the daemon is owned by a
  # systemd unit, so we start *that* rather than spawning a raw `emacs
  # --daemon`: two daemons racing for one socket deadlocks the unit into a
  # crash loop (the standalone one squats the socket, `--fg-daemon` can never
  # bind it, Restart=on-failure relaunches forever, pegging a core).
  #
  # NEW HAZARD with two flavors: the raw fallback MUST carry `=<serverName>`.
  # A bare `emacs --daemon` from the vanilla wrapper would squat the PRIMARY's
  # socket and reproduce that same deadlock against the daily driver.
  mkEnsureDaemon = {
    package,
    unit,
    serverName ? null,
  }: let
    s = lib.optionalString (serverName != null) " -s ${serverName}";
    d = lib.optionalString (serverName != null) "=${serverName}";
  in ''
    if ! ${package}/bin/emacsclient${s} -n -e "(if (daemonp) t)" >/dev/null 2>&1; then
      echo "Starting Emacs daemon (${unit})..."
      ${
      if pkgs.stdenv.hostPlatform.isLinux
      then "systemctl --user start ${unit} 2>/dev/null || ${package}/bin/emacs --daemon${d} || true"
      else "${package}/bin/emacs --daemon${d} || true"
    }
      for _ in $(seq 1 100); do
        ${package}/bin/emacsclient${s} -n -e t >/dev/null 2>&1 && break
        sleep 0.1
      done
    fi
  '';

  # A GUI-or-TTY wrapper plus a TTY-only wrapper, for one flavor.
  mkClients = {
    guiName,
    ttyName,
    package,
    unit,
    serverName ? null,
  }: let
    ensure = mkEnsureDaemon {inherit package unit serverName;};
    s = lib.optionalString (serverName != null) "-s ${serverName}";
  in [
    (pkgs.writeShellApplication {
      name = guiName;
      text = ''
        ${ensure}
        if [ -t 0 ] && [ -z "''${DISPLAY:-}" ] && [ -z "''${WAYLAND_DISPLAY:-}" ]; then
          exec ${package}/bin/emacsclient ${s} -t "$@"
        else
          exec ${package}/bin/emacsclient ${s} -c "$@"
        fi
      '';
    })
    (pkgs.writeShellApplication {
      name = ttyName;
      text = ''
        ${ensure}
        exec ${package}/bin/emacsclient ${s} -t "$@"
      '';
    })
  ];

  primaryClients = mkClients {
    guiName = "em";
    ttyName = "emt";
    package = cfg.primaryPackage;
    unit = "emacs";
  };

  # Named for the flavor rather than "experimental": emv/emvt for vanilla,
  # emd/emdt for doom. Same idea as `nix run .#tmux-experimental` -- a separate
  # entry point that never shadows the daily driver's `em`/`emt`.
  secondaryClients = lib.optionals (secondary != null) (mkClients {
    guiName = "em${builtins.substring 0 1 secondaryName}";
    ttyName = "em${builtins.substring 0 1 secondaryName}t";
    inherit (secondary) package serverName;
    unit = "emacs-${secondaryName}";
  });
in {
  options.my.emacs = {
    enable = lib.mkEnableOption "Emacs (Doom and/or the hand-built vanilla config)";

    flavor = lib.mkOption {
      type = lib.types.enum ["doom" "vanilla"];
      default = "doom";
      description = ''
        Which build is the daily driver. The primary flavor owns the DEFAULT
        server socket (%t/emacs/server), so EDITOR, `em`, emacs-doctor and the
        emacs MCP server all follow it with no further configuration. The other
        flavor, when enabled, always runs on a named socket.

        Graduation is this one word, and so is rollback: the two keep entirely
        separate state (~/.local/share/nix-doom versus ~/.config/emacs plus
        ~/.cache/emacs), so flipping back changes nothing else.
      '';
    };

    package = lib.mkOption {
      type = lib.types.package;
      description = "The Doom Emacs package (built externally with nix-doom-emacs-unstraightened).";
    };

    primaryPackage = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default =
        if cfg.flavor == "doom"
        then cfg.package
        else cfg.vanilla.package;
      defaultText = lib.literalExpression ''if flavor == "doom" then package else vanilla.package'';
      description = ''
        Resolved daily-driver package. Consumers that need emacsclient to reach
        the daemon on the DEFAULT socket -- modules/emacs-mcp.nix and
        modules/emacs-doctor/default.nix -- must read this rather than
        `package`, or they will talk to the wrong Emacs the moment `flavor`
        flips.
      '';
    };

    vanilla = {
      enable = lib.mkEnableOption ''
        the hand-built vanilla Emacs as a SECOND daemon alongside the daily
        driver, on its own server socket. Mirrors the tmux-experimental
        precedent: `tmux -L experimental` there, `emacsclient -s vanilla` here
      '';

      package = lib.mkOption {
        type = lib.types.package;
        description = "Vanilla Emacs (modules/emacs/vanilla/package.nix).";
      };

      serverName = lib.mkOption {
        type = lib.types.str;
        default = "vanilla";
        description = ''
          `server-name` for the non-primary daemon, i.e. the argument to
          `emacsclient -s`. Resolves to $XDG_RUNTIME_DIR/emacs/<name> -- the
          same %t/emacs directory the primary's socket lives in, which is why
          both units' ExecStartPre name exactly one file and never remove the
          directory.
        '';
      };

      manageConfig = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Link the elisp tree into $XDG_CONFIG_HOME/emacs. Set false to hand
          that directory to a working copy during heavy iteration, so editing
          init.el does not need an `hms` per keystroke.
        '';
      };
    };

    daemon.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable the primary Emacs daemon via a systemd user service";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages =
      [
        # EXACTLY ONE Emacs package may appear here. home.path is
        # pkgs.buildEnv with ignoreCollisions unset, so listing both flavors is
        # a hard build failure on bin/emacs, bin/emacsclient, bin/ctags and
        # emacs.desktop -- not a warning. The secondary is reachable only via
        # the wrappers below and its systemd unit, both of which reference it
        # by absolute store path.
        cfg.primaryPackage
        pkgs.ispell
        pkgs.typescript-language-server
        pkgs.pyright
        pkgs.gopls
        pkgs.jdt-language-server
      ]
      ++ primaryClients
      ++ secondaryClients
      # sbcl is gated to Linux: the ECL bootstrap segfaults on macOS
      # (upstream nixpkgs issue with SBCL 2.6.3). Installed via Homebrew
      # on Darwin instead (see home/darwin.nix).
      ++ lib.optional pkgs.stdenv.hostPlatform.isLinux pkgs.sbcl
      # haskell-language-server is gated to Linux: cache.nixos.org has been
      # delivering the darwin closure at byte-trickle speed (multiple CI runs
      # blew the 60min cap copying this single path), and the user doesn't
      # write Haskell on the corporate Mac. Linux runs build it from cache
      # in seconds.
      ++ lib.optional pkgs.stdenv.hostPlatform.isLinux pkgs.haskell-language-server;

    services.emacs = lib.mkIf cfg.daemon.enable {
      enable = true;
      package = cfg.primaryPackage;
      # true = WantedBy default.target (any user session, works in headless WSL).
      # "graphical" = WantedBy graphical-session.target (display server required).
      startWithUserSession =
        if pkgs.stdenv.hostPlatform.isLinux
        then true
        else "graphical";
      # home-manager appends extraOptions after --fg-daemon. Only needed when
      # vanilla is the primary; Doom's wrapper supplies its own init directory.
      extraOptions =
        lib.optionals (cfg.flavor == "vanilla")
        ["--init-directory=${config.xdg.configHome}/emacs"];
    };

    # Harden the systemd-managed daemon against the socket-squat deadlock:
    #   - ExecStartPre clears a stale server socket so a clean (re)start always
    #     wins the socket path (`%t` = $XDG_RUNTIME_DIR, e.g. /run/user/1000).
    #   - StartLimitBurst/RestartSec bound the restart loop: if it fails 3x in
    #     60s it stops in `failed` state (visible) instead of relaunching every
    #     ~100ms and burning a CPU core indefinitely.
    #
    # CRITICAL NOW THAT TWO DAEMONS SHARE %t/emacs: this removes ONE FILE. It
    # must never become `rm -rf %t/emacs`, which would delete the other
    # flavor's live socket and drop IT into exactly this crash loop.
    systemd.user.services.emacs = lib.mkIf (cfg.daemon.enable && pkgs.stdenv.hostPlatform.isLinux) {
      Service = {
        ExecStartPre = "-${pkgs.coreutils}/bin/rm -f %t/emacs/server";
        RestartSec = 5;
      };
      Unit = {
        StartLimitIntervalSec = 60;
        StartLimitBurst = 3;
      };
    };

    # The non-primary daemon. Hand-rolled because home-manager's services.emacs
    # is a singleton: it hardcodes systemd.user.services.emacs and the socket
    # path %t/emacs/server, with no server-name option.
    #
    # LOAD-BEARING ASSUMPTION: home-manager makes %t/emacs read-only while the
    # primary runs (ExecStartPost chmod -w) ONLY when `needsSocketWorkaround`,
    # which is `versionOlder emacsVersion "28" && socketActivation.enable`.
    # Emacs here is 30+, so the directory stays writable and this daemon can
    # create its socket beside the primary's. Turning on socketActivation with
    # an Emacs older than 28 would silently break that.
    systemd.user.services."emacs-${secondaryName}" = lib.mkIf (secondary != null && cfg.daemon.enable && pkgs.stdenv.hostPlatform.isLinux) {
      Unit = {
        Description = "Emacs daemon (${secondaryName} flavor, socket '${secondary.serverName}')";
        Documentation = "info:emacs man:emacs(1)";
        # Deliberately the OPPOSITE of home-manager's primary unit, which
        # sets X-RestartIfChanged = false so `hms` never eats the daily
        # driver's unsaved buffers. This flavor is the one under active
        # development: picking up a new config immediately is the point, and
        # there are no precious buffers in it yet. Flip to false at
        # graduation.
        X-RestartIfChanged = true;
        StartLimitIntervalSec = 60;
        StartLimitBurst = 3;
      };
      Service = {
        Type = "notify";
        # `exec` so the sd_notify sender is MAINPID. home-manager's own unit
        # omits it and gets away with it because sh -c execs a single
        # command; extraArgs make this a multi-token command line, so being
        # explicit is what stops a 90s TimeoutStartSec hang on every start.
        ExecStart = ''${pkgs.runtimeShell} -l -c "exec ${secondary.package}/bin/emacs --fg-daemon=${secondary.serverName} ${lib.escapeShellArgs secondary.extraArgs}"'';
        # ONE FILE -- see the primary unit's comment.
        ExecStartPre = "-${pkgs.coreutils}/bin/rm -f %t/emacs/${secondary.serverName}";
        SuccessExitStatus = 15; # Emacs exits 15 on SIGTERM
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install.WantedBy = ["default.target"];
    };

    # NOTE: `recursive = true` is load-bearing. Without it home-manager makes
    # ~/.config/emacs a single symlink INTO THE STORE, and Emacs can then never
    # create custom.el, transient/, eln-cache/ or its server directory inside
    # user-emacs-directory. With it, real directories are created and each file
    # is linked individually, so the tree stays writable while every .el stays
    # store-managed and reproducible.
    xdg.configFile."emacs" = lib.mkIf (cfg.vanilla.enable && cfg.vanilla.manageConfig) {
      source = cfg.vanilla.package.configDir;
      recursive = true;
    };

    # Only the primary package is on PATH, so a bare `emacsclient` here
    # unambiguously resolves to the daily driver.
    home.sessionVariables = {
      EDITOR =
        if cfg.daemon.enable
        then "emacsclient -t --alternate-editor 'emacs -nw'"
        else "emacs -nw";
      VISUAL =
        if cfg.daemon.enable
        then "emacsclient -c --alternate-editor emacs"
        else "emacs";
    };
  };
}
