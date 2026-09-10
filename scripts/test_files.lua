-- nvim --headless -n -u NONE -i NONE -l scripts/test_files.lua
vim.opt.rtp:prepend(".")
package.loaded["vim._core.ui2"] = { cmdheight = 1 }
package.loaded["minibuffer.internal.guard"] = { check = function() end }
for _, name in ipairs({ "fzf-lua", "fff", "snacks" }) do
  package.preload[name] = function() error("files must be standalone") end
end
package.loaded["nvim-web-devicons"] = { get_icon = function() return "界", "Type" end }
local picker
package.loaded["minibuffer"] = { select = function(opts) picker = opts end }
local files = require("minibuffer.builtin.files")
local ui = require("minibuffer.builtin.files-ui")
local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/src", "p")
local function git(...)
  local cmd = { "git", "-C", root }
  vim.list_extend(cmd, { ... })
  local res = vim.system(cmd, { text = true }):wait()
  assert(res.code == 0, res.stderr)
  return res.stdout
end
local function write(path, text) vim.fn.writefile({ text }, root .. "/" .. path) end
git("init", "-q")
write("src/中文.lua", "original")
write("deleted.lua", "original")
write("rename.lua", "original")
write(".gitignore", "ignored/")
git("add", ".")
git("-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "-qm", "fixture")
write("src/中文.lua", "modified")
vim.fn.delete(root .. "/deleted.lua")
git("mv", "rename.lua", "renamed.lua")
write("new.lua", "staged")
git("add", "new.lua")
write("space name.lua", "untracked")
write("line\nbreak.lua", "untracked")
vim.fn.mkdir(root .. "/ignored", "p")
write("ignored/cache.lua", "ignored")
files({ cwd = root, matcher = { frecency = false }, git = { status_text_color = true } })
local all, second
picker.fetch_fn("", function(items, err) assert(not err, err); all = items end)
picker.fetch_fn("x", function(items, err) assert(not err, err); second = items end)
assert(vim.wait(5000, function() return all ~= nil and second ~= nil end))
assert(all == second, "concurrent fetches share one completed scan")
local by_path = {}
for _, item in ipairs(all) do by_path[item.path] = item end
assert(by_path[root .. "/src/中文.lua"].git_status == "modified")
assert(by_path[root .. "/new.lua"].git_status == "staged_new")
assert(by_path[root .. "/space name.lua"].git_status == "untracked")
assert(by_path[root .. "/line\nbreak.lua"].name == "line↵break.lua")
assert(not by_path[root .. "/ignored/cache.lua"])
assert(not by_path[root .. "/deleted.lua"])
local statuses = require("minibuffer.builtin.files-git").parse(
  " D deleted.lua\0R  renamed.lua\0old name.lua\0?? space name.lua\0 M work.lua\0A  new.lua\0", root)
assert(statuses[root .. "/deleted.lua"] == "deleted")
assert(statuses[root .. "/space name.lua"] == "untracked", "rename source is consumed separately")
assert(statuses[root .. "/work.lua"] == "modified")
local matched = picker.filter_fn({ input = "中文", items = all })
assert(#matched == 1 and matched[1].name == "中文.lua")
local util = require("minibuffer.internal.util")
local cmd_buf = vim.api.nvim_create_buf(false, true)
local cmd_win = vim.api.nvim_open_win(cmd_buf, false, {
  relative = "editor", row = 0, col = 0, width = 80, height = 1, style = "minimal",
})
util.get_cmd_win = function() return cmd_win end
util.wipe_cmd_buffer = function() end
util.set_cmdheight = function() end
local sess = require("minibuffer.sessions.select").new(picker)
sess:pre_start()
sess._items, sess._input = matched, "中文"
vim.api.nvim_buf_set_lines(sess._entry.buf, 0, -1, false, { "Files> 中文" })
picker.on_start(sess, function() end)
local body = vim.api.nvim_buf_get_lines(sess._display.buf, 0, -1, false)
local row = 0
assert(body[row + 1]:match("^界 中文%.lua +│ src$"), body[row + 1])
assert(body[#body - sess._header_height + 1]:find("::", 1, true), "hints follow the list")
assert(vim.api.nvim_win_get_position(sess._entry.win)[1] + 1
  == vim.api.nvim_win_get_position(sess._display.win)[1])
local marks = vim.api.nvim_buf_get_extmarks(sess._display.buf,
  require("minibuffer.internal.state").ns, 0, -1, { details = true })
local groups, sign = {}, nil
for _, mark in ipairs(marks) do
  if mark[2] == row then
    local detail = mark[4]
    if detail.hl_group then groups[detail.hl_group] = true end
    if detail.sign_text then sign = detail.sign_text end
  end
end
assert(groups.IncSearch and groups.Comment and groups.FFFGitModified)
assert(sign and sign:find("┃", 1, true), "fff git border sign")
sess._selected_indices = { 1 }
sess:render()
marks = vim.api.nvim_buf_get_extmarks(sess._display.buf,
  require("minibuffer.internal.state").ns, 0, -1, { details = true })
local selected = false
for _, mark in ipairs(marks) do
  if mark[4].sign_hl_group == "FFFSelectedActive" then selected = true end
end
assert(selected, "fff selection replaces the git border")
assert(ui.shorten("alpha/beta/gamma/delta/omega", 15) == "alpha/.../omega")
assert(vim.fn.strdisplaywidth(ui.shorten("目录/非常长的名称/末尾", 8)) <= 8)
vim.api.nvim_set_hl(0, "FFFGitModified", { fg = "#123456" })
ui.setup()
assert(vim.api.nvim_get_hl(0, { name = "FFFGitModified" }).fg == 0x123456)
picker.on_accept({ { item = by_path[root .. "/space name.lua"] }, { item = matched[1] } })
assert(vim.api.nvim_buf_get_name(vim.fn.getqflist()[1].bufnr) == root .. "/space name.lua")
git("status", "--porcelain") -- fixture is still intact after browsing
local sibling = root .. "-sibling"
vim.fn.mkdir(sibling, "p")
vim.fn.writefile({ "outside" }, sibling .. "/outside.lua")
local outside = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(outside, sibling .. "/outside.lua")
local function scan(filter)
  files({ cwd = root, filter = { cwd = filter }, matcher = { frecency = false },
    keymaps = { next = { "<C-j>", "<Down>" }, previous = { "<C-k>", "<Up>" },
      split = { "<C-s>", "<C-w>s" }, vsplit = {}, accept = { "<CR>", "<C-l>" },
      toggle = { "<C-x>", "<M-x>" }, toggle_all = {}, close = { "<Esc>", "<C-q>" } },
  })
  local result
  picker.fetch_fn("", function(value, err) assert(not err, err); result = value end)
  assert(vim.wait(5000, function() return result ~= nil end))
  return result
end
for _, item in ipairs(scan(true)) do
  assert(vim.fs.relpath(root, item.path), "cwd excludes sibling directories and outside buffers")
end
local unrestricted = scan(false)
assert(vim.iter(unrestricted):any(function(item) return item.path == sibling .. "/outside.lua" end))
local configured = require("minibuffer.sessions.select").new(picker)
configured:pre_start()
configured._items = unrestricted
local keys = {}
util.create_condition_keyset = function()
  return function(_, key, cb) keys[key] = cb end
end
configured:post_start()
assert(keys["<C-j>"] and keys["<Down>"] and keys["<C-k>"] and keys["<Up>"])
assert(keys["<C-s>"] and keys["<C-w>s"] and not keys["<C-v>"])
assert(keys["<C-l>"] and keys["<M-x>"] and not keys["<C-a>"])
keys["<C-j>"]()
assert(configured._current_index == 2)
keys["<C-k>"]()
assert(configured._current_index == 1)
local separator_col
for _, item in ipairs(unrestricted) do
  local text = ""
  for _, chunk in ipairs(picker.format_fn(item, { input = "" })) do text = text .. chunk.text end
  local first = assert(text:find("│", 1, true))
  local col = vim.fn.strdisplaywidth(text:sub(1, first - 1))
  assert(not separator_col or col == separator_col, "filename-first separators align across Unicode paths")
  separator_col = col
end
local hint = ""
for _, line in ipairs(picker.header_fn({ items = unrestricted, selected_indices = {} }, 120)) do
  for _, chunk in ipairs(line) do hint = hint .. chunk.text end
end
assert(hint:find("ctrl-s/ctrl-w s", 1, true))
assert(not hint:find("vsplit", 1, true) and not hint:find("toggle-all", 1, true))
vim.fn.delete(sibling, "rf")
vim.fn.delete(root, "rf")
print("standalone files scan/cache, fuzzy ranking, fff layout, Git signs and multi-selection passed")
