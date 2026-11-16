local function eq(a, b, msg)
  if not vim.deep_equal(a, b) then
    error((msg or "") .. " expected " .. vim.inspect(b) .. " got " .. vim.inspect(a), 2)
  end
end

local function respond(req)
  if req.kind == "synonyms" then return { items = { "nice", "pleasant", "fine", "sunny" } } end
  if req.kind == "selection" then return { items = { "walked fast", "strolled swiftly" } } end
  if req.kind == "variations" then
    return { items = { "On the mat sat the cat.", "The cat was sitting on the mat." } }
  end
  return {
    plans = { { title = "One thread", text = "Cats like mats. They sit on them." } },
    off_topic = { "taxes" },
  }
end

local function fresh(lines, spell_extra)
  vim.cmd("silent! %bwipeout!")
  package.loaded["writing"] = nil
  local writing = require("writing")
  writing.setup({
    log_file = vim.fn.tempname(),
    delays = { word = 30, sentence = 30, spell = 30 },
    spell = vim.tbl_extend("force", { langs = { "en" } }, spell_extra or {}),
    providers = {
      fast = { type = "fake", respond = respond, delay = 5 },
      strong = { type = "fake", respond = respond, delay = 5 },
    },
  })
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].undolevels = 1000
  writing.attach(buf)
  return writing, buf
end

local function event(buf)
  vim.api.nvim_exec_autocmds("CursorMoved", { buffer = buf })
end

local function wait_ready(writing)
  local core = writing._core()
  local ok = vim.wait(1000, function() return core.view.status == "ready" end, 10)
  if not ok then error("never became ready, status=" .. core.view.status) end
  return core
end

return {
  {
    name = "accepting a synonym is one undo step and moves cursor after text",
    fn = function()
      local writing, buf = fresh({ "The weather is lovely today." })
      vim.api.nvim_win_set_cursor(0, { 1, 16 })
      event(buf)
      local core = wait_ready(writing)
      core:accept()
      eq(vim.api.nvim_buf_get_lines(buf, 0, -1, false), { "The weather is nice today." })
      eq(vim.api.nvim_win_get_cursor(0), { 1, 19 })
      vim.cmd("silent undo")
      eq(vim.api.nvim_buf_get_lines(buf, 0, -1, false), { "The weather is lovely today." })
    end,
  },
  {
    name = "box is a non-focusable float and never takes focus; ghost clears after accept",
    fn = function()
      local writing, buf = fresh({ "The weather is lovely today." })
      local original = vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_cursor(0, { 1, 16 })
      event(buf)
      local core = wait_ready(writing)
      local win = require("writing.box").window()
      eq(vim.api.nvim_win_get_config(win).focusable, false)
      eq(vim.api.nvim_get_current_win(), original)
      local ghost_ns = vim.api.nvim_create_namespace("writing_ghost")
      eq(#vim.api.nvim_buf_get_extmarks(buf, ghost_ns, 0, -1, {}), 1)
      core:accept()
      eq(#vim.api.nvim_buf_get_extmarks(buf, ghost_ns, 0, -1, {}), 0)
      eq(require("writing.box").window(), nil)
    end,
  },
  {
    name = "keys are mapped only while the box is visible",
    fn = function()
      local writing, buf = fresh({ "The weather is lovely today." })
      eq(vim.fn.maparg("<S-Tab>", "n", false, true).buffer, nil)
      vim.api.nvim_win_set_cursor(0, { 1, 16 })
      event(buf)
      local core = wait_ready(writing)
      eq(vim.fn.maparg("<S-Tab>", "n", false, true).buffer, 1)
      core:ignore()
      eq(vim.fn.maparg("<S-Tab>", "n", false, true).buffer, nil)
    end,
  },
  {
    name = "sentence variation replaces just that sentence",
    fn = function()
      local writing, buf = fresh({ "Intro line. The cat sat on the mat." })
      local line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
      vim.api.nvim_win_set_cursor(0, { 1, #line - 1 })
      event(buf)
      local core = wait_ready(writing)
      eq(core.view.kind, "variations")
      core:accept()
      eq(vim.api.nvim_buf_get_lines(buf, 0, -1, false), { "Intro line. On the mat sat the cat." })
    end,
  },
  {
    name = "make sense previews diff then applies on second accept",
    fn = function()
      local writing, buf = fresh({ "intro", "", "cats mats taxes sit", "", "outro" })
      vim.api.nvim_win_set_cursor(0, { 3, 0 })
      writing.make_sense()
      local core = wait_ready(writing)
      core:accept()
      eq(vim.api.nvim_buf_get_lines(buf, 0, -1, false)[3], "cats mats taxes sit")
      local ghost_ns = vim.api.nvim_create_namespace("writing_ghost")
      eq(#vim.api.nvim_buf_get_extmarks(buf, ghost_ns, 0, -1, {}), 1)
      core:accept()
      eq(vim.api.nvim_buf_get_lines(buf, 0, -1, false), { "intro", "", "Cats like mats. They sit on them.", "", "outro" })
    end,
  },
  {
    name = "typing clears the box",
    fn = function()
      local writing, buf = fresh({ "The weather is lovely today." })
      vim.api.nvim_win_set_cursor(0, { 1, 16 })
      event(buf)
      local core = wait_ready(writing)
      vim.api.nvim_buf_set_text(buf, 0, 0, 0, 0, { "x" })
      vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf })
      eq(core.view.status, "idle")
      eq(require("writing.box").window(), nil)
    end,
  },
  {
    name = "misspelled words are underlined, give synonyms at rest, and spelling fixes on demand",
    fn = function()
      local writing, buf = fresh({ "I like teh weather." })
      eq(vim.wo.spell, true)
      vim.api.nvim_win_set_cursor(0, { 1, 8 })
      event(buf)
      local core = wait_ready(writing)
      eq(core.view.kind, "synonyms")
      writing.suggest_now()
      core = wait_ready(writing)
      eq(core.view.kind, "spelling")
      eq(core.view.items[1].text, "the")
      core:accept()
      eq(vim.api.nvim_buf_get_lines(buf, 0, -1, false), { "I like the weather." })
    end,
  },
  {
    name = "ambient spelling fires on a misspelled word when enabled",
    fn = function()
      local writing, buf = fresh({ "I like teh weather." }, { ambient = true })
      vim.api.nvim_win_set_cursor(0, { 1, 8 })
      event(buf)
      local core = wait_ready(writing)
      eq(core.view.kind, "spelling")
      core:accept()
      eq(vim.api.nvim_buf_get_lines(buf, 0, -1, false), { "I like the weather." })
    end,
  },
  {
    name = "accepting a selection suggestion replaces only the selected fragment",
    fn = function()
      local writing, buf = fresh({ "She walked quickly to the station." })
      local ctx = require("writing.context").selection({ "She walked quickly to the station." }, 1, 4, 18, 2)
      ctx.row = 1
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      event(buf)
      local core = writing._core()
      core:trigger(ctx)
      core = wait_ready(writing)
      eq(core.view.kind, "selection")
      core:accept()
      eq(vim.api.nvim_buf_get_lines(buf, 0, -1, false), { "She walked fast to the station." })
    end,
  },
  {
    name = "burst mode silences suggestions and the underline, editor mode restores both",
    fn = function()
      local writing, buf = fresh({ "I like teh weather and lovely things." })
      eq(vim.wo.spell, true)
      writing.burst_mode()
      eq(vim.wo.spell, false)
      eq(writing.mode(), "burst")
      eq(writing.statusline(), "BURST")
      vim.api.nvim_win_set_cursor(0, { 1, 20 })
      event(buf)
      vim.wait(200, function() return false end, 10)
      eq(writing._core().view.status, "idle")
      writing.suggest_now()
      eq(writing._core().view.status, "idle")
      writing.editor_mode()
      eq(writing.mode(), "editor")
      eq(vim.wo.spell, true)
      event(buf)
      wait_ready(writing)
    end,
  },
  {
    name = "starting in burst mode keeps everything quiet until editor mode",
    fn = function()
      vim.cmd("silent! %bwipeout!")
      package.loaded["writing"] = nil
      local writing = require("writing")
      writing.setup({
        mode = "burst", log_file = vim.fn.tempname(), delays = { word = 30, sentence = 30, spell = 30 },
        spell = { langs = { "en" } },
        providers = { fast = { type = "fake", respond = respond }, strong = { type = "fake", respond = respond } },
      })
      local buf = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_set_current_buf(buf)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "I like teh weather and lovely things." })
      writing.attach(buf)
      eq(vim.wo.spell, false)
      vim.api.nvim_win_set_cursor(0, { 1, 20 })
      event(buf)
      vim.wait(200, function() return false end, 10)
      eq(writing._core().view.status, "idle")
      writing.editor_mode()
      eq(vim.wo.spell, true)
    end,
  },
  {
    name = "a mode badge is always visible in attached buffers and follows the mode",
    fn = function()
      local writing, buf = fresh({ "Some text here." })
      local box = require("writing.box")
      eq(box.badge_text(), "EDITOR")
      writing.burst_mode()
      eq(box.badge_text(), "BURST")
      writing.editor_mode()
      eq(box.badge_text(), "EDITOR")
      vim.api.nvim_set_current_buf(vim.api.nvim_create_buf(true, false))
      vim.api.nvim_exec_autocmds("BufEnter", {})
      eq(box.badge_text(), nil)
      vim.api.nvim_set_current_buf(buf)
      vim.api.nvim_exec_autocmds("BufEnter", {})
      eq(box.badge_text(), "EDITOR")
    end,
  },
  {
    name = "suggestion box stacks above the badge without overlapping it",
    fn = function()
      local writing, buf = fresh({ "The weather is lovely today." })
      vim.api.nvim_win_set_cursor(0, { 1, 16 })
      event(buf)
      wait_ready(writing)
      local box = require("writing.box")
      local sugg = vim.api.nvim_win_get_config(box.window())
      local badge_row = vim.o.lines - vim.o.cmdheight - (vim.o.laststatus > 0 and 1 or 0)
      eq(sugg.row, badge_row - 1)
    end,
  },
  {
    name = "the word or sentence being changed is highlighted, selections are not, and it clears on accept",
    fn = function()
      local writing, buf = fresh({ "Intro line. The cat sat on the mat." })
      local target_ns = vim.api.nvim_create_namespace("writing_target")
      local function marks() return vim.api.nvim_buf_get_extmarks(buf, target_ns, 0, -1, { details = true }) end

      vim.api.nvim_win_set_cursor(0, { 1, 17 })
      event(buf)
      local core = wait_ready(writing)
      eq(core.view.kind, "synonyms")
      eq(#marks(), 1)
      eq({ marks()[1][3], marks()[1][4].end_col }, { 16, 19 })
      core:accept()
      eq(#marks(), 0)

      local line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
      vim.api.nvim_win_set_cursor(0, { 1, #line - 1 })
      event(buf)
      core = wait_ready(writing)
      eq(core.view.kind, "variations")
      eq({ marks()[1][3], marks()[1][4].end_col }, { 12, #line })
      core:ignore()
      eq(#marks(), 0)

      local ctx = require("writing.context").selection({ line }, 1, 12, 23, 2)
      ctx.row = 1
      core:trigger(ctx)
      wait_ready(writing)
      eq(#marks(), 0)
    end,
  },
  {
    name = "resting on a misspelled word still gives synonyms; the action key gives spelling, then the sentence",
    fn = function()
      local writing, buf = fresh({ "I like teh weather." })
      local calls = {}
      local original = writing._core().providers.fast.request
      writing._core().providers.fast.request = function(req, cb)
        calls[#calls + 1] = req
        return original(req, cb)
      end
      vim.api.nvim_win_set_cursor(0, { 1, 8 })
      event(buf)
      local core = wait_ready(writing)
      eq(core.view.kind, "synonyms")
      eq(core.view.ctx.misspelled, true)
      eq(calls[1].system:find("misspelled", 1, true) ~= nil, true)
      writing.suggest_now()
      core = wait_ready(writing)
      eq(core.view.kind, "spelling")
      eq(core.view.items[1].text, "the")
      writing.suggest_now()
      vim.wait(1000, function() return core.view.kind == "variations" and core.view.status ~= "loading" end, 10)
      eq(core.view.kind, "variations")
      core:ignore()
      writing.synonyms_now()
      core = wait_ready(writing)
      eq(core.view.kind, "synonyms")
    end,
  },
}
