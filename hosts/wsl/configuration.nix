# NixOS-WSL specific configuration
{ userConfig, ... }:

let
  linuxUsers = builtins.filter
    (user: builtins.elem "x86_64-linux" user.systems)
    userConfig.users;
  primaryUser = builtins.head linuxUsers;
  inherit (primaryUser) username;
in
{
  imports = [ ../common ];

  wsl = {
    enable = true;
    defaultUser = username;
    docker-desktop.enable = true;
  };

  users.users.${username}.extraGroups = [ "wheel" "docker" ];

  system.stateVersion = "25.05";
}
