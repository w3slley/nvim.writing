local dict = require("writing.dict")
local describe = require("writing.describe")

local function eq(a, b, msg)
  if not vim.deep_equal(a, b) then
    error((msg or "") .. " expected " .. vim.inspect(b) .. " got " .. vim.inspect(a), 2)
  end
end

local LINES = {
  "noun\tnostalgia\tlonging for something past\tlonging feeling",
  "noun\tpessimist\ta person who expects the worst\tperson",
  "noun\tclaustrophobia\ta morbid fear of being closed in a confined space\tphobia state",
  "verb\twander|roam\tmove about aimlessly or without any destination\tmove motion",
  "noun\tCynic\ta member of a group of ancient Greek philosophers\tphilosopher person",
  "noun\tcynic|faultfinder\tsomeone who is critical of the motives of others\tunpleasant person",
  "adj\tephemeral|short-lived\tlasting a very short time\tadjective",
}

local function index() return dict.build(LINES) end

local function words(items)
  local out = {}
  for _, it in ipairs(items) do out[#out + 1] = it.word end
  return out
end

return {
  { name = "stem folds common suffixes", fn = function()
    for _, pair in ipairs({
      { "longing", "long" }, { "lasting", "lasts" }, { "spaces", "space" }, { "worries", "worry" },
      { "closed", "close" }, { "aimlessly", "aimless" }, { "stopped", "stop" },
    }) do
      eq(dict.stem(pair[1]), dict.stem(pair[2]), pair[1] .. "/" .. pair[2])
    end
  end },
  { name = "tokens drop stop words", fn = function()
    eq(dict.tokens("a feeling of longing for the past"), { "feel", "long", "past" })
  end },
  { name = "search ranks the matching definition first", fn = function()
    local r = dict.search(index(), "a longing for the past", 3)
    eq(r[1].words, { "nostalgia" })
    eq(dict.search(index(), "to walk aimlessly", 1)[1].words, { "wander", "roam" })
  end },
  { name = "search leaves out words already in the description", fn = function()
    local r = dict.search(index(), "something short-lived that lasts a very short time", 1)
    eq(r[1].words, { "ephemeral" })
  end },
  { name = "lookup rejects words not in the dictionary", fn = function()
    eq(dict.lookup(index(), "milden", "make less severe"), nil)
  end },
  { name = "lookup prefers the sense matching the guess's case", fn = function()
    local hit = dict.lookup(index(), "cynic", "someone who doubts others")
    eq(hit.word, "cynic")
    eq(hit.definition, "someone who is critical of the motives of others")
    eq(dict.lookup(index(), "Pessimist", "").word, "pessimist")
  end },
  { name = "merge keeps only dictionary words, model guesses first", fn = function()
    local idx = index()
    local q = "a longing for the past"
    local cands = describe.candidates(idx, q, 5)
    local out = describe.merge(idx, q, cands, { items = { "saudade", "pessimist", "nostalgia", "past" } }, 3)
    eq(words(out), { "pessimist", "nostalgia" })
    eq(out[1].source, "model")
    eq(out[1].definition, "a person who expects the worst")
  end },
  { name = "merge falls back to dictionary matches without a reply", fn = function()
    local idx = index()
    local q = "fear of a confined space"
    local out = describe.merge(idx, q, describe.candidates(idx, q, 5), nil, 2)
    eq(out[1].word, "claustrophobia")
    eq(out[1].source, "dictionary")
  end },
  { name = "request does not leak the candidates to the model", fn = function()
    local req = describe.request("a longing for the past", { guesses = 5 })
    eq(req.user, "Description: a longing for the past")
    assert(req.system:find("5 single words"), req.system)
  end },
}
