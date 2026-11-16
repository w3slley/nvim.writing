vim.opt.runtimepath:prepend(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h"))
vim.g.mapleader = " "
vim.cmd("filetype plugin on")
require("writing").setup()
