# Build a Docker image from a Home Manager configuration
#
# profile = "full" (default) bundles the entire home-manager closure
# (editors, LSPs, grammars — large). profile = "slim" builds a portable
# rescue shell (zsh + tmux + git + core CLI) with no homeConfiguration
# required and a much smaller closure.
{
  pkgs,
  # Required when profile == "full"; unused by "slim".
  homeConfiguration ? null,
  username,
  homeDirectory,
  uid ? 1000,
  gid ? 1000,
  imageName ? "home-manager",
  imageTag ? "latest",
  profile ? "full",
  # stream = true emits a script that writes the image tarball to stdout
  # (pipe into `docker load`) instead of materializing a tar.gz in the
  # store — roughly halves peak disk usage, which matters on CI runners.
  stream ? false,
}:
assert pkgs.lib.assertMsg (builtins.elem profile ["full" "slim"])
"docker-image.nix: profile must be \"full\" or \"slim\", got \"${profile}\"";
assert pkgs.lib.assertMsg (profile == "slim" || homeConfiguration != null)
"docker-image.nix: homeConfiguration is required when profile == \"full\""; let
  isSlim = profile == "slim";

  # Only forced in the full profile (lazy evaluation keeps slim safe).
  inherit (homeConfiguration) activationPackage;
  homePath = "${activationPackage}/home-path";

  loginShell =
    if isSlim
    then "${pkgs.zsh}/bin/zsh"
    else "${homePath}/bin/zsh";

  customNss = pkgs.symlinkJoin {
    name = "custom-nss";
    paths = [
      (pkgs.writeTextDir "etc/passwd" ''
        root:x:0:0:root:/root:/bin/bash
        nobody:x:65534:65534:Nobody:/nonexistent:/usr/sbin/nologin
        ${username}:x:${toString uid}:${toString gid}::${homeDirectory}:${loginShell}
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

  # Minimal interactive zsh config for the slim rescue shell. Nix's zsh
  # reads /etc/zshrc for interactive shells, so no per-user dotfiles are
  # needed in the (tmpfs) home directory.
  slimZshrc = pkgs.writeTextDir "etc/zshrc" ''
    # slim-profile rescue shell config
    HISTFILE="$HOME/.zsh_history"
    HISTSIZE=10000
    SAVEHIST=10000
    setopt SHARE_HISTORY HIST_IGNORE_DUPS HIST_IGNORE_SPACE
    setopt AUTO_CD INTERACTIVE_COMMENTS
    bindkey -e
    autoload -Uz compinit && compinit -u -d "$HOME/.zcompdump"
    PROMPT='%F{green}%n@slim%f %F{blue}%~%f %(?.%F{green}.%F{red})%#%f '
    alias ll='ls -lah'
    alias grep='grep --color=auto'
    export PAGER=less
  '';

  entrypoint = pkgs.writeShellApplication {
    name = "entrypoint";
    text =
      if isSlim
      then ''
        export HOME=${homeDirectory}
        export USER=${username}
        mkdir -p "$HOME"
        exec ${pkgs.zsh}/bin/zsh -l
      ''
      else ''
        export HOME=${homeDirectory}
        export USER=${username}

        mkdir -p "$HOME/.cache/oh-my-zsh/completions"
        mkdir -p "$HOME/.cache/starship"
        mkdir -p "$HOME/.local/share/nvim/lazy"
        mkdir -p "$HOME/.local/state/nvim"
        mkdir -p "$HOME/.config/tmux"
        mkdir -p "$HOME/.config/nvim"
        mkdir -p "$HOME/.config/zsh"
        mkdir -p "$HOME/.zsh/plugins"
        mkdir -p "$HOME/.tmux/plugins"

        echo "Setting up home-manager environment..."
        if [ -d "${activationPackage}/home-files" ]; then
          "${pkgs.rsync}/bin/rsync" -rL "${activationPackage}/home-files/" "$HOME"/
        fi

        export PATH="${homePath}/bin:$PATH"
        export LD_LIBRARY_PATH="${pkgs.stdenv.cc.cc.lib}/lib:${pkgs.glibc}/lib:${pkgs.zlib}/lib:''${LD_LIBRARY_PATH:-}"
        export TMUX_PLUGIN_MANAGER_PATH="$HOME/.tmux/plugins"

        if [ -f "${homePath}/etc/profile.d/hm-session-vars.sh" ]; then
          # hm-session-vars.sh uses $__HM_SESS_VARS_SOURCED without a default,
          # which trips set -u.  Disable nounset for the source, then restore.
          set +u
          # shellcheck source=/dev/null
          source "${homePath}/etc/profile.d/hm-session-vars.sh"
          set -u
        fi

        exec "${homePath}/bin/zsh"
      '';
  };

  fullContents = [
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

  slimContents = [
    pkgs.zsh
    pkgs.tmux
    # gitMinimal = git without perl/python/gitweb — saves ~150MB of
    # closure in a rescue-shell image.
    pkgs.gitMinimal
    pkgs.coreutils
    pkgs.findutils
    pkgs.gnugrep
    pkgs.gnused
    pkgs.gawk
    pkgs.less
    pkgs.which
    pkgs.ncurses
    pkgs.curl
    pkgs.cacert
    pkgs.iana-etc
    pkgs.openssh
    pkgs.ripgrep
    pkgs.fzf
    pkgs.jq
    pkgs.bat
    pkgs.htop
    customNss
    slimZshrc
  ];

  commonEnv = [
    "HOME=${homeDirectory}"
    "USER=${username}"
    # Use C.UTF-8 instead of en_US.UTF-8 (used by home/common.nix) to
    # avoid bundling glibcLocales (~200MB). C.UTF-8 is built into glibc
    # and provides full UTF-8 support without locale data files.
    "LANG=C.UTF-8"
    "LC_ALL=C.UTF-8"
    "TERM=xterm-256color"
    "COLORTERM=truecolor"
  ];

  profileEnv =
    if isSlim
    then [
      "PATH=/bin"
      "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
    ]
    else [
      "PATH=${homePath}/bin:/bin"
      "NIX_PATH=nixpkgs=${pkgs.path}"
      "EDITOR=emacsclient -t --alternate-editor 'emacs -nw'"
      "VISUAL=emacsclient -c --alternate-editor 'emacs'"
    ];

  mkImage =
    if stream
    then pkgs.dockerTools.streamLayeredImage
    else pkgs.dockerTools.buildLayeredImage;
in
  mkImage {
    name = imageName;
    tag = imageTag;

    contents =
      if isSlim
      then slimContents
      else fullContents;

    extraCommands = ''
      mkdir -p home/${username}/.config
      mkdir -p home/${username}/.local
      mkdir -p home/${username}/.cache
      chmod -R a+rwX home/${username}
      mkdir -p tmp
      chmod 1777 tmp
    '';

    config = {
      Cmd = ["${entrypoint}/bin/entrypoint"];
      Env = commonEnv ++ profileEnv;
      WorkingDir = homeDirectory;
      User = username;
    };
  }
