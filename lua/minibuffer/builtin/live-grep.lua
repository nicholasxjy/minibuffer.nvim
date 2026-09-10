if vim.fn.executable("rg") == 0 then
  vim.notify("rg is required for using the grep picker")
  return function() end
end

local util = require("minibuffer.internal.util")
local ui = require("minibuffer.builtin.live-grep-ui")

local debounce = util.make_debounced(100)
local generation = 0
local current_proc ---@type vim.SystemObj?

local function parse_rg_line(line)
  local event = vim.json.decode(line)
  if event.type ~= "match" then
    return nil
  end
  local data = event.data
  local function decode(value)
    return value.text or vim.base64.decode(value.bytes)
  end
  return {
    file = decode(data.path),
    line = data.line_number,
    col = data.submatches[1] and data.submatches[1].start + 1 or 1,
    text = decode(data.lines):gsub("\r?\n$", ""),
    matches = data.submatches,
  }
end

local function filter_fn(ctx, current_file, cwd)
  local groups, order, width = {}, {}, 0
  for _, item in ipairs(ctx.items) do
    if not groups[item.file] then
      groups[item.file] = {}
      order[#order + 1] = item.file
    end
    table.insert(groups[item.file], item)
    width = math.max(width, #tostring(item.line) + #tostring(item.col) + 1)
  end
  if current_file and current_file ~= "" then
    for i, file in ipairs(order) do
      local path = file:match("^/") or file:match("^%a:[/\\]")
      path = vim.fn.fnamemodify(path and file or vim.fs.joinpath(cwd, file), ":p")
      if vim.fs.normalize(path) == current_file then
        table.insert(order, 1, table.remove(order, i))
        break
      end
    end
  end
  local items = {}
  for _, file in ipairs(order) do
    for _, item in ipairs(groups[file]) do
      item.location_width = width
      items[#items + 1] = item
    end
  end
  return items
end

local function run_grep(opts, input, cb)
  generation = generation + 1
  local current = generation
  if current_proc then
    current_proc:kill("sigterm")
    current_proc = nil
  end
  if input == "" then
    cb({})
    return
  end

  local cmd = vim.list_extend({}, opts.rg_opts)
  cmd[#cmd + 1] = "--json"
  cmd[#cmd + 1] = "-e"
  cmd[#cmd + 1] = input

  local system_opts = { text = true }

  if opts.cwd then
    system_opts.cwd = opts.cwd
  end

  current_proc = vim.system(cmd, system_opts, function(res)
    if current ~= generation then
      return
    end
    current_proc = nil

    local out = {}

    if res.code ~= 0 and res.code ~= 1 then
      cb(nil, res.stderr)
      return
    end

    for _, line in ipairs(vim.split(res.stdout, "\n", { trimempty = true })) do
      local item = parse_rg_line(line)
      if item then
        out[#out + 1] = item
      end
    end
    cb(out)
  end)
end

---@class minibuffer.builtin.LiveGrepOpts: minibuffer.builtin.Opts
---@field current_file_first? boolean Put the invoking buffer's file first (default false).
---@field query? string Initial search query.
---@field rg_opts string[]|nil
---@field cwd string|nil
---@field filename_first? boolean Show filename before directory (default true).
---@field keymaps? minibuffer.config.select.keymaps Navigation keys, each a string or list.

---@param opts? minibuffer.builtin.LiveGrepOpts|string
return function(opts)
  require("minibuffer.internal.guard").check()
  if type(opts) == "string" then opts = { query = opts } end

  ---@type minibuffer.builtin.LiveGrepOpts
  local default_opts = {
    rg_opts = {
      "rg",
      "--with-filename",
      "--line-number",
      "--column",
      "--no-heading",
      "--color=never",
      "--no-config",
      "--smart-case",
      "--hidden",
      "-g",
      "!**/.git/**",
    },
    cwd = nil,
  }
  opts = require("minibuffer.builtin.config").resolve(opts, default_opts)
  opts.cwd = vim.fs.normalize(opts.cwd or vim.fn.getcwd())
  vim.validate("current_file_first", opts.current_file_first, "boolean", true)
  local current_file = opts.current_file_first and vim.api.nvim_buf_get_name(0) or nil
  if current_file and current_file ~= "" then current_file = vim.fs.normalize(current_file) end
  vim.validate("filename_first", opts.filename_first, "boolean", true)
  local keymaps = opts.keymaps
  ui.setup()
  local session

  require("minibuffer.builtin.config").select(opts, {
    query = opts.query,
    resumable = true,
    keymaps = keymaps,
    group_fn = function(item, previous)
      return ui.group(item, previous, opts.filename_first)
    end,
    prompt = "> ",
    prompt_position = "top",
    highlights = {
      normal = "FzfLuaFzfNormal",
      query = "FzfLuaLivePrompt",
      prompt = "FzfLuaFzfPrompt",
      selection = "FzfLuaFzfCursorLine",
      multi_selection = "FzfLuaFzfNormal",
      loading = "FzfLuaFzfSpinner",
    },
    header_position = "bottom",
    header_fn = function(ctx, width)
      return ui.header(ctx, width, opts.cwd, keymaps)
    end,
    on_change = function()
      if session then
        ui.info(session)
      end
    end,
    multi = true,
    dynamic_height = false,
    max_height = 18,
    fetch_fn = function(input, cb)
      debounce(function()
        run_grep(opts, input, cb)
      end)
    end,
    format_fn = ui.format,
    filter_fn = function(ctx)
      return filter_fn(ctx, current_file, opts.cwd)
    end,
    on_accept = function(selection)
      if #selection == 1 then
        local item = selection[1].item

        vim.cmd("edit " .. vim.fn.fnameescape(vim.fs.joinpath(opts.cwd, item.file)))
        pcall(vim.api.nvim_win_set_cursor, 0, {
          item.line,
          item.col - 1,
        })
        vim.cmd("normal! zz")
        return
      end

      local qf = {}

      for _, selected in ipairs(selection) do
        local item = selected.item
        qf[#qf + 1] = {
          filename = vim.fs.joinpath(opts.cwd, item.file),
          lnum = item.line,
          col = item.col,
          text = item.text,
        }
      end

      vim.fn.setqflist({}, " ", { title = "Grep Results", items = qf })
      vim.cmd("copen")
    end,
    on_start = function(sess, keyset)
      session = sess
      ui.info(sess)
      require("minibuffer.builtin.config").bind(keyset, keymaps.split, function()
        local selected = sess:get_selected()
        if selected then
          sess:close(function()
            vim.cmd(
              "split " .. vim.fn.fnameescape(vim.fs.joinpath(opts.cwd, selected.file))
            )
            pcall(vim.api.nvim_win_set_cursor, 0, {
              selected.line,
              selected.col - 1,
            })
            vim.cmd("normal! zz")
          end)
        end
      end)
      require("minibuffer.builtin.config").bind(keyset, keymaps.vsplit, function()
        local selected = sess:get_selected()
        if selected then
          sess:close(function()
            vim.cmd(
              "vsplit " .. vim.fn.fnameescape(vim.fs.joinpath(opts.cwd, selected.file))
            )
            pcall(vim.api.nvim_win_set_cursor, 0, {
              selected.line,
              selected.col - 1,
            })
            vim.cmd("normal! zz")
          end)
        end
      end)
    end,
  })
end
