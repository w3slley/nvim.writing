local Core = require("writing.core")
local config = require("writing.config").resolve({})

local function eq(a, b, msg)
  if not vim.deep_equal(a, b) then
    error((msg or "") .. " expected " .. vim.inspect(b) .. " got " .. vim.inspect(a), 2)
  end
end

local function harness(responder)
  local h = { now = 0, timers = {}, calls = {}, views = {}, applied = {}, logs = {} }

  function h.advance(ms)
    local target = h.now + ms
    while true do
      local next_t
      for _, t in ipairs(h.timers) do
        if not t.dead and (not next_t or t.at < next_t.at) then next_t = t end
      end
      if not next_t or next_t.at > target then break end
      h.now = next_t.at
      next_t.dead = true
      next_t.fn()
    end
    h.now = target
  end

  local function make_provider(name)
    return {
      request = function(req, cb)
        local call = { tier = name, req = req, cb = cb, cancelled = false }
        h.calls[#h.calls + 1] = call
        if responder then responder(call) end
        return function() call.cancelled = true end
      end,
    }
  end

  h.core = Core.new({
    config = config,
    providers = { fast = make_provider("fast"), strong = make_provider("strong") },
    timer = {
      start = function(ms, fn)
        local t = { at = h.now + ms, fn = fn }
        h.timers[#h.timers + 1] = t
        return function() t.dead = true end
      end,
    },
    clock = function() return h.now end,
    on_change = function(v) h.views[#h.views + 1] = vim.deepcopy(v.status) end,
    apply = function(edit)
      h.applied[#h.applied + 1] = edit
      return { tick = 99, row = 1, col = 0 }
    end,
    log = function(e) h.logs[#h.logs + 1] = e end,
  })
  return h
end

local function word_ctx(text)
  return { kind = "synonyms", row = 1, scol = 0, ecol = #text, target = text, sentence = "A " .. text .. " day." }
end

local function sentence_ctx()
  return { kind = "variations", row = 1, scol = 0, ecol = 20, target = "The cat sat on the mat.", sentence = "The cat sat on the mat." }
end

local function reply(call, items)
  call.cb(nil, { items = items }, {})
end

return {
  {
    name = "word rest fires after delay, not before",
    fn = function()
      local h = harness()
      h.core:on_event({ tick = 1, row = 1, col = 2, insert = false, context = word_ctx("lovely") })
      h.advance(699)
      eq(#h.calls, 0)
      h.advance(2)
      eq(#h.calls, 1)
      eq(h.calls[1].tier, "fast")
    end,
  },
  {
    name = "typing cancels pending timer and in-flight request",
    fn = function()
      local h = harness()
      h.core:on_event({ tick = 1, row = 1, col = 2, insert = false, context = word_ctx("lovely") })
      h.advance(800)
      eq(#h.calls, 1)
      h.core:on_event({ tick = 2, row = 1, col = 3, insert = true, context = nil })
      eq(h.calls[1].cancelled, true)
      eq(h.core.view.status, "idle")
    end,
  },
  {
    name = "stale response is discarded",
    fn = function()
      local h = harness()
      h.core:on_event({ tick = 1, row = 1, col = 2, insert = false, context = word_ctx("lovely") })
      h.advance(800)
      h.core:on_event({ tick = 1, row = 2, col = 0, insert = false, context = nil })
      reply(h.calls[1], { "nice", "pleasant" })
      eq(h.core.view.status, "idle")
      eq(h.logs[#h.logs].event, "discarded")
    end,
  },
  {
    name = "response shows ready view and drops identical suggestion",
    fn = function()
      local h = harness()
      h.core:on_event({ tick = 1, row = 1, col = 2, insert = false, context = word_ctx("lovely") })
      h.advance(800)
      reply(h.calls[1], { "lovely", "nice", "pleasant" })
      eq(h.core.view.status, "ready")
      eq(#h.core.view.items, 2)
    end,
  },
  {
    name = "fast tier error falls back once to strong tier",
    fn = function()
      local h = harness()
      h.core:on_event({ tick = 1, row = 1, col = 2, insert = false, context = word_ctx("lovely") })
      h.advance(800)
      h.calls[1].cb("timeout")
      eq(#h.calls, 2)
      eq(h.calls[2].tier, "strong")
      h.calls[2].cb("boom")
      eq(h.core.view.status, "error")
      eq(#h.calls, 2)
    end,
  },
  {
    name = "ignore remembers the target at that revision",
    fn = function()
      local h = harness()
      local ctx = word_ctx("lovely")
      h.core:on_event({ tick = 1, row = 1, col = 2, insert = false, context = ctx })
      h.advance(800)
      reply(h.calls[1], { "nice" })
      h.core:ignore()
      eq(h.core.view.status, "idle")
      h.core:on_event({ tick = 1, row = 1, col = 3, insert = false, context = ctx })
      h.advance(2000)
      eq(#h.calls, 1)
      h.core:on_event({ tick = 2, row = 1, col = 3, insert = false, context = ctx })
      h.advance(800)
      eq(h.core.view.status, "ready")
      eq(#h.calls, 1)
    end,
  },
  {
    name = "insert mode never schedules a word suggestion path",
    fn = function()
      local h = harness()
      h.core:on_event({ tick = 1, row = 1, col = 2, insert = true, context = nil })
      h.advance(5000)
      eq(#h.calls, 0)
    end,
  },
  {
    name = "manual-only and hidden suppress ambient triggers",
    fn = function()
      local h = harness()
      h.core:toggle_manual()
      h.core:on_event({ tick = 1, row = 1, col = 2, insert = false, context = word_ctx("lovely") })
      h.advance(2000)
      eq(#h.calls, 0)
      h.core:toggle_manual()
      h.core:toggle()
      h.core:on_event({ tick = 2, row = 1, col = 2, insert = false, context = word_ctx("lovely") })
      h.advance(2000)
      eq(#h.calls, 0)
    end,
  },
  {
    name = "repeated request is served from cache",
    fn = function()
      local h = harness()
      local ctx = word_ctx("lovely")
      h.core:on_event({ tick = 1, row = 1, col = 2, insert = false, context = ctx })
      h.advance(800)
      reply(h.calls[1], { "nice" })
      h.core:on_event({ tick = 1, row = 2, col = 0, insert = false, context = nil })
      h.core:on_event({ tick = 1, row = 1, col = 2, insert = false, context = ctx })
      h.advance(800)
      eq(#h.calls, 1)
      eq(h.core.view.status, "ready")
    end,
  },
  {
    name = "accept applies selected item once and silences own events",
    fn = function()
      local h = harness()
      h.core:on_event({ tick = 1, row = 1, col = 2, insert = false, context = word_ctx("lovely") })
      h.advance(800)
      reply(h.calls[1], { "nice", "pleasant" })
      h.core:move(1)
      h.core:accept()
      eq(#h.applied, 1)
      eq(h.applied[1].text, "pleasant")
      eq(h.core.view.status, "idle")
      h.core:on_event({ tick = 99, row = 1, col = 0, insert = false, context = word_ctx("pleasant") })
      h.advance(2000)
      eq(#h.calls, 1)
    end,
  },
  {
    name = "make sense needs a second accept to apply",
    fn = function()
      local h = harness()
      local ctx = { kind = "make_sense", first = 1, last = 2, target = "a b c\nd e f", neighbours = {} }
      h.core:trigger(ctx)
      eq(h.calls[1].tier, "strong")
      h.calls[1].cb(nil, { plans = { { title = "One thread", text = "a b c, then d e f" } }, off_topic = { "e" } }, {})
      eq(h.core.view.status, "ready")
      eq(h.core.view.flags, { "e" })
      h.core:accept()
      eq(#h.applied, 0)
      h.core:accept()
      eq(#h.applied, 1)
    end,
  },
  {
    name = "regenerate bypasses cache and applies tweak",
    fn = function()
      local h = harness()
      local ctx = sentence_ctx()
      h.core:trigger(ctx)
      reply(h.calls[1], { "On the mat the cat sat." })
      h.core:regenerate("tighter")
      eq(#h.calls, 2)
      eq(h.calls[2].req.system:find("tighter", 1, true) ~= nil, true)
      eq(h.calls[2].req.system:find("On the mat the cat sat.", 1, true) ~= nil, true)
      reply(h.calls[2], { "On the mat the cat sat.", "The cat sat upon the mat." })
      eq(#h.core.view.items, 1)
      eq(h.core.view.items[1].text, "The cat sat upon the mat.")
    end,
  },
  {
    name = "rate cap blocks ambient requests",
    fn = function()
      local h = harness()
      h.core.config = vim.tbl_deep_extend("force", {}, config, { max_requests_per_minute = 1 })
      h.core:on_event({ tick = 1, row = 1, col = 2, insert = false, context = word_ctx("lovely") })
      h.advance(800)
      h.core:on_event({ tick = 2, row = 1, col = 2, insert = false, context = word_ctx("sunny") })
      h.advance(800)
      eq(#h.calls, 1)
    end,
  },
  {
    name = "ignoring an error view still remembers the target",
    fn = function()
      local h = harness()
      local ctx = word_ctx("lovely")
      h.core:on_event({ tick = 1, row = 1, col = 2, insert = false, context = ctx })
      h.advance(800)
      h.calls[1].cb("boom")
      h.calls[2].cb("boom")
      eq(h.core.view.status, "error")
      h.core:ignore()
      h.core:on_event({ tick = 1, row = 1, col = 3, insert = false, context = ctx })
      h.advance(2000)
      eq(#h.calls, 2)
      eq(h.core.view.status, "idle")
    end,
  },
  {
    name = "a misspelled word at rest is requested as synonyms flagged misspelled",
    fn = function()
      local h = harness()
      local ctx = { kind = "spelling", row = 1, scol = 0, ecol = 3, target = "teh", sentence = "teh cat" }
      h.core:on_event({ tick = 1, row = 1, col = 1, insert = false, context = ctx })
      h.advance(800)
      eq(#h.calls, 1)
      eq(h.calls[1].req.kind, "synonyms")
      eq(h.calls[1].req.system:find("misspelled", 1, true) ~= nil, true)
    end,
  },
  {
    name = "a misspelled word right after typing it stays quiet unless ambient spelling is on",
    fn = function()
      local h = harness()
      local ctx = { kind = "spelling", row = 1, scol = 0, ecol = 3, target = "teh", sentence = "teh " }
      h.core:on_event({ tick = 1, row = 1, col = 4, insert = true, context = ctx })
      h.advance(2000)
      eq(#h.calls, 0)
    end,
  },
}
