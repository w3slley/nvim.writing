local M = {}

local PT = {}
for w in ([[de da do das dos que não uma um para com por os as em no na nos nas é são foi ser está estão mas ou se como mais também já muito isto isso esta este aqui onde quando porque pelo pela às ao aos]]):gmatch("%S+") do
  PT[w] = true
end

local EN = {}
for w in ([[the of and to in is are was were be been that this it for with as on at by from or an not but have has had you your we they he she his her what when where which will would can could]]):gmatch("%S+") do
  EN[w] = true
end

function M.detect(text)
  local pt, en = 0, 0
  local lower = text:lower()
  for w in lower:gmatch("[%a\128-\255]+") do
    if PT[w] then pt = pt + 1 end
    if EN[w] then en = en + 1 end
  end
  if lower:find("[ãõçáéíóúâêô]") then pt = pt + 2 end
  if pt > en then return "pt" end
  return "en"
end

return M
