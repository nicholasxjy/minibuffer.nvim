-- Run: nvim --clean -l scripts/test_fzf_grep.lua /path/to/fzf-lua
vim.opt.rtp:prepend(".")
vim.opt.rtp:append(assert(arg[1], "Pass the fzf-lua checkout"))
local fzf = require("fzf-lua")
local opts
fzf.live_grep = function(value)
  opts = value
end
require("minibuffer.integrations.fzf").live_grep()
local formatter = fzf.config.globals["formatters.path.filename_first"]
opts.hls = { dir_part = "Comment", file_part = "Normal" }
opts._fmt.to = assert(loadstring(formatter._to(opts)))()
opts._fmt.from = formatter.from
-- Callbacks also run in fzf-lua's separate worker without captured upvalues.
local transform = assert(loadstring(string.dump(opts.fn_transform)))
local preprocess = assert(loadstring(string.dump(opts.fn_preprocess)))
preprocess(opts)
local function check(raw, expected_header, expected_line, expected_col)
  local result = assert(transform(raw, opts))
  local display = assert(result:match("\31(.*)$"))
  assert((display:find("\n", 1, true) ~= nil) == expected_header, display)
  local location = fzf.path.entry_to_file(result, opts)
  assert(
    location.line == expected_line and location.col == expected_col,
    vim.inspect(location)
  )
  return display, location
end
local first, location = check("src/中文 file.lua:12:4:needle", true, 12, 4)
assert(location.path == "src/中文 file.lua", vim.inspect(location))
assert(first:find("中文 file.lua", 1, true), first)
local second = check("src/中文 file.lua:25:9:second: needle\ttext", false, 25, 9)
assert(second == "    25 │ second: needle\ttext", second)
check("lib/中文 file.lua:3:1:other", true, 3, 1)
preprocess(opts)
check("lib/中文 file.lua:3:1:other", true, 3, 1)
check("lib/中文 file.lua:\27[32m8\27[0m:\27[32m2\27[0m:\27[31mneedle\27[0m", false, 8, 2)
check("plain.lua:7:grep without columns", true, 7, 0)
opts.file_ignore_patterns = { "ignored" }
assert(transform("ignored.lua:1:1:needle", opts) == nil)
check("plain.lua:8:1:next", false, 8, 1)
print("grouping, reload, ANSI, filtering and jump locations: OK")
