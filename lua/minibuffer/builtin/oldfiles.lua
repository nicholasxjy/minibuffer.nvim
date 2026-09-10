local actions = require("minibuffer.builtin.actions")
local config = require("minibuffer.builtin.config")

local function gather_oldfiles(cwd)
  local files = vim.v.oldfiles or {}
  local items = {}

  cwd = cwd and vim.fn.fnamemodify(cwd, ":p")
  for _, path in ipairs(files) do
    path = vim.fn.fnamemodify(path, ":p")
    if vim.fn.filereadable(path) == 1 then
      if not cwd or vim.fs.relpath(cwd, path) ~= nil then
        items[#items + 1] = {
          path = path,
          name = vim.fn.fnamemodify(path, ":t"),
        }
      end
    end
  end

  return items
end

local function format_fn(item)
  local dir = vim.fn.fnamemodify(item.path, ":h")
  return {
    { text = item.name, hl = "Normal" },
    { text = "  " .. dir, hl = "Comment" },
  }
end

local filter_fn = require("minibuffer.builtin.match").fuzzy("path")

---@class minibuffer.builtin.OldfilesOpts: minibuffer.builtin.Opts
---@field cwd string|nil

---@param opts minibuffer.builtin.OldfilesOpts
return function(opts)
  require("minibuffer.internal.guard").check()

  opts = config.resolve(opts)

  local oldfiles =
    gather_oldfiles(opts.cwd or (opts.filter.cwd and vim.fn.getcwd() or nil))
  config.select(opts, {
    resumable = true,
    prompt = "Oldfiles: ",
    multi = true,
    dynamic_height = false,
    max_height = 15,
    fetch_fn = function(_, cb)
      cb(oldfiles)
    end,
    format_fn = function(item)
      if opts.filename_first == false then
        return { { text = item.path, hl = "Normal" } }
      end
      return format_fn(item)
    end,
    filter_fn = filter_fn,
    on_accept = function(selection)
      if #selection == 1 then
        local item = selection[1].item
        actions.open_file(item.path)
        vim.cmd('normal! g`"')
        return
      end

      actions.quickfix(selection, "Selected Oldfiles", function(item)
        return {
          filename = item.path,
          lnum = 1,
          col = 1,
        }
      end)
    end,
    on_start = function(sess, keyset)
      actions.bind_open(sess, keyset, opts.keymaps, function(item, command)
        actions.open_file(item.path, command)
      end)
    end,
    footer_fn = function(ctx)
      return require("minibuffer.builtin.buffers-ui").footer(
        ctx,
        vim.tbl_extend("force", opts.keymaps, { delete = {} }),
        #oldfiles
      )
    end,
  })
end
