local M = {}

local active_task = nil

local function format_item(format, picker, item)
  local line = {}

  local function append(chunks)
    for _, chunk in ipairs(chunks or {}) do
      if chunk.resolve then
        append(chunk.resolve(math.max(vim.o.columns - 4, 20)))
      elseif type(chunk[1]) == "string" then
        line[#line + 1] = {
          text = chunk[1],
          hl = type(chunk[2]) == "table" and chunk[2][1] or chunk[2],
        }
      elseif chunk.virt_text then
        for _, text in ipairs(chunk.virt_text) do
          line[#line + 1] = { text = text[1], hl = text[2] }
        end
      end
    end
  end

  append(format(item, picker))
  if #line == 0 then
    line[1] = { text = item.text or tostring(item) }
  end
  return line
end

local function open_item(item)
  local Snacks = require("snacks")
  if item.buf and vim.api.nvim_buf_is_valid(item.buf) then
    vim.cmd.buffer(item.buf)
  else
    local path = Snacks.picker.util.path(item)
    if not path then
      return
    end
    vim.cmd.edit(vim.fn.fnameescape(path))
  end

  if item.pos and item.pos[1] > 0 then
    pcall(vim.api.nvim_win_set_cursor, 0, { item.pos[1], item.pos[2] })
  end
end

local function start(source, user_opts)
  local Snacks = require("snacks")
  local config = Snacks.picker.config
  local opts = config.get(vim.tbl_deep_extend("force", {
    source = source,
  }, user_opts or {}))

  if active_task and active_task:running() then
    active_task:abort()
  end

  local picker = {
    closed = false,
    opts = opts,
  }
  local filter = require("snacks.picker.core.filter").new(picker)
  local matcher = require("snacks.picker.core.matcher").new(opts.matcher)
  local sorter = config.sort(opts)
  local format = config.format(opts)
  local found = {}

  function picker:cwd()
    return filter.cwd
  end

  function picker:count()
    return #found
  end

  local find = assert(config.finder(opts.finder), "minibuffer: Snacks picker finder not found")
  local finder = require("snacks.picker.core.finder").new(find)
  finder:init(filter)
  local ctx = finder:ctx(picker)
  local transform = config.transform(opts)
  local limit = opts.limit or math.huge

  local function add(item)
    if #found >= limit then
      return
    end
    local transformed
    if transform then
      transformed = transform(item, ctx)
    end
    item = type(transformed) == "table" and transformed or item
    if transformed ~= false then
      item.idx = #found + 1
      item.score = require("snacks.picker.core.matcher").DEFAULT_SCORE
      found[#found + 1] = item
    end
  end

  local result = find(opts, ctx)
  local loaded = type(result) == "table"
  if loaded then
    for _, item in ipairs(result) do
      add(item)
    end
  end

  matcher.cwd = svim.fs.normalize(opts.cwd or (vim.uv or vim.loop).cwd() or ".")
  local function match_items(input)
    matcher:init(input)
    if input == "" and not opts.matcher.sort_empty then
      return vim.list_slice(found)
    end

    local matched = {}
    for _, item in ipairs(found) do
      if matcher:update(picker, item) then
        matched[#matched + 1] = item
      end
    end
    table.sort(matched, sorter)
    return matched
  end

  local closed = false
  local task = nil
  local latest_input = ""
  local latest_callback = nil
  local update_pending = false

  local function deliver()
    if not closed and latest_callback then
      latest_callback(match_items(latest_input))
    end
  end

  local function request_delivery()
    if update_pending then
      return
    end
    update_pending = true
    vim.defer_fn(function()
      update_pending = false
      deliver()
    end, 20)
  end

  local started = false
  local function fetch(input, callback)
    latest_input = input
    latest_callback = callback
    if loaded then
      return deliver()
    end
    request_delivery()
    if started then
      return
    end
    started = true

    local Async = require("snacks.picker.util.async")
    task = Async.new(function()
      ctx.async = Async.running()
      result(function(item)
        add(item)
        request_delivery()
      end)
    end):on("done", function()
      loaded = true
      vim.schedule(deliver)
    end)
    active_task = task
  end

  local prompt = opts.title or (source == "smart" and "Smart" or "Buffers")
  return require("minibuffer").select({
    prompt = prompt .. ":",
    items = loaded and found or {},
    async_fetch = loaded and nil or fetch,
    max_height = 15,
    allow_shrink = false,
    format_fn = function(item)
      return format_item(format, picker, item)
    end,
    filter_fn = function(items, input)
      return loaded and match_items(input) or items
    end,
    on_select = function(items)
      if items[1] then
        open_item(items[1])
      end
    end,
    on_close = function()
      closed = true
      picker.closed = true
      matcher:close()
      if task and task:running() then
        task:abort()
      end
      if active_task == task then
        active_task = nil
      end
    end,
  })
end

function M.smart(opts)
  return start("smart", opts)
end

function M.buffers(opts)
  return start("buffers", opts)
end

function M.setup()
  local picker = require("snacks.picker")
  picker.smart = M.smart
  picker.buffers = M.buffers
end

return M
