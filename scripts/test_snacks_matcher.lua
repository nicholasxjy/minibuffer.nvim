-- SNACKS_REFERENCE=/path/to/snacks.nvim nvim --headless -u NONE -i NONE -l scripts/test_snacks_matcher.lua
-- Differential test against upstream source; Snacks is a test dependency only.
vim.opt.rtp:prepend(".")
local reference =
  assert(vim.env.SNACKS_REFERENCE, "Set SNACKS_REFERENCE to a Snacks checkout")
vim.opt.rtp:append(reference)
package.loaded["snacks.picker.util.async"] = {
  nop = function()
    return { abort = function() end }
  end,
}
_G.Snacks = { picker = { util = {
  path = function(item)
    return item.path
  end,
} } }
local Matcher = require("snacks.picker.core.matcher")
local fuzzy = require("minibuffer.fuzzy")
local sorter =
  require("snacks.picker.sort").default({ fields = { "score:desc", "#text", "idx" } })
local texts = {
  "aabba",
  "a_bc",
  "fooBar.lua",
  "foo/src.lua",
  "src/foo.lua",
  "foo bar",
  "foobar",
  "src/目录/中文.lua",
  "界面/配置.lua",
  "foo.lua",
  "lib/foo.lua",
  "README.md",
  "src/foo_test.lua",
  "src/file01.lua",
  "src/file10.lua",
  "foo:bar.lua",
  "x/" .. string.rep("a_b", 300) .. "c.lua",
  "a" .. string.rep("x", 100) .. "b",
}
math.randomseed(7341)
local alphabet = "abcABC01/_-. "
for _ = 1, 300 do
  local text = {}
  for _ = 1, math.random(4, 70) do
    local pos = math.random(#alphabet)
    text[#text + 1] = alphabet:sub(pos, pos)
  end
  texts[#texts + 1] = table.concat(text)
end
local queries = {
  "",
  "a",
  "ab",
  "abc",
  "aba",
  "a_bc",
  "foo",
  "fB",
  "FB",
  "aB",
  "0",
  "01",
  "lua",
  "^foo",
  "foo$",
  "'foo",
  "'foo'",
  "!test foo",
  "foo | bar",
  "!zzz | foo",
  "foo bar",
  "^foo$",
  "file:foo",
  "file:^src",
  "foo.lua:10",
  "src/foo.lua:10:2",
  "name:!absent",
  "name:foo",
  "text:lua",
  "中文",
  "配置",
  "!中文",
  "'目录",
  "foo\tbar",
  "a | b c",
  "!a !b",
  "a | ^b",
  "^",
  "!",
  "|",
  "!^a",
  "!a$",
}
for _ = 1, 70 do
  local text = texts[math.random(#texts)]
  queries[#queries + 1] = text:sub(1, math.random(1, math.min(8, #text)))
end
local comparisons = 0
for _, extra in ipairs({
  {},
  { history_bonus = true },
  { filename_bonus = false },
  { fuzzy = false },
  { smartcase = false, ignorecase = false },
}) do
  local opts = vim.tbl_extend("force", {
    filename_bonus = true,
    cwd_bonus = false,
    frecency = false,
  }, extra)
  local oracle, ranker = Matcher.new(opts), fuzzy.new_snacks(opts)
  local candidates = {}
  for index, text in ipairs(texts) do
    candidates[index] = { text = text, file = text, path = "/repo/" .. text, idx = index }
  end
  for _, query in ipairs(queries) do
    oracle:init(query)
    local expected = {}
    for _, item in ipairs(candidates) do
      local score = oracle:match(item)
      if score > 0 then
        expected[#expected + 1] = { idx = item.idx, text = item.text, score = score }
      end
    end
    table.sort(expected, sorter)
    local actual = ranker:rank(query, candidates)
    assert(
      #expected == #actual,
      vim.inspect({ query = query, opts = opts, expected = #expected, actual = #actual })
    )
    for i, item in ipairs(actual) do
      assert(
        item.idx == expected[i].idx and item.score == expected[i].score,
        vim.inspect({ query = query, opts = opts, expected = expected[i], actual = item })
      )
      -- Compare byte positions from upstream with our character-indexed render masks.
      local bytes = {}
      for field, positions in pairs(oracle:positions(item)) do
        if field == "text" or field == "file" then
          for _, position in ipairs(positions) do
            bytes[position] = true
          end
        end
      end
      local mask, offset = {}, 1
      for index, char in ipairs(vim.fn.split(item.text, "\\zs")) do
        for byte = offset, offset + #char - 1 do
          if bytes[byte] then
            mask[index - 1] = true
            break
          end
        end
        offset = offset + #char
      end
      assert(
        vim.deep_equal(mask, ranker:positions(query, item)),
        vim.inspect({ query = query, text = item.text, expected_positions = mask })
      )
    end
    comparisons = comparisons + #candidates
  end
end
-- Smart's cwd and frecency bonuses are compared with a fixed clock-free store.
local store = {
  get = function(_, item)
    return item.idx % 4
  end,
}
local oracle = Matcher.new({ filename_bonus = true, cwd_bonus = true, frecency = false })
oracle.cwd, oracle.frecency = "/repo", store
local ranker = fuzzy.new_snacks({ cwd = "/repo", frecency = store })
local candidates = {
  { text = "src/foo.lua", file = "src/foo.lua", path = "/repo/src/foo.lua", idx = 1 },
  { text = "lib/foo.lua", file = "lib/foo.lua", path = "/outside/lib/foo.lua", idx = 2 },
}
for _, query in ipairs({ "", "foo", "!missing foo" }) do
  oracle:init(query)
  local expected = vim.deepcopy(candidates)
  for _, item in ipairs(expected) do
    assert(oracle:update({}, item))
  end
  table.sort(expected, sorter)
  local actual = ranker:rank(query, candidates)
  for i, item in ipairs(actual) do
    assert(item.idx == expected[i].idx and item.score == expected[i].score)
  end
end
print(
  ("Snacks differential scores, order and positions passed (%d candidate/query comparisons)"):format(
    comparisons
  )
)
