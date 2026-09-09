-- nvim --headless -u NONE -i NONE -l scripts/test_diagnostics.lua
vim.opt.rtp:prepend(".")
package.loaded["vim._core.ui2"] = { cmdheight = 1 }
package.loaded["minibuffer.internal.guard"] = { check = function() end }
package.preload["fzf-lua"] = function() error("fzf-lua must not be loaded") end
package.preload["minibuffer.integrations.fzf"] = function() error("fzf integration must not be loaded") end
local picker
package.loaded["minibuffer"] = { select = function(opts) picker = opts end }
local diagnostics = require("minibuffer.builtin.diagnostics")
local ns = vim.api.nvim_create_namespace("diagnostic-test")
local buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_name(buf, vim.fn.getcwd() .. "/src/文件.lua")
local other = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "one", "two" })
local data = {}
for level = 4, 1, -1 do
  data[#data + 1] = { lnum = 0, col = 0, severity = level, message = "中文 message",
    source = "test", code = level }
end
vim.diagnostic.set(ns, buf, data)
vim.diagnostic.set(ns, other, { { lnum = 0, col = 0, severity = 1, message = "other" } })
local function get(opts)
  diagnostics(opts)
  local items
  picker.fetch_fn("", function(value) items = value end)
  return items
end
local items = get({ scope = "buffer" })
assert(#items == 4 and items[1].severity == 1 and items[4].severity == 4)
assert(#get({ severity_only = "error" }) == 2)
assert(#get({ scope = "buffer", severity_limit = "WARN" }) == 2)
assert(#get({ scope = "buffer", severity_bound = 2 }) == 3)
assert(#get({ scope = "buffer", severity_bound = 2, severity_limit = 3 }) == 2)
assert(get({ scope = "buffer", sort = "reverse" })[1].severity == 4)
assert(not pcall(diagnostics, { severity_only = "invalid" }))
assert(not pcall(diagnostics, { severity_only = 1, severity_limit = 2 }))
items = get({ scope = "buffer" })
local matched = picker.filter_fn({ items = items, input = "中" })
assert(#matched == 4, "duplicate messages must retain all diagnostics")
local chunks = picker.format_fn(matched[1], { current_index = 1, selected_indices = {} }, 1)
local highlighted = ""
for _, chunk in ipairs(chunks) do
  assert(chunk.hl == "MinibufferBuffersBold" or chunk.hl[2] == "MinibufferBuffersBold")
  if type(chunk.hl) == "table" and chunk.hl[1] == "FzfLuaFzfMatch" then
    highlighted = highlighted .. chunk.text
  end
end
assert(highlighted == "中", "Unicode fuzzy highlight")
assert(picker.prompt_position == "top" and picker.multi)
assert(picker.highlights.query == "FzfLuaFzfQuery")
picker.on_accept({ { item = matched[1] }, { item = matched[2] } })
assert(#vim.fn.getqflist() == 2)
assert(items[1].search_text:find("文件.lua:1:1  src", 1, true))
vim.api.nvim_set_current_buf(buf)
items = get({ scope = "buffer", filename_first = false, keymaps = {
  next = { "<C-j>", "<Down>" }, previous = { "<C-k>", "<Up>" },
} })
assert(items[1].search_text:find("src/文件.lua:1:1", 1, true))
local session = require("minibuffer.sessions.select").new(picker)
assert(vim.deep_equal(session.keymaps.next, { "<C-j>", "<Down>" }))
assert(vim.deep_equal(session.keymaps.previous, { "<C-k>", "<Up>" }))
local hints = ""
for _, line in ipairs(picker.header_fn({ items = items, selected_indices = {} }, 120)) do
  for _, chunk in ipairs(line) do hints = hints .. chunk.text end
end
assert(hints:find("ctrl-j/down", 1, true) and hints:find("ctrl-k/up", 1, true))
for _, chunk in ipairs(picker.format_fn(items[1], { current_index = 2, selected_indices = {} }, 1)) do
  assert(type(chunk.hl) ~= "table", "non-current rows must not receive bold overlay")
end
vim.diagnostic.reset(ns)
print("standalone diagnostics severity sorting/filtering, Unicode matching and quickfix passed")
