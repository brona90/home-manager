# Common NixOS settings shared across all hosts
{ pkgs, userConfig, ... }:

let
  # Get the first user configured for x86_64-linux
  linuxUsers = builtins.filter
    (user: builtins.elem "x86_64-linux" user.systems)
    userConfig.users;
  primaryUser = builtins.head linuxUsers;
  inherit (primaryUser) username;
  inherit (userConfig.repo) cachixCache;
in
{
  # Nix settings
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "root" username ];
    max-jobs = "auto";
    cores = 0;

    substituters = [
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"
      "https://emacs.cachix.org"
      "https://${cachixCache}.cachix.org"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "emacs.cachix.org-1:b1SMJNLY/mZF6GxQE+eDBeps7WnkT0Po55TAyzwOxTY="
      "gfoster.cachix.org-1:O73e1PtN7sjaB5xDnBO/UMJSfheJjqlt6l6howghGvw="
    ];

    connect-timeout = 5;
    keep-outputs = true;
    keep-derivations = true;
  };

  # User configuration
  users.users.${username} = {
    isNormalUser = true;
    home = "/home/${username}";
    description = "Gregory Foster";
    extraGroups = [ "wheel" ];
    shell = pkgs.zsh;
  };

  # System packages
  programs.zsh.enable = true;

  # Passwordless sudo for wheel
  security.sudo.wheelNeedsPassword = false;
}
