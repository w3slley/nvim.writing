local M = {}

local path

function M.setup(file)
  path = file
  vim.fn.mkdir(vim.fn.fnamemodify(file, ":h"), "p")
end

function M.write(entry)
  if not path then return end
  entry.ts = os.date("!%Y-%m-%dT%H:%M:%SZ")
  local f = io.open(path, "a")
  if not f then return end
  f:write(vim.json.encode(entry), "\n")
  f:close()
end

return M
