-- Run with: nvim --clean -l scripts/test_buffers.lua
vim.opt.rtp:prepend(".")
vim.g.loaded_minibuffer = true
package.loaded["minibuffer.internal.guard"] = { check = function() end }
local picker
local active_win = vim.api.nvim_get_current_win()
package.loaded["minibuffer"] = {
  select = function(opts)
    picker = opts
  end,
  get_active_window = function()
    return active_win
  end,
}
local Select = require("minibuffer.sessions.select")
local buffers = require("minibuffer.builtin.buffers")
local state = require("minibuffer.internal.state")
local ui = require("minibuffer.builtin.buffers-ui")
local util = require("minibuffer.internal.util")
local first = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_name(first, vim.fn.getcwd() .. "/中文.lua")
vim.api.nvim_buf_set_lines(first, 0, -1, false, { "one", "two" })
vim.api.nvim_win_set_cursor(active_win, { 2, 0 })
local second = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(second, vim.fn.getcwd() .. "/second.lua")
vim.api.nvim_set_current_buf(second)
local unnamed = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_lines(unnamed, 0, -1, false, { "" })
vim.bo[first].readonly = true
buffers({ keymaps = { split = { "<C-s>", "<C-w>s" }, delete = {} } })
local all
picker.fetch_fn("", function(items)
  all = items
end)
assert(all[1].bufnr == second and all[2].bufnr == first, "current and alternate order")
local matched = picker.filter_fn({ input = "中", items = all })
assert(#matched == 1 and matched[1].bufnr == first)
assert(matched[1].lnum == 2 and matched[1].flags == "h=+")
assert(vim.deep_equal(matched[1].match_positions, { 0 }))

-- Use real Neovim windows and extmarks to catch byte/character offset errors.
local cmd_buf = vim.api.nvim_create_buf(false, true)
local cmd_win = vim.api.nvim_open_win(cmd_buf, false, {
  relative = "editor",
  row = 0,
  col = 0,
  width = 80,
  height = 1,
  style = "minimal",
})
util.get_cmd_win = function()
  return cmd_win
end
util.wipe_cmd_buffer = function() end
util.set_cmdheight = function() end
util.set_win_height = vim.api.nvim_win_set_height
local sess = Select.new(picker)
sess:pre_start()
sess._items = matched
sess._input = "中"
sess._selected_indices = { 1 }
vim.api.nvim_buf_set_lines(sess._entry.buf, 0, -1, false, { picker.prompt .. "中" })
sess:render()
local line = vim.api.nvim_buf_get_lines(sess._display.buf, 0, 1, false)[1]
assert(line:sub(1, 2) == ">>", "cursor and multi-select markers")
assert(line:find("中文.lua:2", 1, true), line)
local groups = {}
for _, mark in
  ipairs(
    vim.api.nvim_buf_get_extmarks(sess._display.buf, state.ns, 0, -1, { details = true })
  )
do
  local detail = mark[4]
  if detail.hl_group then
    groups[detail.hl_group] = line:sub(mark[3] + 1, detail.end_col)
  end
  if detail.line_hl_group then
    assert(detail.line_hl_group == "FzfLuaFzfCursorLine")
  end
end
assert(groups.FzfLuaFzfMatch == "中", "Unicode match must cover precisely one character")
assert(groups.FzfLuaBufNr == tostring(first))
assert(groups.FzfLuaBufFlagAlt == "#")
assert(groups.FzfLuaPathLineNr == "2")
local prompt_marks =
  vim.api.nvim_buf_get_extmarks(sess._entry.buf, state.ns, 0, -1, { details = true })
assert(prompt_marks[1][4].hl_group == "FzfLuaFzfPrompt")
assert(prompt_marks[1][4].end_col == #picker.prompt)
assert(vim.wo[sess._entry.win].winhighlight:find("FzfLuaFzfQuery", 1, true))
assert(vim.wo[sess._display.win].winhighlight:find("FzfLuaFzfNormal", 1, true))
assert(vim.api.nvim_win_get_config(sess._display.win).footer_pos == "left")
local footer = picker.footer_fn(sess:get_ctx())
local text = ""
local hint_groups = {}
for _, chunk in ipairs(footer) do
  text = text .. chunk[1]
  hint_groups[chunk[2]] = true
end
assert(text:find("<ctrl-s/ctrl-w s> to split", 1, true), text)
assert(not text:find("delete", 1, true), "disabled actions have no hint")
assert(text:find("1/3 (1)", 1, true), text)
assert(hint_groups.FzfLuaHeaderBind and hint_groups.FzfLuaHeaderText)
local unfiltered = picker.filter_fn({ input = "", items = all })
for _, item in ipairs(unfiltered) do
  assert(item.match_positions == nil, "clearing query clears match highlights")
  if item.bufnr == unnamed then
    local chunks = ui.format(item)
    local rendered = ""
    for _, chunk in ipairs(chunks) do
      rendered = rendered .. chunk.text
    end
    assert(rendered:find("[No Name]", 1, true) and not rendered:find(":1", 1, true))
  end
end
local keys = {}
picker.on_start(sess, function(_, key, callback)
  keys[key] = callback
end)
assert(keys["<C-s>"] and keys["<C-w>s"] and not keys["<C-d>"])
local commands = {}
local cmd = vim.cmd
vim.cmd = function(command)
  commands[#commands + 1] = command
end
sess.close = function(_, done)
  done()
end
keys["<C-s>"]()
assert(commands[1] == "split" and vim.api.nvim_get_current_buf() == first)
vim.cmd = cmd
buffers()
local deleted = false
picker.on_start({
  get_selected = function()
    return { bufnr = unnamed }
  end,
  refresh_results = function()
    deleted = true
  end,
}, function(_, key, callback)
  keys[key] = callback
end)
vim.bo[unnamed].modified = false
keys["<C-d>"]()
assert(deleted and not vim.api.nvim_buf_is_valid(unnamed))
picker.fetch_fn("", function(items)
  for _, item in ipairs(items) do
    assert(item.bufnr ~= unnamed)
  end
end)
-- Existing theme definitions must not be overwritten.
vim.api.nvim_set_hl(0, "FzfLuaBufNr", { fg = "#123456" })
ui.setup()
assert(vim.api.nvim_get_hl(0, { name = "FzfLuaBufNr" }).fg == 0x123456)
-- Other builtins retain their original selection and prompt defaults.
local plain = Select.new({
  fetch_fn = function() end,
  filter_fn = function() end,
  format_fn = function() end,
})
assert(vim.deep_equal(plain.highlights, {}) and plain.footer_pos == "right")
print("buffers layout, hints, Unicode highlights and actions passed")
