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
      home.packages = with pkgs; [
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
          { use-agent = true; }
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
          else { disable-ccid = true; }
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
        defaultCacheTtl = 28800;
        defaultCacheTtlSsh = 28800;
        maxCacheTtl = 86400;
        maxCacheTtlSsh = 86400;
        extraConfig = "allow-loopback-pinentry";
      };
    })

    # --- Windows forwarding (WSL YubiKey bridge) ---
    (lib.mkIf (isLinux && cfg.forwardToWindows) {
      programs.gpg.settings = {
        pinentry-mode = "loopback";
      };

      programs.zsh.initContent = lib.mkAfter ''
        if [[ -t 1 ]]; then
          GPG_TTY=$(tty)
          export GPG_TTY
        fi

        gpg-restart() {
          local gpg4win="/mnt/c/Program Files/GnuPG/bin"

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
      '';

      home.file.".local/bin/gpg_touch.ps1".text = ''
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        $f = New-Object System.Windows.Forms.Form
        $f.Text = 'GPG Signing'
        $f.Size = New-Object System.Drawing.Size(300, 100)
        $f.StartPosition = 'CenterScreen'
        $f.TopMost = $true
        $f.FormBorderStyle = 'FixedSingle'
        $f.MaximizeBox = $false
        $f.MinimizeBox = $false
        $l = New-Object System.Windows.Forms.Label
        $l.Text = 'Touch your YubiKey to sign'
        $l.AutoSize = $true
        $l.Location = New-Object System.Drawing.Point(30, 35)
        $f.Controls.Add($l)
        $f.ShowDialog() | Out-Null
      '';

      home.file.".local/bin/gpg-win-bridge" = {
        text = bridgeScript;
        executable = true;
      };

      systemd.user.services.gpg-win-bridge = {
        Unit = {
          Description = "GPG agent bridge to Windows Gpg4win";
          After = [ "default.target" ];
        };
        Service = {
          Type = "simple";
          ExecStart = "%h/.local/bin/gpg-win-bridge";
          Restart = "on-failure";
          RestartSec = "2s";
        };
        Install.WantedBy = [ "default.target" ];
      };

      home.activation.maskGpgAgentUnits = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        for unit in gpg-agent.socket gpg-agent-extra.socket gpg-agent-ssh.socket gpg-agent-browser.socket gpg-agent.service; do
          mkdir -p "$HOME/.config/systemd/user"
          ln -sf /dev/null "$HOME/.config/systemd/user/$unit"
        done
        $DRY_RUN_CMD systemctl --user daemon-reload 2>/dev/null || true
        $DRY_RUN_CMD systemctl --user enable --now gpg-win-bridge.service 2>/dev/null || true
      '';
    })
  ]);
}
