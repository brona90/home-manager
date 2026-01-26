# Build a Docker image from a Home Manager configuration
{ pkgs
, homeConfiguration
, username
, homeDirectory
, imageName ? "home-manager"
, imageTag ? "latest"
}:

let
  inherit (homeConfiguration) activationPackage;
  homePath = "${activationPackage}/home-path";

  customNss = pkgs.symlinkJoin {
    name = "custom-nss";
    paths = [
      (pkgs.writeTextDir "etc/passwd" ''
        root:x:0:0:root:/root:/bin/bash
        nobody:x:65534:65534:Nobody:/nonexistent:/usr/sbin/nologin
        ${username}:x:1000:1000::${homeDirectory}:${homePath}/bin/zsh
      '')
      (pkgs.writeTextDir "etc/group" ''
        root:x:0:
        nobody:x:65534:
        ${username}:x:1000:
      '')
      (pkgs.writeTextDir "etc/nsswitch.conf" ''
        hosts: files dns
      '')
      (pkgs.runCommand "var-empty" { } ''
        mkdir -p $out/var/empty
      '')
    ];
  };

  entrypoint = pkgs.writeShellScript "entrypoint.sh" ''
    export HOME=${homeDirectory}
    export USER=${username}

    mkdir -p ~/.cache/oh-my-zsh/completions 2>/dev/null || true
    mkdir -p ~/.cache/starship 2>/dev/null || true
    mkdir -p ~/.local/share/nvim/lazy 2>/dev/null || true
    mkdir -p ~/.local/state/nvim 2>/dev/null || true
    mkdir -p ~/.config/tmux 2>/dev/null || true
    mkdir -p ~/.config/nvim 2>/dev/null || true
    mkdir -p ~/.config/zsh 2>/dev/null || true
    mkdir -p ~/.zsh/plugins 2>/dev/null || true
    mkdir -p ~/.tmux/plugins 2>/dev/null || true

    echo "Setting up home-manager environment..."
    if [ -d ${activationPackage}/home-files ]; then
      ${pkgs.rsync}/bin/rsync -rL ${activationPackage}/home-files/ ~/ 2>/dev/null || \
        cp -rL ${activationPackage}/home-files/. ~/ 2>/dev/null || true
    fi

    export PATH="${homePath}/bin:$PATH"
    export LD_LIBRARY_PATH="${pkgs.stdenv.cc.cc.lib}/lib:${pkgs.glibc}/lib:${pkgs.zlib}/lib:$LD_LIBRARY_PATH"
    export TMUX_PLUGIN_MANAGER_PATH="$HOME/.tmux/plugins"

    if [ -f ${homePath}/etc/profile.d/hm-session-vars.sh ]; then
      source ${homePath}/etc/profile.d/hm-session-vars.sh
    fi

    exec ${homePath}/bin/zsh
  '';

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
    mkdir -p tmp
    chmod 1777 tmp
  '';

  config = {
    Cmd = [ "${entrypoint}" ];
    Env = [
      "HOME=${homeDirectory}"
      "USER=${username}"
      "PATH=${homePath}/bin:/bin"
      "NIX_PATH=nixpkgs=${pkgs.path}"
      "EDITOR=emacsclient -t"
      "VISUAL=emacsclient -c"
      "LANG=C.UTF-8"
      "LC_ALL=C.UTF-8"
      "TERM=xterm-256color"
      "COLORTERM=truecolor"
    ];
    WorkingDir = homeDirectory;
    User = username;
  };
}
