{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.my.btop;

  # btop's GPU box needs the vendor's monitoring library (NVML for NVIDIA),
  # which it locates at RUNTIME with dlopen("libnvidia-ml.so.1") rather than
  # at link time. nixpkgs cannot make that a store dependency: the userspace
  # driver has to match the host's kernel driver, so it ships with the host.
  # Nix's glibc never reads /etc/ld.so.conf, so on a standalone install the
  # dlopen fails quietly and btop shows CPU, memory and disks with no GPU.
  #
  # LD_LIBRARY_PATH rather than a RUNPATH entry, deliberately. Adding the
  # directory to btop's RUNPATH (nixpkgs' own autoAddDriverRunpath approach,
  # measured here with LD_DEBUG=libs on 2026-09-16) does load
  # libnvidia-ml.so.1 -- but on WSL2 NVML then dlopens libdxcore.so by bare
  # name from inside itself, and that lookup consults the CALLER's RUNPATH,
  # which the host library does not have. Only the environment reaches it.
  # The wrapper is a symlinkJoin over the cached btop, so a nixpkgs bump does
  # not turn into a local LTO rebuild for the sake of one exported variable.
  btopPackage =
    if cfg.driverLibraryPath == null
    then pkgs.btop
    else
      pkgs.symlinkJoin {
        name = "${pkgs.btop.name}-driver-path";
        paths = [pkgs.btop];
        nativeBuildInputs = [pkgs.makeWrapper];
        inherit (pkgs.btop) meta;
        postBuild = ''
          wrapProgram "$out/bin/btop" \
            --prefix LD_LIBRARY_PATH : ${lib.escapeShellArg cfg.driverLibraryPath}
        '';
      };
in {
  options.my.btop = {
    enable = lib.mkEnableOption "btop system monitor";

    updateMs = lib.mkOption {
      type = lib.types.int;
      default = 100;
      description = "Update time in milliseconds";
    };

    driverLibraryPath = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/usr/lib/wsl/lib";
      description = ''
        Directory holding the host's GPU driver libraries (libnvidia-ml.so.1),
        prepended to LD_LIBRARY_PATH for btop alone so its GPU box can load
        them. Not a nix store path and it cannot be one; see
        my.ollama.driverLibraryPath for why. Set per host: WSL2 publishes the
        Windows driver's Linux half in /usr/lib/wsl/lib. Leave null on a
        machine with no GPU and btop is the unmodified nixpkgs package.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    programs.btop = {
      enable = true;
      package = btopPackage;
      settings = {
        color_theme = "matcha-dark-sea";
        theme_background = false;
        vim_keys = true;
        update_ms = cfg.updateMs;
      };
    };

    # force = true: btop rewrites its config on exit; without this HM link management fails
    xdg.configFile."btop/btop.conf".force = true;
  };
}
