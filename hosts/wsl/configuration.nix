# NixOS-WSL specific configuration
{ ... }:

{
  imports = [ ../common ];

  wsl = {
    enable = true;
    defaultUser = "gfoster";
    docker-desktop.enable = true;
  };

  users.users.gfoster.extraGroups = [ "wheel" "docker" ];

  system.stateVersion = "25.05";
}
