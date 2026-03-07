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
    # Install Homebrew if not present
    if ! command -v brew &>/dev/null \
        && [[ ! -x /opt/homebrew/bin/brew ]] \
        && [[ ! -x /usr/local/bin/brew ]]; then
      $DRY_RUN_CMD NONINTERACTIVE=1 /bin/bash -c \
        "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi

    # Resolve brew path (may not be on PATH yet in a fresh install)
    if command -v brew &>/dev/null; then
      _brew=brew
    elif [[ -x /opt/homebrew/bin/brew ]]; then
      _brew=/opt/homebrew/bin/brew
    elif [[ -x /usr/local/bin/brew ]]; then
      _brew=/usr/local/bin/brew
    else
      echo "warning: brew not found after installation attempt; skipping cask installs" >&2
      _brew=""
    fi

    if [[ -n "$_brew" ]]; then
      $DRY_RUN_CMD "$_brew" install --cask google-chrome
    fi
  '';
}
