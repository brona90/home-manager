# macOS-specific home-manager configuration
_:

{
  my.gpg.enableYubiKey = true;

  my.zsh.extraAliases = {
    ls = "ls -G";  # macOS ls uses -G for color
  };
}
