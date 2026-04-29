{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.my.tmux;

  # Path to the helper binary. On darwin with preferSystemPath, point at
  # /usr/local/bin/tmux-helper (installed once via the tmux-helper-install
  # flake app) so BeyondTrust EPM has a stable fingerprintable path. Else
  # use the /nix/store output directly. Phase 2 first referenced this only
  # when useHelper = true; remains lazy when useHelper is off.
  helperBin =
    if cfg.preferSystemPath && pkgs.stdenv.isDarwin
    then "/usr/local/bin/tmux-helper"
    else "${config.my.tmuxHelper.package}/bin/tmux-helper";

  themes = import ./themes.nix;
  themesJson = pkgs.writeText "tmux-themes.json" (builtins.toJSON themes);

  experimentalConf = pkgs.writeText "tmux-experimental.conf" (
    import ./conf-experimental.nix {
      inherit helperBin;
      defaultThemePreset = cfg.theme.preset;
    }
  );
in {
  options.my.tmux = {
    enable = lib.mkEnableOption "tmux configuration (gpakosz/.tmux)";

    configDir = lib.mkOption {
      type = lib.types.path;
      description = "Path to the tmux config directory containing .tmux.conf and .tmux.conf.local";
    };

    useHelper = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        When true, replaces the bundled gpakosz config with the Nix-generated
        experimental tmux.conf driven by the tmux-helper Go binary. Off by
        default until the rewrite reaches feature parity (Phase 9). For ad-hoc
        testing without flipping this flag, run `nix run .#tmux-experimental`
        which spins up a parallel tmux server on a separate socket.
      '';
    };

    theme.preset = lib.mkOption {
      type = lib.types.enum [
        "molokai"
        "gpakosz"
        "catppuccin-mocha"
        "tokyonight"
        "gruvbox"
        "rose-pine"
        "nord"
        "dracula"
        "solarized-dark"
        "kanagawa"
      ];
      default = "molokai";
      description = ''
        Default tmux color palette to apply at conf load. Switchable at
        runtime via prefix-T (cycle) without home-manager-switch. The
        runtime choice is stored in @tmux_theme_preset on the tmux server
        for the session lifetime; persisting across server restarts
        requires changing this option and running home-manager switch.
      '';
    };

    preferSystemPath = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Use /usr/local/bin/tmux-helper instead of the /nix/store path in
        keybindings and #(...) substitutions. Set true on macOS so every
        helper invocation has a stable path BeyondTrust EPM can fingerprint
        by, plus a stable ad-hoc cdhash. Requires the binary to actually be
        installed there -- run `nix run .#tmux-helper-install` once after
        the first home-manager switch and on every helper version bump.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [pkgs.perl];

    programs.tmux = {
      enable = true;
      terminal = "tmux-256color";
      extraConfig =
        if cfg.useHelper
        then ''
          source-file ${experimentalConf}
        ''
        else ''
          # UTF-8 and true color support
          set -g default-terminal "tmux-256color"
          set -ag terminal-overrides ",xterm-256color:RGB"
          set -ag terminal-overrides ",*256col*:Tc"

          # Ensure UTF-8
          set -q -g status-utf8 on
          setw -q -g utf8 on

          # Source the gpakosz config
          source-file ${cfg.configDir}/.tmux.conf
        '';
    };

    home.sessionVariables = {
      TMUX_CONF = "${cfg.configDir}/.tmux.conf";
      TMUX_CONF_LOCAL = "${cfg.configDir}/.tmux.conf.local";
      TMUX_PLUGIN_MANAGER_PATH = "$HOME/.tmux/plugins";
      # Read by `tmux-helper reload` so prefix-r knows what to source-file.
      TMUX_HELPER_CONF = "${experimentalConf}";
      # Read by `tmux-helper theme apply/cycle` to load the palette JSON.
      TMUX_HELPER_THEMES = "${themesJson}";
    };
  };
}
