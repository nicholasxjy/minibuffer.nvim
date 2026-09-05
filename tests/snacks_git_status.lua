-- Run with snacks.nvim on the runtimepath:
-- nvim --headless -u tests/minimal_init.lua --cmd 'set rtp+=/path/to/snacks.nvim' -l tests/snacks_git_status.lua
require("snacks").setup({ picker = { enabled = true } })
require("minibuffer.integrations.snacks-picker").setup({ smart = { git_status = true } })

local root = vim.fn.tempname()
local picker
local ok, err = xpcall(function()
  vim.fn.mkdir(root, "p")
  local function git(...)
    local result = vim.system({ "git", "-C", root, ... }):wait()
    assert(result.code == 0, result.stderr)
  end
  git("init", "-q")
  vim.fn.writefile({ "original" }, root .. "/a-clean.lua")
  vim.fn.writefile({ "original" }, root .. "/z-changed.lua")
  git("add", ".")
  git(
    "-c",
    "user.name=Test",
    "-c",
    "user.email=test@example.com",
    "commit",
    "-qm",
    "initial"
  )
  vim.fn.writefile({ "modified" }, root .. "/z-changed.lua")

  for _, cwd in ipairs({ root, vim.fs.dirname(root) }) do
    picker = Snacks.picker.smart({
      cwd = cwd,
      multi = { "files" }, -- File discovery exercises the real fast-event sorter.
      matcher = { frecency = false },
      icons = { files = { enabled = false } },
      layout = { preview = false },
    })
    assert(
      vim.wait(3000, function()
        return not picker:is_active() and picker.list:count() == 2
      end),
      "picker did not finish"
    )
    local first = picker.list:get(1)
    assert(first.file:find("z-changed.lua", 1, true), "modified file must sort first")
    local chunks = Snacks.picker.highlight.resolve(picker.format(first, picker), 80)
    local highlight, sign
    for _, chunk in ipairs(chunks) do
      highlight = highlight or chunk[2] == "FFFGitModified"
      sign = sign or chunk.sign_text == "┃"
    end
    assert(highlight and sign, "modified file must have a Git highlight and sign")
    picker:close()
    picker = nil
  end
end, debug.traceback)
if picker then
  picker:close()
end
vim.fn.delete(root, "rf")
assert(ok, err)
print(
  "ok - smart Git status works inside and outside a repository during async discovery"
)
