local M = {}

local config_mod = require("writing.config")
local context = require("writing.context")
local Core = require("writing.core")
local box = require("writing.box")
local log = require("writing.log")
local provider = require("writing.provider")

local cfg
local core
local group
local active_buf
local mapped = {}
local style_cache = {}
local spell_ready = false
local applying = false
local enabled = true
local show_spell, hide_spell
local spell = require("writing.spell")

local function real_timer()
  return {
    start = function(ms, fn)
      local t = vim.uv.new_timer()
      local function close()
        if not t:is_closing() then
          t:stop()
          t:close()
        end
      end
      t:start(ms, 0, vim.schedule_wrap(function()
        close()
        fn()
      end))
      return close
    end,
  }
end

local function buffer_dir(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" then return vim.uv.cwd() end
  return vim.fs.dirname(name)
end

local function project_disabled(buf)
  return vim.fs.find(cfg.disable_file, { upward = true, path = buffer_dir(buf) })[1] ~= nil
end

local function read_style()
  local buf = active_buf or vim.api.nvim_get_current_buf()
  local path = vim.fs.find(cfg.style_file, { upward = true, path = buffer_dir(buf) })[1]
  if not path then return nil end
  local stat = vim.uv.fs_stat(path)
  local cached = style_cache[path]
  if cached and stat and cached.mtime == stat.mtime.sec then return cached.text end
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then return nil end
  local text = table.concat(lines, "\n")
  style_cache[path] = { mtime = stat and stat.mtime.sec, text = text }
  return text
end

local function snapshot(buf, min_words)
  local mode = vim.api.nvim_get_mode().mode
  local insert = mode:sub(1, 1) == "i"
  local pos = vim.api.nvim_win_get_cursor(0)
  local row, col = pos[1], pos[2]
  local snap = { tick = vim.api.nvim_buf_get_changedtick(buf), row = row, col = col, insert = insert }
  if insert or mode == "n" then
    local start = math.max(1, row - 1)
    local lines = vim.api.nvim_buf_get_lines(buf, start - 1, row, false)
    local ctx = context.analyze(lines, row - start + 1, col, insert, spell_ready and spell.is_bad or nil)
    if ctx then ctx.row = row end
    snap.context = ctx
  elseif mode == "v" or mode == "V" then
    local a, b = vim.fn.getpos("v"), vim.fn.getpos(".")
    snap.anchor = a[2] .. ":" .. a[3]
    if a[2] == b[2] then
      local start = math.max(1, row - 1)
      local lines = vim.api.nvim_buf_get_lines(buf, start - 1, row, false)
      local line = lines[#lines]
      local first, last = math.min(a[3], b[3]), math.max(a[3], b[3])
      if mode == "V" then
        first, last = 1, #line
      else
        while line:byte(last + 1) and line:byte(last + 1) >= 0x80 and line:byte(last + 1) < 0xC0 do last = last + 1 end
      end
      local ctx = context.selection(lines, row - start + 1, first - 1, last, min_words or 2)
      if ctx then ctx.row = row end
      snap.context = ctx
    end
  end
  return snap
end

local function do_apply(edit)
  local buf = active_buf
  local ctx = edit.ctx
  if vim.api.nvim_get_mode().mode:match("^[vV\22]") then
    vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)
  end
  local win = vim.api.nvim_get_current_win()
  local before = vim.api.nvim_win_get_cursor(win)
  vim.cmd("let &undolevels = &undolevels")
  local row, col
  if ctx.kind == "make_sense" then
    local new_lines = vim.split(edit.text, "\n", { plain = true })
    vim.api.nvim_buf_set_lines(buf, ctx.first - 1, ctx.last, false, new_lines)
    row = ctx.first + #new_lines - 1
    col = #new_lines[#new_lines]
  else
    local text = edit.text:gsub("%s*\n%s*", " ")
    vim.api.nvim_buf_set_text(buf, ctx.row - 1, ctx.scol, ctx.row - 1, ctx.ecol, { text })
    row = ctx.row
    col = ctx.scol + #text
    if before[1] == row and before[2] >= ctx.ecol then col = before[2] + #text - (ctx.ecol - ctx.scol) end
  end
  vim.api.nvim_win_set_cursor(win, { row, col })
  local pos = vim.api.nvim_win_get_cursor(win)
  return { tick = vim.api.nvim_buf_get_changedtick(buf), row = pos[1], col = pos[2] }
end

local function apply_edit(edit)
  applying = true
  local ok, result = pcall(do_apply, edit)
  applying = false
  if not ok then error(result) end
  return result
end

local function unmap_keys()
  for _, m in ipairs(mapped) do
    pcall(vim.keymap.del, { "n", "i", "x" }, m.lhs, { buffer = m.buf })
  end
  mapped = {}
end

local function map_keys(buf)
  if #mapped > 0 then return end
  local function map(lhs, fn)
    vim.keymap.set({ "n", "i", "x" }, lhs, fn, { buffer = buf, nowait = true, silent = true })
    mapped[#mapped + 1] = { lhs = lhs, buf = buf }
  end
  local k = cfg.keys
  map(k.next, function() core:move(1) end)
  map(k.prev, function() core:move(-1) end)
  map(k.accept, function() core:accept() end)
  map(k.ignore, function()
    core:ignore()
    if vim.api.nvim_get_mode().mode:match("^[vV\22]") then
      vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "n", false)
    end
  end)
  map(k.regenerate, function() core:regenerate() end)
  map(k.tighter, function() core:regenerate("tighter") end)
  map(k.clearer, function() core:regenerate("clearer") end)
  map(k.formal, function() core:regenerate("formal") end)
end

local function on_change(view)
  local buf = active_buf
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    box.close()
    unmap_keys()
    return
  end
  box.render(view, cfg.keys, buf, cfg.box.position)
  if core:visible() then
    map_keys(buf)
  else
    unmap_keys()
  end
end

local function sentence_context_at(buf)
  local pos = vim.api.nvim_win_get_cursor(0)
  local row, col = pos[1], pos[2]
  local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ""
  local best
  for _, s in ipairs(context.sentences(line)) do
    if s.s - 1 <= col then best = s end
  end
  if not best then return nil end
  local prev_lines = vim.api.nvim_buf_get_lines(buf, math.max(0, row - 2), row, false)
  local ctx = context.analyze(prev_lines, #prev_lines, best.e - 1, false)
  if ctx and ctx.kind == "synonyms" then
    ctx = { kind = "variations", scol = best.s - 1, ecol = best.e, target = best.text, sentence = best.text, previous = ctx.previous }
  elseif not ctx then
    ctx = { kind = "variations", scol = best.s - 1, ecol = best.e, target = best.text, sentence = best.text }
  end
  ctx.row = row
  return ctx
end

local function as_synonyms(ctx)
  return vim.tbl_extend("force", ctx, { kind = "synonyms", misspelled = ctx.kind == "spelling" or nil })
end

function M.synonyms_now()
  if not enabled then return vim.notify("writing: burst mode (switch with " .. cfg.keys.switch .. ")") end
  local buf = vim.api.nvim_get_current_buf()
  active_buf = buf
  local snap = snapshot(buf, 1)
  local ctx = snap.context
  if not ctx or (ctx.kind ~= "synonyms" and ctx.kind ~= "spelling") then
    return vim.notify("writing: put the cursor on a word", vim.log.levels.INFO)
  end
  core.snap = snap
  core:trigger(as_synonyms(ctx), { tick = snap.tick })
end

function M.suggest_now()
  if not enabled then return vim.notify("writing: burst mode (switch with " .. cfg.keys.switch .. ")") end
  local buf = vim.api.nvim_get_current_buf()
  active_buf = buf
  local snap = snapshot(buf, 1)
  local ctx = snap.context
  local shown = core.view.status ~= "idle" and core.view.kind or nil
  if not ctx then
    ctx = sentence_context_at(buf)
  elseif ctx.kind == "spelling" then
    if shown == "spelling" then ctx = sentence_context_at(buf) end
  elseif ctx.kind == "synonyms" and shown == "synonyms" then
    ctx = sentence_context_at(buf)
  end
  if not ctx then
    vim.notify("writing: nothing to suggest here", vim.log.levels.INFO)
    return
  end
  core.snap = snap
  core:trigger(ctx, { tick = snap.tick })
end

function M.make_sense()
  if not enabled then return vim.notify("writing: burst mode (switch with " .. cfg.keys.switch .. ")") end
  local buf = vim.api.nvim_get_current_buf()
  active_buf = buf
  local mode = vim.api.nvim_get_mode().mode
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local first, last
  if mode == "v" or mode == "V" or mode == "\22" then
    local a, b = vim.fn.line("v"), vim.fn.line(".")
    first, last = math.min(a, b), math.max(a, b)
    vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)
  end
  local ctx = context.paragraph(lines, row, first, last)
  if not ctx then
    vim.notify("writing: no paragraph under the cursor", vim.log.levels.INFO)
    return
  end
  core.snap = snapshot(buf)
  core:trigger(ctx, { tick = core.snap.tick })
end

local function update_badge()
  local buf = vim.api.nvim_get_current_buf()
  if cfg.box.badge and vim.b[buf].writing_attached then
    box.badge(M.statusline(), cfg.box.position, enabled and "WritingBadgeEditor" or "WritingBadgeBurst")
  else
    box.hide_badge()
  end
end

function M.editor_mode()
  enabled = true
  core:set_hidden(false)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.b[buf].writing_attached then show_spell(buf) end
  end
  update_badge()
end

function M.burst_mode()
  enabled = false
  core:set_hidden(true)
  hide_spell()
  update_badge()
end

function M.mode()
  return enabled and "editor" or "burst"
end

function M.toggle()
  if enabled then M.burst_mode() else M.editor_mode() end
end

function M.statusline()
  return enabled and "EDITOR" or "BURST"
end

function M.toggle_manual()
  local manual = core:toggle_manual()
  vim.notify("writing: " .. (manual and "manual only" or "ambient suggestions on"))
end

function show_spell(buf)
  if not (enabled and spell_ready and cfg.spell.highlight) then return end
  vim.bo[buf].spellcapcheck = ""
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    vim.wo[win].spell = true
    vim.w[win].writing_spell = true
  end
end

function hide_spell()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.w[win].writing_spell then
      vim.wo[win].spell = false
      vim.w[win].writing_spell = nil
    end
  end
end

function M.attach(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if vim.b[buf].writing_attached then return end
  if project_disabled(buf) then return end
  vim.b[buf].writing_attached = true
  update_badge()
  if spell_ready then spell.apply(buf, cfg.spell.langs) end
  show_spell(buf)
  vim.api.nvim_create_autocmd("BufWinEnter", { group = group, buffer = buf, callback = function() show_spell(buf) end })

  local function handle()
    if not enabled or applying or vim.api.nvim_get_current_buf() ~= buf then return end
    active_buf = buf
    core:on_event(snapshot(buf))
  end

  local events = { "CursorMoved", "CursorMovedI", "TextChanged", "TextChangedI", "ModeChanged" }
  vim.api.nvim_create_autocmd(events, { group = group, buffer = buf, callback = handle })
  vim.api.nvim_create_autocmd({ "BufLeave", "WinLeave" }, {
    group = group, buffer = buf,
    callback = function()
      core:cancel_pending()
      core:clear()
    end,
  })

  local k = cfg.keys
  local function bmap(modes, lhs, fn, desc)
    vim.keymap.set(modes, lhs, fn, { buffer = buf, silent = true, desc = "writing: " .. desc })
  end
  bmap({ "n", "x" }, k.action, M.suggest_now, "suggest now")
  bmap("n", k.synonyms, M.synonyms_now, "synonyms for the word")
  bmap({ "n", "x" }, k.make_sense, M.make_sense, "make sense")
  bmap("n", k.toggle, M.toggle, "switch burst/editor mode")
  vim.keymap.set({ "n", "i", "x" }, k.switch, M.toggle, { buffer = buf, silent = true, desc = "writing: switch burst/editor mode" })
  bmap("n", k.burst, M.burst_mode, "burst mode")
  bmap("n", k.editor, M.editor_mode, "editor mode")
  bmap("n", k.manual, M.toggle_manual, "manual only")
end

local function refresh_spell()
  local missing = spell.missing(cfg.spell.langs)
  spell_ready = cfg.spell.enabled and #missing == 0
  if cfg.spell.enabled and #missing > 0 then
    vim.schedule(function()
      vim.notify("writing: spelling mode off, missing spell files for: " .. table.concat(missing, ", ") .. " (run :WritingSpellInstall)", vim.log.levels.WARN)
    end)
  end
  if spell_ready then
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if vim.b[b].writing_attached then
        spell.apply(b, cfg.spell.langs)
        M._show_spell(b)
      end
    end
  end
end

function M.setup(user)
  cfg = config_mod.resolve(user)
  log.setup(cfg.log_file)
  box.setup_highlights(cfg.spell.highlight)

  local providers = {
    fast = provider.create(cfg.providers.fast),
    strong = provider.create(cfg.providers.strong),
  }

  core = Core.new({
    config = cfg,
    providers = providers,
    timer = real_timer(),
    clock = function() return vim.uv.hrtime() / 1e6 end,
    on_change = on_change,
    apply = apply_edit,
    log = function(e) log.write(e) end,
    style = read_style,
    spell = function(ctx) return spell.suggest(ctx.target, cfg.spell.suggestions) end,
  })

  enabled = cfg.mode ~= "burst"
  refresh_spell()
  group = vim.api.nvim_create_augroup("writing", { clear = true })
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = cfg.filetypes,
    callback = function(args) M.attach(args.buf) end,
  })

  vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter", "VimResized" }, { group = group, callback = update_badge })
  vim.api.nvim_create_user_command("WritingAttach", function() M.attach() end, {})
  vim.api.nvim_create_user_command("WritingNow", M.suggest_now, {})
  vim.api.nvim_create_user_command("WritingSense", M.make_sense, { range = true })
  vim.api.nvim_create_user_command("WritingToggle", M.toggle, {})
  vim.api.nvim_create_user_command("WritingBurst", function() M.burst_mode() end, {})
  vim.api.nvim_create_user_command("WritingEditor", function() M.editor_mode() end, {})
  vim.api.nvim_create_user_command("WritingManual", M.toggle_manual, {})
  vim.api.nvim_create_user_command("WritingSpellInstall", function()
    vim.notify("writing: downloading spell files…")
    spell.install(cfg.spell.langs, function(ok)
      refresh_spell()
      vim.notify(ok and "writing: spell files installed" or "writing: spell download failed", ok and vim.log.levels.INFO or vim.log.levels.ERROR)
    end)
  end, {})
  vim.api.nvim_create_user_command("WritingLog", function() vim.cmd.edit(cfg.log_file) end, {})

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.tbl_contains(cfg.filetypes, vim.bo[buf].filetype) then
      M.attach(buf)
    end
  end
  if not enabled then
    core:set_hidden(true)
    hide_spell()
  end
end

function M._show_spell(buf) show_spell(buf) end

function M._core()
  return core
end

return M
