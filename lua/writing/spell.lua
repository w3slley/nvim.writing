local M = {}

local BASE_URL = "https://ftp.nluug.nl/pub/vim/runtime/spell/"

local function file_for(lang)
  return lang:match("^[^_]+") .. ".utf-8.spl"
end

local function site_dir()
  return vim.fn.stdpath("data") .. "/site"
end

function M.ensure_rtp()
  local site = site_dir()
  if vim.uv.fs_stat(site .. "/spell") and not vim.tbl_contains(vim.opt.runtimepath:get(), site) then
    vim.opt.runtimepath:append(site)
  end
end

function M.missing(langs)
  M.ensure_rtp()
  local out = {}
  for _, lang in ipairs(langs) do
    if #vim.api.nvim_get_runtime_file("spell/" .. file_for(lang), false) == 0 then out[#out + 1] = lang end
  end
  return out
end

function M.is_bad(word)
  local res = vim.fn.spellbadword(word)
  return res[1] ~= "" and res[2] == "bad"
end

function M.suggest(word, n)
  return vim.fn.spellsuggest(word, n)
end

function M.apply(buf, langs)
  vim.bo[buf].spelllang = table.concat(langs, ",")
end

function M.install(langs, on_done)
  local dir = vim.fn.stdpath("data") .. "/site/spell"
  vim.fn.mkdir(dir, "p")
  local pending = M.missing(langs)
  if #pending == 0 then return on_done(true) end
  local remaining = #pending
  local failed = false
  for _, lang in ipairs(pending) do
    local file = file_for(lang)
    vim.system({ "curl", "-sSfL", "-o", dir .. "/" .. file, BASE_URL .. file }, { text = true }, function(res)
      vim.schedule(function()
        if res.code ~= 0 then failed = true end
        remaining = remaining - 1
        if remaining == 0 then on_done(not failed) end
      end)
    end)
  end
end

return M
