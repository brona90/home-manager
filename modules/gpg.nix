{ config, lib, pkgs, ... }:

let
  cfg = config.my.gpg;
in
{
  options.my.gpg = {
    enable = lib.mkEnableOption "GPG configuration with signing support";

    defaultKey = lib.mkOption {
      type = lib.types.str;
      default = "ECA2632B08E80FC6";
      description = "Default GPG key ID for signing";
    };

    enableSshSupport = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable GPG agent SSH support";
    };
  };

  config = lib.mkIf cfg.enable {
    # Install GPG
    home.packages = with pkgs; [
      gnupg
      pinentry-curses  # Terminal-based pinentry for WSL/headless systems
    ];

    # Configure GPG
    programs.gpg = {
      enable = true;
      settings = {
        # Use GPG agent
        use-agent = true;
        # Default key
        default-key = cfg.defaultKey;
      };
    };

    # Configure GPG agent
    services.gpg-agent = {
      enable = true;
      enableSshSupport = cfg.enableSshSupport;
      
      # Use curses pinentry for WSL/headless systems
      pinentry.package = pkgs.pinentry-curses;
      
      # Cache settings
      defaultCacheTtl = 3600;         # 1 hour
      defaultCacheTtlSsh = 3600;
      maxCacheTtl = 86400;            # 24 hours
      maxCacheTtlSsh = 86400;
    };

    # Set GPG_TTY in shell
    programs.zsh.initContent = lib.mkAfter ''
      # GPG TTY configuration
      export GPG_TTY=$(tty)
      
      # Refresh gpg-agent tty in case user switches to another tty
      gpg-connect-agent updatestartuptty /bye >/dev/null 2>&1
    '';

    programs.bash.initContent = lib.mkAfter ''
      # GPG TTY configuration
      export GPG_TTY=$(tty)
      
      # Refresh gpg-agent tty
      gpg-connect-agent updatestartuptty /bye >/dev/null 2>&1
    '';
  };
}
