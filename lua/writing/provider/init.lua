local M = {}

function M.create(cfg)
  if cfg.type == "claude_cli" then return require("writing.provider.claude_cli").new(cfg) end
  if cfg.type == "openai" then return require("writing.provider.openai").new(cfg) end
  if cfg.type == "fake" then return require("writing.provider.fake").new(cfg) end
  error("unknown provider type: " .. tostring(cfg.type))
end

return M
