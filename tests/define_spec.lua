local dict = require("writing.dict")
local define = require("writing.define")

local function eq(a, b, msg)
  if not vim.deep_equal(a, b) then
    error((msg or "") .. " expected " .. vim.inspect(b) .. " got " .. vim.inspect(a), 2)
  end
end

local INDEX = {
  en = dict.build({
    "noun\tnostalgia\tlonging for something past\t",
    "verb\twander|roam\tmove about aimlessly or without any destination\t",
    "verb\twander|stray\tbe sexually unfaithful to one's partner\t",
  }, nil, "en"),
  pt = dict.build({
    "subst.\tsaudade\tlembrança de pessoas ou coisas distantes\t",
    "subst.\tsaudade\tmemória ou recordação grata\t",
    "adj.\tefémero\tque é de curta duração\t",
    "adj.\tfechado\tque se fechou\t",
  }, nil, "pt"),
}

local function index(l) return INDEX[l] end

return {
  { name = "lookup tries the context's language first, then the other", fn = function()
    local entries, l = define.lookup("saudade", "O tempo está muito bonito hoje", { index = index })
    eq(l, "pt")
    eq(#entries[1].senses, 2)
    eq(entries[1].senses[1].definition, "lembrança de pessoas ou coisas distantes", "the main sense stays first")
    local _, l2 = define.lookup("nostalgia", "O tempo está muito bonito hoje", { index = index })
    eq(l2, "en", "an English word in Portuguese text")
  end },
  { name = "lookup reads inflected forms and other accent spellings", fn = function()
    local entries = define.lookup("wandered", "I wandered home", { index = index })
    eq(entries[1].word, "wander")
    eq(entries[1].form, "wandered")
    eq(define.lookup("fechados", "estão fechados", { index = index })[1].word, "fechado")
    eq(define.lookup("efêmero", "é muito efêmero", { index = index })[1].word, "efémero")
  end },
  { name = "lookup says whether the word or the dictionaries are missing", fn = function()
    eq(select(2, define.lookup("xyzzy", "", { index = index })), "missing")
    eq(select(2, define.lookup("xyzzy", "", { index = function() return nil end })), "no_dictionary")
  end },
  { name = "senses follow the dictionary's rank for that word", fn = function()
    local idx = dict.build({
      "noun\tcat|Caterpillar\ta large tracked vehicle\t\t5|1",
      "noun\tcat|true cat\tfeline mammal\t\t1|1",
    }, nil, "en")
    local e = define.lookup("cat", "", { index = function(l) return l == "en" and idx or nil end })[1]
    eq(e.senses[1].definition, "feline mammal")
    eq(e.senses[2].synonyms, { "Caterpillar" })
  end },
  { name = "english convert keeps sense ranks and irregular forms", fn = function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    vim.fn.writefile({ vim.json.encode({
      ["1-n"] = { members = { "cat" }, definition = { "feline mammal" }, partOfSpeech = "n" },
      ["2-n"] = { members = { "cat", "Caterpillar" }, definition = { "a tracked vehicle" }, partOfSpeech = "n" },
      ["3-v"] = { members = { "buy" }, definition = { "obtain by purchase" }, partOfSpeech = "v" },
    }) }, dir .. "/noun.animal.json")
    vim.fn.writefile({ vim.json.encode({
      cat = { n = { sense = { { synset = "1-n" }, { synset = "2-n" } } } },
      buy = { v = { form = { "bought" }, sense = { { synset = "3-v" } } } },
    }) }, dir .. "/entries-c.json")
    local lines, forms = dict.convert(dir)
    vim.fn.delete(dir, "rf")
    eq(lines, {
      "noun\tcat\tfeline mammal\tanimal\t1",
      "noun\tcat|Caterpillar\ta tracked vehicle\tanimal\t2|99",
      "verb\tbuy\tobtain by purchase\tanimal\t1",
    })
    eq(forms, { "bought\tbuy:verb" })
  end },
  { name = "the modal shows the meaning of the typed word and closes back to the text", fn = function()
    vim.cmd("silent! %bwipeout!")
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "O tempo está muito bonito hoje" })
    define.open(nil, { index = index, preload = false })
    local s = define._state()
    eq(vim.api.nvim_buf_get_lines(s.result_buf, 0, -1, false), { "Type a word to see its meaning" })
    vim.api.nvim_buf_set_lines(s.input_buf, 0, -1, false, { "saudade" })
    define.search()
    local rows = vim.api.nvim_buf_get_lines(s.result_buf, 0, -1, false)
    eq(rows[1], "**saudade**")
    eq(rows[3], "1. lembrança de pessoas ou coisas distantes")
    eq(vim.api.nvim_win_get_config(s.result_win).footer[1][1], " PT ")
    vim.api.nvim_buf_set_lines(s.input_buf, 0, -1, false, { "xyzzy" })
    define.search()
    eq(vim.api.nvim_buf_get_lines(s.result_buf, 0, -1, false), { '"xyzzy" is not in the dictionary' })
    define.close()
    eq(define.is_open(), false)
    eq(vim.api.nvim_get_current_buf(), buf)
  end },
  { name = "the modal updates as the word is typed", fn = function()
    define.open(nil, { index = index, preload = false, delay = 10 })
    local s = define._state()
    vim.api.nvim_buf_set_lines(s.input_buf, 0, -1, false, { "nostalgia" })
    vim.api.nvim_exec_autocmds("TextChangedI", { buffer = s.input_buf })
    vim.wait(500, function() return vim.api.nvim_buf_get_lines(s.result_buf, 0, 1, false)[1] == "**nostalgia**" end, 5)
    eq(vim.api.nvim_buf_get_lines(s.result_buf, 0, 1, false)[1], "**nostalgia**")
    define.close()
  end },
  { name = "a word given up front is looked up at once", fn = function()
    define.open("fechados", { index = index, preload = false })
    eq(vim.api.nvim_buf_get_lines(define._state().result_buf, 0, 1, false)[1], "**fechados** → **fechado**")
    define.close()
  end },
  { name = "lines group senses by part of speech and show other members", fn = function()
    local entries = define.lookup("wandered", "I wandered", { index = index })
    eq(define.lines(entries, "en"), {
      "**wandered** → **wander**",
      "_verb_",
      "1. move about aimlessly or without any destination _(also: roam)_",
      "2. be sexually unfaithful to one's partner _(also: stray)_",
    })
  end },
}
