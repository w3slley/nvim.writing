local M = {}

local PT = {}
for w in ([[de da do das dos que não uma um para com por os as em no na nos nas é são foi ser está estão mas ou se como mais também já muito isto isso esta este aqui onde quando porque pelo pela às ao aos entretanto porém contudo todavia então assim depois antes sempre nunca ainda agora hoje ontem amanhã mesmo tem têm há ter fazer fui meu minha seu sua nosso ela ele eu nós você vocês bom boa tempo casa dia mas pois logo portanto embora enquanto durante sobre entre sem até desde segundo conforme apesar além aliás ora]]):gmatch("%S+") do
  PT[w] = true
end

local EN = {}
for w in ([[the of and to in is are was were be been that this it for with as on at by from or an not but have has had you your we they he she his her what when where which will would can could]]):gmatch("%S+") do
  EN[w] = true
end

-- `fallback` decides when the text has no clue either way, such as a single word.
function M.detect(text, fallback)
  local pt, en = 0, 0
  local lower = text:lower()
  for w in lower:gmatch("[%a\128-\255]+") do
    if PT[w] then pt = pt + 1 end
    if EN[w] then en = en + 1 end
  end
  if lower:find("[ãõçáéíóúâêô]") then pt = pt + 2 end
  if lower:find("[a-z]nh[ao]") or lower:find("[a-z]lh[ao]") or lower:find("%a+mente%f[%A]") then pt = pt + 1 end
  if pt > en then return "pt" end
  if en > pt then return "en" end
  return fallback or "en"
end

return M
