local M = {}

M.defaults = {
  mode = "editor",
  filetypes = { "markdown", "text" },
  delays = { word = 700, sentence = 600, spell = 250, selection = 500 },
  spell = { enabled = true, langs = { "en", "pt" }, suggestions = 4, highlight = true, ambient = false },
  max_requests_per_minute = 30,
  style_file = ".writing-style.md",
  disable_file = ".writing-off",
  log_file = vim.fn.stdpath("state") .. "/writing.log",
  counts = { synonyms = 4, variations = 3, make_sense = 2, selection = 3 },
  providers = {
    fast = { type = "claude_cli", model = "claude-haiku-5-5", timeout = 20000 },
    strong = { type = "claude_cli", model = "claude-haiku-5-5", timeout = 40000 },
  },
  keys = {
    action = "<leader>ws",
    synonyms = "<leader>wy",
    make_sense = "<leader>wp",
    toggle = "<leader>wt",
    switch = "<A-m>",
    burst = "<leader>wb",
    editor = "<leader>we",
    manual = "<leader>wm",
    next = "<S-Tab>",
    prev = "<A-k>",
    accept = "<Tab>",
    ignore = "<Esc>",
    regenerate = "<C-r>",
    tighter = "<A-t>",
    clearer = "<A-c>",
    formal = "<A-f>",
  },
  box = { position = "bottom_right", badge = true },
}

function M.resolve(user)
  return vim.tbl_deep_extend("force", {}, M.defaults, user or {})
end

return M
