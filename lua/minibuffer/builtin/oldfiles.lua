local function is_in_cwd(path, cwd)
  return vim.fs.relpath(cwd, path) ~= nil
end

local function gather_oldfiles(cwd)
  local files = vim.v.oldfiles or {}
  local items = {}

  cwd = cwd and vim.fn.fnamemodify(cwd, ":p")
  for _, path in ipairs(files) do
    path = vim.fn.fnamemodify(path, ":p")
    if vim.fn.filereadable(path) == 1 then
      if not cwd or is_in_cwd(path, cwd) then
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

local function filter_fn(ctx)
  if ctx.input == "" then
    return ctx.items
  end

  local paths = {}
  local lookup = {}

  for _, item in ipairs(ctx.items) do
    paths[#paths + 1] = item.path
    lookup[item.path] = item
  end
  local matches = vim.fn.matchfuzzy(paths, ctx.input)

  local results = {}
  for _, path in ipairs(matches) do
    results[#results + 1] = lookup[path]
  end

  return results
end

---@class minibuffer.builtin.OldfilesOpts: minibuffer.builtin.Opts
---@field cwd string|nil

---@param opts minibuffer.builtin.OldfilesOpts
return function(opts)
  require("minibuffer.internal.guard").check()

  opts = require("minibuffer.builtin.config").resolve(opts)

  local oldfiles = gather_oldfiles(opts.cwd or (opts.filter.cwd and vim.fn.getcwd() or nil))
  require("minibuffer.builtin.config").select(opts, {
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
        vim.cmd("edit " .. vim.fn.fnameescape(item.path))
        vim.cmd('normal! g`"')
        return
      end

      local qf = {}
      for _, selected in ipairs(selection) do
        local item = selected.item
        qf[#qf + 1] = {
          filename = vim.fn.fnameescape(item.path),
          lnum = 1,
          col = 1,
        }
      end

      vim.fn.setqflist({}, " ", { title = "Selected Oldfiles", items = qf })
      vim.cmd("copen")
    end,
    on_start = function(sess, keyset)
      require("minibuffer.builtin.config").bind(keyset, opts.keymaps.split, function()
        local selected = sess:get_selected()
        if selected then
          if selected then
            sess:close(function()
              vim.cmd("split " .. vim.fn.fnameescape(selected.path))
            end)
          end
        end
      end)
      require("minibuffer.builtin.config").bind(keyset, opts.keymaps.vsplit, function()
        local selected = sess:get_selected()
        if selected then
          if selected then
            sess:close(function()
              vim.cmd("vsplit " .. vim.fn.fnameescape(selected.path))
            end)
          end
        end
      end)
    end,
    footer_fn = function(ctx)
      return require("minibuffer.builtin.buffers-ui").footer(ctx,
        vim.tbl_extend("force", opts.keymaps, { delete = {} }), #oldfiles)
    end,
  })
end
