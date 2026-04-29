# Installs the tmux-helper binary to /usr/local/bin via sudo cp. Run via
# `nix run .#tmux-helper-install` after the first home-manager switch on
# macOS, and on every helper version bump. Stable path + stable cdhash so
# BeyondTrust EPM can fingerprint by either.
{
  pkgs,
  helperPackage,
}:
pkgs.writeShellApplication {
  name = "tmux-helper-install";
  runtimeInputs = [pkgs.coreutils pkgs.sudo];
  text = ''
    set -euo pipefail
    HELPER=${helperPackage}/bin/tmux-helper
    DEST=/usr/local/bin/tmux-helper

    if [ ! -x "$HELPER" ]; then
      echo "tmux-helper not found at $HELPER -- did the package build?" >&2
      exit 1
    fi

    echo "Source : $HELPER"
    echo "Dest   : $DEST"
    if [ -f "$DEST" ]; then
      echo "Existing: $(stat -f '%z bytes, %Sm' "$DEST" 2>/dev/null || stat -c '%s bytes, %y' "$DEST")"
    fi

    echo "Sudo will be required to install into /usr/local/bin."
    sudo install -m 0755 -o root -g wheel "$HELPER" "$DEST"

    echo "Installed. Verifying signature:"
    codesign -dvv "$DEST" 2>&1 | grep -E "Identifier|Sealed|TeamIdentifier|CDHash" || true

    echo "Done."
  '';
}
