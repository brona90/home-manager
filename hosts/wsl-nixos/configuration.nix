# NixOS-WSL configuration
{ config, lib, pkgs, ... }:

{
  # Hostname must match the flake's nixosConfigurations attribute name
  # This allows: sudo nixos-rebuild switch --flake .
  networking.hostName = "wsl-nixos";

  wsl.enable = true;
  wsl.defaultUser = "gfoster";
  wsl.docker-desktop.enable = true;

  # Nix settings
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "root" "gfoster" ];
    max-jobs = "auto";
    cores = 0;

    substituters = [
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"
      "https://emacs.cachix.org"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "emacs.cachix.org-1:b1SMJNLY/mZF6GxQE+eDBeps7WnkT0Po55TAyzwOxTY="
    ];

    connect-timeout = 5;
    keep-outputs = true;
    keep-derivations = true;
  };

  # User configuration
  users.users.gfoster = {
    isNormalUser = true;
    home = "/home/gfoster";
    description = "Gregory Foster";
    extraGroups = [ "wheel" "docker" ];
    shell = pkgs.zsh;
  };

  # System packages
  programs.zsh.enable = true;

  # Passwordless sudo for wheel
  security.sudo.wheelNeedsPassword = false;

  system.stateVersion = "25.05";
}
