local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root)
io.write(require("writing.dict").convert_to(arg[1], arg[2], arg[3], arg[4]))
