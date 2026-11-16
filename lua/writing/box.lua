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
  hl("WritingGhost", "Comment")
  hl("WritingTarget", "Visual")
  hl("WritingGhostNew", "DiffAdd")
  hl("WritingDiffOld", "DiffDelete")
  hl("WritingDiffNew", "DiffAdd")
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
  if view.kind == "variations" or view.kind == "selection" then
    parts[#parts + 1] = label(keys.tighter) .. label(keys.clearer):gsub("^⌥", "") .. label(keys.formal):gsub("^⌥", "") .. " tweak"
  end
  if view.kind ~= "spelling" then parts[#parts + 1] = label(keys.regenerate) .. " more" end
  parts[#parts + 1] = label(keys.ignore) .. " ignore"
  return table.concat(parts, " · ")
end

function M.build_lines(view, keys, width)
  local lines, marks = {}, {}
  local counter = ""
  if view.items and #view.items > 0 then counter = ("%d/%d"):format(view.index, #view.items) end
  local suffix = view.status == "loading" and "  …" or ""
  local head = ("%s · %s"):format(TITLES[view.kind] or "", short(view.target or "", width - 14))
  lines[1] = head .. suffix .. (counter ~= "" and ("  " .. counter) or "")
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

local function ensure_window(width, height, position)
  if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then
    state.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[state.buf].bufhidden = "wipe"
  end
  local anchor, row = corner(position, badge_open() and 1 or 0)
  local config = {
    relative = "editor", anchor = anchor, col = vim.o.columns, row = row,
    width = width, height = height,
    style = "minimal", border = "rounded", focusable = false, zindex = 60, noautocmd = true,
  }
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_set_config(state.win, config)
  else
    state.win = vim.api.nvim_open_win(state.buf, false, config)
    vim.wo[state.win].winhighlight = "NormalFloat:WritingBox,FloatBorder:WritingBoxBorder"
    vim.wo[state.win].wrap = false
  end
end

function M.close()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    pcall(vim.api.nvim_win_close, state.win, true)
  end
  state.win = nil
  state.buf = nil
  if state.target_buf and vim.api.nvim_buf_is_valid(state.target_buf) then
    vim.api.nvim_buf_clear_namespace(state.target_buf, ghost_ns, 0, -1)
    vim.api.nvim_buf_clear_namespace(state.target_buf, target_ns, 0, -1)
  end
end

local function render_target(buf, view)
  vim.api.nvim_buf_clear_namespace(buf, target_ns, 0, -1)
  local ctx = view.ctx
  if not (ctx and HIGHLIGHTED[view.kind]) then return end
  vim.api.nvim_buf_set_extmark(buf, target_ns, ctx.row - 1, ctx.scol, {
    end_row = ctx.row - 1, end_col = ctx.ecol, hl_group = "WritingTarget", priority = 150,
  })
end

local function render_ghost(buf, view)
  vim.api.nvim_buf_clear_namespace(buf, ghost_ns, 0, -1)
  local ctx = view.ctx
  if not ctx or not view.items or not view.items[view.index] then return end
  local text = view.items[view.index].text

  if view.kind == "make_sense" then
    if not view.confirmed then return end
    local virt = {}
    for _, l in ipairs(vim.split(ctx.target, "\n", { plain = true })) do
      virt[#virt + 1] = { { "- " .. l, "WritingDiffOld" } }
    end
    for _, l in ipairs(vim.split(text, "\n", { plain = true })) do
      virt[#virt + 1] = { { "+ " .. l, "WritingDiffNew" } }
    end
    vim.api.nvim_buf_set_extmark(buf, ghost_ns, ctx.last - 1, 0, { virt_lines = virt })
    return
  end

  local line = vim.api.nvim_buf_get_lines(buf, ctx.row - 1, ctx.row, false)[1] or ""
  local replacement = text:gsub("%s*\n%s*", " ")
  vim.api.nvim_buf_set_extmark(buf, ghost_ns, ctx.row - 1, 0, {
    virt_lines = { {
      { "↳ " .. line:sub(1, ctx.scol), "WritingGhost" },
      { replacement, "WritingGhostNew" },
      { line:sub(ctx.ecol + 1), "WritingGhost" },
    } },
  })
end

function M.render(view, keys, buf, position)
  if view.status == "idle" then
    M.close()
    return
  end
  state.target_buf = buf
  local width = math.max(30, math.min(56, vim.o.columns - 6))
  local lines, marks = M.build_lines(view, keys, width)
  ensure_window(width, #lines, position)
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
  for _, m in ipairs(marks) do
    vim.api.nvim_buf_set_extmark(state.buf, ns, m.row, 0, { line_hl_group = m.group })
  end
  render_target(buf, view)
  if view.status == "ready" or (view.status == "loading" and view.items) then
    render_ghost(buf, view)
  else
    vim.api.nvim_buf_clear_namespace(buf, ghost_ns, 0, -1)
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
