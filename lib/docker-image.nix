# Build a Docker image from a Home Manager configuration
{
  pkgs,
  homeConfiguration,
  username,
  homeDirectory,
  uid ? 1000,
  gid ? 1000,
  imageName ? "home-manager",
  imageTag ? "latest",
}: let
  inherit (homeConfiguration) activationPackage;
  homePath = "${activationPackage}/home-path";

  customNss = pkgs.symlinkJoin {
    name = "custom-nss";
    paths = [
      (pkgs.writeTextDir "etc/passwd" ''
        root:x:0:0:root:/root:/bin/bash
        nobody:x:65534:65534:Nobody:/nonexistent:/usr/sbin/nologin
        ${username}:x:${toString uid}:${toString gid}::${homeDirectory}:${homePath}/bin/zsh
      '')
      (pkgs.writeTextDir "etc/group" ''
        root:x:0:
        nobody:x:65534:
        ${username}:x:${toString gid}:
      '')
      (pkgs.writeTextDir "etc/nsswitch.conf" ''
        hosts: files dns
      '')
      (pkgs.runCommand "var-empty" {} ''
        mkdir -p $out/var/empty
      '')
    ];
  };

  entrypoint = pkgs.writeShellApplication {
    name = "entrypoint";
    text = ''
      export HOME=${homeDirectory}
      export USER=${username}

      mkdir -p ~/.cache/oh-my-zsh/completions
      mkdir -p ~/.cache/starship
      mkdir -p ~/.local/share/nvim/lazy
      mkdir -p ~/.local/state/nvim
      mkdir -p ~/.config/tmux
      mkdir -p ~/.config/nvim
      mkdir -p ~/.config/zsh
      mkdir -p ~/.zsh/plugins
      mkdir -p ~/.tmux/plugins

      echo "Setting up home-manager environment..."
      if [ -d ${activationPackage}/home-files ]; then
        ${pkgs.rsync}/bin/rsync -rL ${activationPackage}/home-files/ "$HOME"/
      fi

      export PATH="${homePath}/bin:$PATH"
      export LD_LIBRARY_PATH="${pkgs.stdenv.cc.cc.lib}/lib:${pkgs.glibc}/lib:${pkgs.zlib}/lib:''${LD_LIBRARY_PATH:-}"
      export TMUX_PLUGIN_MANAGER_PATH="$HOME/.tmux/plugins"

      if [ -f ${homePath}/etc/profile.d/hm-session-vars.sh ]; then
        # shellcheck source=/dev/null
        source ${homePath}/etc/profile.d/hm-session-vars.sh
      fi

      exec ${homePath}/bin/zsh
    '';
  };
in
  pkgs.dockerTools.buildLayeredImage {
    name = imageName;
    tag = imageTag;

    contents = [
      pkgs.bashInteractive
      pkgs.coreutils
      pkgs.findutils
      pkgs.gnugrep
      pkgs.gnused
      pkgs.gawk
      pkgs.less
      pkgs.which
      pkgs.ncurses
      pkgs.nix
      pkgs.cacert
      pkgs.rsync
      pkgs.gcc
      pkgs.glibc
      pkgs.zlib
      pkgs.stdenv.cc.cc.lib
      pkgs.iana-etc
      pkgs.curl
      pkgs.dnsutils
      pkgs.iputils
      customNss
      homePath
      activationPackage
    ];

    extraCommands = ''
      mkdir -p home/${username}/.config
      mkdir -p home/${username}/.local
      mkdir -p home/${username}/.cache
      chown -R ${toString uid}:${toString gid} home/${username}
      mkdir -p tmp
      chmod 1777 tmp
    '';

    config = {
      Cmd = ["${entrypoint}/bin/entrypoint"];
      Env = [
        "HOME=${homeDirectory}"
        "USER=${username}"
        "PATH=${homePath}/bin:/bin"
        "NIX_PATH=nixpkgs=${pkgs.path}"
        "EDITOR=emacsclient -t"
        "VISUAL=emacsclient -c"
        # Use C.UTF-8 instead of en_US.UTF-8 (used by home/common.nix) to
        # avoid bundling glibcLocales (~200MB). C.UTF-8 is built into glibc
        # and provides full UTF-8 support without locale data files.
        "LANG=C.UTF-8"
        "LC_ALL=C.UTF-8"
        "TERM=xterm-256color"
        "COLORTERM=truecolor"
      ];
      WorkingDir = homeDirectory;
      User = username;
    };
  }
