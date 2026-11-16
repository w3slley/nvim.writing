local dict = require("writing.dict")
local finder = require("writing.finder")

local function eq(a, b, msg)
  if not vim.deep_equal(a, b) then
    error((msg or "") .. " expected " .. vim.inspect(b) .. " got " .. vim.inspect(a), 2)
  end
end

local INDEX = dict.build({
  "noun\tnostalgia\tlonging for something past\tlonging feeling",
  "noun\tpessimist\ta person who expects the worst\tperson",
  "adj\tephemeral|short-lived\tlasting a very short time\tadjective",
})

local function buffer(line)
  vim.cmd("silent! %bwipeout!")
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { line })
  return buf
end

local function line(buf) return vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] end

local function fake(items, delay)
  return require("writing.provider").create({
    type = "fake", delay = delay or 5,
    respond = function() return { items = items } end,
  })
end

local function type_query(text)
  local s = finder._state()
  vim.api.nvim_buf_set_lines(s.input_buf, 0, -1, false, { text })
end

local function words()
  local out = {}
  for _, it in ipairs(finder._state().items) do out[#out + 1] = it.word end
  return out
end

return {
  { name = "insert after the cursor char in normal mode adds spaces only where needed", fn = function()
    local buf = buffer("I felt a deep  for home.")
    finder.insert({ win = 0, buf = buf, row = 1, col = 13, insert = false }, "nostalgia")
    eq(line(buf), "I felt a deep nostalgia for home.")
    eq(vim.api.nvim_win_get_cursor(0), { 1, 22 })
  end },
  { name = "insert at the cursor in insert mode touching words gets spaces", fn = function()
    local buf = buffer("a deepfor home")
    finder.insert({ win = 0, buf = buf, row = 1, col = 6, insert = true }, "nostalgia")
    eq(line(buf), "a deep nostalgia for home")
    eq(vim.api.nvim_win_get_cursor(0), { 1, 16 })
  end },
  { name = "insert at the end of a sentence after a space", fn = function()
    local buf = buffer("She was a ")
    finder.insert({ win = 0, buf = buf, row = 1, col = 10, insert = true }, "pessimist")
    eq(line(buf), "She was a pessimist")
  end },
  { name = "dictionary matches show at once, model guesses arrive on top", fn = function()
    buffer("x")
    finder.open({ provider = fake({ "wistfulness", "pessimist" }, 20), index = function() return INDEX end })
    type_query("a longing for the past")
    finder.confirm()
    eq(words(), { "nostalgia" })
    assert(finder._state().status:find("asking"), finder._state().status)
    vim.wait(500, function() return finder._state().status == finder.STATUS.done end, 5)
    eq(words(), { "pessimist", "nostalgia" }, "invented or unknown guesses are dropped")
    eq(finder._state().index, 1, "selection stays on top when the user has not moved")
    eq(finder._state().items[1].definition, "a person who expects the worst")
    local rows = vim.api.nvim_buf_get_lines(finder._state().list_buf, 0, -1, false)
    assert(rows[1]:find("✨ pessimist", 1, true), rows[1])
    assert(rows[2]:find("📖 nostalgia", 1, true), rows[2])
    finder.close()
  end },
  { name = "enter on an unchanged query inserts the selected word and closes", fn = function()
    local buf = buffer("It was ")
    vim.api.nvim_win_set_cursor(0, { 1, 6 })
    finder.open({ provider = fake({ "ephemeral" }), index = function() return INDEX end })
    type_query("lasting a short time")
    finder.confirm()
    vim.wait(500, function() return finder._state().status == finder.STATUS.done end, 5)
    finder.move(1)
    finder.move(-1)
    finder.confirm()
    eq(finder.is_open(), false)
    eq(line(buf), "It was ephemeral")
  end },
  { name = "a failing model keeps the dictionary matches", fn = function()
    buffer("x")
    local broken = { request = function(_, cb) vim.schedule(function() cb("boom") end) return function() end end }
    finder.open({ provider = broken, index = function() return INDEX end })
    type_query("a longing for the past")
    finder.confirm()
    vim.wait(500, function() return finder._state().status ~= finder.STATUS.asking end, 5)
    eq(words(), { "nostalgia" })
    eq(finder._state().status, finder.STATUS.failed)
    finder.close()
  end },
  { name = "the description's language picks the dictionary and the prompt", fn = function()
    buffer("x")
    local asked, loaded = {}, {}
    local provider = { request = function(req, cb)
      asked[#asked + 1] = req.language
      vim.schedule(function() cb(nil, { items = {} }) end)
      return function() end
    end }
    finder.open({ provider = provider, preload = false, index = function(l) loaded[#loaded + 1] = l return INDEX end })
    type_query("medo de espaços fechados")
    finder.confirm()
    eq(finder._state().lang, "pt")
    eq(vim.api.nvim_win_get_config(finder._state().input_win).title[1][1], " Describe a word · PT ")
    type_query("fear of closed spaces")
    finder.confirm()
    eq(loaded, { "pt", "en" })
    eq(asked, { "pt", "en" })
    finder.close()
  end },
  { name = "a description with no language clue follows the text being written", fn = function()
    buffer("Ontem à noite senti uma enorme")
    vim.api.nvim_win_set_cursor(0, { 1, 30 })
    finder.open({ preload = false, index = function() return INDEX end })
    type_query("saudade")
    finder.confirm()
    eq(finder._state().lang, "pt")
    finder.close()
  end },
  { name = "a missing dictionary says how to install it", fn = function()
    buffer("x")
    finder.open({ index = function() return nil end })
    type_query("anything")
    finder.confirm()
    assert(finder._state().empty:find("No English dictionary installed. Run :WritingDictInstall en", 1, true),
      finder._state().empty)
    finder.close()
  end },
}
