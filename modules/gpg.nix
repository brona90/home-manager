{
  config,
  lib,
  pkgs,
  gitConfig,
  ...
}: let
  cfg = config.my.gpg;
  inherit (pkgs.stdenv) isLinux;
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

  config = lib.mkIf cfg.enable {
    # Install GPG and optional smart card support
    home.packages = with pkgs;
      [
        gnupg
        pinentry-tty
      ]
      ++ lib.optionals (cfg.enableYubiKey && isLinux && !cfg.forwardToWindows) [
        pcsclite
        ccid
      ]
      ++ lib.optionals cfg.forwardToWindows [
        socat
      ];

    programs = {
      gpg = {
        enable = true;
        homedir = "${config.home.homeDirectory}/.gnupg";
        settings =
          {
            use-agent = true;
          }
          // lib.optionalAttrs (cfg.defaultKey != "") {
            default-key = cfg.defaultKey;
          };

        # scdaemon configuration for local smart cards (not used when forwarding)
        scdaemonSettings = lib.mkIf (cfg.enableYubiKey && !cfg.forwardToWindows) (
          if isLinux
          then {
            pcsc-driver = "${lib.getLib pkgs.pcsclite}/lib/libpcsclite.so.1";
            card-timeout = "5";
            disable-ccid = true;
          }
          else {
            disable-ccid = true;
          }
        );
      };

      # mkAfter (priority 1500) ensures GPG_TTY is set after all other
      # initContent contributions, including sops.nix helper functions
      # that depend on GPG being configured.
      zsh.initContent = lib.mkAfter (
        if cfg.forwardToWindows
        then ''
          # Forward GPG agent to Windows Gpg4win via Assuan TCP+nonce relay.
          # Modern Gpg4win (2.4+) uses Assuan sockets (port+nonce in a file),
          # not named pipes.  socat bridges the WSL Unix socket to Windows.
          if [[ -t 1 ]]; then
            GPG_TTY=$(tty)
            export GPG_TTY
          fi

          _gpg_wsl_socket="$(gpgconf --list-dirs agent-socket)"

          if [[ -x "/mnt/c/Windows/System32/cmd.exe" ]]; then
            _win_user=$(/mnt/c/Windows/System32/cmd.exe /c 'echo %USERNAME%' 2>/dev/null | tr -d '\r')
          fi

          if [[ -n "''${_win_user:-}" ]]; then
            _win_sock="/mnt/c/Users/$_win_user/AppData/Local/gnupg/S.gpg-agent"

            # Start relay if not already running
            if ! pgrep -f "socat.*UNIX-LISTEN.*S.gpg-agent" >/dev/null 2>&1; then
              rm -f "$_gpg_wsl_socket"
              mkdir -p "$(dirname "$_gpg_wsl_socket")"

              if [[ -f "$_win_sock" ]]; then
                _port=$(head -1 "$_win_sock" | tr -d '\r\n')
                _nonce_file=$(mktemp)
                # Extract 16-byte nonce (everything after the first line)
                tail -c +$(( ''${#_port} + 2 )) "$_win_sock" | head -c 16 > "$_nonce_file"

                # Relay: pipe nonce + client data into a second socat that
                # connects to the Windows agent's TCP port.
                (setsid socat UNIX-LISTEN:"$_gpg_wsl_socket",fork,unlink-early \
                  "SYSTEM:(cat '$_nonce_file'; cat) | socat - TCP\\:127.0.0.1\\:$_port" &) >/dev/null 2>&1
              fi
            fi

            unset _win_sock _port _nonce_file
          fi

          unset _win_user _gpg_wsl_socket
        ''
        else ''
          # GPG TTY configuration
          if [[ -t 1 ]]; then
            GPG_TTY=$(tty)
            export GPG_TTY

            # Refresh gpg-agent tty in case user switches to another tty
            gpg-connect-agent updatestartuptty /bye >/dev/null 2>&1
          fi
        ''
      );
    };

    # Mask system-provided gpg-agent socket units when forwarding so
    # they don't intercept connections meant for the Windows relay.
    systemd.user.sockets = lib.mkIf (isLinux && cfg.forwardToWindows) {
      gpg-agent = lib.mkForce {};
      gpg-agent-extra = lib.mkForce {};
      gpg-agent-ssh = lib.mkForce {};
      gpg-agent-browser = lib.mkForce {};
    };

    # Disable local gpg-agent when forwarding to Windows (the Windows
    # agent handles signing + YubiKey; the relay replaces the socket)
    services.gpg-agent = lib.mkIf (isLinux && !cfg.forwardToWindows) {
      enable = true;
      inherit (cfg) enableSshSupport;
      pinentry.package = pkgs.pinentry-qt;
      defaultCacheTtl = 28800;
      defaultCacheTtlSsh = 28800;
      maxCacheTtl = 86400;
      maxCacheTtlSsh = 86400;
      extraConfig = ''
        allow-loopback-pinentry
      '';
    };
  };
}
