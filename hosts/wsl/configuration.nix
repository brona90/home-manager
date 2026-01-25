# NixOS-WSL specific configuration
{ config, lib, pkgs, ... }:

{
  imports = [ ../common ];

  # WSL-specific settings
  wsl.enable = true;
  wsl.defaultUser = "gfoster";
  wsl.docker-desktop.enable = true;

  # Add docker group for WSL Docker Desktop integration
  users.users.gfoster.extraGroups = [ "wheel" "docker" ];

  system.stateVersion = "25.05";
}
