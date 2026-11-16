local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root)
package.path = root .. "/?.lua;" .. package.path

local only = arg and arg[1]
local failed, total = 0, 0

for _, name in ipairs({ "context", "core", "buffer" }) do
  if not only or only == name then
    local tests = dofile(root .. "/tests/" .. name .. "_spec.lua")
    for _, t in ipairs(tests) do
      total = total + 1
      local ok, err = pcall(t.fn)
      if ok then
        print("ok   " .. name .. ": " .. t.name)
      else
        failed = failed + 1
        print("FAIL " .. name .. ": " .. t.name .. "\n     " .. tostring(err))
      end
    end
  end
end

print(("\n%d tests, %d failed"):format(total, failed))
vim.cmd(failed == 0 and "qa!" or "cq!")
