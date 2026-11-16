local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root)

local prompts = require("writing.prompts")
local context = require("writing.context")

local DEFAULT_TARGETS = table.concat({
  "groq-8b|https://api.groq.com/openai/v1/chat/completions|llama-3.1-8b-instant|GROQ_API_KEY",
  "groq-oss20b|https://api.groq.com/openai/v1/chat/completions|openai/gpt-oss-20b|GROQ_API_KEY",
  "cerebras|https://api.cerebras.ai/v1/chat/completions|llama3.1-8b|CEREBRAS_API_KEY",
}, ";")

local RUNS = tonumber(vim.env.BENCH_RUNS) or 2

local SAMPLES = {
  { "synonyms", "The weather is lovely today.", "lovely" },
  { "synonyms", "She walked quickly to the station.", "quickly" },
  { "synonyms", "O tempo está muito bonito hoje.", "bonito" },
  { "synonyms", "Fui ao mercado comprar pão.", "mercado" },
  { "variations", "I went to the market and bought some bread." },
  { "variations", "The meeting was long and nobody listened." },
  { "variations", "Fui ao mercado e comprei pão fresco." },
  { "variations", "A reunião foi longa e ninguém prestou atenção." },
}

local function build_ctx(sample)
  local kind, line, word = sample[1], sample[2], sample[3]
  local col
  if kind == "synonyms" then
    col = line:find(word, 1, true) - 1
  else
    col = #line - 1
  end
  return context.analyze({ line }, 1, col, false)
end

local function body_for(ctx, model)
  local req = prompts.build(ctx, {})
  local body = {
    model = model,
    temperature = 0.5,
    max_tokens = ctx.kind == "synonyms" and 80 or 160,
    response_format = { type = "json_object" },
    messages = {
      { role = "system", content = req.system .. "\n\nReply with JSON only, in this shape: " .. req.format_hint },
      { role = "user", content = req.user },
    },
  }
  if model:find("gpt-oss", 1, true) then body.reasoning_effort = "low" end
  return vim.json.encode(body), req
end

local WRITE_OUT = "\n@@%{time_connect} %{time_appconnect} %{time_starttransfer} %{time_total}\n"

local function curl_segment(url, key, body)
  local args = {
    "-sS", "-m", "20",
    "-H", "Content-Type: application/json",
    "-w", WRITE_OUT,
    "-d", body,
    url,
  }
  if key ~= "" then vim.list_extend(args, { "-H", "Authorization: Bearer " .. key }) end
  return args
end

local function parse_output(out)
  local results = {}
  for payload, connect, appconnect, ttfb, total in out:gmatch("(.-)\n@@([%d%.]+) ([%d%.]+) ([%d%.]+) ([%d%.]+)\n") do
    local ok, decoded = pcall(vim.json.decode, payload)
    local valid, content = false, nil
    if ok and type(decoded) == "table" and decoded.choices then
      content = decoded.choices[1].message.content
      local parsed_ok, parsed = pcall(vim.json.decode, content or "")
      valid = parsed_ok and type(parsed) == "table" and type(parsed.items) == "table" and #parsed.items > 0
    end
    results[#results + 1] = {
      connect = tonumber(connect) * 1000, tls = tonumber(appconnect) * 1000,
      ttfb = tonumber(ttfb) * 1000, total = tonumber(total) * 1000, valid = valid, content = content,
      error = (not ok or not decoded.choices) and payload:sub(1, 120) or nil,
    }
  end
  return results
end

local function percentile(values, p)
  table.sort(values)
  if #values == 0 then return 0 end
  local idx = math.max(1, math.ceil(#values * p))
  return values[idx]
end

local function summarize(label, values)
  return ("%-26s median %5.0f ms   p95 %5.0f ms   min %5.0f ms"):format(
    label, percentile(vim.deepcopy(values), 0.5), percentile(vim.deepcopy(values), 0.95), math.min(unpack(values))
  )
end

local function run_target(name, url, model, key)
  local bodies, kinds = {}, {}
  for _ = 1, RUNS do
    for _, sample in ipairs(SAMPLES) do
      local ctx = build_ctx(sample)
      local body = body_for(ctx, model)
      bodies[#bodies + 1] = body
      kinds[#kinds + 1] = ctx.kind
    end
  end

  local cold_wall, cold_total, invalid = {}, {}, 0
  local by_kind = {}
  local first_output
  for i, body in ipairs(bodies) do
    local args = { "curl" }
    vim.list_extend(args, curl_segment(url, key, body))
    local started = vim.uv.hrtime()
    local res = vim.system(args, { text = true }):wait()
    local wall = (vim.uv.hrtime() - started) / 1e6
    local parsed = parse_output(res.stdout or "")[1]
    if parsed and parsed.valid then
      cold_wall[#cold_wall + 1] = wall
      cold_total[#cold_total + 1] = parsed.total
      by_kind[kinds[i]] = by_kind[kinds[i]] or {}
      table.insert(by_kind[kinds[i]], parsed.total)
      first_output = first_output or parsed.content
    else
      invalid = invalid + 1
      if invalid == 1 then print(("  first failure (%s): %s"):format(kinds[i], parsed and parsed.error or (res.stderr or ""):sub(1, 120))) end
    end
  end

  local args = { "curl" }
  for i, body in ipairs(bodies) do
    if i > 1 then args[#args + 1] = "--next" end
    vim.list_extend(args, curl_segment(url, key, body))
  end
  local res = vim.system(args, { text = true }):wait()
  local warm = parse_output(res.stdout or "")
  local warm_total, warm_ttfb, warm_invalid = {}, {}, 0
  for i, r in ipairs(warm) do
    if i > 1 then
      if r.valid then
        warm_total[#warm_total + 1] = r.total
        warm_ttfb[#warm_ttfb + 1] = r.ttfb
      else
        warm_invalid = warm_invalid + 1
      end
    end
  end

  print(("\n== %s  (%s)  %d requests each"):format(name, model, #bodies))
  if #cold_wall > 0 then
    print("  " .. summarize("cold, process + connect", cold_wall))
    print("  " .. summarize("cold, server time only", cold_total))
  end
  for _, kind in ipairs({ "synonyms", "variations" }) do
    if by_kind[kind] then print("  " .. summarize("  cold server, " .. kind, by_kind[kind])) end
  end
  if #warm_total > 0 then
    print("  " .. summarize("warm, reused connection", warm_total))
    print("  " .. summarize("warm, time to first byte", warm_ttfb))
  end
  print(("  invalid responses: cold %d, warm %d"):format(invalid, warm_invalid))
  if first_output then print("  sample output: " .. first_output:gsub("%s+", " "):sub(1, 140)) end
end

local targets = vim.env.BENCH_TARGETS or DEFAULT_TARGETS
local ran = 0
for spec in targets:gmatch("[^;]+") do
  local name, url, model, key_env = unpack(vim.split(spec, "|", { plain = true }))
  local key = key_env and vim.env[key_env] or ""
  if not key_env or key ~= "" then
    run_target(name, url, model, key)
    ran = ran + 1
  else
    print(("skipping %s: %s is not set"):format(name, key_env))
  end
end

if ran == 0 then print("\nno targets ran; set an API key or BENCH_TARGETS") end
vim.cmd("qa!")
