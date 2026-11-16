local dict = require("writing.dict")

local M = {}

-- The model never sees the dictionary candidates: shown a list, small models just echo it back. It guesses
-- freely and the dictionary then acts as the filter, which is what keeps invented words out.
local SYSTEM = "You help a writer find the word they have in mind from a description. Give the %d single words "
  .. "that best match it, best first. Only real dictionary words, never invented ones, and never a word that is "
  .. "already in the description.%s Reply only with JSON in this shape: {\"items\":[\"word\",\"word\"]}"

local LANG_RULE = {
  en = " The words must be English.",
  pt = " The description is in Portuguese: the words must be European Portuguese (PT-PT), spelled with the new "
    .. "orthography (Acordo Ortográfico), never Brazilian terms or spellings.",
}

local function query_words(query)
  local out = {}
  for w in query:lower():gmatch("[%a\128-\255'%-]+") do out[w] = true end
  return out
end

function M.candidates(idx, query, n)
  local out, seen = {}, {}
  for _, r in ipairs(dict.search(idx, query, n)) do
    for i = 1, math.min(2, #r.words) do
      local key = r.words[i]:lower()
      if not seen[key] then
        seen[key] = true
        out[#out + 1] = { word = r.words[i], pos = r.pos, definition = r.definition, source = "dictionary" }
      end
    end
    if #out >= n then break end
  end
  return out
end

function M.request(query, opts)
  opts = opts or {}
  return {
    kind = "describe",
    tier = "fast",
    language = opts.lang or "en",
    system = SYSTEM:format(opts.guesses or 8, LANG_RULE[opts.lang] or LANG_RULE.en),
    user = "Description: " .. query,
    format_hint = '{"items":["word","word"]}',
    schema = {
      type = "object",
      properties = { items = { type = "array", items = { type = "string" } } },
      required = { "items" },
    },
    temperature = opts.temperature or 0.2,
  }
end

-- `reserve` slots are kept for dictionary matches, so a model that fills the whole list cannot hide them.
function M.merge(idx, query, candidates, reply, limit, reserve)
  local skip = query_words(query)
  local scores = dict.scores(idx, query)
  local seen = {}
  local function fresh(item)
    local key = item.word:lower()
    if seen[key] or skip[key] then return false end
    seen[key] = true
    return true
  end
  local model, dictionary = {}, {}
  local guesses = type(reply) == "table" and type(reply.items) == "table" and reply.items or {}
  for _, w in ipairs(guesses) do
    if type(w) == "string" then
      local found = dict.lookup(idx, w, query, scores)
      if found and fresh(found) then model[#model + 1] = vim.tbl_extend("force", found, { source = "model" }) end
    end
  end
  for _, c in ipairs(candidates) do
    if fresh(c) then dictionary[#dictionary + 1] = c end
  end
  local out = {}
  local n_model = math.min(#model, limit - math.min(reserve or 3, #dictionary))
  for i = 1, n_model do out[#out + 1] = model[i] end
  for _, c in ipairs(dictionary) do
    if #out >= limit then break end
    out[#out + 1] = c
  end
  return out
end

return M
