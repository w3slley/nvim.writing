local dict = require("writing.dict")
local describe = require("writing.describe")
local lang = require("writing.lang")
local log = require("writing.log")

local M = {}

local ns = vim.api.nvim_create_namespace("writing_finder")

vim.api.nvim_set_hl(0, "WritingDescribeModel", { fg = "#c678dd", bold = true, default = true })
vim.api.nvim_set_hl(0, "WritingDescribeDict", { fg = "#61afef", default = true })

local ICON = { model = "✨", dictionary = "📖" }
local WORD_HL = { model = "WritingDescribeModel", dictionary = "WritingDescribeDict" }

M.STATUS = {
  asking = "📖 dictionary · ✨ asking model…",
  done = "✨ model  📖 dictionary",
  failed = "📖 dictionary only · model failed",
  dictionary = "📖 dictionary",
}
local LANG_NAME = { en = "English", pt = "Portuguese" }
local state

local function valid_win(win) return win and vim.api.nvim_win_is_valid(win) end

local function truncate(text, width)
  if vim.fn.strdisplaywidth(text) <= width then return text end
  return vim.fn.strcharpart(text, 0, math.max(0, width - 1)) .. "…"
end

local function query_text()
  return vim.trim(vim.api.nvim_buf_get_lines(state.input_buf, 0, 1, false)[1] or "")
end

-- Sits right under the line being written so the sentence stays visible, and flips above it only when the
-- full list does not fit below but fits better above. The side is chosen with the full list height, so the
-- modal does not jump when results arrive; when neither side has room, the list is shortened and scrolls.
local function layout()
  local a = state.anchor
  local width = math.min(76, vim.o.columns - 4)
  local results = state.opts.results or 8
  local bottom = vim.o.lines - vim.o.cmdheight
  local below, above = bottom - a.row, a.row - 1
  local flip = 5 + results > below and above > below
  local max_list = math.max(1, math.min(results, (flip and above or below) - 5))
  local height = math.max(1, math.min(#state.lines, max_list))
  local row = flip and math.max(0, a.row - 1 - (5 + max_list)) or a.row
  local col = math.max(0, math.min(a.col, vim.o.columns - width - 2))
  return width, height, row, col
end

local function render()
  local s = state
  local width = layout()
  local lines, marks = {}, {}
  if #s.items == 0 then
    lines[1] = " " .. (s.empty or "Describe the word you have in mind, then press Enter")
    marks[1] = { { 0, #lines[1], "WritingBoxDim" } }
  end
  for i, it in ipairs(s.items) do
    local prefix = (i == s.index and " › " or "   ") .. (ICON[it.source] or "  ") .. " "
    local head = prefix .. it.word
    local pos = "  " .. it.pos .. "  "
    local line = head .. pos .. truncate(it.definition, width - vim.fn.strdisplaywidth(head .. pos) - 1)
    lines[i] = line
    marks[i] = { { #prefix, #head, WORD_HL[it.source] or "WritingDescribeDict" }, { #head, #line, "WritingBoxDim" } }
  end
  s.lines = lines
  vim.bo[s.list_buf].modifiable = true
  vim.api.nvim_buf_set_lines(s.list_buf, 0, -1, false, lines)
  vim.bo[s.list_buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(s.list_buf, ns, 0, -1)
  for i, ms in ipairs(marks) do
    for _, m in ipairs(ms) do
      vim.api.nvim_buf_set_extmark(s.list_buf, ns, i - 1, m[1], { end_col = m[2], hl_group = m[3] })
    end
    if i == s.index and s.items[i] then
      vim.api.nvim_buf_set_extmark(s.list_buf, ns, i - 1, 0, { line_hl_group = "WritingBoxSel" })
    end
  end
  local w, h, row, col = layout()
  vim.api.nvim_win_set_config(s.input_win, { relative = "editor", row = row, col = col, width = w, height = 1 })
  vim.api.nvim_win_set_config(s.list_win, {
    relative = "editor", row = row + 3, col = col, width = w, height = h,
    footer = s.status and (" " .. s.status .. " ") or "", footer_pos = "right",
  })
  if s.items[s.index] then vim.api.nvim_win_set_cursor(s.list_win, { s.index, 0 }) end
end

function M.close()
  if not state then return end
  local s = state
  state = nil
  if s.cancel then s.cancel() end
  for _, win in ipairs({ s.input_win, s.list_win }) do
    if valid_win(win) then vim.api.nvim_win_close(win, true) end
  end
  for _, buf in ipairs({ s.input_buf, s.list_buf }) do
    if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
  end
  if valid_win(s.origin.win) then vim.api.nvim_set_current_win(s.origin.win) end
end

-- Inserts after the character under the cursor in normal mode (like `a`), at the cursor in insert mode,
-- and adds a space on either side only where the word would otherwise touch another word.
function M.insert(origin, word)
  local buf, row = origin.buf, origin.row
  local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ""
  local col = math.min(origin.col, #line)
  if not origin.insert and #line > 0 then
    col = col + #vim.fn.strcharpart(line:sub(col + 1), 0, 1)
  end
  local before, after = line:sub(1, col), line:sub(col + 1)
  local lead = (before:match("[%w\128-\255%.,;:!%?]$") and " ") or ""
  local trail = (after:match("^[%w\128-\255]") and " ") or ""
  vim.api.nvim_buf_set_text(buf, row - 1, col, row - 1, col, { lead .. word .. trail })
  local stop = col + #lead + #word
  if valid_win(origin.win) then
    vim.api.nvim_win_set_cursor(origin.win, { row, origin.insert and stop or math.max(0, stop - 1) })
  end
  return stop
end

local function keep_selection(items, word)
  for i, it in ipairs(items) do
    if it.word == word then return i end
  end
  return 1
end

local function title(language)
  return " Describe a word" .. (language and (" · " .. language:upper()) or "") .. " "
end

function M.search()
  local s = state
  if not s then return end
  local query = query_text()
  if query == "" then return end
  if s.cancel then s.cancel() end
  s.cancel = nil
  s.req_id = s.req_id + 1
  local id = s.req_id
  s.query = query
  s.moved = false
  local language = lang.detect(query, s.context_lang)
  s.lang = language
  vim.api.nvim_win_set_config(s.input_win, { title = title(language), title_pos = "left" })

  if s.opts.loading(language) then
    s.status = "loading dictionary…"
    render()
    vim.cmd.redraw()
  end
  local idx = s.opts.index(language)
  if not idx then
    s.items, s.status = {}, nil
    s.empty = ("No %s dictionary installed. Run :WritingDictInstall %s"):format(LANG_NAME[language] or language, language)
    return render()
  end
  local limit = s.opts.results or 8
  local candidates = describe.candidates(idx, query, 30)
  s.items, s.index = describe.merge(idx, query, candidates, nil, limit), 1
  s.empty = "No match in the dictionary"
  local provider = s.opts.provider
  s.status = provider and M.STATUS.asking or M.STATUS.dictionary
  render()
  if not provider then return end

  local started = vim.uv.hrtime()
  local req = describe.request(query, { guesses = s.opts.guesses, lang = language })
  local function send(p, retried)
    s.cancel = p.request(req, function(err, reply)
      if not state or state.req_id ~= id then return end
      state.cancel = nil
      if err and not retried and s.opts.fallback and s.opts.fallback ~= p then return send(s.opts.fallback, true) end
      log.write({ event = "describe", error = err and tostring(err), total_ms = math.floor((vim.uv.hrtime() - started) / 1e6) })
      if err then
        state.status = M.STATUS.failed
      else
        local selected = state.items[state.index]
        state.items = describe.merge(idx, query, candidates, reply, limit)
        state.index = (state.moved and selected) and keep_selection(state.items, selected.word) or 1
        state.status = M.STATUS.done
      end
      render()
    end)
  end
  send(provider, false)
end

function M.move(delta)
  local s = state
  if not s or #s.items == 0 then return end
  s.moved = true
  s.index = ((s.index - 1 + delta) % #s.items) + 1
  render()
end

function M.confirm()
  local s = state
  if not s then return end
  if query_text() ~= s.query or #s.items == 0 then return M.search() end
  local item = s.items[s.index]
  local origin = s.origin
  log.write({ event = "describe_accept", index = s.index, source = item.source })
  M.close()
  M.insert(origin, item.word)
  if origin.insert then
    if vim.api.nvim_get_mode().mode:sub(1, 1) ~= "i" then vim.cmd.startinsert() end
  elseif vim.api.nvim_get_mode().mode:sub(1, 1) == "i" then
    vim.cmd.stopinsert()
    local cursor = vim.api.nvim_win_get_cursor(origin.win)
    vim.schedule(function()
      if valid_win(origin.win) then pcall(vim.api.nvim_win_set_cursor, origin.win, cursor) end
    end)
  end
end

function M.is_open() return state ~= nil end

function M._state() return state end

function M.open(opts)
  if state then M.close() end
  local win = vim.api.nvim_get_current_win()
  local pos = vim.api.nvim_win_get_cursor(win)
  local mode = vim.api.nvim_get_mode().mode
  state = {
    opts = vim.tbl_extend("keep", opts or {}, {
      index = dict.load,
      loading = dict.loading,
    }),
    origin = { win = win, buf = vim.api.nvim_get_current_buf(), row = pos[1], col = pos[2], insert = mode:sub(1, 1) == "i" },
    items = {}, index = 1, req_id = 0, lines = { "" },
  }
  local first = math.max(1, pos[1] - 2)
  state.context_lang = lang.detect(table.concat(vim.api.nvim_buf_get_lines(0, first - 1, pos[1], false), " "))
  local info = vim.fn.getwininfo(win)[1]
  local text = vim.api.nvim_buf_get_lines(0, pos[1] - 1, pos[1], false)[1] or ""
  local screen = vim.fn.screenpos(win, pos[1], math.max(1, #text))
  state.anchor = {
    row = screen.row > 0 and screen.row or vim.fn.screenrow(),
    col = info.wincol - 1 + info.textoff,
  }
  local s = state
  s.input_buf = vim.api.nvim_create_buf(false, true)
  s.list_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[s.input_buf].bufhidden = "wipe"
  vim.bo[s.list_buf].bufhidden = "wipe"
  local w, h, row, col = layout()
  s.list_win = vim.api.nvim_open_win(s.list_buf, false, {
    relative = "editor", row = row + 3, col = col, width = w, height = h,
    style = "minimal", border = "rounded", focusable = false, zindex = 60,
  })
  s.input_win = vim.api.nvim_open_win(s.input_buf, true, {
    relative = "editor", row = row, col = col, width = w, height = 1,
    style = "minimal", border = "rounded", title = title(), title_pos = "left", zindex = 61,
  })
  for _, wn in ipairs({ s.input_win, s.list_win }) do
    vim.wo[wn].winhighlight = "NormalFloat:WritingBox,FloatBorder:WritingBoxBorder"
  end
  vim.wo[s.list_win].wrap = false

  local function map(modes, lhs, fn)
    vim.keymap.set(modes, lhs, fn, { buffer = s.input_buf, nowait = true, silent = true })
  end
  map({ "i", "n" }, "<CR>", M.confirm)
  map({ "i", "n" }, "<C-n>", function() M.move(1) end)
  map({ "i", "n" }, "<C-p>", function() M.move(-1) end)
  map({ "i", "n" }, "<Down>", function() M.move(1) end)
  map({ "i", "n" }, "<Up>", function() M.move(-1) end)
  map({ "i", "n" }, "<Tab>", function() M.move(1) end)
  map({ "i", "n" }, "<S-Tab>", function() M.move(-1) end)
  map({ "i", "n" }, "<Esc>", M.close)
  map("n", "q", M.close)
  vim.api.nvim_create_autocmd({ "WinLeave", "BufLeave" }, {
    buffer = s.input_buf, once = true,
    callback = function()
      vim.schedule(function()
        if state == s then M.close() end
      end)
    end,
  })

  render()
  vim.cmd.startinsert()
  if s.opts.preload ~= false then dict.preload(s.context_lang) end
end

return M
