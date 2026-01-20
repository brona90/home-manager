-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
vim.opt.rtp:prepend(lazypath)

-- Load config options first
require("config.options")

-- Setup lazy.nvim (immutable - plugins managed by Nix)
require("lazy").setup({
  spec = {
    { "LazyVim/LazyVim", import = "lazyvim.plugins" },
    { import = "plugins" },
  },
  defaults = {
    lazy = false,
    version = false,
  },
  install = {
    -- Don't auto-install missing plugins (Nix manages them)
    missing = false,
    colorscheme = { "tokyonight", "habamax" },
  },
  checker = {
    -- Don't check for plugin updates (Nix manages versions)
    enabled = false,
  },
  change_detection = {
    -- Don't auto-reload on config changes (config is immutable)
    enabled = false,
  },
  rocks = {
    -- Disable luarocks integration (we manage deps via Nix)
    enabled = false,
  },
  performance = {
    rtp = {
      disabled_plugins = {
        "gzip",
        "tarPlugin",
        "tohtml",
        "tutor",
        "zipPlugin",
      },
    },
  },
})
