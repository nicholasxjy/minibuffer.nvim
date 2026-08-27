test("filename matches receive the Snacks filename bonus", function()
  local ranker = require("minibuffer.fuzzy").new({
    cwd = "/repo",
    cwd_bonus = false,
    frecency = false,
  })
  local ranked = ranker:rank("foo", {
    { text = "foo/src.lua", path = "/repo/foo/src.lua", display = "foo/src.lua" },
    { text = "src/foo.lua", path = "/repo/src/foo.lua", display = "src/foo.lua" },
  })

  eq(
    {
      { text = "src/foo.lua", score = 90 },
      { text = "foo/src.lua", score = 88 },
    },
    vim.tbl_map(function(item)
      return { text = item.text, score = item.score }
    end, ranked)
  )
end)

test("filename matching accepts Windows path separators", function()
  local fuzzy = require("minibuffer.fuzzy")
  local candidate = {
    { text = "src\\foo.lua", path = "C:/repo/src/foo.lua" },
  }
  local posix = fuzzy.new({
    cwd_bonus = false,
    frecency = false,
    path_separator = "/",
  })
  local windows = fuzzy.new({
    cwd_bonus = false,
    frecency = false,
    path_separator = "\\",
  })

  eq(94, posix:rank("src", candidate)[1].score)
  eq(88, windows:rank("src", candidate)[1].score)
end)

test("matching preserves original case for camel-case scoring", function()
  local ranker = require("minibuffer.fuzzy").new({ cwd_bonus = false, frecency = false })
  local ranked = ranker:rank("fb", {
    { text = "fooBar.lua", path = "/repo/fooBar.lua" },
  })

  eq(61, ranked[1].score)
  eq(
    {},
    ranker:rank("FB", {
      { text = "fooBar.lua", path = "/repo/fooBar.lua" },
    })
  )
end)

test("extended queries match like Snacks", function()
  local ranker = require("minibuffer.fuzzy").new({ cwd_bonus = false, frecency = false })
  local quote = string.char(39)
  local cases = {
    { query = "^foo", text = "foobar.lua", score = 94 },
    { query = "bar$", text = "foobar", score = 62 },
    { query = quote .. "foo", text = "xxfoo.lua", score = 62 },
    { query = "!test foo", text = "src/foo.lua", score = 1090 },
    { query = "!test foo", text = "test/foo.lua", score = nil },
    { query = "foo | bar", text = "src/bar.lua", score = 90 },
    { query = "foo bar", text = "foo/bar.lua", score = 178 },
    { query = quote .. "foo" .. quote, text = "foo bar", score = 94 },
    { query = quote .. "foo" .. quote, text = "foobar", score = nil },
  }

  for _, case in ipairs(cases) do
    local ranked = ranker:rank(case.query, {
      { text = case.text, path = "/repo/" .. case.text },
    })
    eq(case.score, ranked[1] and ranked[1].score)
  end
end)

test("OR alternatives preserve Snacks inverse entropy ordering", function()
  local ranker = require("minibuffer.fuzzy").new({ cwd_bonus = false, frecency = false })
  local ranked = ranker:rank("!zzz | foo", {
    { text = "foo.lua", path = "/repo/foo.lua" },
  })

  eq(1000, ranked[1].score)
end)

test("file position queries score the file path without the position", function()
  local ranker = require("minibuffer.fuzzy").new({ cwd_bonus = false, frecency = false })
  local ranked = ranker:rank("foo.lua:10", {
    { text = "src/foo.lua", path = "/repo/src/foo.lua" },
  })

  eq(190, ranked[1].score)
end)

test("cwd and frecency bonuses compose with the fuzzy score", function()
  local ranker = require("minibuffer.fuzzy").new({
    cwd = "/repo",
    frecency = {
      get = function(_, candidate)
        return candidate.path:find("outside", 1, true) and 3 or 0
      end,
    },
  })
  local ranked = ranker:rank("foo", {
    { text = "a/foo.lua", path = "/repo/a/foo.lua" },
    { text = "b/foo.lua", path = "/outside/b/foo.lua" },
  })

  eq(
    { 100, 96 },
    vim.tbl_map(function(item)
      return item.score
    end, ranked)
  )
end)

test("history bonus uses chronological boundary weighting", function()
  local normal = require("minibuffer.fuzzy").new({ cwd_bonus = false, frecency = false })
  local history = require("minibuffer.fuzzy").new({
    cwd_bonus = false,
    frecency = false,
    history_bonus = true,
  })
  local candidates = { { text = "src/foo.lua", path = "/repo/src/foo.lua" } }

  eq(90, normal:rank("foo", candidates)[1].score)
  eq(86, history:rank("foo", candidates)[1].score)
end)

test("bonuses can be disabled independently", function()
  local ranker = require("minibuffer.fuzzy").new({
    filename_bonus = false,
    cwd = "/repo",
    cwd_bonus = false,
    frecency = false,
  })
  local ranked = ranker:rank("foo", {
    { text = "src/foo.lua", path = "/repo/src/foo.lua" },
  })

  eq(84, ranked[1].score)
end)

test("empty queries sort by bonuses, length, then source order", function()
  local ranker = require("minibuffer.fuzzy").new({
    cwd = "/repo",
    frecency = false,
  })
  local ranked = ranker:rank("", {
    { text = "outside.lua", path = "/repo-other/outside.lua" },
    { text = "long-name.lua", path = "/repo/long-name.lua" },
    { text = "a.lua", path = "/repo/a.lua" },
    { text = "b.lua", path = "/repo/b.lua" },
  })

  eq(
    { "a.lua", "b.lua", "long-name.lua", "outside.lua" },
    vim.tbl_map(function(item)
      return item.text
    end, ranked)
  )
end)
