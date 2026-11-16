local M = {}

function M.new(cfg)
  local self = {}

  function self.request(req, cb)
    local cancelled = false
    vim.defer_fn(function()
      if cancelled then return end
      cb(nil, cfg.respond(req), {})
    end, cfg.delay or 0)
    return function() cancelled = true end
  end

  return self
end

return M
