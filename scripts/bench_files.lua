-- MINIBUFFER_BENCH_RTP=/path/to/checkout nvim --headless -u NONE -i NONE -l scripts/bench_files.lua
-- Measures CPU work with deterministic scan output, not filesystem/process latency.
vim.opt.rtp:prepend(vim.env.MINIBUFFER_BENCH_RTP or ".")
package.loaded["vim._core.ui2"] = { cmdheight = 1 }
package.loaded["minibuffer.internal.guard"] = { check = function() end }
vim.v.oldfiles = {}
local picker
package.loaded["minibuffer"] = {
  select = function(opts)
    picker = opts
  end,
}
if vim.env.MINIBUFFER_BENCH_ICONS == "1" then
  package.loaded["nvim-web-devicons"] = {
    get_icon = function()
      return "", "Type"
    end,
  }
end
local count = tonumber(vim.env.MINIBUFFER_BENCH_COUNT) or 20000
local paths, status = {}, {}
local stems = {
  "config",
  "controller",
  "component",
  "cache",
  "client",
  "request",
  "render",
  "service",
}
for i = 1, count do
  local path = ("src/package_%03d/%s_%05d.lua"):format(i % 200, stems[i % #stems + 1], i)
  paths[i] = path
  if i % 7 == 0 then
    status["/bench/" .. path] = "modified"
  end
end
local output = table.concat(paths, "\0") .. "\0"
package.loaded["minibuffer.builtin.files-git"] = {
  load = function(_, callback)
    vim.schedule(function()
      callback(status)
    end)
  end,
}
vim.system = function(_, _, callback)
  vim.schedule(function()
    callback({ code = 0, stdout = output })
  end)
end
local files = require("minibuffer.builtin.files")
local function timed(fn)
  collectgarbage("collect")
  local start = vim.uv.hrtime()
  fn()
  return (vim.uv.hrtime() - start) / 1e6
end
local function median(values)
  table.sort(values)
  return values[math.ceil(#values / 2)]
end
local opens, searches, highlighted = {}, {}, {}
for run = 1, 3 do
  local items
  opens[run] = timed(function()
    files({ cwd = "/bench", matcher = { frecency = false } })
    picker.fetch_fn("", function(value, err)
      assert(not err, err)
      items = value
    end)
    assert(vim.wait(30000, function()
      return items ~= nil
    end))
    assert(#items == count)
    picker.filter_fn({ items = items, input = "" })
  end)
  searches[run] = timed(function()
    for _, query in ipairs({
      "c",
      "co",
      "con",
      "conf",
      "config",
      "lua",
      "!test config",
      "^src service$",
    }) do
      picker.filter_fn({ items = items, input = query })
    end
  end)
  files({
    cwd = "/bench",
    matcher = { frecency = false },
    fuzzy_query_highlighting = true,
  })
  highlighted[run] = timed(function()
    local matches = picker.filter_fn({ items = items, input = "co" })
    for i = 1, math.min(15, #matches) do
      picker.format_fn(
        matches[i],
        { input = "co", current_index = 1, selected_indices = {} },
        i
      )
    end
  end)
end
print(vim.json.encode({
  candidates = count,
  icons = vim.env.MINIBUFFER_BENCH_ICONS == "1",
  runs = 3,
  units = "ms (median)",
  open_cpu = median(opens),
  eight_queries = median(searches),
  highlighted_query_and_15_rows = median(highlighted),
}))
