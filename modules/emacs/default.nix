{ config, lib, pkgs, ... }:

# NOTE: This module is a placeholder. The Doom Emacs configuration requires
# the nix-doom-emacs-unstraightened flake overlay, which is complex to inline.
# For now, you can either:
# 1. Keep using the external nix-emacs flake as a package
# 2. Use the nix-doom-emacs-unstraightened overlay directly in your flake.nix
#
# Example usage in flake.nix:
#   inputs.doom-emacs.url = "github:marienz/nix-doom-emacs-unstraightened";
#   
#   Then in your module:
#     home.packages = [ pkgs.emacsWithDoom { doomDir = ./doom.d; } ];

with lib;

let
  cfg = config.my.emacs;
in
{
  options.my.emacs = {
    enable = mkEnableOption "Gregory's Doom Emacs configuration";
    
    package = mkOption {
      type = types.package;
      description = "The Doom Emacs package (built externally with nix-doom-emacs-unstraightened)";
    };
  };

  config = mkIf cfg.enable {
    home.packages = [
      cfg.package
      pkgs.ispell
    ];

    home.sessionVariables = {
      EDITOR = "emacs -nw";
      VISUAL = "emacs -nw";
    };
  };
}
