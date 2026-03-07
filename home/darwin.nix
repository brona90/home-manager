# macOS-specific home-manager configuration
{ lib, ... }: {
  my.gpg.enableYubiKey = true;

  my.zsh.extraAliases = {
    ls = "ls -G"; # macOS ls uses -G for color
  };

  home.activation.homebrew = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if ! command -v brew &>/dev/null; then
      echo "warning: brew not found; skipping Homebrew package installation" >&2
    else
      $DRY_RUN_CMD brew install --cask google-chrome
    fi
  '';
}
