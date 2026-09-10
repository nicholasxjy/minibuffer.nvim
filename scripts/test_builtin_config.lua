-- nvim --headless -n -u NONE -i NONE -l scripts/test_builtin_config.lua
vim.opt.rtp:prepend(".")
vim.g.minibuffer = {
  select = { keymaps = { next = { "<Down>" } } },
  builtin = {
    prompt = "Search> ",
    pointer = "界",
    filename_first = false,
    filter = { cwd = true },
    max_height = 9,
    keymaps = { split = { "<M-s>" }, accept = { "<M-a>" }, toggle_all = {} },
    highlights = {
      prompt = "TestPrompt",
      pointer = "TestPointer",
      normal = "TestNormal",
      directory_path = "TestDir",
      matched = "TestMatch",
    },
  },
}
package.loaded["minibuffer.internal.guard"] = { check = function() end }
local picker
package.loaded["minibuffer"] = {
  select = function(opts)
    picker = opts
    return true
  end,
}
local common = require("minibuffer.builtin.config")
local global = vim.deepcopy(require("minibuffer.config").builtin)
local opts = common.resolve({
  filename_first = true,
  filter = { cwd = false },
  keymaps = { split = {}, next = "<M-n>" },
  highlights = { normal = "LocalNormal" },
})
assert(opts.filename_first and not opts.filter.cwd)
assert(vim.deep_equal(opts.keymaps.split, {}) and opts.keymaps.next == "<M-n>")
assert(
  opts.highlights.normal == "LocalNormal" and opts.highlights.directory_path == "TestDir"
)
opts.keymaps.accept[1] = "changed"
assert(
  vim.deep_equal(global, require("minibuffer.config").builtin),
  "resolution must not mutate global defaults"
)
assert(common.resolve().keymaps.next[1] == "<Down>")
assert(common.resolve({ filter = {}, highlights = {} }).filter.cwd)
assert(common.resolve({ highlights = {} }).highlights.normal == "TestNormal")
assert(common.resolve({ hl = { matched = "LocalMatch" } }).hl.matched == "LocalMatch")
assert(
  common.resolve({ highlights = { matched = "LocalMatch" } }).hl.matched == "LocalMatch"
)
for _, bad in ipairs({
  { filename_first = 1 },
  { filter = { cwd = "yes" } },
  { keymaps = { split = false } },
  { highlights = { normal = false } },
  { max_height = 0 },
  { prompt = false },
  { prompt = "bad\nprompt" },
  { pointer = 1 },
  { pointer = "\t" },
}) do
  assert(not pcall(common.resolve, bad), vim.inspect(bad))
end

-- Decoration must not mutate cached rows or share output between sessions.
local cached = {
  { text = ">", hl = { "FzfLuaFzfPointer", "MinibufferBuffersBold" } },
  { text = "name", hl = "FzfLuaFilePart" },
}
local original = vim.deepcopy(cached)
local function decorated(pointer, hl)
  local session = {
    format_fn = function()
      return cached
    end,
    group_fn = function()
      return nil
    end,
    footer_fn = function()
      return { { "key", "FzfLuaHeaderBind" } }
    end,
  }
  require("minibuffer.builtin.render").configure({
    pointer = pointer,
    highlights = { pointer = hl, header_bind = hl },
  }, session)
  return session
end
local first_render, second_render = decorated("界", "First"), decorated("→", "Second")
local first_row = first_render.format_fn({}, { current_index = 1 }, 1)
local second_row = second_render.format_fn({}, { current_index = 1 }, 1)
assert(first_row[1].text == "界" and first_row[1].hl[1] == "First")
assert(second_row[1].text == "→" and second_row[1].hl[1] == "Second")
assert(vim.deep_equal(cached, original), "cached renderer output remains unchanged")
assert(first_render.group_fn() == nil)
assert(first_render.footer_fn()[1][2] == "First")
assert(common.resolve({}, { keymaps = { custom = "<M-z>" } }).keymaps.custom == "<M-z>")

local inside = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_name(inside, vim.fn.getcwd() .. "/src/inside.lua")
local outside = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(outside, vim.fn.getcwd() .. "-outside/outside.lua")
require("minibuffer.builtin.buffers")()
local items
picker.fetch_fn("", function(value)
  items = value
end)
assert(
  #items == 1 and items[1].bufnr == inside,
  "global cwd filter excludes sibling paths"
)
assert(picker.max_height == 9 and picker.highlights.normal == "TestNormal")
assert(picker.prompt == "Search> " and picker.highlights.prompt == "TestPrompt")
local active = picker.format_fn(items[1], { current_index = 1, selected_indices = {} }, 1)
assert(active[1].text == "界" and active[1].hl[1] == "TestPointer")
local inactive =
  picker.format_fn(items[1], { current_index = 0, selected_indices = {} }, 1)
assert(inactive[1].text == "  " and inactive[1].hl == "TestPointer")
require("minibuffer.builtin.buffers")({
  prompt = "Local> ",
  pointer = "→",
  highlights = { prompt = "LocalPrompt", pointer = "LocalPointer" },
})
assert(picker.prompt == "Local> " and picker.highlights.prompt == "LocalPrompt")
active = picker.format_fn(items[1], { current_index = 1, selected_indices = {} }, 1)
assert(active[1].text == "→" and active[1].hl[1] == "LocalPointer")
require("minibuffer.builtin.buffers")({ prompt = "", pointer = "" })
assert(picker.prompt == "")
active = picker.format_fn(items[1], { current_index = 1, selected_indices = {} }, 1)
assert(active[1].text == "")
local chunks = picker.format_fn(items[1], { current_index = 0, selected_indices = {} }, 1)
assert(vim.iter(chunks):any(function(chunk)
  return chunk.hl == "TestDir"
end))
require("minibuffer.builtin.buffers")({ filter = { cwd = false } })
picker.fetch_fn("", function(value)
  items = value
end)
assert(#items == 2)

require("minibuffer.builtin.live-grep")("TODO")
assert(picker.query == "TODO" and picker.max_height == 9)
chunks = picker.group_fn({ file = "src/inside.lua" })
assert(chunks[3].text == "src/" and chunks[3].hl == "TestDir")
local grep_row = { line = 1, col = 1, location_width = 3, text = "text", matches = {} }
assert(
  picker.format_fn(grep_row, { current_index = 1, selected_indices = {} }, 1)[1].text
    == "界"
)
local bindings = {}
local grep_ui = require("minibuffer.builtin.live-grep-ui")
grep_ui.info = function() end
picker.on_start({}, function(_, key)
  bindings[key] = true
end)
assert(bindings["<M-s>"] and not bindings["<C-s>"], "split uses the configured keys")

require("minibuffer.builtin.history")()
assert(picker.keymaps.accept[1] == "<M-a>" and picker.highlights.normal == "TestNormal")
require("minibuffer.builtin.ui_select")({ "item" }, {}, function() end)
assert(picker.max_height == 9 and picker.keymaps.accept[1] == "<M-a>")
local plain = picker.format_fn("item", { current_index = 1 }, 1)
assert(plain[1].text == "界 " and plain[1].hl == "TestPointer")

local util = require("minibuffer.internal.util")
local command_buffer = vim.api.nvim_create_buf(false, true)
local command_window = vim.api.nvim_open_win(command_buffer, false, {
  relative = "editor",
  row = 0,
  col = 0,
  width = 80,
  height = 1,
  style = "minimal",
})
util.get_cmd_win = function()
  return command_window
end
util.wipe_cmd_buffer = function() end
util.set_cmdheight = function() end
util.create_condition_keyset = function()
  return function(_, key, callback)
    bindings[key] = callback
  end
end
bindings = {}
local session = require("minibuffer.sessions.select").new({
  multi = true,
  keymaps = common.resolve().keymaps,
  fetch_fn = function(_, cb)
    cb({})
  end,
  filter_fn = function(ctx)
    return ctx.items
  end,
  format_fn = function(item)
    return { { text = tostring(item) } }
  end,
})
session:pre_start()
session:post_start()
assert(bindings["<M-a>"] and not bindings["<CR>"] and not bindings["<C-y>"])
assert(not bindings["<C-a>"], "empty key lists disable the default binding")
assert(bindings["<Down>"] and not bindings["<C-n>"], "navigation lists replace defaults")
for _, builtin in ipairs({ {}, { keymaps = {} } }) do
  vim.g.minibuffer = { builtin = builtin }
  local config = assert(loadfile("lua/minibuffer/config/internal.lua"))()
  assert(config.builtin.filename_first and config.builtin.keymaps.split == "<C-s>")
end
print(
  "builtin global inheritance, overrides, filtering, highlights and action bindings passed"
)
