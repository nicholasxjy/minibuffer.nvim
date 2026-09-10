local actions = require("minibuffer.builtin.actions")
local config = require("minibuffer.builtin.config")
local function format_fn(item)
  return {
    { text = item, hl = "Normal" },
  }
end

local filter_fn = require("minibuffer.builtin.match").fuzzy()

---@class minibuffer.builtin.GitFilesOpts: minibuffer.builtin.Opts
---@field cwd? string
---@field show_untracked? boolean

---@param opts? minibuffer.builtin.GitFilesOpts
return function(opts)
  require("minibuffer.internal.guard").check()

  opts = config.resolve(opts)
  local cwd = vim.fn.fnamemodify(opts.cwd or vim.fn.getcwd(), ":p")
  opts.cwd = cwd
  local show_untracked = opts.show_untracked == true

  local git = vim
    .system({
      "git",
      "-C",
      cwd,
      "rev-parse",
      "--is-inside-work-tree",
    }, {
      text = true,
    })
    :wait()
  if git.code ~= 0 or vim.trim(git.stdout or "") ~= "true" then
    vim.notify(("Not a git repository: %s"):format(cwd), vim.log.levels.ERROR)
    return
  end

  config.select(opts, {
    resumable = true,
    prompt = "Git Files: ",
    multi = true,
    dynamic_height = false,
    max_height = 15,
    fetch_fn = function(_, cb)
      local g_opts = {
        "git",
        "-C",
        cwd,
        "ls-files",
        "--cached",
        "--exclude-standard",
      }
      if show_untracked then
        table.insert(g_opts, "--others")
      end
      vim.system(g_opts, {
        text = true,
      }, function(res)
        if res.code ~= 0 then
          cb(nil, res.stderr)
          return
        end

        local items = vim.split(res.stdout or "", "\n", {
          trimempty = true,
        })
        cb(items)
      end)
    end,
    format_fn = format_fn,
    filter_fn = filter_fn,
    on_accept = function(selection)
      if #selection == 1 then
        local item = selection[1].item
        actions.open_file(vim.fs.joinpath(cwd, item))
        return
      end

      actions.quickfix(selection, "Selected Files", function(item)
        return {
          filename = vim.fs.joinpath(opts.cwd, item),
          lnum = 1,
          col = 1,
        }
      end)
    end,
    on_start = function(sess, keyset)
      actions.bind_open(sess, keyset, opts.keymaps, function(item, command)
        actions.open_file(vim.fs.joinpath(cwd, item), command)
      end)
    end,
    footer_fn = function(ctx)
      return require("minibuffer.builtin.buffers-ui").footer(
        ctx,
        vim.tbl_extend("force", opts.keymaps, { delete = {} }),
        #ctx.items
      )
    end,
  })
end
