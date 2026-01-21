{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.my.vim;

  # VictorMono Nerd Font
  victorMonoNerdFont = pkgs.nerd-fonts.victor-mono;

  # Pre-fetch lazy.nvim (plugin manager)
  lazyNvim = pkgs.fetchFromGitHub {
    owner = "folke";
    repo = "lazy.nvim";
    rev = "v11.16.2";
    sha256 = "sha256-48i6Z6cwccjd5rRRuIyuuFS68J0lAIAEEiSBJ4Vq5vY=";
  };

  # Pre-fetch LazyVim distribution
  lazyVimDistro = pkgs.fetchFromGitHub {
    owner = "LazyVim";
    repo = "LazyVim";
    rev = "v15.13.0";
    sha256 = "sha256-pm1B4tdHqSV8n+hM78asqw5WNdMfC5fUSiZcjg8ZtAg=";
  };

  # Use vimPlugins from nixpkgs
  vp = pkgs.vimPlugins;

  # Create a combined treesitter grammars path from withAllGrammars.dependencies
  treesitterGrammars = pkgs.symlinkJoin {
    name = "nvim-treesitter-grammars";
    paths = vp.nvim-treesitter.withAllGrammars.dependencies;
  };

  # Build the plugins directory using nixpkgs vimPlugins
  pluginsDir = pkgs.linkFarm "lazy-plugins" [
    { name = "lazy.nvim"; path = lazyNvim; }
    { name = "LazyVim"; path = lazyVimDistro; }
    # UI
    { name = "tokyonight.nvim"; path = vp.tokyonight-nvim; }
    { name = "catppuccin"; path = vp.catppuccin-nvim; }
    { name = "which-key.nvim"; path = vp.which-key-nvim; }
    { name = "noice.nvim"; path = vp.noice-nvim; }
    { name = "nui.nvim"; path = vp.nui-nvim; }
    { name = "nvim-notify"; path = vp.nvim-notify; }
    { name = "mini.icons"; path = vp.mini-icons; }
    { name = "dressing.nvim"; path = vp.dressing-nvim; }
    { name = "bufferline.nvim"; path = vp.bufferline-nvim; }
    { name = "lualine.nvim"; path = vp.lualine-nvim; }
    { name = "indent-blankline.nvim"; path = vp.indent-blankline-nvim; }
    { name = "mini.indentscope"; path = vp.mini-indentscope; }
    { name = "dashboard-nvim"; path = vp.dashboard-nvim; }
    # Editor
    { name = "neo-tree.nvim"; path = vp.neo-tree-nvim; }
    { name = "nvim-spectre"; path = vp.nvim-spectre; }
    { name = "telescope.nvim"; path = vp.telescope-nvim; }
    { name = "telescope-fzf-native.nvim"; path = vp.telescope-fzf-native-nvim; }
    { name = "flash.nvim"; path = vp.flash-nvim; }
    { name = "gitsigns.nvim"; path = vp.gitsigns-nvim; }
    { name = "vim-illuminate"; path = vp.vim-illuminate; }
    { name = "mini.bufremove"; path = vp.mini-bufremove; }
    { name = "trouble.nvim"; path = vp.trouble-nvim; }
    { name = "todo-comments.nvim"; path = vp.todo-comments-nvim; }
    # Treesitter
    { name = "nvim-treesitter"; path = vp.nvim-treesitter.withAllGrammars; }
    { name = "nvim-treesitter-textobjects"; path = vp.nvim-treesitter-textobjects; }
    { name = "nvim-ts-autotag"; path = vp.nvim-ts-autotag; }
    # LSP
    { name = "nvim-lspconfig"; path = vp.nvim-lspconfig; }
    { name = "mason.nvim"; path = vp.mason-nvim; }
    { name = "mason-lspconfig.nvim"; path = vp.mason-lspconfig-nvim; }
    { name = "neoconf.nvim"; path = vp.neoconf-nvim; }
    { name = "lazydev.nvim"; path = vp.lazydev-nvim; }
    # Completion
    { name = "nvim-cmp"; path = vp.nvim-cmp; }
    { name = "cmp-nvim-lsp"; path = vp.cmp-nvim-lsp; }
    { name = "cmp-buffer"; path = vp.cmp-buffer; }
    { name = "cmp-path"; path = vp.cmp-path; }
    { name = "LuaSnip"; path = vp.luasnip; }
    { name = "friendly-snippets"; path = vp.friendly-snippets; }
    # Formatting & Linting
    { name = "conform.nvim"; path = vp.conform-nvim; }
    { name = "nvim-lint"; path = vp.nvim-lint; }
    # Utilities
    { name = "plenary.nvim"; path = vp.plenary-nvim; }
    { name = "nvim-web-devicons"; path = vp.nvim-web-devicons; }
    { name = "persistence.nvim"; path = vp.persistence-nvim; }
    { name = "mini.pairs"; path = vp.mini-pairs; }
    { name = "mini.ai"; path = vp.mini-ai; }
    { name = "mini.surround"; path = vp.mini-surround; }
    { name = "mini.comment"; path = vp.mini-comment; }
    { name = "vim-startuptime"; path = vp.vim-startuptime; }
    { name = "snacks.nvim"; path = vp.snacks-nvim; }
    { name = "ts-comments.nvim"; path = vp.ts-comments-nvim; }
    { name = "blink.cmp"; path = vp.blink-cmp; }
    { name = "sqlite.lua"; path = vp.sqlite-lua; }
  ];

  # Core dependencies
  coreDeps = with pkgs; [
    git curl wget unzip gnutar gzip ripgrep fd fzf gnumake cmake pkg-config
    sqlite ast-grep
  ] ++ (if pkgs.stdenv.isLinux then [ xclip wl-clipboard gcc ] else [ ]);

  # Language servers
  lspServers = with pkgs; [
    lua-language-server nil pyright ruff
    nodePackages.typescript-language-server
    nodePackages.vscode-langservers-extracted
    gopls delve rust-analyzer
    nodePackages.bash-language-server
    yaml-language-server taplo marksman
    dockerfile-language-server terraform-ls
  ];

  # Formatters
  formatters = with pkgs; [
    stylua nixfmt alejandra black isort
    nodePackages.prettier gofumpt shfmt taplo
  ];

  # Linters
  linters = with pkgs; [
    ruff pylint nodePackages.eslint shellcheck markdownlint-cli yamllint
  ];

  # Debuggers
  debuggers = with pkgs; [ python3Packages.debugpy delve ];

  # Additional tools
  additionalTools = with pkgs; [ lazygit delta tree nodejs_22 python3 ];

  allDeps = coreDeps ++ lspServers ++ formatters ++ linters ++ debuggers ++ additionalTools ++ [ pkgs.tree-sitter ];

  neovimPackage = pkgs.neovim.override {
    withNodeJs = true;
    withPython3 = true;
    withRuby = false;
  };

  # Nvim config directory
  nvimConfigDir = ./nvim-config;

  # Wrapper script
  lazyVimWrapper = pkgs.writeShellScriptBin "lvim" ''
    export FONTCONFIG_FILE=${pkgs.fontconfig.out}/etc/fonts/fonts.conf
    export FONTCONFIG_PATH=${victorMonoNerdFont}/share/fonts

    # Set SSL certificate path for git
    export GIT_SSL_CAINFO=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
    export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt

    # Use XDG directories for mutable data
    export XDG_DATA_HOME=''${XDG_DATA_HOME:-$HOME/.local/share}
    export XDG_STATE_HOME=''${XDG_STATE_HOME:-$HOME/.local/state}
    export XDG_CACHE_HOME=''${XDG_CACHE_HOME:-$HOME/.cache}

    # Ensure directories exist
    mkdir -p "$XDG_DATA_HOME/nvim/lazy"
    mkdir -p "$XDG_STATE_HOME/nvim"
    mkdir -p "$XDG_CACHE_HOME/nvim"

    # Add path to dependencies
    export PATH="${lib.makeBinPath allDeps}:$PATH"

    # Set sqlite library path for sqlite.lua
    export LIBSQLITE="${pkgs.sqlite.out}/lib/libsqlite3${if pkgs.stdenv.isDarwin then ".dylib" else ".so"}"

    # Export treesitter grammars path for init.lua to use
    export TREESITTER_GRAMMARS="${treesitterGrammars}"

    # Copy pre-fetched plugins (not symlink) so we can add .git markers
    for plugin in ${pluginsDir}/*; do
      name=$(basename "$plugin")
      target="$XDG_DATA_HOME/nvim/lazy/$name"
      if [ ! -d "$target" ]; then
        cp -rL "$plugin" "$target"
        chmod -R u+w "$target"
        # Create .git marker so lazy.nvim thinks plugin is installed
        mkdir -p "$target/.git"
      fi
    done

    # Run neovim with immutable config
    exec ${neovimPackage}/bin/nvim -u "${nvimConfigDir}/init.lua" "$@"
  '';

in
{
  options.my.vim = {
    enable = mkEnableOption "Gregory's LazyVim configuration";
  };

  config = mkIf cfg.enable {
    home.packages = [
      lazyVimWrapper
      victorMonoNerdFont
    ] ++ allDeps;

    # Create nvim config directory structure
    xdg.configFile = {
      "nvim/init.lua".source = "${nvimConfigDir}/init.lua";
      "nvim/init.lua".force = true;
      "nvim/lua/config/options.lua".source = "${nvimConfigDir}/lua/config/options.lua";
      "nvim/lua/config/options.lua".force = true;
      "nvim/lua/plugins/theme.lua".source = "${nvimConfigDir}/lua/plugins/theme.lua";
      "nvim/lua/plugins/theme.lua".force = true;
      "nvim/lua/plugins/treesitter.lua".source = "${nvimConfigDir}/lua/plugins/treesitter.lua";
      "nvim/lua/plugins/treesitter.lua".force = true;
    };
  };
}
