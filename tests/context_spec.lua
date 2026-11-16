local context = require("writing.context")
local lang = require("writing.lang")

local function eq(a, b, msg)
  if not vim.deep_equal(a, b) then
    error((msg or "") .. " expected " .. vim.inspect(b) .. " got " .. vim.inspect(a), 2)
  end
end

return {
  {
    name = "splits sentences and flags unterminated tail",
    fn = function()
      local s = context.sentences("Hello world. How are you? Fine and you")
      eq(#s, 3)
      eq(s[1].text, "Hello world.")
      eq(s[2].text, "How are you?")
      eq(s[3].text, "Fine and you")
      eq(s[3].terminated, false)
    end,
  },
  {
    name = "does not split on decimals",
    fn = function()
      eq(#context.sentences("It costs 3.50 euros today."), 1)
    end,
  },
  {
    name = "word under cursor in normal mode gives synonyms",
    fn = function()
      local c = context.analyze({ "The weather is lovely today." }, 1, 5, false)
      eq(c.kind, "synonyms")
      eq(c.target, "weather")
      eq(c.scol, 4)
      eq(c.ecol, 11)
    end,
  },
  {
    name = "handles accented words",
    fn = function()
      local c = context.analyze({ "A coração é grande." }, 1, 4, false)
      eq(c.target, "coração")
    end,
  },
  {
    name = "cursor on period gives sentence variations",
    fn = function()
      local line = "First one. Second one is here."
      local c = context.analyze({ line }, 1, #line - 1, false)
      eq(c.kind, "variations")
      eq(c.target, "Second one is here.")
      eq(c.previous, "First one.")
    end,
  },
  {
    name = "insert mode right after period gives variations",
    fn = function()
      local line = "I wrote this."
      local c = context.analyze({ line }, 1, #line, true)
      eq(c.kind, "variations")
    end,
  },
  {
    name = "a space after the period means a new sentence, so no variations",
    fn = function()
      local line = "I wrote this. "
      eq(context.analyze({ line }, 1, #line, true), nil)
      eq(context.analyze({ line }, 1, #line - 1, false), nil)
    end,
  },
  {
    name = "insert mode mid-word gives nothing",
    fn = function()
      eq(context.analyze({ "I wrote thi" }, 1, 11, true), nil)
    end,
  },
  {
    name = "previous sentence comes from previous line",
    fn = function()
      local c = context.analyze({ "Before it all.", "Then this happened." }, 2, 18, false)
      eq(c.previous, "Before it all.")
    end,
  },
  {
    name = "paragraph with neighbours",
    fn = function()
      local lines = { "one", "", "two a", "two b", "", "three" }
      local p = context.paragraph(lines, 3)
      eq(p.first, 3)
      eq(p.last, 4)
      eq(p.target, "two a\ntwo b")
      eq(p.neighbours, { "one", "three" })
    end,
  },
  {
    name = "language detection",
    fn = function()
      eq(lang.detect("Isto não é uma frase muito boa."), "pt")
      eq(lang.detect("This is not a very good sentence."), "en")
    end,
  },
  {
    name = "misspelled word under cursor is spelling, not synonyms",
    fn = function()
      local bad = function(w) return w == "teh" end
      local c = context.analyze({ "I like teh weather." }, 1, 8, false, bad)
      eq(c.kind, "spelling")
      eq(c.target, "teh")
      eq(context.analyze({ "I like the weather." }, 1, 8, false, bad).kind, "synonyms")
    end,
  },
  {
    name = "insert mode right after a misspelled word and space gives spelling",
    fn = function()
      local bad = function(w) return w == "teh" end
      local line = "I like teh "
      local c = context.analyze({ line }, 1, #line, true, bad)
      eq(c.kind, "spelling")
      eq(c.scol, 7)
      eq(c.ecol, 10)
      eq(context.analyze({ "I like teh" }, 1, 10, true, bad), nil)
    end,
  },
  {
    name = "selection of several words becomes a selection context with sentence",
    fn = function()
      local lines = { "Intro. She walked quickly to the old station today." }
      local c = context.selection(lines, 1, 18, 36, 2)
      eq(c.kind, "selection")
      eq(c.target, "quickly to the old")
      eq(c.sentence, "She walked quickly to the old station today.")
      eq(c.previous, "Intro.")
    end,
  },
  {
    name = "selection trims whitespace and needs enough words",
    fn = function()
      local lines = { "She walked quickly home." }
      local c = context.selection(lines, 1, 3, 18, 2)
      eq(c.target, "walked quickly")
      eq(c.scol, 4)
      eq(context.selection(lines, 1, 4, 10, 2), nil)
      eq(context.selection(lines, 1, 4, 10, 1).target, "walked")
    end,
  },
}
