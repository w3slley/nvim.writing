local log = require("writing.log")

local M = {}

function M.new(cfg)
  local self = {}

  function self.request(req, cb)
    local key = cfg.api_key_env and vim.env[cfg.api_key_env] or nil
    if cfg.api_key_env and (not key or key == "") then
      vim.schedule(function() cb("missing " .. tostring(cfg.api_key_env)) end)
      return function() end
    end

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
