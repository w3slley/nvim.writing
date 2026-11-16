local dict = require("writing.dict")

local M = {}

-- The model never sees the dictionary candidates: shown a list, small models just echo it back. It guesses
-- freely and the dictionary then acts as the filter, which is what keeps invented words out.
local SYSTEM = "You help a writer find the word they have in mind from a description. Give the %d single words "
  .. "that best match it, best first. Only real dictionary words, never invented ones, and never a word that is "
  .. "already in the description. Reply only with JSON in this shape: {\"items\":[\"word\",\"word\"]}"

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
    language = "en",
    system = SYSTEM:format(opts.guesses or 8),
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

function M.merge(idx, query, candidates, reply, limit)
  local skip = query_words(query)
  local scores = dict.scores(idx, query)
  local out, seen = {}, {}
  local function add(item)
    local key = item.word:lower()
    if seen[key] or skip[key] then return end
    seen[key] = true
    out[#out + 1] = item
  end
  local guesses = type(reply) == "table" and type(reply.items) == "table" and reply.items or {}
  for _, w in ipairs(guesses) do
    if type(w) == "string" then
      local found = dict.lookup(idx, w, query, scores)
      if found then add(vim.tbl_extend("force", found, { source = "model" })) end
    end
  end
  for _, c in ipairs(candidates) do add(c) end
  while #out > limit do table.remove(out) end
  return out
end

return M
