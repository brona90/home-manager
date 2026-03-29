# macOS-specific home-manager configuration
{
  lib,
  pkgs,
  ...
}: {
  my.gpg.enableYubiKey = true;

  my.zsh.extraAliases = {
    ls = "ls -G"; # macOS ls uses -G for color
    zscaler-stop = "sudo launchctl bootout system/com.zscaler.tray; sudo launchctl bootout system/com.zscaler.zfd; sudo launchctl bootout system/com.zscaler.tunnel";
  };

  nixpkgs.config = {
    problems.handlers = {
      nss_wrapper.broken = "warn";  # or "ignore" if you want zero output
    };
  };
  
  home = {
    # Make Nerd Fonts available to macOS CoreText (GUI apps like Emacs, terminals).
    # On Darwin, fonts in home.packages are NOT visible to CoreText; they must be
    # symlinked into ~/Library/Fonts/ so macOS can discover them.
    file."Library/Fonts/victor-mono-nerd-font" = {
      source = "${pkgs.nerd-fonts.victor-mono}/share/fonts";
      recursive = true;
    };
    file."Library/Fonts/nerd-symbols-font" = {
      source = "${pkgs.nerd-fonts.symbols-only}/share/fonts";
      recursive = true;
    };

    activation.homebrew = lib.hm.dag.entryAfter ["writeBoundary"] ''
      # Install Homebrew if not present
      if ! command -v brew &>/dev/null \
          && [[ ! -x /opt/homebrew/bin/brew ]] \
          && [[ ! -x /usr/local/bin/brew ]]; then
        $DRY_RUN_CMD /bin/bash -eu -c \
          'NONINTERACTIVE=1 bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
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
        $DRY_RUN_CMD "$_brew" install --cask \
          calibre \
          chrome-remote-desktop-host \
          clipy \
          claude \
          discord \
          google-chrome \
          iterm2 \
          microsoft-teams \
          rectangle \
          signal \
          slack
        $DRY_RUN_CMD "$_brew" install lilypond
      fi
    '';
  };
}
