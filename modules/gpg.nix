{
  config,
  lib,
  pkgs,
  gitConfig,
  ...
}: let
  cfg = config.my.gpg;
  inherit (pkgs.stdenv) isLinux;

  bridgeScript = builtins.readFile ./scripts/gpg-win-bridge.py;

  # ONE definition of the PIN cache TTLs on Linux/WSL: 8h idle, 24h absolute.
  # Read by the local gpg-agent below, by the gpg-agent.conf this module renders
  # for Windows Gpg4win through my.windowsBridge.files, and by the gpg-win-setup
  # shell function that patches that same Windows file imperatively. Those three
  # carried the numbers separately and had already fallen out of step: the live
  # Windows file said 7200, gpg-win-setup's awk wrote 28800, and gpg-win-setup's
  # own summary line still announced "-> 7200". macOS is deliberately NOT part of
  # this -- it runs 60/300 so that signing re-prompts, which is a different
  # decision rather than a stale copy of this one.
  cacheTtl = {
    default = 28800;
    max = 86400;
  };

  # Windows Gpg4win reads %APPDATA%\gnupg\scdaemon.conf. The imperative
  # gpg-scd-shared() below still appends this line on a machine that has not run
  # `hms' yet (gpg-restart calls it, and it has to keep working standalone), but
  # THIS is now where the setting comes from.
  winScdaemonConf = ''
    # Managed by home-manager: modules/gpg.nix, installed by
    # modules/windows-bridge.nix. Edit the flake, not this file -- `hms' reports
    # and backs up local edits, then replaces them.
    #
    # pcsc-shared is not a tuning knob, it is what makes the YubiKey work at all
    # here. scdaemon otherwise asks PC/SC for EXCLUSIVE access to the card, and
    # Windows' Certificate Propagation service (CertPropSvc) already holds every
    # inserted card SHARED and never lets go. The collision returns
    # SCARD_E_SHARING_VIOLATION and gpg misreports it as
    # `selecting card failed: No such device', which reads like an unplugged key
    # and is nothing of the sort. Full diagnosis: the comment above
    # gpg-scd-shared() in modules/gpg.nix.
    pcsc-shared
  '';

  # Windows Gpg4win reads %APPDATA%\gnupg\gpg-agent.conf. Every line below was
  # already in the live file and is kept for the reason noted; only the TTLs
  # move, and they move to the single definition above.
  winGpgAgentConf = ''
    # Managed by home-manager: modules/gpg.nix, installed by
    # modules/windows-bridge.nix. Edit the flake, not this file -- `hms' reports
    # and backs up local edits, then replaces them.

    # Serve the Windows-native SSH agent protocols. Windows OpenSSH and PuTTY
    # both reach this agent for the YubiKey's authentication subkey.
    enable-win32-openssh-support
    enable-putty-support

    # PIN cache, same numbers as the Linux gpg-agent in this module (`cacheTtl',
    # one definition). Gpg4win's own default is ~10 minutes, which made batch
    # signing -- rebases, multi-commit sessions -- re-prompt constantly.
    default-cache-ttl ${toString cacheTtl.default}
    max-cache-ttl ${toString cacheTtl.max}

    # The WSL bridge (~/.local/bin/gpg-win-bridge) passes PINs through to this
    # agent, which requires loopback pinentry to be permitted. The timeout is
    # how long the prompt waits for a physical touch before giving up.
    pinentry-timeout 300
    allow-loopback-pinentry

    # Gpg4win splits its install: the GnuPG core lands in C:\Program Files\GnuPG\bin
    # (gpg.exe, scdaemon.exe, gpg-connect-agent.exe -- the path gpg-restart uses)
    # but the pinentry lands in C:\Program Files\Gpg4win\bin. The two are not
    # interchangeable and there is no pinentry-w32.exe under GnuPG\bin.
    pinentry-program "C:\Program Files\Gpg4win\bin\pinentry-w32.exe"
  '';
in {
  options.my.gpg = {
    enable = lib.mkEnableOption "GPG configuration with signing support";

    defaultKey = lib.mkOption {
      type = lib.types.str;
      default = gitConfig.signingKey or "";
      description = "Default GPG key ID for signing";
    };

    enableSshSupport = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable GPG agent SSH support";
    };

    enableYubiKey = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable YubiKey smart card support (local pcscd)";
    };

    forwardToWindows = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Forward GPG agent to Windows Gpg4win (for YubiKey in WSL without usbipd)";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    # --- Common config (all platforms) ---
    {
      home.packages = with pkgs;
        [
          gnupg
          pinentry-tty
        ]
        ++ lib.optionals (cfg.enableYubiKey && isLinux && !cfg.forwardToWindows) [
          pcsclite
          ccid
        ];

      programs.gpg = {
        enable = true;
        homedir = "${config.home.homeDirectory}/.gnupg";
        settings =
          {use-agent = true;}
          // lib.optionalAttrs (cfg.defaultKey != "") {
            default-key = cfg.defaultKey;
          };

        scdaemonSettings = lib.mkIf (cfg.enableYubiKey && !cfg.forwardToWindows) (
          if isLinux
          then {
            pcsc-driver = "${lib.getLib pkgs.pcsclite}/lib/libpcsclite.so.1";
            card-timeout = "5";
            disable-ccid = true;
          }
          else {disable-ccid = true;}
        );
      };
    }

    # --- Local gpg-agent (non-forwarding) ---
    (lib.mkIf (isLinux && !cfg.forwardToWindows) {
      programs.zsh.initContent = lib.mkAfter ''
        if [[ -t 1 ]]; then
          GPG_TTY=$(tty)
          export GPG_TTY
          gpg-connect-agent updatestartuptty /bye >/dev/null 2>&1
        fi
      '';

      services.gpg-agent = {
        enable = true;
        inherit (cfg) enableSshSupport;
        pinentry.package = pkgs.pinentry-qt;
        defaultCacheTtl = cacheTtl.default;
        defaultCacheTtlSsh = cacheTtl.default;
        maxCacheTtl = cacheTtl.max;
        maxCacheTtlSsh = cacheTtl.max;
        extraConfig = "allow-loopback-pinentry";
      };
    })

    # --- macOS gpg-agent (no Linux home-manager service available on Darwin) ---
    (lib.mkIf (!isLinux) {
      programs.zsh.initContent = lib.mkAfter ''
        if [[ -t 1 ]]; then
          GPG_TTY=$(tty)
          export GPG_TTY
          gpg-connect-agent updatestartuptty /bye >/dev/null 2>&1
        fi
      '';

      home.file.".gnupg/gpg-agent.conf".text = ''
        # Managed by home-manager (modules/gpg.nix). Short cache TTL so commit
        # signing prompts for a passphrase rather than silently using cached
        # credentials. default = idle re-prompt; max = absolute re-prompt.
        pinentry-program ${pkgs.pinentry_mac}/Applications/pinentry-mac.app/Contents/MacOS/pinentry-mac
        default-cache-ttl 60
        max-cache-ttl 300
      '';

      # Drop cached credentials and pick up the new config on every activation.
      home.activation.reloadGpgAgent = lib.hm.dag.entryAfter ["writeBoundary"] ''
        $DRY_RUN_CMD ${pkgs.gnupg}/bin/gpgconf --kill gpg-agent 2>/dev/null || true
      '';
    })

    # --- Windows forwarding (WSL YubiKey bridge) ---
    (lib.mkIf (isLinux && cfg.forwardToWindows) {
      programs.gpg.settings = {
        pinentry-mode = "loopback";
      };

      # The two Windows-side gnupg configs. Declared here because this module
      # owns what goes in them; modules/windows-bridge.nix is only the transport
      # and the drift alarm.
      #
      # Mode "own" rather than "merge": Gpg4win never rewrites either file. The
      # only writers are a human with an editor and the two shell functions
      # above, so whole-file ownership loses nothing and makes the flake
      # unambiguously the source of truth -- which is the whole point, given that
      # `pcsc-shared' spent months existing only as an undocumented hand edit.
      my.windowsBridge.files = {
        gnupg-scdaemon = {
          target = "AppData/Roaming/gnupg/scdaemon.conf";
          mode = "own";
          text = winScdaemonConf;
        };
        gnupg-agent = {
          target = "AppData/Roaming/gnupg/gpg-agent.conf";
          mode = "own";
          text = winGpgAgentConf;
        };
      };

      programs.zsh.initContent = lib.mkAfter ''
        if [[ -t 1 ]]; then
          GPG_TTY=$(tty)
          export GPG_TTY
        fi

        # gpg-scd-shared: make scdaemon coexist with Windows' card holder.
        #
        # THIS IS WHAT MAKES gpg-restart ABLE TO RECOVER. scdaemon asks PC/SC
        # for EXCLUSIVE access to the card. Windows' Certificate Propagation
        # service (CertPropSvc) connects to every inserted smart card and holds
        # it SHARED, permanently. Exclusive-against-shared returns
        # SCARD_E_SHARING_VIOLATION (0x8010000b), and gpg reports that as
        # `selecting card failed: No such device' -- which reads like an unplugged
        # key and is nothing of the sort.
        #
        # It stays invisible for weeks because scdaemon usually wins the race at
        # boot and then never lets go. It only bites once something makes it
        # RELEASE the card -- `SCD KILLSCD', `gpgconf --kill scdaemon', killing
        # gpg-agent, or gpg-restart itself. After that it can never reacquire,
        # and unplugging the key does NOT help: CertPropSvc re-grabs on every
        # insert. Diagnosed 2026-08-28 after gpg-restart left signing dead;
        # `disable-ccid' is a red herring, the reader was always detected.
        #
        # To see it rather than guess: put `log-file <path>' and
        # `debug-level guru' in scdaemon.conf, restart scdaemon, then run
        # `gpg-connect-agent "SCD SERIALNO" /bye'. The log says
        # `detected reader ...' and `pcsc_connect failed: sharing violation'
        # on adjacent lines. Nothing else tells absent from held.
        #
        # The DECLARATIVE source for this file is now winScdaemonConf in
        # modules/gpg.nix, installed by modules/windows-bridge.nix on every
        # switch. This function stays because gpg-restart calls it and because a
        # machine that has not run `hms' yet still needs a way out; it must keep
        # working standalone. Where they disagree, `hms' wins on the next switch
        # -- and says so, rather than quietly reverting the edit.
        #
        # Idempotent, same shape as gpg-win-setup: every other line is preserved.
        gpg-scd-shared() {
          local winuser gnupg_dir conf tmp
          winuser=$(/mnt/c/Windows/System32/cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r\n')
          [[ -n "$winuser" ]] || { echo "gpg-scd-shared: no Windows username" >&2; return 1; }

          gnupg_dir="/mnt/c/Users/$winuser/AppData/Roaming/gnupg"
          conf="$gnupg_dir/scdaemon.conf"
          mkdir -p "$gnupg_dir" || return 1
          [[ -f "$conf" ]] || touch "$conf"

          if awk '{sub(/\r$/, "")} $1 == "pcsc-shared" {found = 1} END {exit !found}' "$conf"; then
            return 0
          fi

          tmp=$(mktemp "$gnupg_dir/.scdaemon.conf.XXXXXX") || return 1
          { awk '{sub(/\r$/, ""); print}' "$conf"; echo "pcsc-shared"; } >"$tmp" || {
            rm -f "$tmp"; echo "gpg-scd-shared: failed to rewrite $conf" >&2; return 1
          }
          if ! mv -f "$tmp" "$conf" 2>/dev/null; then
            cp "$tmp" "$conf" || { rm -f "$tmp"; return 1; }
            rm -f "$tmp"
          fi
          echo "Added pcsc-shared to $conf (scdaemon may now share the card)"
        }

        gpg-restart() {
          local gpg4win="/mnt/c/Program Files/GnuPG/bin"

          # Before tearing anything down: guarantee scdaemon can get the card
          # back afterwards. Without this, gpg-restart reliably makes signing
          # worse -- it releases a handle it cannot reacquire.
          gpg-scd-shared || echo "gpg-restart: could not verify pcsc-shared; signing may not recover" >&2

          echo "Resetting Windows Gpg4win..."
          "$gpg4win/gpg-connect-agent.exe" "SCD KILLSCD" /bye 2>/dev/null || true
          "$gpg4win/gpg-connect-agent.exe" killagent /bye 2>/dev/null || true

          echo "Resetting WSL bridge..."
          systemctl --user kill -s SIGKILL gpg-win-bridge 2>/dev/null || true
          pkill -9 -f "gpg-agent --homedir" 2>/dev/null || true

          echo "Waking up Gpg4win with card..."
          "$gpg4win/gpg.exe" --card-status 2>/dev/null | grep -E "Reader|Serial|PIN retry" || echo "Card not detected"

          sleep 0.5
          systemctl --user start gpg-win-bridge
          echo "Done — bridge restarted"
        }

        # gpg-win-setup: tune the Windows Gpg4win agent's PIN cache.
        #
        # The DECLARATIVE source for this file is now winGpgAgentConf in
        # modules/gpg.nix, installed by modules/windows-bridge.nix on every
        # switch; this function is the imperative fallback for a machine that
        # has not run `hms' yet, and the TTLs below come from the same `cacheTtl'
        # binding so the two cannot disagree.
        #
        # Ensures default-cache-ttl ${toString cacheTtl.default} (8h idle, matching the WSL agent above)
        # and max-cache-ttl ${toString cacheTtl.max}
        # (24h absolute) in %APPDATA%\gnupg\gpg-agent.conf. Gpg4win's default
        # PIN cache is only ~10 minutes (default-cache-ttl 600), which made
        # batch signing (rebases, multi-commit sessions) re-prompt for the
        # PIN constantly. Idempotent and safe to re-run: only the two TTL
        # keys are replaced/appended; every other line is preserved.
        gpg-win-setup() {
          local gpg4win="/mnt/c/Program Files/GnuPG/bin"

          if [[ ! -x "$gpg4win/gpg-connect-agent.exe" ]]; then
            echo "gpg-win-setup: Gpg4win not found at $gpg4win" >&2
            return 1
          fi

          local winuser
          winuser=$(/mnt/c/Windows/System32/cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r\n')
          if [[ -z "$winuser" ]]; then
            echo "gpg-win-setup: could not determine the Windows username" >&2
            return 1
          fi

          local gnupg_dir="/mnt/c/Users/$winuser/AppData/Roaming/gnupg"
          local conf="$gnupg_dir/gpg-agent.conf"
          if ! mkdir -p "$gnupg_dir"; then
            echo "gpg-win-setup: cannot create $gnupg_dir" >&2
            return 1
          fi
          [[ -f "$conf" ]] || touch "$conf"

          local old_default old_max
          old_default=$(awk '{sub(/\r$/, "")} $1 == "default-cache-ttl" {v = $2} END {print v}' "$conf")
          old_max=$(awk '{sub(/\r$/, "")} $1 == "max-cache-ttl" {v = $2} END {print v}' "$conf")

          # Rewrite via a temp file in the same directory so the swap is a
          # plain rename on the 9P mount; fall back to cp+rm if mv fails
          # there. No partial writes ever land in gpg-agent.conf itself.
          local tmp
          tmp=$(mktemp "$gnupg_dir/.gpg-agent.conf.XXXXXX") || return 1
          awk '
            {sub(/\r$/, "")}
            $1 == "default-cache-ttl" {print "default-cache-ttl ${toString cacheTtl.default}"; d = 1; next}
            $1 == "max-cache-ttl" {print "max-cache-ttl ${toString cacheTtl.max}"; m = 1; next}
            {print}
            END {
              if (!d) print "default-cache-ttl ${toString cacheTtl.default}"
              if (!m) print "max-cache-ttl ${toString cacheTtl.max}"
            }
          ' "$conf" >"$tmp" || {
            rm -f "$tmp"
            echo "gpg-win-setup: failed to rewrite config" >&2
            return 1
          }

          if cmp -s "$conf" "$tmp"; then
            rm -f "$tmp"
            echo "gpg-win-setup: already configured ($conf)"
            return 0
          fi

          if ! mv -f "$tmp" "$conf" 2>/dev/null; then
            if ! cp "$tmp" "$conf"; then
              rm -f "$tmp"
              echo "gpg-win-setup: failed to update $conf" >&2
              return 1
            fi
            rm -f "$tmp"
          fi

          echo "Updated $conf:"
          echo "  default-cache-ttl: ''${old_default:-unset (gpg4win default 600)} -> ${toString cacheTtl.default}"
          echo "  max-cache-ttl:     ''${old_max:-unset} -> ${toString cacheTtl.max}"

          # gpg-agent only reads its conf at startup, so restart it to apply.
          # This is the same kill sequence gpg-restart uses; it drops the PIN
          # cache, but the user invokes gpg-win-setup deliberately, never
          # mid-signing, so an inline restart is safe here.
          echo "Restarting Windows gpg-agent to apply..."
          "$gpg4win/gpg-connect-agent.exe" "SCD KILLSCD" /bye 2>/dev/null || true
          "$gpg4win/gpg-connect-agent.exe" killagent /bye 2>/dev/null || true
          if "$gpg4win/gpg-connect-agent.exe" "GETINFO version" /bye >/dev/null 2>&1; then
            echo "Done — new cache TTLs are active (run gpg-restart if signing misbehaves)"
          else
            echo "Windows gpg-agent did not respond — run gpg-restart to reset agent and bridge" >&2
            return 1
          fi
        }
      '';

      home = {
        # The "touch your YubiKey" popup script is embedded inline in
        # gpg-win-bridge.py (powershell -Command) so nothing is staged in
        # the world-shared Windows Temp directory.
        file = {
          ".local/bin/gpg-win-bridge" = {
            text = bridgeScript;
            executable = true;
          };
        };
        activation.maskGpgAgentUnits = lib.hm.dag.entryAfter ["writeBoundary"] ''
          for unit in gpg-agent.socket gpg-agent-extra.socket gpg-agent-ssh.socket gpg-agent-browser.socket gpg-agent.service; do
            mkdir -p "$HOME/.config/systemd/user"
            ln -sf /dev/null "$HOME/.config/systemd/user/$unit"
          done
          $DRY_RUN_CMD systemctl --user daemon-reload 2>/dev/null || true
          $DRY_RUN_CMD systemctl --user enable --now gpg-win-bridge.service 2>/dev/null || true
        '';
      };

      systemd.user.services.gpg-win-bridge = {
        Unit = {
          Description = "GPG agent bridge to Windows Gpg4win";
          After = ["default.target"];
        };
        Service = {
          Type = "simple";
          ExecStart = "%h/.local/bin/gpg-win-bridge";
          Restart = "on-failure";
          RestartSec = "2s";
        };
        Install.WantedBy = ["default.target"];
      };
    })
  ]);
}
