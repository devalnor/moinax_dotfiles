return {
  {
    "karb94/neoscroll.nvim",
    event = "VeryLazy",
    opts = {
      duration_multiplier = 0.25,
    },
  },
  -- Unpin aerial.nvim from AstroNvim's ^2.2 constraint
  -- v3.0+ is needed for Neovim 0.12 treesitter API compatibility
  { "stevearc/aerial.nvim", version = false },
}
