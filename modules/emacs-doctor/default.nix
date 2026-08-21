{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.my.emacsDoctor;

  # Resolve emacsclient from the SAME Emacs the daemon on the DEFAULT socket
  # runs -- whichever flavor `my.emacs.flavor` names, Doom today. Version skew
  # vs that daemon would break the emacsclient eval calls; fall back to
  # pkgs.emacs only when the emacs module is disabled.
  emacsPackage =
    if config.my.emacs.enable
    # primaryPackage, NOT package: `package` is always Doom. Reading it here
    # would keep wrapping Doom's emacsclient after my.emacs.flavor flips to
    # "vanilla", while the DEFAULT socket is served by the vanilla daemon --
    # a version-skew failure with a confusing error.
    then config.my.emacs.primaryPackage
    else pkgs.emacs;

  raw = pkgs.callPackage ./package.nix {};

  # Wrap so the system tools the binary actually shells out to are always on
  # PATH, and `emacsclient` is the daemon's own. The exec'd commands are:
  # emacsclient (emacsPackage), systemctl (systemd), pgrep/ps/free (procps),
  # xeyes/xwininfo. nvidia-smi is WSL-provided (not in the closure) and the
  # tool resolves it at runtime. Everything else is done via Go stdlib
  # (os.Remove, runtime.NumCPU, os.ReadFile), so no coreutils/grep/awk needed.
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
  config = lib.mkIf (cfg.enable && pkgs.stdenv.hostPlatform.isLinux) {
    home.packages = [cfg.package];
  };
}
