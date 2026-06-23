{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.my.emacsDoctor;

  # Resolve emacsclient from the SAME Emacs the daemon runs (the Doom package).
  # Version skew vs the daemon would break the emacsclient eval calls; fall back
  # to pkgs.emacs only when the emacs module is disabled.
  emacsPackage =
    if config.my.emacs.enable
    then config.my.emacs.package
    else pkgs.emacs;

  raw = pkgs.callPackage ./package.nix {};

  # Wrap so the system tools the binary shells out to are always on PATH, and
  # `emacsclient` is the daemon's own. nvidia-smi is WSL-provided (not in the
  # closure) and resolved at runtime by the tool itself.
  wrapped =
    pkgs.runCommand "emacs-doctor" {
      nativeBuildInputs = [pkgs.makeWrapper];
      inherit (raw) meta;
    } ''
      makeWrapper ${raw}/bin/emacs-doctor $out/bin/emacs-doctor \
        --prefix PATH : ${lib.makeBinPath [
        emacsPackage
        pkgs.systemd
        pkgs.procps
        pkgs.coreutils
        pkgs.gnugrep
        pkgs.gawk
        pkgs.xeyes
        pkgs.xwininfo
      ]}
    '';
in {
  options.my.emacsDoctor = {
    enable = lib.mkEnableOption "emacs-doctor: Emacs daemon health/recovery + WSL diagnostics CLI";

    package = lib.mkOption {
      type = lib.types.package;
      default = wrapped;
      defaultText = lib.literalExpression "wrapped emacs-doctor (callPackage ./package.nix {})";
      description = "The emacs-doctor package to install.";
    };
  };

  # Linux-only: systemd user units + /proc + WSLg checks.
  config = lib.mkIf (cfg.enable && pkgs.stdenv.isLinux) {
    home.packages = [cfg.package];
  };
}
