local M = {}

M.defaults = {
  enabled = true,
  mode = "editor",
  filetypes = { "markdown", "text" },
  delays = { word = 400, sentence = 350, spell = 250, selection = 350 },
  prefetch = 100,
  spell = { enabled = true, langs = { "en", "pt" }, suggestions = 4, highlight = true, while_typing = false },
  max_requests_per_minute = 30,
  style_file = ".writing-style.md",
  disable_file = ".writing-off",
  log_file = vim.fn.stdpath("state") .. "/writing.log",
  describe = { results = 8, guesses = 8 },
  counts = { synonyms = 4, variations = 3, make_sense = 2, selection = 3, spelling = 4 },
  providers = {
    fast = { type = "claude_cli", model = "claude-haiku-5-5", timeout = 20000 },
    strong = { type = "claude_cli", model = "claude-haiku-5-5", timeout = 40000 },
  },
  keys = {
    action = "<leader>ls",
    synonyms = "<leader>ly",
    make_sense = "<leader>lp",
    toggle = "<leader>lt",
    switch = "<A-m>",
    layout = "<leader>lv",
    preview = "<leader>ld",
    burst = "<leader>lb",
    editor = "<leader>le",
    manual = "<leader>lm",
    describe = "<leader>lw",
    describe_insert = "<A-w>",
    define = "<leader>lk",
    next = "<S-Tab>",
    prev = "<A-k>",
    accept = "<Tab>",
    ignore = "<Esc>",
    regenerate = "<C-r>",
  },
  box = { layout = "popup", preview = "strike", position = "bottom_right", badge = true },
}

function M.resolve(user)
  return vim.tbl_deep_extend("force", {}, M.defaults, user or {})
end

return M
