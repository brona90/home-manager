# Host: 888973's corporate Mac (aarch64-darwin). Selected via the
# users.*.hosts mapping in config.nix.
#
# Only the Homebrew package lists live here; the idempotent brew-sync
# activation itself is shared in home/darwin.nix (my.homebrew options).
#
# The lists below are defaults: a fork (or this machine) can replace them
# from config.local.nix (gitignored) via
#   hosts.corp-mac.brew = { casks = [...]; formulas = [...]; };
# Lists REPLACE wholesale (no concat), so copy the full list and edit.
{userConfig, ...}: let
  brew = userConfig.hosts.corp-mac.brew or {};
in {
  my = {
    # Zscaler bypass routes for build registry traffic — corporate machine only.
    zscalerBypass.enable = true;

    homebrew = {
      casks =
        brew.casks
        or [
          "betterdisplay"
          "chrome-remote-desktop-host"
          "clipy"
          "google-chrome"
          "iterm2"
          "microsoft-teams"
          "rectangle"
          "slack"
        ];
      formulas =
        brew.formulas
        or [
          "lilypond"
          "sbcl"
          "displayplacer"
        ];
    };
  };
}
