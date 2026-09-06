test("frecency decays visits with a thirty-day half-life", function()
  local now = 10000000
  local store = require("minibuffer.fuzzy.frecency").new({
    data = {},
    now = function()
      return now
    end,
  })
  local candidate = { path = "/repo/visited.lua" }

  store:visit(candidate)
  eq(1, store:get(candidate))

  now = now + 30 * 24 * 60 * 60
  near(0.5, store:get(candidate))
  store:visit(candidate)
  near(1.5, store:get(candidate))
end)

test("frecency seeds recent files from their last-used time", function()
  local now = 10000000
  local store = require("minibuffer.fuzzy.frecency").new({
    data = {},
    now = function()
      return now
    end,
  })
  local score = store:get({
    path = "/repo/recent.lua",
    recent = true,
    info = { lastused = now - 30 * 24 * 60 * 60 },
  })

  near(0.5, score)
end)

test("frecency seeds recent files from mtime when buffer info is unavailable", function()
  local now = 10000000
  local store = require("minibuffer.fuzzy.frecency").new({
    data = {},
    now = function()
      return now
    end,
    stat = function()
      return { mtime = { sec = now - 30 * 24 * 60 * 60 } }
    end,
  })

  near(0.5, store:get({ path = "/repo/recent.lua", recent = true }))
end)

test("frecency persists only the most recent bounded entries", function()
  local path = vim.fn.tempname()
  local now = 10000000
  local module = require("minibuffer.fuzzy.frecency")
  local store = module.new({
    max_size = 2,
    now = function()
      return now
    end,
    path = path,
  })

  for _, name in ipairs({ "old.lua", "middle.lua", "new.lua" }) do
    store:visit({ path = "/repo/" .. name })
    now = now + 1
  end
  eq(true, store:save())

  local reloaded = module.new({
    path = path,
    now = function()
      return now
    end,
  })
  eq(0, reloaded:get({ path = "/repo/old.lua" }))
  near(1, reloaded:get({ path = "/repo/middle.lua" }), 1e-6)
  near(1, reloaded:get({ path = "/repo/new.lua" }), 1e-6)
  vim.uv.fs_unlink(path)
end)

test("frecency ignores a corrupt persisted store", function()
  local path = vim.fn.tempname()
  vim.fn.writefile({ "not json" }, path)
  local store = require("minibuffer.fuzzy.frecency").new({ path = path })

  eq(0, store:get({ path = "/repo/file.lua" }))
  vim.uv.fs_unlink(path)
end)
