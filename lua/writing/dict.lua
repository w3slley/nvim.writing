local M = {}

local SOURCES = {
  en = { url = "https://en-word.net/static/english-wordnet-2025-json.zip", archive = "zip", name = "Open English WordNet" },
  pt = {
    url = "https://kaikki.org/ptwiktionary/Portugu%C3%AAs/kaikki.org-dictionary-Portugu%C3%AAs.jsonl.gz",
    archive = "gz",
    name = "Portuguese Wiktionary",
  },
}

function M.source(lang) return SOURCES[lang] end

local POS = { n = "noun", v = "verb", a = "adj", s = "adj", r = "adv" }

local function word_set(text)
  local set = {}
  for w in text:gmatch("%S+") do set[w] = true end
  return set
end

local STOP = {
  en = word_set([[a an the of to in on at by for with from as or and is are be been being that this which who whom
    whose what when where how it its into than then so such very something someone somebody thing things one ones
    person people word words way kind sort type someones somethings used use usually often especially etc not no
    make do have has give get can may might will would should]]),
  pt = word_set([[a o as os um uma uns umas de da do das dos em na no nas nos por pela pelo pelas pelos para pra com
    sem sob sobre entre ate desde ao aos a e ou mas nem que se como mais menos muito muita muitos muitas pouco
    tao ja nao sim ser estar ter haver fazer ficar e sao era foi esta estao tem ha seu sua seus suas lhe lhes ele ela
    eles elas isto isso aquilo este esta esse essa aquele aquela aqueles aquelas qual quais quem cujo cuja onde quando
    algo alguem alguma algum coisa coisas pessoa pessoas palavra modo tipo qualquer outro outra outros outras mesmo
    mesma diz-se diz relativo relativa usado usada geralmente etc]]),
}

local K1, B = 1.2, 0.75
local EXTRA_WEIGHT = 0.4

function M.path(lang)
  return vim.fn.stdpath("data") .. "/writing/dict-" .. lang .. ".tsv"
end

function M.forms_path(lang)
  return vim.fn.stdpath("data") .. "/writing/forms-" .. lang .. ".tsv"
end

function M.available(lang)
  return vim.uv.fs_stat(M.path(lang)) ~= nil
end

local FOLD = {
  ["á"] = "a", ["à"] = "a", ["â"] = "a", ["ã"] = "a", ["ä"] = "a", ["Á"] = "a", ["À"] = "a", ["Â"] = "a", ["Ã"] = "a",
  ["é"] = "e", ["ê"] = "e", ["è"] = "e", ["É"] = "e", ["Ê"] = "e",
  ["í"] = "i", ["Í"] = "i",
  ["ó"] = "o", ["ô"] = "o", ["õ"] = "o", ["Ó"] = "o", ["Ô"] = "o", ["Õ"] = "o",
  ["ú"] = "u", ["ü"] = "u", ["Ú"] = "u",
  ["ç"] = "c", ["Ç"] = "c",
}

function M.fold(w)
  return (w:lower():gsub("[\195][\128-\191]", FOLD))
end

local function stem_en(w)
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

local PT_PLURAL = { { "oes", "ao" }, { "aes", "ao" }, { "ais", "al" }, { "eis", "el" }, { "ois", "ol" }, { "ns", "m" },
  { "res", "r" }, { "zes", "z" }, { "les", "l" }, { "s", "" } }
local PT_SUFFIX = { "amente", "mente", "amento", "imento", "acao", "icao", "ador", "edor", "idor", "ancia", "encia",
  "ando", "endo", "indo", "ado", "ido", "ada", "ida", "ar", "er", "ir" }

-- A light stemmer on accent-folded words: plurals, derivational and verb endings, then the final vowel, so
-- "fechados", "fechada" and "fechar" all meet at "fech".
local function stem_pt(w)
  w = M.fold(w)
  if #w <= 3 then return w end
  for _, p in ipairs(PT_PLURAL) do
    if #w - #p[1] >= 3 and w:sub(-#p[1]) == p[1] then
      w = w:sub(1, -#p[1] - 1) .. p[2]
      break
    end
  end
  for _, suf in ipairs(PT_SUFFIX) do
    if #w - #suf >= 4 and w:sub(-#suf) == suf then
      w = w:sub(1, -#suf - 1)
      break
    end
  end
  if #w > 3 and w:match("[aeo]$") then w = w:sub(1, -2) end
  return w
end

function M.stem(w, lang)
  if lang == "pt" then return stem_pt(w) end
  return stem_en(w)
end

function M.tokens(text, lang)
  lang = lang or "en"
  local stop = STOP[lang] or STOP.en
  local out = {}
  for w in text:lower():gmatch("[%a\128-\255%-]+") do
    w = w:gsub("^%-+", ""):gsub("%-+$", "")
    local key = lang == "pt" and M.fold(w) or w
    if #w > 1 and not stop[key] then
      for part in w:gmatch("[^%-]+") do
        local pkey = lang == "pt" and M.fold(part) or part
        if #part > 1 and not stop[pkey] then out[#out + 1] = M.stem(part, lang) end
      end
    end
  end
  return out
end

local function clean(s)
  return (s:gsub("[\t\n]", " "))
end

-- Each synset becomes one line: pos, members joined by "|", definition, hypernym members and the topic (e.g.
-- "feeling" from noun.feeling) as lower-weight search text, then each member's sense rank, so a word's most
-- common sense is listed first. Irregular forms from the entries files ("bought" -> "buy") come back as forms.
function M.convert(dir)
  local synsets, rank, lemmas_of = {}, {}, {}
  for name, kind in vim.fs.dir(dir) do
    local topic = name:match("^%a+%.(%a+)%.json$")
    if kind == "file" and (topic or name:match("^entries%-.+%.json$")) then
      local data = vim.json.decode(table.concat(vim.fn.readfile(dir .. "/" .. name), "\n"))
      if topic then
        for id, s in pairs(data) do
          s.topic = topic ~= "all" and topic ~= "pert" and topic ~= "ppl" and topic ~= "Tops" and topic or nil
          synsets[id] = s
        end
      else
        for lemma, by_pos in pairs(data) do
          for pos, entry in pairs(by_pos) do
            for i, sense in ipairs(entry.sense or {}) do
              rank[sense.synset] = rank[sense.synset] or {}
              rank[sense.synset][lemma] = i
            end
            for _, form in ipairs(entry.form or {}) do
              local item = lemma .. ":" .. (POS[pos] or pos)
              lemmas_of[form] = lemmas_of[form] or {}
              if not vim.tbl_contains(lemmas_of[form], item) then table.insert(lemmas_of[form], item) end
            end
          end
        end
      end
    end
  end
  local lines = {}
  for id, s in pairs(synsets) do
    local def = s.definition and s.definition[1]
    if def and s.members and #s.members > 0 then
      local extra = {}
      for _, h in ipairs(s.hypernym or s.similar or {}) do
        local hs = synsets[h]
        if hs then vim.list_extend(extra, hs.members) end
      end
      if s.topic then extra[#extra + 1] = s.topic end
      local ranks = {}
      for i, m in ipairs(s.members) do ranks[i] = tostring(rank[id] and rank[id][m] or 99) end
      lines[#lines + 1] = table.concat({
        POS[s.partOfSpeech] or s.partOfSpeech,
        clean(table.concat(s.members, "|")),
        clean(def),
        clean(table.concat(extra, " ")),
        table.concat(ranks, "|"),
      }, "\t")
    end
  end
  table.sort(lines)
  local forms = {}
  for form, ls in pairs(lemmas_of) do
    if not form:find("\t") then forms[#forms + 1] = form .. "\t" .. table.concat(ls, "|") end
  end
  table.sort(forms)
  return lines, forms
end

local PT_POS = { noun = "subst.", verb = "verbo", adj = "adj.", adv = "adv.", phrase = "expr." }
local OTHER_REGION = { Brazil = true, Brazilian = true, ["Northeast-Brazil"] = true, ["Rio Grande do Sul"] = true,
  Galicia = true, Angola = true, Mozambique = true }

local function other_region(item)
  local portugal = false
  local other = false
  for _, t in ipairs(item.tags or {}) do
    if t == "Portugal" or t == "Portuguese" or t == "Lusitanian" then portugal = true end
    if OTHER_REGION[t] then other = true end
  end
  for _, t in ipairs(item.raw_tags or {}) do
    if t:find("Portugal") then portugal = true end
    if (t:find("Brasil") and not t:find("Exceto")) or t:find("Município") or t:find("Moçambique") then other = true end
  end
  return other and not portugal
end

local function has(list, value)
  return list ~= nil and vim.tbl_contains(list, value)
end

-- Reads the Portuguese Wiktionary extract (one JSON entry per line) and keeps one line per sense, in the same
-- shape as the English file: pos, word, definition, then topic tags and synonyms as lower-weight search text.
-- Inflected forms are skipped, as are senses and spellings used only outside Portugal: Brazil-only senses,
-- and a Brazilian "econômico" when the European "económico" exists. Cross-references ("ver efémero") take
-- the definition of the word they point to. Senses keep the source's order, so a word's main sense comes first.
-- Inflected forms come back separately as "form<TAB>lemma:pos|lemma:pos" lines ("casas" -> "casa:subst.|casar:verbo"); they are read
-- with a pattern instead of a JSON decode, which keeps the 300,000 conjugation entries cheap.
function M.convert_pt(path)
  local senses, words, lemmas_of = {}, {}, {}
  for line in io.lines(path) do
    local _, glosses = line:gsub('"glosses"', "")
    local _, forms = line:gsub('"form_of"', "")
    if forms > 0 then
      local form = line:match('^{"word": "([^"\\]+)"')
      local fpos = PT_POS[line:match('"pos": "(%a+)"')]
      if form and fpos and line:find('"lang_code": "pt"', 1, true) then
        for lemma in line:gmatch('"form_of": %[{"word": "([^"\\]+)"') do
          local item = lemma .. ":" .. fpos
          if lemma ~= form then
            lemmas_of[form] = lemmas_of[form] or {}
            if not vim.tbl_contains(lemmas_of[form], item) then table.insert(lemmas_of[form], item) end
          end
        end
      end
    end
    local e = glosses > forms and vim.json.decode(line) or nil
    local pos = e and PT_POS[e.pos]
    if pos and e.lang_code == "pt" and not e.word:find("[\t|]") and not other_region(e) then
      local syns = {}
      for _, syn in ipairs(e.synonyms or {}) do
        if type(syn.word) == "string" and not other_region(syn) then syns[#syns + 1] = syn.word end
      end
      for _, sense in ipairs(e.senses or {}) do
        local gloss = sense.glosses and sense.glosses[#sense.glosses]
        if gloss and not sense.form_of and not has(sense.tags, "form-of") and not has(sense.tags, "no-gloss")
          and not other_region(sense) then
          local extra = vim.list_extend(vim.list_extend({}, sense.raw_tags or {}), syns)
          senses[#senses + 1] = { pos = pos, word = e.word, gloss = clean(vim.trim(gloss)), extra = extra }
          words[e.word] = words[e.word] or {}
          table.insert(words[e.word], #senses)
        end
      end
    end
  end
  local function target_gloss(word, pos)
    local fallback
    for _, i in ipairs(words[word] or {}) do
      local t = senses[i]
      if not t.gloss:match("^ver ") and not t.gloss:match("^vide ") then
        if t.pos == pos then return t.gloss end
        fallback = fallback or t.gloss
      end
    end
    return fallback
  end
  local lines = {}
  for _, sense in ipairs(senses) do
    local w = sense.word
    local european = w:gsub("ô([mn])", "ó%1"):gsub("ê([mn])", "é%1")
    if european == w or not words[european] then
      local def = sense.gloss
      local ref = def:match("^ver ([^%s,;.]+)%.?$") or def:match("^vide ([^%s,;.]+)%.?$")
      if ref then def = target_gloss(ref, sense.pos) end
      if def and def ~= "" then
        lines[#lines + 1] = table.concat({ sense.pos, w, def, clean(table.concat(sense.extra, " ")) }, "\t")
      end
    end
  end
  local forms = {}
  for form, ls in pairs(lemmas_of) do
    if not form:find("\t") then forms[#forms + 1] = form .. "\t" .. table.concat(ls, "|") end
  end
  table.sort(forms)
  return lines, forms
end

local function unpack_source(src, file, dir, on_done)
  if src.archive == "zip" then
    vim.system({ "unzip", "-oq", file, "-d", dir }, { text = true }, function(res)
      on_done(res.code == 0 and dir or nil, "unzip failed: " .. (res.stderr or ""))
    end)
  else
    vim.system({ "gzip", "-df", file }, { text = true }, function(res)
      on_done(res.code == 0 and file:gsub("%.gz$", "") or nil, "gunzip failed: " .. (res.stderr or ""))
    end)
  end
end

local ROOT = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")

function M.convert_to(lang, src, out, forms_out)
  local lines, forms
  if lang == "pt" then lines, forms = M.convert_pt(src) else lines, forms = M.convert(src) end
  vim.fn.writefile(lines, out)
  if forms then vim.fn.writefile(forms, forms_out) end
  return #lines
end

-- Converting runs in a headless Neovim: the Portuguese file takes about 10 seconds to parse, and work sliced
-- on timers inside the editor stalls whenever a "Press ENTER" prompt is open. Files are written next to the
-- final ones and renamed, so a failed install leaves the previous dictionary in place.
function M.install(lang, on_done)
  local src = SOURCES[lang]
  if not src then return on_done(false, "no dictionary source for " .. lang) end
  local tmp = vim.fn.tempname()
  vim.fn.mkdir(tmp, "p")
  local file = tmp .. "/src." .. src.archive
  local out, forms_out = M.path(lang), M.forms_path(lang)
  vim.fn.mkdir(vim.fs.dirname(out), "p")
  local function finish(ok, info)
    vim.schedule(function()
      vim.fn.delete(tmp, "rf")
      if ok then
        vim.uv.fs_rename(out .. ".new", out)
        if vim.uv.fs_stat(forms_out .. ".new") then vim.uv.fs_rename(forms_out .. ".new", forms_out) end
        M.cache[lang] = nil
      else
        vim.fn.delete(out .. ".new")
        vim.fn.delete(forms_out .. ".new")
      end
      on_done(ok, info)
    end)
  end
  vim.system({ "curl", "-sSfL", "-o", file, src.url }, { text = true }, function(res)
    if res.code ~= 0 then return finish(false, "download failed: " .. (res.stderr or "")) end
    unpack_source(src, file, tmp .. "/src", function(unpacked, err)
      if not unpacked then return finish(false, err) end
      vim.system({
        vim.v.progpath, "--headless", "-u", "NONE", "-l", ROOT .. "/scripts/dict_convert.lua",
        lang, unpacked, out .. ".new", forms_out .. ".new",
      }, { text = true }, function(conv)
        local count = tonumber(vim.trim(conv.stdout or ""))
        if conv.code ~= 0 or not count then
          return finish(false, "convert failed: " .. vim.trim((conv.stderr or "") .. (conv.stdout or "")))
        end
        finish(true, count)
      end)
    end)
  end)
end

function M.build(lines, yield, lang)
  lang = lang or "en"
  local idx = { lang = lang, docs = {}, postings = {}, lemmas = {}, folded = {}, total_len = 0 }
  for n, line in ipairs(lines) do
    if yield and n % 1000 == 0 then yield() end
    local pos, members, def, extra, ranks = line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t?([^\t]*)\t?([^\t]*)$")
    if members then
      local doc = { pos = pos, words = vim.split(members, "|", { plain = true }), definition = def }
      if ranks ~= "" then doc.ranks = vim.split(ranks, "|", { plain = true }) end
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
        local fkey = M.fold(key)
        if fkey ~= key then
          idx.folded[fkey] = idx.folded[fkey] or {}
          table.insert(idx.folded[fkey], id)
        end
      end
      local tf, len = {}, 0
      for _, t in ipairs(M.tokens(def, lang)) do
        tf[t] = (tf[t] or 0) + 1
        len = len + 1
      end
      for _, t in ipairs(M.tokens(extra, lang)) do
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
    return M.build(lines, coroutine.yield, lang)
  end)
  local function tick()
    if building[lang] and not step(lang) then vim.defer_fn(tick, 0) end
  end
  vim.defer_fn(tick, 0)
end

function M.unload()
  M.cache = {}
  building = {}
end

function M.loading(lang)
  return building[lang] ~= nil or (M.cache[lang] == nil and M.available(lang))
end

function M.load(lang)
  if M.cache[lang] then return M.cache[lang] end
  if not building[lang] then
    if not M.available(lang) then return nil end
    local path = M.path(lang)
    building[lang] = coroutine.create(function() return M.build(vim.fn.readfile(path), coroutine.yield, lang) end)
  end
  while not step(lang) do end
  return M.cache[lang]
end

function M.scores(idx, query)
  local n_docs = #idx.docs
  local scores = {}
  local seen = {}
  for _, t in ipairs(M.tokens(query, idx.lang)) do
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
-- the dictionary's meaning, not the model's. A guess spelled with other accents (a Brazilian "efêmero" for
-- "efémero") falls back to the accent-folded form and comes back in the dictionary's spelling.
function M.lookup(idx, word, query, scores)
  word = vim.trim(word)
  local key = word:lower()
  local ids = idx.lemmas[key]
  if not ids then
    local fkey = M.fold(key)
    ids = idx.folded[fkey] or idx.lemmas[fkey]
    if not ids then return nil end
    key = idx.docs[ids[1]].words[1]:lower()
    for _, w in ipairs(idx.docs[ids[1]].words) do
      if M.fold(w) == fkey then key = w:lower() end
    end
    word = key
  end
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

local function senses_of(idx, word)
  local key = word:lower()
  local ids = idx.lemmas[key] or idx.folded[M.fold(key)]
  if not ids then return nil end
  local entry = { word = word, senses = {} }
  for n, id in ipairs(ids) do
    local doc = idx.docs[id]
    local others, rank = {}, 99
    for i, w in ipairs(doc.words) do
      if w:lower() == key or M.fold(w) == M.fold(key) then
        entry.word = w
        rank = math.min(rank, tonumber(doc.ranks and doc.ranks[i]) or 99)
      else
        others[#others + 1] = w
      end
    end
    entry.senses[#entry.senses + 1] = { pos = doc.pos, definition = doc.definition, synonyms = others, rank = rank, n = n }
  end
  table.sort(entry.senses, function(a, b) return a.rank < b.rank or (a.rank == b.rank and a.n < b.n) end)
  for _, sense in ipairs(entry.senses) do sense.rank, sense.n = nil, nil end
  return entry
end

local EN_ENDINGS = { { "ies", "y" }, { "ied", "y" }, { "ves", "f" }, { "es", "" }, { "s", "" }, { "ed", "" }, { "ed", "e" },
  { "ing", "" }, { "ing", "e" }, { "er", "" }, { "est", "" }, { "ly", "" } }

local PT_ENDINGS = { { "oes", "ao" }, { "ões", "ão" }, { "ães", "ão" }, { "ais", "al" }, { "eis", "el" }, { "is", "l" },
  { "ns", "m" }, { "es", "" }, { "s", "" }, { "as", "o" }, { "a", "o" } }

local function suffix_bases(idx, word, endings)
  local out = {}
  for _, e in ipairs(endings) do
    local suf, add = e[1], e[2]
    if #word - #suf >= 2 and word:sub(-#suf) == suf then
      local base = word:sub(1, -#suf - 1)
      for _, b in ipairs({ base .. add, base:sub(-1) == base:sub(-2, -2) and base:sub(1, -2) or nil }) do
        if idx.lemmas[b] and not vim.tbl_contains(out, b) then out[#out + 1] = b end
      end
    end
  end
  return out
end

-- Scans the forms file instead of loading it: it is only read when a word is not a headword, and holding
-- its hundreds of thousands of lines in memory would cost more than the scan.
local function form_bases(lang, word)
  local path = M.forms_path(lang)
  if not vim.uv.fs_stat(path) then return {} end
  local prefix = word .. "\t"
  for line in io.lines(path) do
    if line:sub(1, #prefix) == prefix then
      local out = {}
      for _, item in ipairs(vim.split(line:sub(#prefix + 1), "|", { plain = true })) do
        local lemma, pos = item:match("^(.*):([^:]*)$")
        out[#out + 1] = { word = lemma or item, pos = pos }
      end
      return out
    end
  end
  return {}
end

-- Every sense of `word`. A word that is not a headword is looked up as an inflected form, so "fui" returns
-- the entries for "ir" and "ser", each marked with the form it came from.
function M.define(idx, word)
  word = vim.trim(word)
  local entry = senses_of(idx, word)
  if entry then return { entry } end
  local lower = word:lower()
  local bases = form_bases(idx.lang, lower)
  if #bases == 0 then
    for _, b in ipairs(suffix_bases(idx, lower, idx.lang == "pt" and PT_ENDINGS or EN_ENDINGS)) do
      bases[#bases + 1] = { word = b }
    end
  end
  local out, by_word = {}, {}
  for _, base in ipairs(bases) do
    local e = by_word[base.word]
    if not e then
      e = senses_of(idx, base.word)
      if e then
        e.form, e.form_pos = word, {}
        by_word[base.word] = e
        out[#out + 1] = e
      end
    end
    if e and base.pos then e.form_pos[base.pos] = true end
  end
  for _, e in ipairs(out) do
    if next(e.form_pos) then
      local first, rest = {}, {}
      for _, sense in ipairs(e.senses) do
        table.insert(e.form_pos[sense.pos] and first or rest, sense)
      end
      e.senses = vim.list_extend(first, rest)
    end
    e.form_pos = nil
  end
  return #out > 0 and out or nil
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
