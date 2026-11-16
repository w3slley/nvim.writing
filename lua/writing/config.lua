local M = {}

M.defaults = {
  filetypes = { "markdown", "text" },
  delays = { word = 700, sentence = 600 },
  max_requests_per_minute = 30,
  style_file = ".writing-style.md",
  disable_file = ".writing-off",
  log_file = vim.fn.stdpath("state") .. "/writing.log",
  counts = { synonyms = 4, variations = 3, make_sense = 2 },
  providers = {
    fast = { type = "claude_cli", model = "claude-haiku-5-5", timeout = 20000 },
    strong = { type = "claude_cli", model = "claude-haiku-5-5", timeout = 40000 },
  },
  keys = {
    action = "<leader>ws",
    make_sense = "<leader>wp",
    toggle = "<leader>wt",
    manual = "<leader>wm",
    next = "j",
    prev = "k",
    accept = "<CR>",
    ignore = "<Esc>",
    regenerate = "r",
    tighter = "t",
    clearer = "c",
    formal = "f",
  },
}

function M.resolve(user)
  return vim.tbl_deep_extend("force", {}, M.defaults, user or {})
end

return M
