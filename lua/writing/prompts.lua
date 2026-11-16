local lang = require("writing.lang")

local M = {}

local BASE = "You are a writing assistant inside a text editor. You only offer alternatives; the writer decides. "
  .. "Never invent facts the writer did not write. Reply only with JSON matching the schema."

local LANG_RULE = {
  en = "Write the alternatives in English.",
  pt = "Write the alternatives in European Portuguese (PT-PT) using the new orthography (Acordo Ortográfico). "
    .. "Avoid Brazilian vocabulary, spelling and constructions (use 'estou a fazer', not 'estou fazendo').",
}

local ITEMS_SCHEMA = {
  type = "object",
  properties = { items = { type = "array", items = { type = "string" } } },
  required = { "items" },
}

local PLANS_SCHEMA = {
  type = "object",
  properties = {
    plans = {
      type = "array",
      items = {
        type = "object",
        properties = { title = { type = "string" }, text = { type = "string" } },
        required = { "title", "text" },
      },
    },
    off_topic = { type = "array", items = { type = "string" } },
  },
  required = { "plans", "off_topic" },
}

local INSTRUCTIONS = {
  synonyms = function(n)
    return ("Give %d alternatives for the target word that can replace it directly in the sentence "
      .. "(same part of speech, same inflection). Single words or very short phrases, no explanations. "
      .. "Never include the target word itself."):format(n)
  end,
  variations = function(n)
    return ("Give %d rewrites of the target sentence. Keep its meaning but vary the structure, not just the wording. "
      .. "If a previous sentence is given and the target feels disconnected from it, at least one rewrite may link "
      .. "the two. Each rewrite is one complete sentence with its end punctuation, ready to replace the original."):format(n)
  end,
  spelling = function(n)
    return ("The target word is misspelled. Using the sentence for context, give %d likely intended words, spelled "
      .. "correctly, most likely first. Single words only, no explanations. Ignore any other typos elsewhere in the "
      .. "sentence; they are not the target."):format(n)
  end,
  selection = function(n)
    return ("Give %d replacements for the fragment. Each replacement is a phrase of similar length that takes the "
      .. "fragment's place inside the sentence, so the sentence stays grammatical and keeps its meaning. Return ONLY "
      .. "the replacement phrases, never the whole sentence. Example: sentence 'She walked quickly to the old "
      .. "station.', fragment 'walked quickly' gives items ['hurried', 'strolled briskly', 'made her way']."):format(n)
  end,
  make_sense = function(n)
    return ("The paragraph holds loose thoughts. Produce exactly %d plans. Plan 1 keeps one thread and rewrites the "
      .. "paragraph around the main idea. Plan 2 splits the paragraph into groups of related ideas, separated by a "
      .. "blank line. Each plan has a short title and the full rewritten text. Keep the writer's own words where "
      .. "possible. Also list in off_topic the fragments of the original that do not belong to the main thread, "
      .. "quoted exactly."):format(n)
  end,
}

local function sample_text(ctx)
  return ctx.target .. " " .. (ctx.sentence or "")
end

function M.build(ctx, opts)
  opts = opts or {}
  local counts = opts.counts or { synonyms = 4, variations = 3, make_sense = 2, selection = 3, spelling = 4 }
  local kind = ctx.kind
  local language = lang.detect(sample_text(ctx))

  local ask = kind == "make_sense" and counts[kind] or counts[kind] + 1
  local system = { BASE, LANG_RULE[language], INSTRUCTIONS[kind](ask) }
  if ctx.misspelled then
    system[#system + 1] = "The target word is misspelled. Work out which single word the writer meant and give "
      .. "alternatives for that word, spelled correctly. Ignore any other typos elsewhere in the sentence; they are "
      .. "not the target."
  end
  if opts.avoid and #opts.avoid > 0 then
    system[#system + 1] = "Already suggested, do not repeat or paraphrase these:\n- " .. table.concat(opts.avoid, "\n- ")
  end
  if opts.style and opts.style ~= "" then
    system[#system + 1] = "Writer's style note (follow it):\n" .. opts.style
  end

  local user
  if kind == "synonyms" or kind == "spelling" then
    local sentence = ctx.sentence
    if ctx.misspelled or kind == "spelling" then
      local at = sentence:find(ctx.target, 1, true)
      if at then
        local from = math.max(1, at - 30)
        local to = math.min(#sentence, at + #ctx.target + 30)
        sentence = sentence:sub(from, to):gsub("^%S*%s", from > 1 and "" or "%0"):gsub("%s%S*$", to < #sentence and "" or "%0")
      end
    end
    user = ("Target word: %s\nSentence: %s"):format(ctx.target, sentence)
  elseif kind == "selection" then
    user = ("Sentence: %s\nFragment to replace: %s"):format(ctx.sentence, ctx.target)
    if ctx.previous then user = user .. "\nPrevious sentence: " .. ctx.previous end
  elseif kind == "variations" then
    user = ("Target sentence: %s"):format(ctx.target)
    if ctx.previous then user = user .. "\nPrevious sentence: " .. ctx.previous end
  else
    user = "Paragraph:\n" .. ctx.target
    if ctx.neighbours and #ctx.neighbours > 0 then
      user = user .. "\n\nNeighbouring paragraphs for context only:\n" .. table.concat(ctx.neighbours, "\n---\n")
    end
  end

  return {
    kind = kind,
    tier = kind == "make_sense" and "strong" or "fast",
    language = language,
    system = table.concat(system, "\n\n"),
    user = user,
    schema = kind == "make_sense" and PLANS_SCHEMA or ITEMS_SCHEMA,
    temperature = opts.temperature,
    format_hint = kind == "make_sense" and '{"plans":[{"title":"...","text":"..."}],"off_topic":["..."]}'
      or '{"items":["...","..."]}',
  }
end

function M.parse(kind, tbl)
  if type(tbl) ~= "table" then return nil, "unexpected response" end
  if kind == "make_sense" then
    local items = {}
    for _, p in ipairs(tbl.plans or {}) do
      if type(p.text) == "string" and p.text ~= "" then
        items[#items + 1] = { text = p.text, label = p.title }
      end
    end
    return { items = items, flags = tbl.off_topic or {} }
  end
  local items = {}
  for _, s in ipairs(tbl.items or {}) do
    if type(s) == "string" and s:match("%S") then items[#items + 1] = { text = vim.trim(s) } end
  end
  return { items = items, flags = {} }
end

return M
