-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
vim.opt.rtp:prepend(lazypath)

-- Add Nix-managed treesitter grammars to runtimepath
local grammars_path = os.getenv("TREESITTER_GRAMMARS")
if grammars_path then
  vim.opt.runtimepath:append(grammars_path)
end

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
  -- Put lockfile in writable location (not read-only Nix store)
  lockfile = vim.fn.stdpath("data") .. "/lazy-lock.json",
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
