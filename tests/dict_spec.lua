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

local PT_LINES = {
  "subst.\tsaudade\tlembrança de pessoas ou coisas distantes, acompanhada da vontade de tornar a vê-las\tSentimento",
  "subst.\tclaustrofobia\taversão mórbida aos espaços fechados\t",
  "adj.\tefémero\tque é de curta duração\tbreve passageiro",
  "verbo\tvaguear\tandar sem destino\tdeambular",
}

local function pt_index() return dict.build(PT_LINES, nil, "pt") end

local function entry(e)
  return vim.json.encode(vim.tbl_extend("keep", e, { lang_code = "pt" }))
end

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
  { name = "portuguese stem folds accents, plurals and verb endings", fn = function()
    for _, pair in ipairs({
      { "fechados", "fechar" }, { "espaços", "espaço" }, { "recordação", "recordar" }, { "rápido", "rapidamente" },
      { "aversões", "aversão" }, { "caminhando", "caminhar" },
    }) do
      eq(dict.stem(pair[1], "pt"), dict.stem(pair[2], "pt"), pair[1] .. "/" .. pair[2])
    end
  end },
  { name = "portuguese tokens drop stop words and clitics", fn = function()
    eq(dict.tokens("Medo de espaços fechados; diz-se do que é locomover-se", "pt"), { "med", "espac", "fech", "locomov" })
  end },
  { name = "portuguese search matches accentless and inflected descriptions", fn = function()
    eq(dict.search(pt_index(), "medo de espaco fechado", 1)[1].words, { "claustrofobia" })
    eq(dict.search(pt_index(), "andar sem destino", 1)[1].words, { "vaguear" })
  end },
  { name = "lookup maps another accent spelling onto the dictionary's", fn = function()
    local hit = dict.lookup(pt_index(), "efêmero", "")
    eq(hit.word, "efémero")
    eq(hit.definition, "que é de curta duração")
    eq(dict.lookup(pt_index(), "autocarro", ""), nil)
  end },
  { name = "portuguese convert keeps PT-PT senses and resolves cross-references", fn = function()
    local path = vim.fn.tempname()
    vim.fn.writefile({
      entry({ word = "comboio", pos = "noun", synonyms = { { word = "trem", tags = { "Brazil" } }, { word = "combói" } },
        senses = { { glosses = { "meio de transporte ferroviário" }, tags = { "Portugal" } } } }),
      entry({ word = "trem", pos = "noun", senses = { { glosses = { "meio de transporte ferroviário" }, tags = { "Brazil" } },
        { glosses = { "bagagem" } } } }),
      '{"word": "fui", "lang_code": "pt", "pos": "verb", "senses": [{"glosses": ["pretérito de ir"], "form_of": [{"word": "ir"}]}, '
        .. '{"glosses": ["pretérito de ser"], "form_of": [{"word": "ser"}]}]}',
      '{"word": "andava", "lang_code": "pt", "pos": "verb", "senses": [{"glosses": ["imperfeito de andar"], "form_of": [{"word": "andar"}]}]}',
      entry({ word = "económico", pos = "adj", senses = { { glosses = { "que gasta pouco" } } } }),
      entry({ word = "econômico", pos = "adj", senses = { { glosses = { "que gasta pouco" } } } }),
      entry({ word = "receção", pos = "noun", senses = { { glosses = { "vide recepção" } } } }),
      entry({ word = "recepção", pos = "noun", senses = { { glosses = { "ato de receber" } } } }),
      entry({ word = "dog", pos = "noun", lang_code = "en", senses = { { glosses = { "cão" } } } }),
    }, path)
    local lines, forms = dict.convert_pt(path)
    vim.fn.delete(path)
    eq(lines, {
      "subst.\tcomboio\tmeio de transporte ferroviário\tcombói",
      "subst.\ttrem\tbagagem\t",
      "adj.\teconómico\tque gasta pouco\t",
      "subst.\treceção\tato de receber\t",
      "subst.\trecepção\tato de receber\t",
    }, "senses keep the source order")
    eq(forms, { "andava\tandar:verbo", "fui\tir:verbo|ser:verbo" })
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
  { name = "merge keeps room for dictionary matches when the model fills the list", fn = function()
    local idx = index()
    local q = "a longing for the past"
    local reply = { items = { "pessimist", "cynic", "ephemeral", "wander" } }
    local out = describe.merge(idx, q, describe.candidates(idx, q, 5), reply, 3, 1)
    eq(words(out), { "pessimist", "cynic", "nostalgia" })
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
  { name = "a portuguese request asks for PT-PT words", fn = function()
    local req = describe.request("medo de espaços fechados", { lang = "pt" })
    eq(req.language, "pt")
    assert(req.system:find("PT-PT", 1, true), req.system)
    eq(describe.request("fear of closed spaces").language, "en")
  end },
}
