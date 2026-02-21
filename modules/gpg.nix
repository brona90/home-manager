{ config, lib, pkgs, gitConfig, ... }:

let
  cfg = config.my.gpg;
  inherit (pkgs.stdenv) isLinux;
in
{
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
    home.packages = with pkgs; [
      gnupg
      pinentry-curses
    ] ++ lib.optionals (cfg.enableYubiKey && isLinux && !cfg.forwardToWindows) [
      pcsclite
      ccid
    ] ++ lib.optionals cfg.forwardToWindows [
      socat
    ];

    programs = {
      gpg = {
        enable = true;
        settings = {
          use-agent = true;
          default-key = cfg.defaultKey;
        };

        # scdaemon configuration for local smart cards (not used when forwarding)
        scdaemonSettings = lib.mkIf (cfg.enableYubiKey && !cfg.forwardToWindows) (
          if isLinux then {
            pcsc-driver = "/usr/lib/x86_64-linux-gnu/libpcsclite.so.1";
            card-timeout = "5";
            disable-ccid = true;
          } else {
            disable-ccid = true;
          }
        );
      };

      zsh.initContent = lib.mkAfter (
        if cfg.forwardToWindows then ''
          # Forward GPG agent to Windows Gpg4win
          export GPG_TTY=$(tty)
          
          _gpg_win_socket="/mnt/c/Users/$(/mnt/c/Windows/System32/cmd.exe /c 'echo %USERNAME%' 2>/dev/null | tr -d '\r')/AppData/Roaming/gnupg/S.gpg-agent"
          _gpg_wsl_socket="$HOME/.gnupg/S.gpg-agent"
          _npiperelay="/mnt/c/Users/$(/mnt/c/Windows/System32/cmd.exe /c 'echo %USERNAME%' 2>/dev/null | tr -d '\r')/.npiperelay/npiperelay.exe"
          
          # Start relay if not running
          if ! pgrep -f "socat.*S.gpg-agent" >/dev/null 2>&1; then
            rm -f "$_gpg_wsl_socket"
            mkdir -p "$(dirname "$_gpg_wsl_socket")"
            
            if [[ -x "$_npiperelay" ]]; then
              (setsid socat UNIX-LISTEN:"$_gpg_wsl_socket",fork EXEC:"$_npiperelay -ei -ep -s //./pipe/gpg-agent",nofork &) >/dev/null 2>&1
            fi
          fi
          
          unset _gpg_win_socket _gpg_wsl_socket _npiperelay
        '' else ''
          # GPG TTY configuration
          export GPG_TTY=$(tty)
          
          # Refresh gpg-agent tty in case user switches to another tty
          gpg-connect-agent updatestartuptty /bye >/dev/null 2>&1
        ''
      );

      bash.initExtra = lib.mkAfter (
        if cfg.forwardToWindows then ''
          # Forward GPG agent to Windows Gpg4win
          export GPG_TTY=$(tty)
          
          _gpg_wsl_socket="$HOME/.gnupg/S.gpg-agent"
          _npiperelay="/mnt/c/Users/$(/mnt/c/Windows/System32/cmd.exe /c 'echo %USERNAME%' 2>/dev/null | tr -d '\r')/.npiperelay/npiperelay.exe"
          
          if ! pgrep -f "socat.*S.gpg-agent" >/dev/null 2>&1; then
            rm -f "$_gpg_wsl_socket"
            mkdir -p "$(dirname "$_gpg_wsl_socket")"
            
            if [[ -x "$_npiperelay" ]]; then
              (setsid socat UNIX-LISTEN:"$_gpg_wsl_socket",fork EXEC:"$_npiperelay -ei -ep -s //./pipe/gpg-agent",nofork &) >/dev/null 2>&1
            fi
          fi
          
          unset _gpg_wsl_socket _npiperelay
        '' else ''
          # GPG TTY configuration
          export GPG_TTY=$(tty)
          
          # Refresh gpg-agent tty
          gpg-connect-agent updatestartuptty /bye >/dev/null 2>&1
        ''
      );
    };

    # Only enable local gpg-agent if not forwarding to Windows
    services.gpg-agent = lib.mkIf (!cfg.forwardToWindows) {
      enable = true;
      inherit (cfg) enableSshSupport;
      pinentry.package = pkgs.pinentry-curses;
      defaultCacheTtl = 3600;
      defaultCacheTtlSsh = 3600;
      maxCacheTtl = 86400;
      maxCacheTtlSsh = 86400;
    };
  };
}
