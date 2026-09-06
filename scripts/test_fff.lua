-- Run with: nvim --clean -l scripts/test_fff.lua /path/to/fff
vim.opt.rtp:prepend(".")
assert(arg[1], "Pass the fff.nvim checkout as the first argument")
vim.opt.rtp:append(arg[1])
local received, items, picker
package.loaded["fff"] = {
  file_search = function(query, opts)
    received = { query = query, opts = vim.deepcopy(opts) }
    return { items = items }
  end,
}
package.loaded["fff"].content_search = package.loaded["fff"].file_search
package.loaded["fff.fuzzy"] = {}
local shorten
package.loaded["fff.rust"] = {
  shorten_path = function(path, width, strategy)
    shorten = { path, width, strategy }
    return vim.fn.strdisplaywidth(path) <= width and path or "…"
  end,
}
package.loaded["nvim-web-devicons"] = {
  get_icon = function(name)
    return name == "中文.lua" and "界" or "λ", "Type"
  end,
}
package.loaded["minibuffer.internal.guard"] = { check = function() end }
package.loaded["minibuffer"] = {
  select = function(opts)
    picker = opts
    return true
  end,
}
vim.g.fff = {
  prompt = "Find: ",
  layout = {
    show_path_first = false,
    prompt_position = "top",
    path_shorten_strategy = "end",
  },
  git = { status_text_color = false },
  keymaps = { move_down = { "<C-j>", "<Down>" }, move_up = "<C-k>" },
  grep = { smart_case = false, modes = { "regex", "plain" }, location_format = ":%d" },
}
local config = require("fff.conf").get()
local original_config = vim.deepcopy(config)
local fff = require("minibuffer.integrations.fff")
local util = require("minibuffer.internal.util")
-- Exercise the renderer in real buffers/windows without ui2 owning a command window.
util.set_cmdheight = function() end
local Select = require("minibuffer.sessions.select")
local function start()
  local sess = Select.new(picker)
  sess._display = { buf = vim.api.nvim_create_buf(false, true) }
  sess._display.win = vim.api.nvim_open_win(sess._display.buf, false, {
    relative = "editor",
    width = 70,
    height = 1,
    row = 1,
    col = 0,
    style = "minimal",
  })
  sess._entry = { buf = vim.api.nvim_create_buf(false, true) }
  sess._entry.win = vim.api.nvim_open_win(sess._entry.buf, false, {
    relative = "editor",
    width = 70,
    height = 1,
    row = 10,
    col = 0,
    style = "minimal",
  })
  sess._items = picker.filter_fn({ items = vim.deepcopy(items) })
  sess._closed = false
  sess.render = function()
    if not sess._closed then
      picker.on_change()
    end
  end
  local keys = {}
  picker.on_start(sess, function(_, key, callback)
    keys[key] = callback
  end)
  return sess, keys
end
local function lines(sess)
  return vim.api.nvim_buf_get_lines(sess._display.buf, 0, -1, false)
end
local function find_line(sess, needle)
  for row, line in ipairs(lines(sess)) do
    if line:find(needle, 1, true) then
      return row - 1, line
    end
  end
  error("missing rendered text: " .. needle)
end
local function display_col(line, needle)
  local byte = assert(line:find(needle, 1, true), "missing text: " .. needle)
  return vim.fn.strdisplaywidth(line:sub(1, byte - 1))
end
local function marks(sess)
  return vim.api.nvim_buf_get_extmarks(
    sess._display.buf,
    require("minibuffer.internal.state").ns,
    0,
    -1,
    { details = true }
  )
end
local function has_mark(sess, field, value)
  for _, mark in ipairs(marks(sess)) do
    local actual = mark[4][field]
    if field == "sign_text" and actual then
      actual = actual:gsub("%s+$", "")
    end
    if actual == value then
      return true
    end
  end
  return false
end
local function has_mark_at(sess, row, field, value, start_col, end_col)
  for _, mark in ipairs(marks(sess)) do
    local details = mark[4]
    if
      mark[2] == row
      and mark[3] == start_col
      and details[field] == value
      and (not end_col or details.end_col == end_col)
    then
      return true
    end
  end
  return false
end
local function dispose(sess)
  sess._closed = true
  vim.wait(1)
  for _, pane in ipairs({ sess._display, sess._entry }) do
    vim.api.nvim_win_close(pane.win, true)
    vim.api.nvim_buf_delete(pane.buf, { force = true })
  end
end

items = {
  {
    relative_path = "src/中文.lua",
    git_status = "modified",
    match_ranges = { { 4, 10 } },
  },
  { relative_path = "lib/a.lua", git_status = "clean" },
}
assert(fff.file_search("中文", {
  max_results = 25,
  file_picker = { fuzzy_query_highlighting = true },
  layout = { show_path_first = true },
}))
picker.fetch_fn("query", function(result)
  assert(result == items)
end)
assert(received.query == "query" and received.opts.max_results == 25)
assert(picker.prompt == "Find: ")
assert(vim.deep_equal(picker.keymaps.next, { "<C-j>", "<Down>" }))
local sess, keys = start()
Select.render(sess)
local path_first_row, path_first_line = find_line(sess, "界 src/中文.lua")
assert(not path_first_line:find(" │ ", 1, true), "path-first layout must stay native")
assert(has_mark(sess, "sign_text", "┃"))
assert(not has_mark(sess, "hl_group", "FFFGitModified"))
assert(has_mark(sess, "hl_group", config.hl.matched))
assert(has_mark_at(sess, path_first_row, "hl_group", config.hl.matched, 8, 14))
assert(shorten[3] == "end")
sess:move(-1)
assert(sess._current_index == 1, "fff wrap_around=false must clamp")
assert(keys["<C-t>"] and keys["<Tab>"], "inherit tab-open and multi-select mappings")
dispose(sess)

local overrides = {
  layout = { prompt_position = "bottom" },
  git = { status_text_color = true },
  hl = { directory_path = "Directory", cursor = "Visual" },
  file_picker = { fuzzy_query_highlighting = true },
  highlights = {
    git_modified = "DiffChange",
    git_sign_modified_selected = { fg = "#123456" },
  },
  git_status_signs = { modified = "M" },
  keymaps = { next = { "<C-n>", "<Tab>" }, previous = "<C-p>" },
  debug = { show_scores = true },
  wrap_around = true,
}
items[1].total_frecency_score = 4
fff.file_search("中文", overrides)
picker.fetch_fn("", function() end)
assert(vim.tbl_isempty(received.opts), "display options must not reach backend")
sess, keys = start()
keys["<Tab>"]()
assert(sess._current_index == 2 and #sess._selected_indices == 0)
keys["<C-p>"]()
local unicode_row, unicode_line = find_line(sess, "界 中文.lua")
local ascii_row, ascii_line = find_line(sess, "λ a.lua")
assert(ascii_row ~= unicode_row, "each filename-first item must render on its own row")
assert(unicode_line:find(" │ src", 1, true))
assert(ascii_line:find(" │ lib", 1, true))
assert(display_col(unicode_line, "src") == display_col(ascii_line, "lib"))
assert(has_mark_at(sess, unicode_row, "hl_group", config.hl.matched, 4, 10))
assert(
  unicode_line:find("✨4", 1, true),
  "score suffix must survive native row rendering"
)
local separator_start = unicode_line:find(" │ ", 1, true)
local directory_start = unicode_line:find("src", 1, true)
assert(
  has_mark_at(
    sess,
    unicode_row,
    "hl_group",
    "Directory",
    separator_start - 1,
    directory_start - 1
  ),
  "separator and directory must use the configured path highlight"
)
assert(has_mark(sess, "hl_group", "DiffChange"))
assert(has_mark(sess, "sign_text", "M"))
assert(has_mark(sess, "hl_group", "Directory"))
sess:move(-1)
assert(sess._current_index == #items)
sess:toggle_selection()
assert(has_mark(sess, "sign_text", "▊"))
assert(vim.deep_equal(config, original_config), "per-call overrides must not mutate fff")
dispose(sess)

items = {
  {
    relative_path = "src/中文.lua",
    line_number = 2,
    col = 1,
    line_content = "abc",
    match_ranges = { { 1, 2 } },
  },
  { relative_path = "src/中文.lua", line_number = 3, col = 0, line_content = "def" },
  { relative_path = "lib/a.lua", line_number = 1, col = 0, line_content = "ghi" },
}
fff.content_search("b", {
  layout = { show_path_first = false },
  hl = { directory_path = "GrepDirectory" },
  grep = { smart_case = true },
  smart_case = false,
  highlights = { grep_match = "Search" },
})
picker.fetch_fn("b", function() end)
assert(received.opts.smart_case == false and received.opts.mode == "regex")
sess, keys = start()
Select.render(sess)
assert(#lines(sess) == 5, "one header per file group")
local grep_unicode_row, grep_unicode_header = find_line(sess, "界 中文.lua")
local grep_ascii_row, grep_ascii_header = find_line(sess, "λ a.lua")
assert(grep_unicode_header:find(" │ src", 1, true))
assert(grep_ascii_header:find(" │ lib", 1, true))
assert(display_col(grep_unicode_header, "src") == display_col(grep_ascii_header, "lib"))
assert(
  grep_unicode_row == 0 and grep_ascii_row == 3,
  "grep headers must precede each file group"
)
assert(lines(sess)[2]:find(" :2  abc", 1, true))
assert(lines(sess)[3]:find(" :3  def", 1, true))
assert(has_mark(sess, "hl_group", "Search"))
local grep_separator_start = grep_unicode_header:find(" │ ", 1, true)
local grep_directory_start = grep_unicode_header:find("src", 1, true)
assert(
  has_mark_at(
    sess,
    grep_unicode_row,
    "hl_group",
    "GrepDirectory",
    grep_separator_start - 1,
    grep_directory_start - 1
  ),
  "grep headers must use the filename-first separator highlight"
)
assert(vim.api.nvim_win_get_height(sess._display.win) == 5)
sess:move(1)
assert(vim.api.nvim_win_get_cursor(sess._display.win)[1] == 3, "cursor must skip headers")
keys["<S-Tab>"]()
picker.fetch_fn("", function() end)
assert(received.opts.mode == "plain")
dispose(sess)

fff.file_search("", { show_git_status = false })
items = { { relative_path = "a", git_status = "modified" } }
sess = start()
assert(not has_mark(sess, "sign_text", "┃"))
dispose(sess)
assert(vim.deep_equal(config, original_config))
-- Opening and quickfix still use the search root, including a single qf result.
local commands, qf, action = {}, nil, nil
vim.cmd = function(command)
  commands[#commands + 1] = command
end
vim.fn.setqflist = function(_, _, data)
  qf = data.items
end
fff.file_search("", {
  cwd = "/tmp",
  select = {
    select_window = function(_, value)
      action = value
    end,
  },
})
items = { { relative_path = "a.lua" } }
sess, keys = start()
sess.close = function(_, callback)
  callback()
end
keys["<C-v>"]()
assert(action == "vsplit" and commands[#commands] == "vsplit /tmp/a.lua")
keys["<C-q>"]()
assert(#qf == 1 and qf[1].filename == "/tmp/a.lua")
assert(commands[#commands] == "copen")
dispose(sess)
assert(not pcall(fff.file_search, "", { git_status_signs = { modified = "wide" } }))
print("fff native layout and configuration checks passed")
