-- if true then return end -- WARN: REMOVE THIS LINE TO ACTIVATE THIS FILE

-- This will run last in the setup process.
-- This is just pure lua so anything that doesn't
-- fit in the normal config locations above can go here
vim.api.nvim_set_hl(0, "Normal", { bg = "none" })
vim.api.nvim_set_hl(0, "NormalFloat", { bg = "none" })

-- Treat all .env.* files (e.g. .env.environment.local) as sh for comment support
vim.filetype.add({
  pattern = {
    ["%.env%.[%w_.%-]+"] = "sh",
  },
})
