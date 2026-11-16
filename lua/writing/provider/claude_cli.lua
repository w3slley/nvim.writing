local log = require("writing.log")

local M = {}

function M.new(cfg)
  local self = {}
  local cwd = vim.fn.stdpath("cache")
  vim.fn.mkdir(cwd, "p")

  function self.request(req, cb)
    local started = vim.uv.hrtime()
    local cancelled = false
    local args = {
      cfg.command or "claude", "-p",
      "--model", cfg.model,
      "--tools", "",
      "--no-session-persistence",
      "--setting-sources", "",
      "--disable-slash-commands",
      "--strict-mcp-config",
      "--output-format", "json",
      "--json-schema", vim.json.encode(req.schema),
      "--system-prompt", req.system,
      req.user,
    }

    local function finish(err, tbl, meta)
      vim.schedule(function()
        if cancelled then return end
        local total = (vim.uv.hrtime() - started) / 1e6
        log.write({
          event = "request", provider = "claude_cli", model = cfg.model, kind = req.kind,
          language = req.language, ttft_ms = meta and meta.ttft_ms, total_ms = math.floor(total), error = err,
        })
        cb(err, tbl, meta)
      end)
    end

    local ok, proc = pcall(vim.system, args, { text = true, cwd = cwd, timeout = cfg.timeout or 20000 }, function(res)
      if cancelled then return end
      if res.code ~= 0 then
        local reason = res.signal ~= 0 and "timeout" or vim.trim(res.stderr or "") ~= "" and vim.trim(res.stderr) or ("exit " .. res.code)
        return finish(reason)
      end
      local decoded_ok, decoded = pcall(vim.json.decode, res.stdout)
      if not decoded_ok or type(decoded) ~= "table" then return finish("invalid cli output") end
      if decoded.is_error then return finish(decoded.result or "cli error") end
      if type(decoded.structured_output) ~= "table" then return finish("no structured output") end
      finish(nil, decoded.structured_output, { ttft_ms = decoded.ttft_ms, total_ms = decoded.duration_ms })
    end)

    if not ok then
      vim.schedule(function() cb("cannot start claude cli: " .. tostring(proc)) end)
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
