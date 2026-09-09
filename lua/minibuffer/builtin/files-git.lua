local M = {}

-- Match fff-core's worktree-before-index precedence.
local function status(xy)
  local x, y = xy:sub(1, 1), xy:sub(2, 2)
  if xy == "??" then return "untracked" end
  if y == "M" then return "modified" end
  if y == "D" then return "deleted" end
  if y == "R" then return "renamed" end
  if x == "A" then return "staged_new" end
  if x == "M" then return "staged_modified" end
  if x == "D" then return "staged_deleted" end
  if xy == "!!" then return "ignored" end
  return "unknown"
end

function M.parse(output, root)
  local records = vim.split(output, "\0", { plain = true, trimempty = true })
  local result, i = {}, 1
  while i <= #records do
    local record = records[i]
    local xy, path = record:sub(1, 2), record:sub(4)
    result[vim.fs.normalize(vim.fs.joinpath(root, path))] = status(xy)
    -- Porcelain -z emits the destination first, then the rename/copy source.
    i = i + (xy:find("[RC]") and 2 or 1)
  end
  return result
end

function M.load(cwd, cb)
  if vim.fn.executable("git") == 0 then return cb({}) end
  vim.system({ "git", "rev-parse", "--show-toplevel" }, { cwd = cwd, text = true }, function(root)
    if root.code ~= 0 then return cb({}) end
    local directory = root.stdout:gsub("[\r\n]+$", "")
    vim.system({ "git", "--no-optional-locks", "status", "--porcelain=v1", "-z",
      "--untracked-files=all", "--ignored=matching" }, { cwd = directory }, function(res)
      cb(res.code == 0 and M.parse(res.stdout, directory) or {})
    end)
  end)
end

return M
