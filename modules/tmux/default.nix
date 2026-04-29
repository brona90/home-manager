# tmux module post-Phase-9.5: helper-driven generated config is the only
# path. The Phase-9 useHelper kill-switch was removed once the config
# proved stable in daily use; rollback to the gpakosz config is via
# `git revert` of the Phase-9 cutover commit.
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
  # use the /nix/store output directly.
  helperBin =
    if cfg.preferSystemPath && pkgs.stdenv.isDarwin
    then "/usr/local/bin/tmux-helper"
    else "${config.my.tmuxHelper.package}/bin/tmux-helper";

  themes = import ./themes.nix;
  themesJson = pkgs.writeText "tmux-themes.json" (builtins.toJSON themes);

  experimentalConf = pkgs.writeText "tmux.conf" (
    import ./conf-experimental.nix {
      inherit helperBin;
      defaultThemePreset = cfg.theme.preset;
    }
  );
in {
  options.my.tmux = {
    enable = lib.mkEnableOption "tmux configuration (helper-driven)";

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
        runtime choice is stored in @tmux_theme_preset on the tmux
        server for the session lifetime; persisting across server
        restarts requires changing this option and running home-manager
        switch.
      '';
    };

    preferSystemPath = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Use /usr/local/bin/tmux-helper instead of the /nix/store path
        in keybindings and #(...) substitutions. Set true on macOS so
        every helper invocation has a stable path BeyondTrust EPM can
        fingerprint by, plus a stable ad-hoc cdhash. Requires the
        binary to actually be installed there -- run
        `nix run .#tmux-helper-install` once after the first
        home-manager switch and on every helper version bump.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    programs.tmux = {
      enable = true;
      terminal = "tmux-256color";
      extraConfig = "source-file ${experimentalConf}\n";
    };

    # Read by `tmux-helper reload` (prefix-r) and `tmux-helper theme
    # apply/cycle` (prefix-T) at runtime. tmux inherits these from the
    # launching shell.
    home.sessionVariables = {
      TMUX_HELPER_CONF = "${experimentalConf}";
      TMUX_HELPER_THEMES = "${themesJson}";
    };
  };
}
