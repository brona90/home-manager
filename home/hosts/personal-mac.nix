# Host: gfoster's personal MacBooks (x86_64-darwin Intel and
# aarch64-darwin Apple Silicon). Selected via the users.*.hosts mapping
# in config.nix.
#
# Only the Homebrew package lists live here; the idempotent brew-sync
# activation itself is shared in home/darwin.nix (my.homebrew options).
#
# The lists below are defaults: a fork (or this machine) can replace them
# from config.local.nix (gitignored) via
#   hosts.personal-mac.brew = { casks = [...]; formulas = [...]; };
# Lists REPLACE wholesale (no concat), so copy the full list and edit.
{userConfig, ...}: let
  brew = userConfig.hosts.personal-mac.brew or {};
in {
  my.homebrew = {
    casks =
      brew.casks
      or [
        "betterdisplay"
        "calibre"
        "chrome-remote-desktop-host"
        "claude"
        "clipy"
        "discord"
        "google-chrome"
        "iterm2"
        "rectangle"
        "signal"
      ];
    formulas =
      brew.formulas
      or [
        "lilypond"
        "sbcl"
        "displayplacer"
      ];
  };
}
