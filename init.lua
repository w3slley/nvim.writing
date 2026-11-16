vim.opt.runtimepath:prepend(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h"))
vim.g.mapleader = " "
vim.cmd("filetype plugin on")
vim.opt.swapfile = false

local local_model = {
  type = "openai",
  url = "http://localhost:11434/v1/chat/completions",
  model = "gemma3:4b",
  timeout = 30000,
}

require("writing").setup({
  providers = { fast = local_model, strong = local_model },
})
