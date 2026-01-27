# macOS-specific home-manager configuration
{ ... }:

{
  my.zsh.extraAliases = {
    ls = "ls -G";  # macOS ls uses -G for color
  };
}
