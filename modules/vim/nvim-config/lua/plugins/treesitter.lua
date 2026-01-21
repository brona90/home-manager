-- Configure nvim-treesitter for Nix-managed grammars
-- Override LazyVim's treesitter config to prevent auto-installation
local grammars_path = os.getenv("TREESITTER_GRAMMARS")

return {
  {
    "nvim-treesitter/nvim-treesitter",
    -- Add grammars to runtimepath in init (runs before config)
    init = function()
      if grammars_path then
        vim.opt.runtimepath:append(grammars_path)
      end
    end,
    -- Use opts function to REPLACE (not merge) LazyVim's opts
    -- The second parameter contains merged opts from other specs - we ignore it
    opts = function(_, _)
      return {
        -- Empty ensure_installed - Nix provides all grammars
        ensure_installed = {},
        -- Disable auto-install
        auto_install = false,
        sync_install = false,
        -- Keep highlight and indent enabled
        highlight = { enable = true },
        indent = { enable = true },
      }
    end,
    -- Disable build (no :TSUpdate)
    build = false,
  },
  -- Also disable nvim-treesitter-textobjects to avoid issues
  {
    "nvim-treesitter/nvim-treesitter-textobjects",
    enabled = false,
  },
}
