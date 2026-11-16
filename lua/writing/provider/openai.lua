local log = require("writing.log")
local prompts = require("writing.prompts")

local M = {}

function M.new(cfg)
  local self = {}

  self.lines = true

  local function stream_request(req, key, cb, on_partial)
    local started = vim.uv.hrtime()
    local cancelled = false
    local body = vim.json.encode(vim.tbl_extend("force", {
      model = cfg.model,
      temperature = req.temperature or cfg.temperature or 0.7,
      max_tokens = req.max_tokens,
      stream = true,
      messages = {
        { role = "system", content = req.system },
        { role = "user", content = req.user },
      },
    }, cfg.extra or {}))

    local args = {
      "curl", "-sS", "-N", "--keepalive-time", "60",
      "-m", tostring(math.floor((cfg.timeout or 20000) / 1000)),
      "-H", "Content-Type: application/json",
      "-d", "@-",
      cfg.url,
    }
    if key then vim.list_extend(args, { "-H", "Authorization: Bearer " .. key }) end

    local buffer, text, raw, finish_reason, api_error, ttft, emitted = "", "", "", nil, nil, nil, 0

    local function consume(line)
      local payload = line:match("^data:%s*(.*)$")
      if not payload then
        raw = raw .. line
        return
      end
      if payload == "[DONE]" then return end
      local ok, decoded = pcall(vim.json.decode, payload)
      if not ok or type(decoded) ~= "table" then return end
      if decoded.error then
        api_error = decoded.error.message or "api error"
        return
      end
      local choice = decoded.choices and decoded.choices[1]
      if not choice then return end
      local delta = choice.delta and choice.delta.content
      if type(delta) == "string" and delta ~= "" then
        ttft = ttft or math.floor((vim.uv.hrtime() - started) / 1e6)
        text = text .. delta
      end
      if type(choice.finish_reason) == "string" then finish_reason = choice.finish_reason end
    end

    local function on_stdout(_, data)
      if not data then return end
      vim.schedule(function()
        if cancelled then return end
        buffer = buffer .. data
        while true do
          local line, rest = buffer:match("^(.-)\r?\n(.*)$")
          if not line then break end
          buffer = rest
          consume(line)
        end
        if on_partial then
          local complete = text:match("^(.*\n)") or ""
          local items = prompts.split_lines(complete)
          if #items > emitted then
            emitted = #items
            on_partial({ items = items }, { ttft_ms = ttft })
          end
        end
      end)
    end

    local function finish(err, tbl, meta)
      if cancelled then return end
      log.write({
        event = "request", provider = "openai", model = cfg.model, kind = req.kind, language = req.language,
        ttft_ms = ttft, total_ms = math.floor((vim.uv.hrtime() - started) / 1e6), error = err,
      })
      cb(err, tbl, meta)
    end

    local ok, proc = pcall(vim.system, args, { text = true, stdin = body, stdout = on_stdout }, function(res)
      vim.schedule(function()
        if cancelled then return end
        if buffer ~= "" then consume(buffer) end
        if res.code ~= 0 then
          return finish(vim.trim(res.stderr or "") ~= "" and vim.trim(res.stderr) or "curl failed")
        end
        if api_error then return finish(api_error) end
        local items = prompts.split_lines(text)
        if finish_reason == "length" and not text:match("\n$") then table.remove(items) end
        if #items == 0 then
          local decoded_ok, decoded = pcall(vim.json.decode, raw)
          if decoded_ok and type(decoded) == "table" and decoded.error then
            return finish(type(decoded.error) == "table" and decoded.error.message or tostring(decoded.error))
          end
          return finish("empty response")
        end
        finish(nil, { items = items }, { ttft_ms = ttft })
      end)
    end)

    if not ok then
      vim.schedule(function() cb("cannot start curl") end)
      return function() cancelled = true end
    end
    return function()
      cancelled = true
      pcall(proc.kill, proc, 15)
    end
  end

  function self.request(req, cb, on_partial)
    local key = cfg.api_key_env and vim.env[cfg.api_key_env] or nil
    if cfg.api_key_env and (not key or key == "") then
      vim.schedule(function() cb("missing " .. tostring(cfg.api_key_env)) end)
      return function() end
    end

    if req.lines then return stream_request(req, key, cb, on_partial) end

    local started = vim.uv.hrtime()
    local cancelled = false
    local body = vim.json.encode(vim.tbl_extend("force", {
      model = cfg.model,
      temperature = req.temperature or cfg.temperature or 0.7,
      response_format = { type = "json_object" },
      messages = {
        { role = "system", content = req.system .. "\n\nReply with JSON only, in this shape: " .. req.format_hint },
        { role = "user", content = req.user },
      },
    }, cfg.extra or {}))

    local args = {
      "curl", "-sS", "--keepalive-time", "60",
      "-m", tostring(math.floor((cfg.timeout or 20000) / 1000)),
      "-H", "Content-Type: application/json",
      "-w", "\n%{time_starttransfer}",
      "-d", "@-",
      cfg.url,
    }
    if key then vim.list_extend(args, { "-H", "Authorization: Bearer " .. key }) end

    local function finish(err, tbl, meta)
      vim.schedule(function()
        if cancelled then return end
        log.write({
          event = "request", provider = "openai", model = cfg.model, kind = req.kind, language = req.language,
          ttft_ms = meta and meta.ttft_ms, total_ms = math.floor((vim.uv.hrtime() - started) / 1e6), error = err,
        })
        cb(err, tbl, meta)
      end)
    end

    local ok, proc = pcall(vim.system, args, { text = true, stdin = body }, function(res)
      if cancelled then return end
      if res.code ~= 0 then return finish(vim.trim(res.stderr or "") ~= "" and vim.trim(res.stderr) or "curl failed") end
      local payload, ttfb = res.stdout:match("^(.*)\n([%d%.]+)$")
      local decoded_ok, decoded = pcall(vim.json.decode, payload or res.stdout)
      if not decoded_ok or type(decoded) ~= "table" then return finish("invalid response") end
      if decoded.error then return finish(decoded.error.message or "api error") end
      local content = decoded.choices and decoded.choices[1] and decoded.choices[1].message.content
      local parsed_ok, parsed = pcall(vim.json.decode, content or "")
      if not parsed_ok or type(parsed) ~= "table" then return finish("invalid model json") end
      finish(nil, parsed, { ttft_ms = ttfb and math.floor(tonumber(ttfb) * 1000) or nil })
    end)

    if not ok then
      vim.schedule(function() cb("cannot start curl") end)
      return function() cancelled = true end
    end
    return function()
      cancelled = true
      pcall(proc.kill, proc, 15)
    end
  end

  return self
end

return M
