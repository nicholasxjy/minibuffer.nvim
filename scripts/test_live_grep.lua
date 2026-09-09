-- Run with: nvim --headless -u NONE -i NONE -l scripts/test_live_grep.lua
vim.opt.rtp:prepend(".")
-- Only command-window ownership is stubbed; rendering uses real windows/extmarks.
package.loaded["vim._core.ui2"] = { cmdheight = 1 }
package.loaded["minibuffer.internal.guard"] = { check = function() end }
local picker
package.loaded["minibuffer"] = { select = function(opts) picker = opts end }
package.loaded["nvim-web-devicons"] = {
  get_icon = function() return "界", "Type" end,
}
local grep = require("minibuffer.builtin.live-grep")
local Select = require("minibuffer.sessions.select")
local util = require("minibuffer.internal.util")
local state = require("minibuffer.internal.state")
local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/src", "p")
local path = root .. "/src/中文 file.lua"
vim.fn.writefile({ "前 test1 中 test2", "nothing", "--needle" }, path)
grep({ cwd = root })
local function fetch(query)
  local result, failure
  picker.fetch_fn(query, function(items, err)
    result, failure = items, err
  end)
  assert(vim.wait(3000, function() return result ~= nil or failure ~= nil end))
  assert(not failure, failure)
  return result
end
local items = picker.filter_fn({ items = fetch("test[12]") })
assert(#items == 1 and #items[1].matches == 2)
assert(items[1].col == 5 and items[1].line == 1)
assert(#fetch("absent-pattern") == 0, "no matches must clear the list")
assert(#fetch("") == 0)
assert(#fetch("--needle") == 1, "a query starting with - is not an rg option")
local cmd_buf = vim.api.nvim_create_buf(false, true)
local cmd_win = vim.api.nvim_open_win(cmd_buf, false, {
  relative = "editor", row = 0, col = 0, width = 80, height = 1, style = "minimal",
})
util.get_cmd_win = function() return cmd_win end
util.wipe_cmd_buffer = function() end
util.set_cmdheight = function() end
local sess = Select.new(picker)
sess:pre_start()
sess._items, sess._input, sess._selected_indices = items, "test[12]", { 1 }
vim.api.nvim_buf_set_lines(sess._entry.buf, 0, -1, false, { "> test[12]" })
picker.on_start(sess, function() end)
sess:render()
assert(vim.api.nvim_win_get_position(sess._entry.win)[1] + 1
  == vim.api.nvim_win_get_position(sess._display.win)[1], "input above hints/results")
local lines = vim.api.nvim_buf_get_lines(sess._display.buf, 0, -1, false)
local row = sess._header_height + 1
assert(lines[1] ~= "" and lines[row] ~= "", "no blank separators")
assert(lines[row] == "  界 中文 file.lua  src", lines[row])
assert(lines[row + 1] == ">> 1:5 │ 前 test1 中 test2", lines[row + 1])
assert(not table.concat(lines, "\n"):find("delete", 1, true), "no nonexistent action")
local groups = {}
for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(sess._display.buf, state.ns,
  0, -1, { details = true })) do
  if mark[2] == row then
    local detail = mark[4]
    if detail.hl_group then
      groups[detail.hl_group] = (groups[detail.hl_group] or "")
        .. lines[row + 1]:sub(mark[3] + 1, detail.end_col)
    elseif detail.line_hl_group then
      assert(detail.line_hl_group == "FzfLuaFzfCursorLine")
    end
  end
end
assert(groups.MinibufferGrepMatch == "test1test2", "rg byte ranges highlight every match")
assert(groups.FzfLuaPathLineNr == "1" and groups.FzfLuaPathColNr == "5")
assert(groups.FzfLuaFzfPointer == ">" and groups.FzfLuaFzfMarker == ">")
assert(vim.wo[sess._entry.win].winhighlight:find("FzfLuaLivePrompt", 1, true))
local info
for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(sess._entry.buf, state.ns,
  0, -1, { details = true })) do
  if mark[4].virt_text then info = mark[4] end
end
assert(info and info.virt_text_pos == "right_align")
assert(info.virt_text[1][1]:find("1/1 (1)", 1, true))
for _, width in ipairs({ 24, 100 }) do
  vim.o.columns = width
  sess:render()
  local header = picker.header_fn(sess:get_ctx(), width)
  -- Actions wrap; the explicit cwd is a separate path row.
  for i = 1, #header - 1 do
    local text = ""
    for _, chunk in ipairs(header[i]) do text = text .. chunk.text end
    assert(vim.fn.strdisplaywidth(text) <= width)
  end
end
local ui = require("minibuffer.builtin.live-grep-ui")
local function flatten(chunks)
  local text = ""
  for _, chunk in ipairs(chunks) do text = text .. chunk.text end
  return text
end
assert(flatten(ui.group(items[1], nil, false)) == "  界 src/中文 file.lua")
local many = {}
for i = 1, 30 do
  many[i] = { file = i % 2 == 0 and "b.lua" or "a.lua", line = i * 10,
    col = 1, text = "    text", matches = {} }
end
sess._items = picker.filter_fn({ items = many })
sess.max_height = 5
for i = 1, #many do
  sess._current_index = i
  sess:render()
  assert(sess:get_selected() == sess._items[i], "navigation selects matches only")
  local body = vim.api.nvim_buf_get_lines(sess._display.buf, sess._header_height, -1, false)
  assert(body[1]:find(".lua", 1, true), "scrolling retains a file header")
  assert(#body <= 5, "group titles count towards the viewport height")
  assert(table.concat(body):find(">", 1, true), "current item remains visible")
  for _, line in ipairs(body) do
    if line:find("│", 1, true) then
      assert(line:find("│     text", 1, true), "content indentation is preserved")
    end
  end
end
grep({ cwd = root, keymaps = { next = { "<C-j>", "<Down>" }, previous = { "<C-k>", "<Up>" } } })
local configured = Select.new(picker)
assert(vim.deep_equal(configured.keymaps.next, { "<C-j>", "<Down>" }))
assert(vim.deep_equal(configured.keymaps.previous, { "<C-k>", "<Up>" }))
picker.on_accept({ { item = items[1] }, { item = items[1] } })
assert(vim.api.nvim_buf_get_name(vim.fn.getqflist()[1].bufnr) == path,
  "quickfix filenames with spaces are not command-escaped")
vim.api.nvim_set_hl(0, "FzfLuaPathColNr", { fg = "#123456" })
require("minibuffer.builtin.live-grep-ui").setup()
assert(vim.api.nvim_get_hl(0, { name = "FzfLuaPathColNr" }).fg == 0x123456)
vim.fn.delete(root, "rf")
print("live grep layout, highlights, regex matches, navigation paths and empty results passed")
