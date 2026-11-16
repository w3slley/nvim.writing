local prompts = require("writing.prompts")
local quality = require("writing.quality")

local Core = {}
Core.__index = Core

local CACHE_LIMIT = 200

function Core.new(opts)
  local self = setmetatable({}, Core)
  self.config = opts.config
  self.providers = opts.providers
  self.timer = opts.timer
  self.clock = opts.clock
  self.on_change = opts.on_change or function() end
  self.apply = opts.apply or function() end
  self.log = opts.log or function() end
  self.style = opts.style or function() return nil end
  self.spell = opts.spell or function() return {} end
  self.req_id = 0
  self.hidden = false
  self.manual_only = false
  self.ignored = {}
  self.cache = {}
  self.cache_size = 0
  self.stamps = {}
  self.view = { status = "idle" }
  return self
end

function Core:visible()
  local s = self.view.status
  return not self.hidden and (s == "loading" or s == "ready" or s == "error")
end

function Core:set_view(view)
  self.view = view
  self.on_change(view)
end

function Core:cancel_pending()
  if self.cancel_timer then
    self.cancel_timer()
    self.cancel_timer = nil
  end
  if self.cancel_request then
    self.cancel_request()
    self.cancel_request = nil
  end
  self.req_id = self.req_id + 1
end

local function ignore_key(ctx, tick)
  return ("%s:%d:%d:%s@%d"):format(ctx.kind, ctx.row or ctx.first, ctx.scol or 0, ctx.target, tick)
end

function Core:clear()
  if self.view.status ~= "idle" then self:set_view({ status = "idle" }) end
end

function Core:on_event(snap)
  local last = self.snap
  if self.quiet and self.quiet.tick == snap.tick and self.quiet.row == snap.row and self.quiet.col == snap.col then
    self.snap = snap
    return
  end
  self.quiet = nil
  if last and last.tick == snap.tick and last.row == snap.row and last.col == snap.col and last.insert == snap.insert then
    return
  end
  self.snap = snap
  self:cancel_pending()
  self:clear()

  if self.hidden or self.manual_only then return end
  local ctx = snap.context
  if not ctx or ctx.kind == "make_sense" then return end
  if ctx.kind == "spelling" and not self.config.spell.ambient then return end
  if self.ignored[ignore_key(ctx, snap.tick)] then return end

  local delay = ({ synonyms = self.config.delays.word, spelling = self.config.delays.spell })[ctx.kind]
    or self.config.delays.sentence
  local id = self.req_id
  self.cancel_timer = self.timer.start(delay, function()
    self.cancel_timer = nil
    if id ~= self.req_id then return end
    self:fire(ctx, { tick = snap.tick })
  end)
end

function Core:allow_request()
  local now = self.clock()
  local fresh = {}
  for _, t in ipairs(self.stamps) do
    if now - t < 60000 then fresh[#fresh + 1] = t end
  end
  self.stamps = fresh
  if #fresh >= self.config.max_requests_per_minute then return false end
  fresh[#fresh + 1] = now
  return true
end

function Core:remember(key, value)
  if self.cache_size >= CACHE_LIMIT then
    self.cache = {}
    self.cache_size = 0
  end
  self.cache[key] = value
  self.cache_size = self.cache_size + 1
end

function Core:fire(ctx, opts)
  opts = opts or {}
  local style = self.style()
  local cache_key = table.concat({ ctx.kind, ctx.target, ctx.previous or "", opts.tweak or "", style or "" }, "\1")

  self:cancel_pending()
  local id = self.req_id
  self.current = { ctx = ctx, opts = opts }

  if ctx.kind == "spelling" then
    local items = {}
    for _, w in ipairs(self.spell(ctx)) do items[#items + 1] = { text = w } end
    items = quality.filter(ctx, items)
    if #items == 0 then
      if opts.manual then
        self:set_view({ status = "error", kind = ctx.kind, ctx = ctx, target = ctx.target, message = "no spelling suggestions" })
      else
        self:clear()
      end
      return
    end
    self:set_view({
      status = "ready", kind = ctx.kind, ctx = ctx, target = ctx.target,
      items = items, flags = {}, index = 1, tick = opts.tick,
    })
    return
  end

  local cached = not opts.fresh and self.cache[cache_key]
  if cached then
    self:set_view({
      status = "ready", kind = ctx.kind, ctx = ctx, target = ctx.target,
      items = cached.items, flags = cached.flags, index = 1, tick = opts.tick,
    })
    return
  end

  if not self:allow_request() then
    if opts.manual then self:set_view({ status = "error", kind = ctx.kind, ctx = ctx, target = ctx.target, message = "rate limit reached" }) end
    return
  end

  local previous = self.view.status == "ready" and self.view.ctx == ctx and self.view or nil
  self:set_view({
    status = "loading", kind = ctx.kind, ctx = ctx, target = ctx.target,
    items = previous and previous.items or nil, flags = previous and previous.flags or nil,
    index = previous and previous.index or 1, tick = opts.tick,
  })

  local req = prompts.build(ctx, { counts = self.config.counts, style = style, tweak = opts.tweak })

  local function send(tier, retried)
    local provider = self.providers[tier]
    self.cancel_request = provider.request(req, function(err, tbl, meta)
      if id ~= self.req_id then
        self.log({ event = "discarded", kind = ctx.kind, tier = tier })
        return
      end
      self.cancel_request = nil
      local parsed
      if not err then
        parsed, err = prompts.parse(ctx.kind, tbl)
      end
      if err and tier == "fast" and not retried and self.providers.strong then
        self.log({ event = "fallback", kind = ctx.kind, error = tostring(err) })
        return send("strong", true)
      end
      if err then
        self:set_view({ status = "error", kind = ctx.kind, ctx = ctx, target = ctx.target, message = tostring(err) })
        return
      end
      local items = quality.filter(ctx, parsed.items)
      if #items == 0 then
        if opts.manual then
          self:set_view({ status = "error", kind = ctx.kind, ctx = ctx, target = ctx.target, message = "no usable suggestions" })
        else
          self:clear()
        end
        return
      end
      self:remember(cache_key, { items = items, flags = parsed.flags })
      self:set_view({
        status = "ready", kind = ctx.kind, ctx = ctx, target = ctx.target,
        items = items, flags = parsed.flags, index = 1, tick = opts.tick, meta = meta,
      })
    end)
  end

  send(req.tier, req.tier ~= "fast")
end

function Core:trigger(ctx, opts)
  if not ctx then return end
  self.hidden = false
  opts = vim.tbl_extend("force", { manual = true, tick = self.snap and self.snap.tick }, opts or {})
  self:fire(ctx, opts)
end

function Core:move(delta)
  local v = self.view
  if v.status ~= "ready" then return end
  local n = #v.items
  v.index = ((v.index - 1 + delta) % n) + 1
  v.confirmed = false
  self:set_view(v)
end

function Core:accept()
  local v = self.view
  if v.status ~= "ready" then return false end
  if v.kind == "make_sense" and not v.confirmed then
    v.confirmed = true
    self:set_view(v)
    return true
  end
  local item = v.items[v.index]
  self.log({ event = "accept", kind = v.kind, index = v.index })
  self:cancel_pending()
  self.quiet = self.apply({ ctx = v.ctx, text = item.text })
  self:set_view({ status = "idle" })
  return true
end

function Core:ignore()
  local v = self.view
  if not self:visible() then return false end
  if v.ctx and v.tick then self.ignored[ignore_key(v.ctx, v.tick)] = true end
  self.log({ event = "ignore", kind = v.kind })
  self:cancel_pending()
  self:set_view({ status = "idle" })
  return true
end

function Core:regenerate(tweak)
  local cur = self.current
  if not cur or self.view.status == "idle" then return false end
  self.log({ event = "regenerate", kind = cur.ctx.kind, tweak = tweak })
  self:fire(cur.ctx, vim.tbl_extend("force", cur.opts, { tweak = tweak or cur.opts.tweak, fresh = true, manual = true }))
  return true
end

function Core:toggle()
  self.hidden = not self.hidden
  if self.hidden then
    self:cancel_pending()
    self:set_view({ status = "idle" })
  end
end

function Core:toggle_manual()
  self.manual_only = not self.manual_only
  return self.manual_only
end

return Core
