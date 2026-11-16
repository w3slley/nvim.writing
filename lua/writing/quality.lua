local M = {}

local function normalize(s)
  return (s:lower():gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function words(s)
  local set, n = {}, 0
  for w in s:lower():gmatch("[%a\128-\255]+") do
    if not set[w] then
      set[w] = true
      n = n + 1
    end
  end
  return set, n
end

local function overlap(a, b)
  local sa, na = words(a)
  local sb, nb = words(b)
  if na == 0 or nb == 0 then return 0 end
  local shared = 0
  for w in pairs(sa) do
    if sb[w] then shared = shared + 1 end
  end
  return shared / math.min(na, nb)
end

function M.filter(ctx, items)
  local out, seen = {}, { [normalize(ctx.target)] = true }
  for _, item in ipairs(items) do
    local key = normalize(item.text)
    local keep = not seen[key]
    seen[key] = true
    if keep and ctx.kind == "variations" then
      local ratio = #item.text / math.max(#ctx.target, 1)
      keep = ratio >= 0.35 and ratio <= 3 and overlap(ctx.target, item.text) >= 0.15
    elseif keep and ctx.kind == "synonyms" then
      keep = select(2, item.text:gsub("%S+", "")) <= 3
    end
    if keep then out[#out + 1] = item end
  end
  return out
end

return M
