{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.my.emacs;

  # ONE EMACS. This module used to carry a `flavor` enum ("doom" | "vanilla"),
  # a `primaryPackage` that resolved it, a second hand-rolled systemd unit and
  # a second pair of client wrappers, so that the hand-built config could run
  # beside Doom on a named socket until it earned the default one. It did, and
  # Doom is gone -- so all of that went with it rather than being left as an
  # enum with one value. What the two-flavour period actually taught is kept
  # below, in the places it applies to: the ExecStartPre that must name ONE
  # FILE, and the explicit EMACS_SOCKET_NAME on the daemon unit.
  #
  # Bringing a second Emacs back is a real change, not a flag flip, and that is
  # the intended trade: `git log -- modules/emacs` has the whole design if it
  # is ever wanted again.

  # Bring up the daemon if none is answering. On Linux the daemon is owned by a
  # systemd unit, so start *that* rather than spawning a raw `emacs --daemon`:
  # two daemons racing for one socket deadlock the unit into a crash loop (the
  # standalone one squats the socket, `--fg-daemon` can never bind it,
  # Restart=on-failure relaunches forever, pegging a core). The raw call is the
  # fallback for when systemd is not there at all, i.e. darwin.
  ensureDaemon = ''
    if ! ${cfg.package}/bin/emacsclient -n -e "(if (daemonp) t)" >/dev/null 2>&1; then
      echo "Starting Emacs daemon..."
      ${
      if pkgs.stdenv.hostPlatform.isLinux
      then "systemctl --user start emacs 2>/dev/null || ${cfg.package}/bin/emacs --daemon || true"
      else "${cfg.package}/bin/emacs --daemon || true"
    }
      for _ in $(seq 1 100); do
        ${cfg.package}/bin/emacsclient -n -e t >/dev/null 2>&1 && break
        sleep 0.1
      done
    fi
  '';

  # A GUI-or-TTY wrapper plus a TTY-only wrapper.
  clients = [
    (pkgs.writeShellApplication {
      name = "em";
      text = ''
        ${ensureDaemon}
        if [ -t 0 ] && [ -z "''${DISPLAY:-}" ] && [ -z "''${WAYLAND_DISPLAY:-}" ]; then
          exec ${cfg.package}/bin/emacsclient -t "$@"
        else
          exec ${cfg.package}/bin/emacsclient -c "$@"
        fi
      '';
    })
    (pkgs.writeShellApplication {
      name = "emt";
      text = ''
        ${ensureDaemon}
        exec ${cfg.package}/bin/emacsclient -t "$@"
      '';
    })
  ];
in {
  options.my.emacs = {
    enable = lib.mkEnableOption "Emacs (the hand-built config in modules/emacs/vanilla)";

    package = lib.mkOption {
      type = lib.types.package;
      description = ''
        The Emacs package, built by modules/emacs/vanilla/package.nix. It owns
        the DEFAULT server socket (%t/emacs/server), so EDITOR, `em`,
        emacs-doctor and the emacs MCP server all reach it with no further
        configuration.
      '';
    };

    manageConfig = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Link the elisp tree into $XDG_CONFIG_HOME/emacs. Set false to hand that
        directory to a working copy during heavy iteration, so editing init.el
        does not need an `hms` per keystroke.
      '';
    };

    daemon.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable the Emacs daemon via a systemd user service";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages =
      [
        # EXACTLY ONE Emacs package may appear here. home.path is pkgs.buildEnv
        # with ignoreCollisions unset, so a second one is a hard build failure
        # on bin/emacs, bin/emacsclient, bin/ctags and emacs.desktop -- not a
        # warning. That is worth knowing before adding any Emacs-adjacent
        # package that wraps its own.
        cfg.package
        pkgs.ispell

        # Language servers backing the `eglot-ensure' hook list in
        # vanilla/config/lisp/my-lang.el. That file is the source of truth for
        # WHICH modes get hooked, and its comment enumerates both what is
        # installed and what is deliberately absent (clangd,
        # cmake-language-server, fortls, texlab, nixd). The two lists move
        # together: a mode is hooked only where a server is on PATH, so
        # dropping a server here turns every find-file in that mode into an
        # eglot connection failure, which is exactly the "config that cries
        # wolf" the hook list was written to avoid.
        #
        # Ten of these moved here from modules/vim/default.nix when LazyVim was
        # removed. They were never neovim's -- eglot is the only consumer left.
        pkgs.bash-language-server
        pkgs.dockerfile-language-server
        pkgs.gopls
        pkgs.jdt-language-server
        pkgs.lua-language-server
        pkgs.nil # nix -- named directly by my-lang.el; the binary really is `nil'
        pkgs.pyright
        pkgs.ruff
        pkgs.rust-analyzer
        pkgs.taplo
        pkgs.typescript-language-server
        pkgs.vscode-langservers-extracted # json/html/css/eslint
        pkgs.yaml-language-server
      ]
      ++ clients
      # marksman (markdown) is gated off Darwin because it is a Swift build
      # that does not go through on macOS in this nixpkgs. Inherited verbatim
      # from modules/vim/default.nix, where the gate was first needed.
      ++ lib.optional pkgs.stdenv.hostPlatform.isLinux pkgs.marksman
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
      inherit (cfg) package;
      # true = WantedBy default.target (any user session, works in headless WSL).
      # "graphical" = WantedBy graphical-session.target (display server required).
      startWithUserSession =
        if pkgs.stdenv.hostPlatform.isLinux
        then true
        else "graphical";
      # home-manager appends extraOptions after --fg-daemon. Required: this
      # Emacs keeps its config in $XDG_CONFIG_HOME/emacs and bakes no init
      # directory into its wrapper, so without this the daemon starts against
      # ~/.emacs.d and looks like a config that silently reverted.
      extraOptions = ["--init-directory=${config.xdg.configHome}/emacs"];
    };

    # Harden the systemd-managed daemon against the socket-squat deadlock:
    #   - ExecStartPre clears a stale server socket so a clean (re)start always
    #     wins the socket path (`%t` = $XDG_RUNTIME_DIR, e.g. /run/user/1000).
    #   - StartLimitBurst/RestartSec bound the restart loop: if it fails 3x in
    #     60s it stops in `failed` state (visible) instead of relaunching every
    #     ~100ms and burning a CPU core indefinitely.
    #
    # THIS REMOVES ONE FILE and must stay that way. It was written when two
    # daemons shared %t/emacs and `rm -rf %t/emacs` would have deleted the
    # other one's live socket; there is one daemon again, but %t/emacs is also
    # where emacsclient's own per-frame state lands, and a recursive remove in
    # an ExecStartPre is never the smaller change it looks like.
    systemd.user.services.emacs = lib.mkIf (cfg.daemon.enable && pkgs.stdenv.hostPlatform.isLinux) {
      Service = {
        ExecStartPre = "-${pkgs.coreutils}/bin/rm -f %t/emacs/server";
        RestartSec = 5;
        # SET EXPLICITLY EVEN THOUGH THE FALLBACK IS ALREADY CORRECT -- and
        # that is the whole argument for the line.
        #
        # modules/claude-code.nix runs its hooks as
        #   emacsclient ''${EMACS_SOCKET_NAME:+-s "$EMACS_SOCKET_NAME"} --eval ...
        # so with the variable UNSET a hook reaches whichever emacsclient is on
        # PATH, talking to the default socket. The right answer, arrived at by
        # accident.
        #
        # It stops being right the moment anything puts EMACS_SOCKET_NAME into
        # the systemd USER MANAGER's environment, because units inherit that.
        # One `systemctl --user import-environment' from a shell where the user
        # had exported it to reach some other Emacs by hand is enough, and it
        # persists until the manager is restarted. Every Claude hook would then
        # be handed a socket name pointing somewhere else, and the diff would
        # open in the wrong place with no error anywhere. A unit-level
        # `Environment=' overrides the inherited environment, so this makes the
        # correct answer a guarantee rather than a coincidence.
        #
        # %t is $XDG_RUNTIME_DIR, expanded by systemd when the unit is loaded,
        # so the value is an ABSOLUTE path and does not depend on the hook
        # process having XDG_RUNTIME_DIR set. `server' is home-manager's
        # hardcoded socket name for this unit -- the same file the ExecStartPre
        # above deletes.
        Environment = ["EMACS_SOCKET_NAME=%t/emacs/server"];
      };
      Unit = {
        StartLimitIntervalSec = 60;
        StartLimitBurst = 3;
      };
    };

    # NOTE: `recursive = true` is load-bearing. Without it home-manager makes
    # ~/.config/emacs a single symlink INTO THE STORE, and Emacs can then never
    # create custom.el, transient/, eln-cache/ or its server directory inside
    # user-emacs-directory. With it, real directories are created and each file
    # is linked individually, so the tree stays writable while every .el stays
    # store-managed and reproducible.
    #
    # NOT gated on Linux. It was, indirectly, for the whole trial period --
    # the old gate was `vanilla.enable`, which meant "run a SECOND daemon" and
    # was false on darwin because home-manager drops user units there
    # silently. This is the only Emacs now, and on darwin it is started by
    # `services.emacs` through a launchd agent that passes the same
    # --init-directory, so the config has to be on disk there too.
    xdg.configFile."emacs" = lib.mkIf cfg.manageConfig {
      source = cfg.package.configDir;
      recursive = true;
    };

    # Only this Emacs is on PATH, so a bare `emacsclient` here unambiguously
    # resolves to it.
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
