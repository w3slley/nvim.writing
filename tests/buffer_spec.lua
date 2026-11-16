local function eq(a, b, msg)
  if not vim.deep_equal(a, b) then
    error((msg or "") .. " expected " .. vim.inspect(b) .. " got " .. vim.inspect(a), 2)
  end
end

local function respond(req)
  if req.kind == "synonyms" then return { items = { "nice", "pleasant", "fine", "sunny" } } end
  if req.kind == "variations" and req.user:find("dog", 1, true) then
    return { items = { "The cat sat on the mat while the dog slept near the fire and the birds sang outside." } }
  end
  if req.kind == "spelling" then return { items = { "tea", "ten", "tech" } } end
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
    name = "disabling detaches every buffer and restores its options; enabling attaches again",
    fn = function()
      vim.cmd("silent! %bwipeout!")
      package.loaded["writing"] = nil
      local writing = require("writing")
      writing.setup({
        log_file = vim.fn.tempname(), delays = { word = 30, sentence = 30, spell = 30 },
        spell = { langs = { "en" } },
        providers = { fast = { type = "fake", respond = respond, delay = 5 }, strong = { type = "fake", respond = respond, delay = 5 } },
      })
      local box = require("writing.box")
      local buf = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_set_current_buf(buf)
      vim.bo[buf].spelllang = "de"
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "The weather is lovely today." })
      writing.attach(buf)
      eq(vim.bo[buf].spelllang, "en")
      eq(vim.fn.maparg("<leader>lk", "n", false, true).buffer, 1)
      writing.disable(true)
      eq(writing.is_enabled(), false)
      eq(vim.b[buf].writing_attached, nil)
      eq(vim.bo[buf].spelllang, "de", "spelllang is restored")
      eq(vim.wo.spell, false)
      eq(vim.fn.maparg("<leader>lk", "n"), "", "buffer keymaps are removed")
      eq(box.badge_text(), nil)
      eq(#vim.api.nvim_get_autocmds({ group = "writing", buffer = buf }), 0)
      vim.api.nvim_win_set_cursor(0, { 1, 16 })
      event(buf)
      vim.wait(150, function() return false end, 10)
      eq(writing._core().view.status, "idle")
      writing.attach(buf)
      eq(vim.b[buf].writing_attached, nil, "nothing attaches while off")
      writing.enable(true)
      eq(vim.b[buf].writing_attached, true, "a buffer attached by hand comes back")
      eq(box.badge_text(), "EDITOR")
      event(buf)
      wait_ready(writing)
    end,
  },
  {
    name = "enabled = false starts off and leaves new buffers alone until enabled",
    fn = function()
      vim.cmd("silent! %bwipeout!")
      package.loaded["writing"] = nil
      local writing = require("writing")
      writing.setup({
        enabled = false, log_file = vim.fn.tempname(), spell = { langs = { "en" } },
        providers = { fast = { type = "fake", respond = respond }, strong = { type = "fake", respond = respond } },
      })
      local buf = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_set_current_buf(buf)
      vim.bo[buf].filetype = "markdown"
      eq(vim.b[buf].writing_attached, nil)
      writing.enable(true)
      eq(vim.b[buf].writing_attached, true)
      writing.disable(true)
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
      writing.set_layout("corner")
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
      writing.set_preview("below")
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
    name = "resting on a misspelled word shows Neovim spell suggestions with no LLM call, and the word is underlined",
    fn = function()
      local writing, buf = fresh({ "I like teh weather." })
      local calls = {}
      local original = writing._core().providers.fast.request
      writing._core().providers.fast.request = function(req, cb)
        calls[#calls + 1] = req
        return original(req, cb)
      end
      eq(vim.wo.spell, true)
      vim.api.nvim_win_set_cursor(0, { 1, 8 })
      event(buf)
      local core = wait_ready(writing)
      eq(core.view.kind, "spelling")
      eq(core.view.items[1].text, "the")
      eq(#calls, 0)
      core:accept()
      eq(vim.api.nvim_buf_get_lines(buf, 0, -1, false), { "I like the weather." })
    end,
  },
  {
    name = "Ctrl+r on spelling suggestions asks the LLM for more and skips the ones already shown",
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
      local first = vim.tbl_map(function(i) return i.text end, core.view.items)
      core:regenerate()
      vim.wait(1000, function() return #calls == 1 and core.view.status == "ready" end, 10)
      eq(#calls, 1)
      eq(calls[1].kind, "spelling")
      eq(calls[1].system:find("misspelled", 1, true) ~= nil, true)
      for _, shown in ipairs(first) do
        eq(calls[1].system:find("- " .. shown, 1, true) ~= nil, true, "avoid list has " .. shown)
      end
      for _, item in ipairs(core.view.items) do
        eq(vim.tbl_contains(first, item.text), false, item.text .. " repeats a local suggestion")
      end
    end,
  },
  {
    name = "on a misspelled word the action key goes spelling -> synonyms -> sentence, and the synonyms key jumps ahead",
    fn = function()
      local writing, buf = fresh({ "I like teh weather." })
      vim.api.nvim_win_set_cursor(0, { 1, 8 })
      writing.suggest_now()
      local core = wait_ready(writing)
      eq(core.view.kind, "spelling")
      writing.suggest_now()
      core = wait_ready(writing)
      eq(core.view.kind, "synonyms")
      eq(core.view.ctx.misspelled, true)
      writing.suggest_now()
      vim.wait(1000, function() return core.view.kind == "variations" and core.view.status ~= "loading" end, 10)
      eq(core.view.kind, "variations")
      core:ignore()
      writing.synonyms_now()
      core = wait_ready(writing)
      eq(core.view.kind, "synonyms")
    end,
  },
  {
    name = "popup layout sits under the text being changed, aligned with it, and flips above near the bottom",
    fn = function()
      local lines = { "first line here", "The weather is lovely today.", "third line" }
      local writing, buf = fresh(lines)
      local box = require("writing.box")
      eq(writing.layout(), "popup")
      vim.api.nvim_win_set_cursor(0, { 2, 16 })
      event(buf)
      wait_ready(writing)
      vim.cmd("redraw")
      local cfg = vim.api.nvim_win_get_config(box.window())
      local at = vim.fn.screenpos(0, 2, 16)
      eq(cfg.anchor, "NW")
      eq(cfg.row, at.row + 1)
      eq(cfg.col, at.col - 1)
      writing._core():ignore()

      local many = {}
      for i = 1, vim.o.lines - 3 do many[i] = "line " .. i end
      many[#many + 1] = "The weather is lovely today."
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, many)
      vim.api.nvim_win_set_cursor(0, { #many, 16 })
      event(buf)
      wait_ready(writing)
      vim.cmd("redraw")
      cfg = vim.api.nvim_win_get_config(box.window())
      eq(cfg.anchor, "SW")
    end,
  },
  {
    name = "list and strip layouts draw inside the buffer with no float, and switching layouts re-renders live",
    fn = function()
      local writing, buf = fresh({ "The weather is lovely today." })
      local box = require("writing.box")
      local ghost_ns = vim.api.nvim_create_namespace("writing_ghost")
      local function virt()
        local m = vim.api.nvim_buf_get_extmarks(buf, ghost_ns, 0, -1, { details = true })[1]
        return m and #m[4].virt_lines or 0
      end
      vim.api.nvim_win_set_cursor(0, { 1, 16 })
      event(buf)
      wait_ready(writing)
      eq(box.window() ~= nil, true)
      eq(virt(), 1)

      writing.set_layout("list")
      eq(box.window(), nil)
      eq(virt() > 4, true)

      writing.set_layout("strip")
      eq(box.window(), nil)
      eq(virt(), 2)

      writing.set_layout("popup")
      eq(box.window() ~= nil, true)
      eq(virt(), 1)

      writing.cycle_layout()
      eq(writing.layout(), "list")
      writing.cycle_layout()
      writing.cycle_layout()
      eq(writing.layout(), "corner")
      writing.cycle_layout()
      eq(writing.layout(), "popup")
    end,
  },
  {
    name = "change preview: old text struck through and new text green, below, above, or inline",
    fn = function()
      local writing, buf = fresh({ "The weather is lovely today." })
      local ghost_ns = vim.api.nvim_create_namespace("writing_ghost")
      local target_ns = vim.api.nvim_create_namespace("writing_target")
      local function marks(ns) return vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true }) end
      local function has(d, group, text)
        local found = false
        for _, line in ipairs(d.virt_lines or {}) do
          for _, chunk in ipairs(line) do
            if chunk[1] == text and tostring(chunk[2]):find(group, 1, true) then found = true end
          end
        end
        return found
      end
      vim.api.nvim_win_set_cursor(0, { 1, 16 })
      event(buf)
      wait_ready(writing)

      writing.set_preview("below")
      local d = marks(ghost_ns)[1][4]
      eq(not d.virt_lines_above, true)
      eq(has(d, "WritingOld", "lovely"), true)
      eq(has(d, "WritingNew", "nice"), true)
      eq(marks(target_ns)[1][4].hl_group, "WritingTarget")

      writing.set_preview("above")
      d = marks(ghost_ns)[1][4]
      eq(d.virt_lines_above, true)
      eq(has(d, "WritingOld", "lovely"), true)

      writing.set_preview("inline")
      d = marks(ghost_ns)[1][4]
      eq(d.virt_lines, nil)
      eq(d.virt_text_pos, "inline")
      eq(d.virt_text[1][1], " nice")
      eq(marks(target_ns)[1][4].hl_group, "WritingOld")

      writing.cycle_preview()
      eq(writing.preview(), "strike")
      writing.cycle_preview()
      eq(writing.preview(), "below")
    end,
  },
  {
    name = "strike preview crosses out the text in place and shows only the new green text below, selections included",
    fn = function()
      local writing, buf = fresh({ "The weather is lovely today." })
      local ghost_ns = vim.api.nvim_create_namespace("writing_ghost")
      local target_ns = vim.api.nvim_create_namespace("writing_target")
      local function marks(ns) return vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true }) end
      eq(writing.preview(), "strike")
      vim.api.nvim_win_set_cursor(0, { 1, 16 })
      event(buf)
      wait_ready(writing)
      eq(marks(target_ns)[1][4].hl_group, "WritingOld")
      local d = marks(ghost_ns)[1][4]
      eq(#d.virt_lines, 1)
      local groups, texts = {}, {}
      for _, chunk in ipairs(d.virt_lines[1]) do
        groups[#groups + 1] = tostring(chunk[2])
        texts[#texts + 1] = chunk[1]
      end
      eq(table.concat(groups, ","):find("WritingOld", 1, true), nil)
      eq(texts[#texts], "nice")
      eq(#texts[1], 15)

      writing._core():ignore()
      local ctx = require("writing.context").selection({ "The weather is lovely today." }, 1, 4, 18, 2)
      ctx.row = 1
      writing._core():trigger(ctx)
      wait_ready(writing)
      eq(writing._core().view.kind, "selection")
      eq(marks(target_ns)[1][4].hl_group, "WritingOld")
    end,
  },
  {
    name = "a long sentence preview wraps into struck-through old lines followed by green new lines",
    fn = function()
      local text = "The cat sat on the mat while the dog slept near the fire and the birds sang loudly outside."
      local writing, buf = fresh({ "Intro line. " .. text })
      writing.set_preview("below")
      local ghost_ns = vim.api.nvim_create_namespace("writing_ghost")
      local line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
      vim.api.nvim_win_set_cursor(0, { 1, #line - 1 })
      event(buf)
      local core = wait_ready(writing)
      eq(core.view.kind, "variations")
      local d = vim.api.nvim_buf_get_extmarks(buf, ghost_ns, 0, -1, { details = true })[1][4]
      eq(#d.virt_lines >= 2, true)
      eq(tostring(d.virt_lines[1][1][2]):find("WritingOld", 1, true) ~= nil, true)
      eq(tostring(d.virt_lines[#d.virt_lines][1][2]):find("WritingNew", 1, true) ~= nil, true)
    end,
  },
  {
    name = "adding a misspelled word to the dictionary stops it being flagged",
    fn = function()
      local spellfile = vim.fn.tempname() .. ".utf-8.add"
      local writing, buf = fresh({ "I like zzqword a lot." }, {})
      vim.bo[buf].spellfile = spellfile
      local spell = require("writing.spell")
      eq(spell.is_bad("zzqword"), true)
      vim.api.nvim_win_set_cursor(0, { 1, 9 })
      writing.spell_add()
      eq(spell.is_bad("zzqword"), false)
      eq(vim.fn.readfile(spellfile), { "zzqword" })
    end,
  },
  {
    name = "adding several words adds each one separately",
    fn = function()
      local spellfile = vim.fn.tempname() .. ".utf-8.add"
      local writing, buf = fresh({ "x" }, {})
      vim.bo[buf].spellfile = spellfile
      local spell = require("writing.spell")
      eq(spell.add("zzqone zzqtwo", 1), { "zzqone", "zzqtwo" })
      eq(spell.is_bad("zzqone"), false)
      eq(spell.is_bad("zzqtwo"), false)
    end,
  },
  {
    name = "removing a word from the dictionary flags it again and leaves built-in words alone",
    fn = function()
      local spellfile = vim.fn.tempname() .. ".utf-8.add"
      local writing, buf = fresh({ "I like zzqword a lot." }, {})
      vim.bo[buf].spellfile = spellfile
      local spell = require("writing.spell")
      spell.add("zzqword", 1)
      eq(spell.is_bad("zzqword"), false)
      vim.api.nvim_win_set_cursor(0, { 1, 9 })
      writing.spell_remove()
      eq(spell.is_bad("zzqword"), true)
      eq(spell.remove("house", 1), {})
      eq(spell.is_bad("house"), false)
    end,
  },
}
