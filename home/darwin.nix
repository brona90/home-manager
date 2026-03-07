# macOS-specific home-manager configuration
{ lib, pkgs, ... }: {
  my.gpg.enableYubiKey = true;

  my.zsh.extraAliases = {
    ls = "ls -G"; # macOS ls uses -G for color
  };

  # Make Nerd Fonts available to macOS CoreText (GUI apps like Emacs, terminals).
  # On Darwin, fonts in home.packages are NOT automatically visible to macOS apps;
  # fonts.fontDirectories symlinks them into ~/Library/Fonts/HomeManager/.
  fonts.fontDirectories = [
    pkgs.nerd-fonts.victor-mono # VictorMono Nerd Font (doom-font in config.el)
    pkgs.nerd-fonts.symbols-only # Symbols Nerd Font Mono (nerd-icons in config.el)
  ];

  home.activation.homebrew = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if ! command -v brew &>/dev/null; then
      echo "warning: brew not found; skipping Homebrew package installation" >&2
    else
      $DRY_RUN_CMD brew install --cask google-chrome
    fi
  '';
}
