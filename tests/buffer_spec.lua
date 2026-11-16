local function eq(a, b, msg)
  if not vim.deep_equal(a, b) then
    error((msg or "") .. " expected " .. vim.inspect(b) .. " got " .. vim.inspect(a), 2)
  end
end

local function respond(req)
  if req.kind == "synonyms" then return { items = { "nice", "pleasant", "fine", "sunny" } } end
  if req.kind == "variations" then
    return { items = { "On the mat sat the cat.", "The cat was sitting on the mat." } }
  end
  return {
    plans = { { title = "One thread", text = "Cats like mats. They sit on them." } },
    off_topic = { "taxes" },
  }
end

local function fresh(lines)
  vim.cmd("silent! %bwipeout!")
  package.loaded["writing"] = nil
  local writing = require("writing")
  writing.setup({
    log_file = vim.fn.tempname(),
    delays = { word = 30, sentence = 30 },
    providers = {
      fast = { type = "fake", respond = respond, delay = 5 },
      strong = { type = "fake", respond = respond, delay = 5 },
    },
  })
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].undolevels = 1000
  writing.attach(buf)
  return writing, buf
end

local function event(buf)
  vim.api.nvim_exec_autocmds("CursorMoved", { buffer = buf })
end

local function wait_ready(writing)
  local core = writing._core()
  local ok = vim.wait(1000, function() return core.view.status == "ready" end, 10)
  if not ok then error("never became ready, status=" .. core.view.status) end
  return core
end

return {
  {
    name = "accepting a synonym is one undo step and moves cursor after text",
    fn = function()
      local writing, buf = fresh({ "The weather is lovely today." })
      vim.api.nvim_win_set_cursor(0, { 1, 16 })
      event(buf)
      local core = wait_ready(writing)
      core:accept()
      eq(vim.api.nvim_buf_get_lines(buf, 0, -1, false), { "The weather is nice today." })
      eq(vim.api.nvim_win_get_cursor(0), { 1, 19 })
      vim.cmd("silent undo")
      eq(vim.api.nvim_buf_get_lines(buf, 0, -1, false), { "The weather is lovely today." })
    end,
  },
  {
    name = "box is a non-focusable float and never takes focus; ghost clears after accept",
    fn = function()
      local writing, buf = fresh({ "The weather is lovely today." })
      local original = vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_cursor(0, { 1, 16 })
      event(buf)
      local core = wait_ready(writing)
      local win = require("writing.box").window()
      eq(vim.api.nvim_win_get_config(win).focusable, false)
      eq(vim.api.nvim_get_current_win(), original)
      local ghost_ns = vim.api.nvim_create_namespace("writing_ghost")
      eq(#vim.api.nvim_buf_get_extmarks(buf, ghost_ns, 0, -1, {}), 1)
      core:accept()
      eq(#vim.api.nvim_buf_get_extmarks(buf, ghost_ns, 0, -1, {}), 0)
      eq(require("writing.box").window(), nil)
    end,
  },
  {
    name = "keys are mapped only while the box is visible",
    fn = function()
      local writing, buf = fresh({ "The weather is lovely today." })
      eq(vim.fn.maparg("j", "n", false, true).buffer, nil)
      vim.api.nvim_win_set_cursor(0, { 1, 16 })
      event(buf)
      local core = wait_ready(writing)
      eq(vim.fn.maparg("j", "n", false, true).buffer, 1)
      core:ignore()
      eq(vim.fn.maparg("j", "n", false, true).buffer, nil)
    end,
  },
  {
    name = "sentence variation replaces just that sentence",
    fn = function()
      local writing, buf = fresh({ "Intro line. The cat sat on the mat." })
      local line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
      vim.api.nvim_win_set_cursor(0, { 1, #line - 1 })
      event(buf)
      local core = wait_ready(writing)
      eq(core.view.kind, "variations")
      core:accept()
      eq(vim.api.nvim_buf_get_lines(buf, 0, -1, false), { "Intro line. On the mat sat the cat." })
    end,
  },
  {
    name = "make sense previews diff then applies on second accept",
    fn = function()
      local writing, buf = fresh({ "intro", "", "cats mats taxes sit", "", "outro" })
      vim.api.nvim_win_set_cursor(0, { 3, 0 })
      writing.make_sense()
      local core = wait_ready(writing)
      core:accept()
      eq(vim.api.nvim_buf_get_lines(buf, 0, -1, false)[3], "cats mats taxes sit")
      local ghost_ns = vim.api.nvim_create_namespace("writing_ghost")
      eq(#vim.api.nvim_buf_get_extmarks(buf, ghost_ns, 0, -1, {}), 1)
      core:accept()
      eq(vim.api.nvim_buf_get_lines(buf, 0, -1, false), { "intro", "", "Cats like mats. They sit on them.", "", "outro" })
    end,
  },
  {
    name = "typing clears the box",
    fn = function()
      local writing, buf = fresh({ "The weather is lovely today." })
      vim.api.nvim_win_set_cursor(0, { 1, 16 })
      event(buf)
      local core = wait_ready(writing)
      vim.api.nvim_buf_set_text(buf, 0, 0, 0, 0, { "x" })
      vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf })
      eq(core.view.status, "idle")
      eq(require("writing.box").window(), nil)
    end,
  },
}
