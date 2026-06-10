-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
vim.opt.rtp:prepend(lazypath)

-- Nix-managed treesitter grammars: passed to lazy.nvim below via
-- performance.rtp.paths. Do NOT append to rtp here — lazy.nvim's
-- performance.rtp.reset rebuilds the runtimepath during setup and would
-- silently discard a manual append.
local grammars_path = os.getenv("TREESITTER_GRAMMARS")
if not grammars_path then
  vim.schedule(function()
    vim.notify("TREESITTER_GRAMMARS not set — use 'lvim' wrapper, not 'nvim' directly", vim.log.levels.WARN)
  end)
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
      -- lazy.nvim resets the runtimepath; re-add the Nix treesitter
      -- grammars through its supported knob so they survive the reset.
      paths = grammars_path and { grammars_path } or {},
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
