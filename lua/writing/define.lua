local dict = require("writing.dict")
local lang = require("writing.lang")

local M = {}

local LANGS = { "en", "pt" }
local ALSO = { en = "also", pt = "também" }

-- The word's own line decides the first dictionary to try; the other one is the fallback, so an English
-- word quoted in Portuguese text still gets its meaning.
function M.lookup(word, context, opts)
  opts = opts or {}
  local index = opts.index or dict.load
  local first = lang.detect(context or "", lang.detect(word))
  local order = { first }
  for _, l in ipairs(LANGS) do
    if l ~= first then order[#order + 1] = l end
  end
  local any = false
  for _, l in ipairs(order) do
    local idx = index(l)
    if idx then
      any = true
      local entries = dict.define(idx, word)
      if entries then return entries, l end
    end
  end
  return nil, any and "missing" or "no_dictionary"
end

function M.lines(entries, language)
  local out = {}
  for n, e in ipairs(entries) do
    if n > 1 then out[#out + 1] = "" end
    out[#out + 1] = e.form and ("**%s** → **%s**"):format(e.form, e.word) or ("**%s**"):format(e.word)
    local groups, order = {}, {}
    for _, s in ipairs(e.senses) do
      if not groups[s.pos] then
        groups[s.pos] = {}
        order[#order + 1] = s.pos
      end
      table.insert(groups[s.pos], s)
    end
    for _, pos in ipairs(order) do
      out[#out + 1] = "_" .. pos .. "_"
      for i, s in ipairs(groups[pos]) do
        local line = ("%d. %s"):format(i, s.definition)
        if #s.synonyms > 0 then
          line = line .. (" _(%s: %s)_"):format(ALSO[language] or ALSO.en, table.concat(s.synonyms, ", "))
        end
        out[#out + 1] = line
      end
    end
  end
  return out
end

local state

local function valid_win(win) return win and vim.api.nvim_win_is_valid(win) end

local function layout(height)
  local width = math.min(80, vim.o.columns - 4)
  local below = vim.o.lines - vim.o.cmdheight - state.anchor.row
  local flip = 5 + height > below and state.anchor.row - 1 > below
  local room = (flip and state.anchor.row - 1 or below) - 5
  height = math.max(1, math.min(height, room, state.opts.max_height or 18))
  local row = flip and math.max(0, state.anchor.row - 1 - (5 + height)) or state.anchor.row
  local col = math.max(0, math.min(state.anchor.col, vim.o.columns - width - 2))
  return width, height, row, col
end

local function render(lines, language)
  local s = state
  vim.bo[s.result_buf].modifiable = true
  vim.api.nvim_buf_set_lines(s.result_buf, 0, -1, false, lines)
  vim.bo[s.result_buf].modifiable = false
  local width = layout(#lines)
  vim.api.nvim_win_set_width(s.result_win, width)
  local text_height = vim.api.nvim_win_text_height(s.result_win, {}).all
  local w, h, row, col = layout(text_height)
  vim.api.nvim_win_set_config(s.input_win, { relative = "editor", row = row, col = col, width = w, height = 1 })
  vim.api.nvim_win_set_config(s.result_win, {
    relative = "editor", row = row + 3, col = col, width = w, height = h,
    footer = language and (" " .. language:upper() .. " ") or "", footer_pos = "right",
  })
  vim.api.nvim_win_set_cursor(s.result_win, { 1, 0 })
end

local function query_text()
  return vim.trim(vim.api.nvim_buf_get_lines(state.input_buf, 0, 1, false)[1] or "")
end

function M.search()
  local s = state
  if not s then return end
  if s.timer then s.timer:stop() end
  local word = query_text()
  if word == s.word then return end
  s.word = word
  if word == "" then return render({ "Type a word to see its meaning" }) end
  for _, l in ipairs(LANGS) do
    if dict.loading(l) and not dict.cache[l] then
      render({ "loading dictionary…" })
      vim.cmd.redraw()
      break
    end
  end
  local entries, language = M.lookup(word, s.context, s.opts)
  if entries then return render(M.lines(entries, language), language) end
  if language == "no_dictionary" then return render({ "No dictionary installed. Run :WritingDictInstall" }) end
  render({ ("%q is not in the dictionary"):format(word) })
end

function M.scroll(keys)
  local s = state
  if not s or not valid_win(s.result_win) then return end
  vim.api.nvim_win_call(s.result_win, function()
    vim.cmd.normal({ vim.api.nvim_replace_termcodes(keys, true, false, true), bang = true })
  end)
end

function M.close()
  if not state then return end
  local s = state
  state = nil
  if s.timer then
    s.timer:stop()
    s.timer:close()
  end
  for _, win in ipairs({ s.input_win, s.result_win }) do
    if valid_win(win) then vim.api.nvim_win_close(win, true) end
  end
  for _, buf in ipairs({ s.input_buf, s.result_buf }) do
    if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
  end
  if valid_win(s.origin_win) then vim.api.nvim_set_current_win(s.origin_win) end
  if s.insert then vim.cmd.startinsert() else vim.cmd.stopinsert() end
end

function M.is_open() return state ~= nil end

function M._state() return state end

-- The meaning updates as the word is typed, after a short pause; Enter looks it up at once.
function M.open(word, opts)
  if state then M.close() end
  local win = vim.api.nvim_get_current_win()
  local row = vim.api.nvim_win_get_cursor(win)[1]
  local first = math.max(1, row - 2)
  local info = vim.fn.getwininfo(win)[1]
  local text = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1] or ""
  local screen = vim.fn.screenpos(win, row, math.max(1, #text))
  state = {
    opts = opts or {},
    origin_win = win,
    insert = vim.api.nvim_get_mode().mode:sub(1, 1) == "i",
    context = table.concat(vim.api.nvim_buf_get_lines(0, first - 1, row, false), " "),
    anchor = { row = screen.row > 0 and screen.row or vim.fn.screenrow(), col = info.wincol - 1 + info.textoff },
    timer = vim.uv.new_timer(),
  }
  local s = state
  s.input_buf = vim.api.nvim_create_buf(false, true)
  s.result_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[s.result_buf].filetype = "markdown"
  local w, h, r, c = layout(1)
  s.result_win = vim.api.nvim_open_win(s.result_buf, false, {
    relative = "editor", row = r + 3, col = c, width = w, height = h,
    style = "minimal", border = "rounded", focusable = false, zindex = 60,
  })
  s.input_win = vim.api.nvim_open_win(s.input_buf, true, {
    relative = "editor", row = r, col = c, width = w, height = 1,
    style = "minimal", border = "rounded", title = " Meaning of a word ", title_pos = "left", zindex = 61,
  })
  for _, wn in ipairs({ s.input_win, s.result_win }) do
    vim.wo[wn].winhighlight = "NormalFloat:WritingBox,FloatBorder:WritingBoxBorder"
  end
  vim.wo[s.result_win].wrap = true
  vim.wo[s.result_win].linebreak = true
  vim.wo[s.result_win].conceallevel = 2

  local function map(modes, lhs, fn)
    vim.keymap.set(modes, lhs, fn, { buffer = s.input_buf, nowait = true, silent = true })
  end
  map({ "i", "n" }, "<CR>", M.search)
  map({ "i", "n" }, "<Esc>", M.close)
  map("n", "q", M.close)
  map({ "i", "n" }, "<C-f>", function() M.scroll("<C-d>") end)
  map({ "i", "n" }, "<C-b>", function() M.scroll("<C-u>") end)
  map({ "i", "n" }, "<C-n>", function() M.scroll("<C-e>") end)
  map({ "i", "n" }, "<C-p>", function() M.scroll("<C-y>") end)
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    buffer = s.input_buf,
    callback = function()
      s.timer:stop()
      s.timer:start(s.opts.delay or 200, 0, vim.schedule_wrap(function()
        if state == s then M.search() end
      end))
    end,
  })
  vim.api.nvim_create_autocmd({ "WinLeave", "BufLeave" }, {
    buffer = s.input_buf, once = true,
    callback = function()
      vim.schedule(function()
        if state == s then M.close() end
      end)
    end,
  })

  if word and word ~= "" then
    vim.api.nvim_buf_set_lines(s.input_buf, 0, -1, false, { word })
    M.search()
  else
    render({ "Type a word to see its meaning" })
  end
  vim.cmd.startinsert({ bang = true })
  if s.opts.preload ~= false then dict.preload(lang.detect(s.context)) end
end

return M
