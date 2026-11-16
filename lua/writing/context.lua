local M = {}

local TERMINATORS = { ["."] = true, ["!"] = true, ["?"] = true }

local function is_word_byte(b)
  return b ~= nil and (b >= 128 or (b >= 48 and b <= 57) or (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or b == 95)
end

function M.sentences(line)
  local out = {}
  local len = #line
  local start = line:find("%S")
  while start and start <= len do
    local i = start
    local stop
    while i <= len do
      local c = line:sub(i, i)
      if TERMINATORS[c] or line:sub(i, i + 2) == "…" then
        local j = i
        while j <= len and (TERMINATORS[line:sub(j, j)] or line:sub(j, j + 2) == "…") do
          j = j + (line:sub(j, j + 2) == "…" and 3 or 1)
        end
        local nextc = line:sub(j, j)
        if j > len or nextc:match("%s") then
          stop = j - 1
          break
        end
        i = j
      else
        i = i + 1
      end
    end
    stop = stop or len
    local text = line:sub(start, stop):gsub("%s+$", "")
    out[#out + 1] = { s = start, e = start + #text - 1, text = text, terminated = stop < len or TERMINATORS[line:sub(stop, stop)] ~= nil or line:sub(stop - 2, stop) == "…" }
    local nxt = line:find("%S", stop + 1)
    start = nxt
  end
  return out
end

function M.word_at(line, col)
  local idx = col + 1
  if not is_word_byte(line:byte(idx)) then return nil end
  local s, e = idx, idx
  while s > 1 and is_word_byte(line:byte(s - 1)) do s = s - 1 end
  while is_word_byte(line:byte(e + 1)) do e = e + 1 end
  return { s = s, e = e, text = line:sub(s, e) }
end

local function sentence_index(sents, pos)
  for i, s in ipairs(sents) do
    if pos >= s.s and pos <= s.e then return i end
  end
end

local function previous_sentence(lines, row, sents, idx)
  if idx > 1 then return sents[idx - 1].text end
  for r = row - 1, 1, -1 do
    if lines[r]:match("%S") then
      local prev = M.sentences(lines[r])
      if #prev > 0 then return prev[#prev].text end
      return nil
    end
    return nil
  end
end

local function ends_with_terminator(text)
  local trimmed = text:gsub("%s+$", "")
  local last = trimmed:sub(-1)
  return TERMINATORS[last] or trimmed:sub(-3) == "…"
end

function M.analyze(lines, row, col, insert, spell_bad)
  local line = lines[row] or ""
  local before = insert and line:sub(1, col) or line:sub(1, col + 1)
  local under = (not insert) and line:sub(col + 1, col + 1) or ""
  local word_here = (not insert) and is_word_byte(line:byte(col + 1))

  if not word_here and before:match("%S") and ends_with_terminator(before) then
    local sents = M.sentences(line)
    local idx = sentence_index(sents, #before:gsub("%s+$", ""))
    if idx and sents[idx].terminated then
      local s = sents[idx]
      return {
        kind = "variations",
        row = row,
        scol = s.s - 1,
        ecol = s.e,
        target = s.text,
        sentence = s.text,
        previous = previous_sentence(lines, row, sents, idx),
      }
    end
  end

  if insert and spell_bad then
    local head = before:match("^(.-)%s+$")
    local w = head and M.word_at(line, #head - 1)
    if w and w.e == #head and #w.text >= 3 and spell_bad(w.text) then
      return {
        kind = "spelling", row = row, scol = w.s - 1, ecol = w.e, target = w.text, sentence = line,
      }
    end
  end

  if word_here then
    local w = M.word_at(line, col)
    if w and #w.text >= 3 then
      local sents = M.sentences(line)
      local idx = sentence_index(sents, w.s)
      local misspelled = spell_bad and spell_bad(w.text)
      return {
        kind = misspelled and "spelling" or "synonyms",
        row = row,
        scol = w.s - 1,
        ecol = w.e,
        target = w.text,
        sentence = idx and sents[idx].text or line,
        previous = idx and previous_sentence(lines, row, sents, idx) or nil,
      }
    end
  end

  return nil
end

function M.paragraph(lines, row, first, last)
  local s, e = row, row
  if first and last then
    s, e = first, last
  else
    if not (lines[row] or ""):match("%S") then return nil end
    while s > 1 and lines[s - 1]:match("%S") do s = s - 1 end
    while e < #lines and lines[e + 1]:match("%S") do e = e + 1 end
  end

  local function block_before(from)
    local r = from - 1
    while r >= 1 and not lines[r]:match("%S") do r = r - 1 end
    if r < 1 then return nil, 0 end
    local top = r
    while top > 1 and lines[top - 1]:match("%S") do top = top - 1 end
    return table.concat(vim.list_slice(lines, top, r), "\n"), top
  end

  local function block_after(from)
    local r = from + 1
    while r <= #lines and not lines[r]:match("%S") do r = r + 1 end
    if r > #lines then return nil end
    local bottom = r
    while bottom < #lines and lines[bottom + 1]:match("%S") do bottom = bottom + 1 end
    return table.concat(vim.list_slice(lines, r, bottom), "\n")
  end

  local neighbours = {}
  local before1, top1 = block_before(s)
  if before1 then
    neighbours[#neighbours + 1] = before1
    local before2 = block_before(top1)
    if before2 then table.insert(neighbours, 1, before2) end
  end
  local after1 = block_after(e)
  if after1 then neighbours[#neighbours + 1] = after1 end

  return {
    kind = "make_sense",
    first = s,
    last = e,
    target = table.concat(vim.list_slice(lines, s, e), "\n"),
    neighbours = neighbours,
  }
end

return M
