local M = {}

local SOURCES = {
  en = "https://en-word.net/static/english-wordnet-2025-json.zip",
}

local POS = { n = "noun", v = "verb", a = "adj", s = "adj", r = "adv" }

local STOP = {}
for w in ([[a an the of to in on at by for with from as or and is are be been being that this which who whom whose
  what when where how it its into than then so such very something someone somebody thing things one ones person
  people word words way kind sort type someones somethings used use usually often especially etc not no
  make do have has give get can may might will would should]]):gmatch("%S+") do
  STOP[w] = true
end

local K1, B = 1.2, 0.75
local EXTRA_WEIGHT = 0.4

function M.path(lang)
  return vim.fn.stdpath("data") .. "/writing/dict-" .. lang .. ".tsv"
end

function M.available(lang)
  return vim.uv.fs_stat(M.path(lang)) ~= nil
end

function M.stem(w)
  if #w <= 4 then return w end
  local s = w:gsub("ies$", "y")
  if s == w then
    for _, suf in ipairs({ "ingly", "edly", "ness", "ment", "ing", "ly", "ed", "es", "s" }) do
      if #w - #suf >= 4 and w:sub(-#suf) == suf and not (suf == "s" and w:match("[su]s$")) then
        s = w:sub(1, -#suf - 1)
        if s:sub(-1) == s:sub(-2, -2) and not s:match("[lsz]$") then s = s:sub(1, -2) end
        break
      end
    end
  end
  if #s > 4 and s:sub(-1) == "e" then s = s:sub(1, -2) end
  return s
end

function M.tokens(text)
  local out = {}
  for w in text:lower():gmatch("[%a\128-\255]+") do
    if #w > 1 and not STOP[w] then out[#out + 1] = M.stem(w) end
  end
  return out
end

local function clean(s)
  return (s:gsub("[\t\n]", " "))
end

-- Each synset becomes one line: pos, members joined by "|", definition, then hypernym members and the
-- topic (e.g. "feeling" from noun.feeling) as lower-weight search text.
function M.convert(dir)
  local synsets = {}
  for name, kind in vim.fs.dir(dir) do
    local topic = name:match("^%a+%.(%a+)%.json$")
    if kind == "file" and topic then
      local data = vim.json.decode(table.concat(vim.fn.readfile(dir .. "/" .. name), "\n"))
      for id, s in pairs(data) do
        s.topic = topic ~= "all" and topic ~= "pert" and topic ~= "ppl" and topic ~= "Tops" and topic or nil
        synsets[id] = s
      end
    end
  end
  local lines = {}
  for _, s in pairs(synsets) do
    local def = s.definition and s.definition[1]
    if def and s.members and #s.members > 0 then
      local extra = {}
      for _, h in ipairs(s.hypernym or s.similar or {}) do
        local hs = synsets[h]
        if hs then vim.list_extend(extra, hs.members) end
      end
      if s.topic then extra[#extra + 1] = s.topic end
      lines[#lines + 1] = table.concat({
        POS[s.partOfSpeech] or s.partOfSpeech,
        clean(table.concat(s.members, "|")),
        clean(def),
        clean(table.concat(extra, " ")),
      }, "\t")
    end
  end
  table.sort(lines)
  return lines
end

function M.install(lang, on_done)
  local url = SOURCES[lang]
  if not url then return on_done(false, "no dictionary source for " .. lang) end
  local tmp = vim.fn.tempname()
  vim.fn.mkdir(tmp, "p")
  local zip = tmp .. "/src.zip"
  local function fail(msg)
    vim.fn.delete(tmp, "rf")
    on_done(false, msg)
  end
  vim.system({ "curl", "-sSfL", "-o", zip, url }, { text = true }, function(res)
    if res.code ~= 0 then return vim.schedule(function() fail("download failed: " .. (res.stderr or "")) end) end
    vim.system({ "unzip", "-oq", zip, "-d", tmp .. "/src" }, { text = true }, function(un)
      vim.schedule(function()
        if un.code ~= 0 then return fail("unzip failed: " .. (un.stderr or "")) end
        local ok, lines = pcall(M.convert, tmp .. "/src")
        if not ok then return fail("convert failed: " .. tostring(lines)) end
        local out = M.path(lang)
        vim.fn.mkdir(vim.fs.dirname(out), "p")
        vim.fn.writefile(lines, out)
        vim.fn.delete(tmp, "rf")
        M.cache[lang] = nil
        on_done(true, #lines)
      end)
    end)
  end)
end

function M.build(lines, yield)
  local idx = { docs = {}, postings = {}, lemmas = {}, total_len = 0 }
  for n, line in ipairs(lines) do
    if yield and n % 1000 == 0 then yield() end
    local pos, members, def, extra = line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t?([^\t]*)$")
    if members then
      local doc = { pos = pos, words = vim.split(members, "|", { plain = true }), definition = def }
      local id = #idx.docs + 1
      idx.docs[id] = doc
      for _, w in ipairs(doc.words) do
        local key = w:lower()
        local ids = idx.lemmas[key]
        if not ids then
          ids = {}
          idx.lemmas[key] = ids
        end
        ids[#ids + 1] = id
      end
      local tf, len = {}, 0
      for _, t in ipairs(M.tokens(def)) do
        tf[t] = (tf[t] or 0) + 1
        len = len + 1
      end
      for _, t in ipairs(M.tokens(extra)) do
        tf[t] = (tf[t] or 0) + EXTRA_WEIGHT
        len = len + EXTRA_WEIGHT
      end
      doc.len = len
      idx.total_len = idx.total_len + len
      for t, f in pairs(tf) do
        local p = idx.postings[t]
        if not p then
          p = {}
          idx.postings[t] = p
        end
        p[#p + 1] = id
        p[#p + 1] = f
      end
    end
  end
  idx.avg_len = #idx.docs > 0 and idx.total_len / #idx.docs or 1
  return idx
end

M.cache = {}
local building = {}

local function step(lang)
  local co = building[lang]
  local ok, idx = coroutine.resume(co)
  if not ok or coroutine.status(co) == "dead" then
    building[lang] = nil
    if ok then M.cache[lang] = idx end
    return true
  end
  return false
end

-- Builds the index in slices on timer ticks, so the editor stays responsive while the user types; load()
-- finishes whatever is left synchronously.
function M.preload(lang)
  if M.cache[lang] or building[lang] or not M.available(lang) then return end
  local path = M.path(lang)
  building[lang] = coroutine.create(function()
    local lines = vim.fn.readfile(path)
    coroutine.yield()
    return M.build(lines, coroutine.yield)
  end)
  local function tick()
    if building[lang] and not step(lang) then vim.defer_fn(tick, 0) end
  end
  vim.defer_fn(tick, 0)
end

function M.loading(lang)
  return building[lang] ~= nil or (M.cache[lang] == nil and M.available(lang))
end

function M.load(lang)
  if M.cache[lang] then return M.cache[lang] end
  if not building[lang] then
    if not M.available(lang) then return nil end
    local path = M.path(lang)
    building[lang] = coroutine.create(function() return M.build(vim.fn.readfile(path), coroutine.yield) end)
  end
  while not step(lang) do end
  return M.cache[lang]
end

function M.scores(idx, query)
  local n_docs = #idx.docs
  local scores = {}
  local seen = {}
  for _, t in ipairs(M.tokens(query)) do
    local p = idx.postings[t]
    if p and not seen[t] then
      seen[t] = true
      local df = #p / 2
      local idf = math.log(1 + (n_docs - df + 0.5) / (df + 0.5))
      for i = 1, #p, 2 do
        local id, f = p[i], p[i + 1]
        local norm = 1 - B + B * idx.docs[id].len / idx.avg_len
        scores[id] = (scores[id] or 0) + idf * f * (K1 + 1) / (f + K1 * norm)
      end
    end
  end
  return scores
end

-- Picks the sense of `word` whose definition best matches `query`, so a word the LLM proposes is shown with
-- the dictionary's meaning, not the model's.
function M.lookup(idx, word, query, scores)
  word = vim.trim(word)
  local key = word:lower()
  local ids = idx.lemmas[key]
  if not ids then return nil end
  scores = scores or M.scores(idx, query or "")
  local best, best_score, best_exact
  for _, id in ipairs(ids) do
    local sc = scores[id] or 0
    local exact = vim.tbl_contains(idx.docs[id].words, word)
    if not best or (exact and not best_exact) or (exact == best_exact and sc > best_score) then
      best, best_score, best_exact = id, sc, exact
    end
  end
  local doc = idx.docs[best]
  for _, w in ipairs(doc.words) do
    if w:lower() == key then word = w end
  end
  return { word = word, pos = doc.pos, definition = doc.definition, score = best_score }
end

function M.search(idx, query, n)
  n = n or 30
  local scores = M.scores(idx, query)
  local query_words = {}
  for w in query:lower():gmatch("[%a\128-\255'%-]+") do query_words[w] = true end
  local ranked = {}
  for id, score in pairs(scores) do ranked[#ranked + 1] = { id = id, score = score } end
  table.sort(ranked, function(a, b) return a.score > b.score or (a.score == b.score and a.id < b.id) end)
  local out = {}
  for _, r in ipairs(ranked) do
    local doc = idx.docs[r.id]
    local words = {}
    for _, w in ipairs(doc.words) do
      if not query_words[w:lower()] then words[#words + 1] = w end
    end
    if #words > 0 then
      out[#out + 1] = { words = words, pos = doc.pos, definition = doc.definition, score = r.score }
      if #out >= n then break end
    end
  end
  return out
end

return M
