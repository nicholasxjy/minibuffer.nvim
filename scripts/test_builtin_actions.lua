-- nvim --headless -n -u NONE -i NONE -l scripts/test_builtin_actions.lua
vim.opt.rtp:prepend(".")
package.loaded["vim._core.ui2"] = { cmdheight = 1 }
package.loaded["minibuffer.internal.guard"] = { check = function() end }
local picker
package.loaded["minibuffer"] = {
  select = function(opts)
    picker = opts
  end,
}
local actions = require("minibuffer.builtin.actions")

-- Equal search text must retain the original item identity, including columns.
vim.fn.setqflist({}, " ", {
  items = {
    { filename = "same.lua", lnum = 1, col = 1, text = "duplicate" },
    { filename = "same.lua", lnum = 1, col = 8, text = "duplicate" },
  },
})
require("minibuffer.builtin.list")()
local items
picker.fetch_fn("", function(value)
  items = value
end)
local matches = picker.filter_fn({ items = items, input = "duplicate" })
assert(#matches == 2 and matches[1] ~= matches[2])
assert(matches[1].col == 1 and matches[2].col == 8)
assert(picker.filter_fn({ items = items, input = "" }) == items)
assert(not pcall(require("minibuffer.builtin.list"), { type = "invalid" }))

-- Default history is command history, including its accept action.
local feedkeys, fed = vim.fn.feedkeys
vim.fn.feedkeys = function(keys, mode)
  fed = { keys, mode }
end
require("minibuffer.builtin.history")()
assert(picker.prompt == "Command History: ")
picker.on_accept({ { item = { text = "echo 42" } } })
assert(fed[1] == ":echo 42" and fed[2] == "n")
picker.on_accept({})
vim.fn.feedkeys = feedkeys
assert(not pcall(require("minibuffer.builtin.history"), { type = "invalid" }))

-- Bind only enabled actions; capture the item before closing the picker.
local selected, opened, after_close = { path = "chosen" }, nil, false
local keys, deferred = {}, nil
actions.bind_open({
  get_selected = function()
    return selected
  end,
  close = function(_, callback)
    deferred = callback
  end,
}, function(mode, key, callback)
  assert(mode == "i")
  keys[key] = callback
end, { split = { "s", "S" }, vsplit = {} }, function(item, command)
  assert(after_close)
  opened = { item, command }
end)
assert(keys.s and keys.S and not keys.v)
local original = selected
keys.s()
assert(not opened and deferred)
selected, after_close = nil, true
deferred()
assert(opened[1] == original and opened[2] == "split")
deferred = nil
keys.S()
assert(deferred == nil, "empty selection does not close the picker")

local root = vim.fn.tempname() .. " space"
vim.fn.mkdir(root, "p")
local path = root .. "/space file.lua"
vim.fn.writefile({ "text" }, path)
local ok, err = xpcall(function()
  -- Ex commands escape the complete path; quickfix receives the raw filename.
  actions.open_file(path)
  assert(vim.api.nvim_buf_get_name(0) == path)
  vim.v.oldfiles = { path }
  require("minibuffer.builtin.oldfiles")()
  picker.on_accept({ { item = { path = path } }, { item = { path = path } } })
  local qf = vim.fn.getqflist()
  assert(#qf == 2 and vim.api.nvim_buf_get_name(qf[1].bufnr) == path)
  vim.cmd("cclose")

  -- Exercise the git picker with spaces in both cwd and the filename.
  assert(vim.system({ "git", "-C", root, "init", "-q" }):wait().code == 0)
  assert(vim.system({ "git", "-C", root, "add", "." }):wait().code == 0)
  require("minibuffer.builtin.git-files")({ cwd = root })
  picker.on_accept({ { item = "space file.lua" } })
  assert(vim.api.nvim_buf_get_name(0) == path)
  local split_keys = {}
  picker.on_start({
    get_selected = function()
      return "space file.lua"
    end,
    close = function(_, callback)
      callback()
    end,
  }, function(_, key, callback)
    split_keys[key] = callback
  end)
  split_keys["<C-v>"]()
  assert(vim.api.nvim_buf_get_name(0) == path)
end, debug.traceback)
vim.fn.delete(root, "rf")
assert(ok, err)
print(
  "builtin duplicate identities, history defaults, deferred actions and spaced paths passed"
)
