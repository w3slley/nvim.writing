local M = {}

local ns = vim.api.nvim_create_namespace("writing_box")
local ghost_ns = vim.api.nvim_create_namespace("writing_ghost")
local target_ns = vim.api.nvim_create_namespace("writing_target")
local HIGHLIGHTED = { synonyms = true, spelling = true, variations = true }

local TITLES = { selection = "Selection", spelling = "Spelling", synonyms = "Synonyms", variations = "Variations", make_sense = "Make sense" }
local KEY_LABELS = { ["<CR>"] = "⏎", ["<Esc>"] = "esc", ["<Tab>"] = "⇥", ["<S-Tab>"] = "⇧⇥" }

local state = { win = nil, buf = nil, target_buf = nil }

function M.setup_highlights(spell_highlight)
  if spell_highlight then
    vim.api.nvim_set_hl(0, "SpellBad", { undercurl = true, sp = "#e06c75" })
  end
  local function hl(name, link) vim.api.nvim_set_hl(0, name, { link = link, default = true }) end
  hl("WritingBox", "NormalFloat")
  hl("WritingBoxBorder", "FloatBorder")
  hl("WritingBoxSel", "PmenuSel")
  hl("WritingBoxDim", "Comment")
  hl("WritingBoxFlag", "WarningMsg")
  hl("WritingTarget", "Visual")
  vim.api.nvim_set_hl(0, "WritingOld", { strikethrough = true, fg = "#e06c75", default = true })
  vim.api.nvim_set_hl(0, "WritingNew", { fg = "#98c379", bold = true, default = true })
  hl("WritingBadgeEditor", "DiffAdd")
  hl("WritingBadgeBurst", "DiffChange")
end

local function label(key)
  local alt = key:match("^<[AM]%-(.+)>$")
  if alt then return "⌥" .. (KEY_LABELS["<" .. alt .. ">"] or alt) end
  local ctrl = key:match("^<C%-(.+)>$")
  if ctrl then return "⌃" .. ctrl end
  return KEY_LABELS[key] or key
end

local function wrap(text, width)
  local out = {}
  for _, para in ipairs(vim.split(text, "\n", { plain = true })) do
    local line = ""
    for word in para:gmatch("%S+") do
      if line == "" then
        line = word
      elseif vim.fn.strdisplaywidth(line .. " " .. word) <= width then
        line = line .. " " .. word
      else
        out[#out + 1] = line
        line = word
      end
    end
    out[#out + 1] = line
  end
  return out
end

local function short(text, max)
  text = text:gsub("%s+", " ")
  if vim.fn.strdisplaywidth(text) <= max then return text end
  return vim.fn.strcharpart(text, 0, max - 1) .. "…"
end

local function footer(view, keys)
  if view.status == "error" then return label(keys.ignore) .. " dismiss" end
  if view.status == "loading" and not view.items then return label(keys.ignore) .. " cancel" end
  local parts = {}
  parts[#parts + 1] = label(keys.next) .. " cycle"
  if view.kind == "make_sense" then
    parts[#parts + 1] = label(keys.accept) .. (view.confirmed and " apply" or " preview")
  else
    parts[#parts + 1] = label(keys.accept) .. " accept"
  end
  parts[#parts + 1] = label(keys.regenerate) .. " more"
  parts[#parts + 1] = label(keys.ignore) .. " ignore"
  return table.concat(parts, " · ")
end

function M.build_lines(view, keys, width)
  local lines, marks = {}, {}
  local counter = ""
  if view.items and #view.items > 0 then counter = ("%d/%d"):format(view.index, #view.items) end
  local suffix = (view.status == "loading" or view.streaming) and "  …" or ""
  lines[1] = (TITLES[view.kind] or "") .. suffix .. (counter ~= "" and ("  " .. counter) or "")
  marks[#marks + 1] = { row = 0, group = "WritingBoxDim" }

  if view.status == "error" then
    lines[#lines + 1] = short(view.message or "error", width)
    marks[#marks + 1] = { row = #lines - 1, group = "WritingBoxFlag" }
  elseif view.items then
    for i, item in ipairs(view.items) do
      local prefix = view.kind == "make_sense" and "" or (i .. " ")
      local text = (item.label and view.kind == "make_sense") and (item.label .. ": " .. item.text) or item.text
      local chunks = wrap(text, width - #prefix - 2)
      local first = #lines
      for j, chunk in ipairs(chunks) do
        lines[#lines + 1] = (i == view.index and "▌ " or "  ") .. (j == 1 and prefix or string.rep(" ", #prefix)) .. chunk
        if view.kind == "make_sense" and j > 3 then
          lines[#lines] = lines[#lines]:sub(1, -2) .. "…"
          break
        end
      end
      if i == view.index then
        for r = first, #lines - 1 do marks[#marks + 1] = { row = r, group = "WritingBoxSel" } end
      end
    end
    if view.flags and #view.flags > 0 then
      lines[#lines + 1] = "off-topic:"
      marks[#marks + 1] = { row = #lines - 1, group = "WritingBoxFlag" }
      for _, f in ipairs(view.flags) do
        lines[#lines + 1] = "  · " .. short(f, width - 4)
        marks[#marks + 1] = { row = #lines - 1, group = "WritingBoxFlag" }
      end
    end
  end

  for _, chunk in ipairs(wrap(footer(view, keys), width)) do
    lines[#lines + 1] = chunk
    marks[#marks + 1] = { row = #lines - 1, group = "WritingBoxDim" }
  end
  return lines, marks
end

local badge = { win = nil, buf = nil }

local function badge_open()
  return badge.win ~= nil and vim.api.nvim_win_is_valid(badge.win)
end

local function corner(position, offset)
  local bottom = position ~= "top_right"
  local base = bottom and (vim.o.lines - vim.o.cmdheight - (vim.o.laststatus > 0 and 1 or 0)) or 1
  return bottom and "SE" or "NE", bottom and base - offset or base + offset
end

M.LAYOUTS = { "popup", "list", "strip", "corner" }

local STRIP_KINDS = { synonyms = true, spelling = true, selection = true }

local function ensure_window(width, height, placement)
  if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then
    state.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[state.buf].bufhidden = "wipe"
  end
  local config = vim.tbl_extend("force", {
    relative = "editor", width = width, height = height,
    style = "minimal", border = "rounded", focusable = false, zindex = 60, noautocmd = true,
  }, placement)
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_set_config(state.win, config)
  else
    state.win = vim.api.nvim_open_win(state.buf, false, config)
    vim.wo[state.win].winhighlight = "NormalFloat:WritingBox,FloatBorder:WritingBoxBorder"
    vim.wo[state.win].wrap = false
  end
end

local function close_float()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    pcall(vim.api.nvim_win_close, state.win, true)
  end
  state.win = nil
  state.buf = nil
end

function M.close()
  close_float()
  if state.target_buf and vim.api.nvim_buf_is_valid(state.target_buf) then
    vim.api.nvim_buf_clear_namespace(state.target_buf, ghost_ns, 0, -1)
    vim.api.nvim_buf_clear_namespace(state.target_buf, target_ns, 0, -1)
  end
end

M.PREVIEWS = { "strike", "below", "above", "inline" }

local function render_target(buf, view, strike)
  vim.api.nvim_buf_clear_namespace(buf, target_ns, 0, -1)
  local ctx = view.ctx
  if not (ctx and (HIGHLIGHTED[view.kind] or (strike and view.kind == "selection"))) then return end
  vim.api.nvim_buf_set_extmark(buf, target_ns, ctx.row - 1, ctx.scol, {
    end_row = ctx.row - 1, end_col = ctx.ecol, hl_group = strike and "WritingOld" or "WritingTarget", priority = 150,
  })
end

local function wrapped_virt(text, width, group)
  local out = {}
  for _, line in ipairs(wrap(text, width)) do out[#out + 1] = { { line, group } } end
  return out
end

local function build_preview(buf, view, style)
  local ctx = view.ctx
  local item = view.items and view.items[view.index]
  if not (ctx and item) then return nil end
  local above = style == "above"

  if view.kind == "make_sense" then
    if not view.confirmed then return nil end
    local virt = {}
    for _, l in ipairs(vim.split(ctx.target, "\n", { plain = true })) do virt[#virt + 1] = { { l, "WritingOld" } } end
    for _, l in ipairs(vim.split(item.text, "\n", { plain = true })) do virt[#virt + 1] = { { l, "WritingNew" } } end
    return { lines = virt, above = above, row = (above and ctx.first or ctx.last) - 1 }
  end

  local new = item.text:gsub("%s*\n%s*", " ")
  if style == "inline" then
    return { inline = { row = ctx.row - 1, col = ctx.ecol, text = " " .. new }, strike = true }
  end

  local win = vim.fn.bufwinid(buf)
  local avail = (win ~= -1 and vim.api.nvim_win_get_width(win) or vim.o.columns) - 6
  local line = vim.api.nvim_buf_get_lines(buf, ctx.row - 1, ctx.row, false)[1] or ""
  local old = line:sub(ctx.scol + 1, ctx.ecol)
  local indent = vim.fn.strdisplaywidth(line:sub(1, ctx.scol))
  if win ~= -1 then
    local sp = vim.fn.screenpos(win, ctx.row, ctx.scol + 1)
    local info = vim.fn.getwininfo(win)[1]
    if sp.row > 0 then indent = math.max(0, sp.col - info.wincol - info.textoff) end
  end
  local joined = vim.fn.strdisplaywidth(old) + vim.fn.strdisplaywidth(new) + 3

  if style == "strike" then
    local virt
    if indent + vim.fn.strdisplaywidth(new) <= avail then
      virt = { { { string.rep(" ", indent), "WritingBoxDim" }, { new, "WritingNew" } } }
    else
      virt = wrapped_virt(new, avail, "WritingNew")
    end
    return { lines = virt, above = false, row = ctx.row - 1, strike = true }
  end

  local virt
  if indent + joined <= avail then
    virt = { {
      { string.rep(" ", indent), "WritingBoxDim" },
      { old, "WritingOld" },
      { " → ", "WritingBoxDim" },
      { new, "WritingNew" },
    } }
  else
    virt = wrapped_virt(old, avail, "WritingOld")
    vim.list_extend(virt, wrapped_virt(new, avail, "WritingNew"))
  end
  return { lines = virt, above = above, row = ctx.row - 1 }
end

local function panel_lines(lines, marks, width)
  local groups = {}
  for _, m in ipairs(marks) do groups[m.row] = m.group end
  local virt = {}
  for i, line in ipairs(lines) do
    local padded = " " .. line .. string.rep(" ", math.max(0, width - vim.fn.strdisplaywidth(line))) .. " "
    virt[#virt + 1] = { { padded, groups[i - 1] or "WritingBox" } }
  end
  return virt
end

local function strip_line(view, keys)
  local chunks = { { " ", "WritingBox" } }
  local function add(text, group) chunks[#chunks + 1] = { text, group } end

  if view.status == "error" then
    add(" " .. short(view.message or "error", 60) .. " ", "WritingBoxFlag")
    add("  " .. label(keys.ignore) .. " dismiss", "WritingBoxDim")
    return { chunks }
  end

  if view.items and #view.items > 0 then
    local total = 0
    for _, item in ipairs(view.items) do total = total + vim.fn.strdisplaywidth(item.text) + 3 end
    if STRIP_KINDS[view.kind] and total <= vim.o.columns - 50 then
      for i, item in ipairs(view.items) do
        add(" " .. item.text .. " ", i == view.index and "WritingBoxSel" or "WritingBox")
      end
    else
      add(" " .. (TITLES[view.kind] or "") .. " ", "WritingBoxDim")
    end
    add(("  %d/%d"):format(view.index, #view.items), "WritingBoxDim")
  else
    add(" " .. (TITLES[view.kind] or "") .. " ", "WritingBoxDim")
  end
  if view.status == "loading" or view.streaming then add("  …", "WritingBoxDim") end
  local accept = view.kind == "make_sense" and (view.confirmed and " apply" or " preview") or " accept"
  add(("   %s%s  %s next  %s more  %s"):format(label(keys.accept), accept, label(keys.next), label(keys.regenerate), label(keys.ignore)), "WritingBoxDim")
  return { chunks }
end

local function popup_placement(buf, view, height, width, below_rows, above_rows)
  local ctx = view.ctx
  local win = vim.fn.bufwinid(buf)
  if win == -1 or not ctx then return nil end
  local first_row = ctx.first or ctx.row
  local last_row = ctx.last or ctx.row
  local first = vim.fn.screenpos(win, first_row, math.max(1, (ctx.scol or 0) + 1))
  local last_line = vim.api.nvim_buf_get_lines(buf, last_row - 1, last_row, false)[1] or ""
  local last = vim.fn.screenpos(win, last_row, math.max(1, #last_line))
  if first.row == 0 or last.row == 0 then return nil end

  first.row = first.row + above_rows
  last.row = last.row + above_rows
  local limit = vim.o.lines - vim.o.cmdheight - (vim.o.laststatus > 0 and 1 or 0)
  local col = math.max(0, math.min(first.col - 1, vim.o.columns - width - 2))
  local below = last.row + below_rows
  if below + height + 2 <= limit then
    return { anchor = "NW", row = below, col = col }
  end
  if first.row - 1 - above_rows - height - 2 >= 0 then
    return { anchor = "SW", row = first.row - 1 - above_rows, col = col }
  end
  return nil
end

function M.render(view, keys, buf, opts)
  opts = opts or {}
  local layout = opts.layout or "popup"
  if view.status == "idle" then
    M.close()
    return
  end
  state.target_buf = buf
  vim.api.nvim_buf_clear_namespace(buf, ghost_ns, 0, -1)

  local showing_items = view.status == "ready" or (view.status == "loading" and view.items)
  local pv = showing_items and build_preview(buf, view, opts.preview or "below") or nil
  render_target(buf, view, pv and pv.strike)

  local below_rows = (pv and pv.lines and not pv.above) and #pv.lines or 0
  local above_rows = (pv and pv.lines and pv.above) and #pv.lines or 0
  local extra = {}
  local width = math.max(30, math.min(56, vim.o.columns - 6))

  if layout == "popup" or layout == "corner" then
    local lines, marks = M.build_lines(view, keys, width)
    local box_width = width
    if layout == "popup" then
      box_width = 24
      for _, line in ipairs(lines) do box_width = math.max(box_width, vim.fn.strdisplaywidth(line)) end
      box_width = math.min(box_width, width)
    end
    local placement = layout == "popup" and popup_placement(buf, view, #lines, box_width, below_rows, above_rows) or nil
    if not placement then
      local anchor, row = corner(opts.position, badge_open() and 1 or 0)
      placement = { anchor = anchor, row = row, col = vim.o.columns }
      box_width = width
    end
    ensure_window(box_width, #lines, placement)
    vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
    vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
    for _, m in ipairs(marks) do
      vim.api.nvim_buf_set_extmark(state.buf, ns, m.row, 0, { line_hl_group = m.group })
    end
  else
    close_float()
    if layout == "list" then
      local lines, marks = M.build_lines(view, keys, width)
      extra = panel_lines(lines, marks, width)
    else
      extra = strip_line(view, keys)
    end
  end

  local ctx = view.ctx
  local below = {}
  if pv and pv.lines and not pv.above then vim.list_extend(below, pv.lines) end
  vim.list_extend(below, extra)
  if pv and pv.lines and pv.above then
    vim.api.nvim_buf_set_extmark(buf, ghost_ns, pv.row, 0, { virt_lines = pv.lines, virt_lines_above = true })
  end
  if #below > 0 then
    local row = (pv and pv.lines and not pv.above) and pv.row or ((ctx.last or ctx.row) - 1)
    vim.api.nvim_buf_set_extmark(buf, ghost_ns, row, 0, { virt_lines = below })
  end
  if pv and pv.inline then
    vim.api.nvim_buf_set_extmark(buf, ghost_ns, pv.inline.row, pv.inline.col, {
      virt_text = { { pv.inline.text, "WritingNew" } }, virt_text_pos = "inline",
    })
  end
end

function M.badge(text, position, group)
  if not (badge.buf and vim.api.nvim_buf_is_valid(badge.buf)) then
    badge.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[badge.buf].bufhidden = "wipe"
  end
  vim.api.nvim_buf_set_lines(badge.buf, 0, -1, false, { " " .. text .. " " })
  local anchor, row = corner(position, 0)
  local config = {
    relative = "editor", anchor = anchor, col = vim.o.columns, row = row,
    width = vim.fn.strdisplaywidth(text) + 2, height = 1,
    style = "minimal", focusable = false, zindex = 40, noautocmd = true,
  }
  if badge_open() then
    vim.api.nvim_win_set_config(badge.win, config)
  else
    badge.win = vim.api.nvim_open_win(badge.buf, false, config)
  end
  badge.text = text
  vim.wo[badge.win].winhighlight = "NormalFloat:" .. group
end

function M.hide_badge()
  if badge_open() then pcall(vim.api.nvim_win_close, badge.win, true) end
  badge.win = nil
  badge.text = nil
end

function M.badge_text()
  return badge_open() and badge.text or nil
end

function M.window()
  return state.win
end

return M
