{ config, lib, pkgs, gitConfig, ... }:

let
  cfg = config.my.gpg;
  inherit (pkgs.stdenv) isLinux isDarwin;
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
      description = "Enable YubiKey smart card support";
    };
  };

  config = lib.mkIf cfg.enable {
    # Install GPG and optional smart card support
    home.packages = with pkgs; [
      gnupg
      pinentry-curses  # Terminal-based pinentry for WSL/headless systems
    ] ++ lib.optionals (cfg.enableYubiKey && isLinux) [
      pcsclite
      ccid
    ];

    programs = {
      # Configure GPG
      gpg = {
        enable = true;
        settings = {
          # Use GPG agent
          use-agent = true;
          # Default key
          default-key = cfg.defaultKey;
        };

        # scdaemon configuration for smart cards
        scdaemonSettings = lib.mkIf cfg.enableYubiKey (
          if isLinux then {
            # Use pcscd on Linux/WSL (required for YubiKey via usbipd)
            pcsc-driver = "/usr/lib/x86_64-linux-gnu/libpcsclite.so.1";
            card-timeout = "5";
            disable-ccid = true;
          } else {
            # macOS uses CryptoTokenKit, minimal config needed
            disable-ccid = true;
          }
        );
      };

      # Set GPG_TTY in shell
      zsh.initContent = lib.mkAfter ''
        # GPG TTY configuration
        export GPG_TTY=$(tty)
        
        # Refresh gpg-agent tty in case user switches to another tty
        gpg-connect-agent updatestartuptty /bye >/dev/null 2>&1
      '';

      bash.initExtra = lib.mkAfter ''
        # GPG TTY configuration
        export GPG_TTY=$(tty)
        
        # Refresh gpg-agent tty
        gpg-connect-agent updatestartuptty /bye >/dev/null 2>&1
      '';
    };

    # Configure GPG agent
    services.gpg-agent = {
      enable = true;
      inherit (cfg) enableSshSupport;
      
      # Use curses pinentry for WSL/headless systems
      pinentry.package = pkgs.pinentry-curses;
      
      # Cache settings
      defaultCacheTtl = 3600;         # 1 hour
      defaultCacheTtlSsh = 3600;
      maxCacheTtl = 86400;            # 24 hours
      maxCacheTtlSsh = 86400;
    };
  };
}
