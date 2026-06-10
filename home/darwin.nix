# macOS-specific home-manager configuration
{
  lib,
  pkgs,
  ...
}: {
  my = {
    gpg.enableYubiKey = true;
    displayplacer.enable = true;

    zsh.extraAliases = {
      ls = "ls -G"; # macOS ls uses -G for color
      zscaler-stop = "sudo launchctl bootout system/com.zscaler.tray; sudo launchctl bootout system/com.zscaler.zfd; sudo launchctl bootout system/com.zscaler.tunnel";
    };
  };

  home = {
    # claude-code is provided by modules/claude-code.nix (my.claudeCode.enable)

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

    # Idempotent, failure-tolerant Homebrew package sync. Activation runs
    # under set -eu, so every brew invocation is wrapped in `if ! ...` --
    # a flaky cask or missing network must never abort the rest of
    # activation. `brew list` checks are local-only, so when everything is
    # already installed this block finishes quickly with no network access.
    #
    # Homebrew itself is deliberately NOT installed here: a curl|bash
    # bootstrap mid-activation needs interactive sudo and is fragile.
    # Install it manually first (https://brew.sh):
    #   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    activation.homebrew = lib.hm.dag.entryAfter ["writeBoundary" "zscalerBypass"] ''
      # Resolve brew path (Apple Silicon vs Intel prefix)
      if command -v brew &>/dev/null; then
        _brew=brew
      elif [[ -x /opt/homebrew/bin/brew ]]; then
        _brew=/opt/homebrew/bin/brew
      elif [[ -x /usr/local/bin/brew ]]; then
        _brew=/usr/local/bin/brew
      else
        _brew=""
        echo "warning: Homebrew not found; skipping cask/formula installs." >&2
        echo "  Install it manually, then re-run home-manager switch:" >&2
        echo '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"' >&2
      fi

      if [[ -n "$_brew" ]]; then
        for _cask in betterdisplay calibre chrome-remote-desktop-host \
            clipy claude discord google-chrome iterm2 microsoft-teams \
            rectangle signal slack; do
          if ! "$_brew" list --cask "$_cask" &>/dev/null; then
            if ! $DRY_RUN_CMD "$_brew" install --cask "$_cask"; then
              echo "warning: brew install --cask $_cask failed; continuing" >&2
            fi
          fi
        done

        for _formula in lilypond sbcl displayplacer; do
          if ! "$_brew" list --formula "$_formula" &>/dev/null; then
            if ! $DRY_RUN_CMD "$_brew" install --formula "$_formula"; then
              echo "warning: brew install --formula $_formula failed; continuing" >&2
            fi
          fi
        done
      fi
    '';
  };
}
