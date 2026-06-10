-- Disable Mason entirely: all LSP servers, formatters, linters and
-- debuggers are provided by Nix on PATH (see modules/vim/default.nix).
-- LazyVim v15 detects the absence of mason-lspconfig.nvim and falls back
-- to enabling servers via vim.lsp.enable() with binaries from PATH
-- (lazyvim/plugins/lsp/init.lua: `have_mason = LazyVim.has("mason-lspconfig.nvim")`).
return {
  { "mason-org/mason.nvim", enabled = false },
  { "mason-org/mason-lspconfig.nvim", enabled = false },
  -- Referenced by the dap/python/typescript extras; disabled pre-emptively
  -- so enabling those extras never pulls Mason back in.
  { "jay-babu/mason-nvim-dap.nvim", enabled = false },
}
