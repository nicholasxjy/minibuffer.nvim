local M = {}

local active_task = nil

local function item_text(item)
  local value = item.text
    or item.file
    or item.name
    or item.label
    or item.desc
    or tostring(item)
  return type(value) == "string" and value or tostring(value)
end

local function apply_overlays(line, overlays)
  if #overlays == 0 then
    return line
  end

  local ret = {}
  local offset = 0
  for _, chunk in ipairs(line) do
    local text = chunk.text or ""
    local boundaries = { 0, #text }
    local spans = {}
    for _, overlay in ipairs(overlays) do
      local start = math.max(0, overlay.start - offset)
      local finish = math.min(#text, overlay.finish - offset)
      if finish > start then
        spans[#spans + 1] = {
          start = start,
          finish = finish,
          hl = overlay.hl,
          priority = overlay.priority or 0,
        }
        boundaries[#boundaries + 1] = start
        boundaries[#boundaries + 1] = finish
      end
    end

    table.sort(boundaries)
    local unique = {}
    for _, boundary in ipairs(boundaries) do
      if unique[#unique] ~= boundary then
        unique[#unique + 1] = boundary
      end
    end

    for i = 1, #unique - 1 do
      local start = unique[i]
      local finish = unique[i + 1]
      local hl = chunk.hl
      local priority = -math.huge
      for _, span in ipairs(spans) do
        if span.start <= start and span.finish >= finish and span.priority >= priority then
          hl = span.hl
          priority = span.priority
        end
      end
      if finish > start then
        ret[#ret + 1] = {
          text = text:sub(start + 1, finish),
          hl = hl,
        }
      end
    end
    offset = offset + #text
  end
  return ret
end

local function format_item(format, picker, item)
  local line = {}
  local overlays = {}
  local offset_map = {}
  local native_offset = 0
  local display_offset = 0

  local function append_text(text, hl, field, virtual, resolved)
    local native_length = resolved and 0 or (virtual and vim.fn.strdisplaywidth(text) or #text)
    offset_map[#offset_map + 1] = {
      native_start = native_offset,
      native_finish = native_offset + native_length,
      display_start = display_offset,
      display_finish = display_offset + #text,
    }
    line[#line + 1] = { text = text, hl = hl, field = field }
    native_offset = native_offset + native_length
    display_offset = display_offset + #text
  end

  local function append(chunks, resolved)
    for _, chunk in ipairs(chunks or {}) do
      if chunk.resolve then
        local ok, resolved = pcall(chunk.resolve, math.max(vim.o.columns - 4, 20))
        if ok then
          append(resolved, true)
        end
      elseif type(chunk[1]) == "string" then
        local hl = chunk[2]
        if type(hl) == "table" then
          hl = hl[1]
        end
        append_text(chunk[1], hl, chunk.field, chunk.virtual, resolved)
      elseif chunk.virt_text then
        for _, text in ipairs(chunk.virt_text) do
          if type(text) == "table" and type(text[1]) == "string" then
            append_text(text[1], text[2], nil, true, resolved)
          end
        end
      elseif chunk.col and chunk.end_col and chunk.hl_group then
        overlays[#overlays + 1] = {
          native_start = chunk.col,
          native_finish = chunk.end_col,
          hl = chunk.hl_group,
          priority = chunk.priority
            or (chunk.hl_group == "SnacksPickerMatch" and 1000 or 10),
        }
      end
    end
  end

  if picker.resolve then
    pcall(picker.resolve, picker, item)
  end
  local source = picker.opts.source
  if picker.opts.format == "file" then
    picker.opts.source = "files"
  end
  local ok, chunks = pcall(format, item, picker)
  if ok then
    append(chunks)
  end
  picker.opts.source = source
  local file_format = picker.opts.format == "file"
    and picker.opts.formatters
    and picker.opts.formatters.file
  if
    item.file
    and file_format
    and file_format.filename_first
    and line[1]
    and line[2]
    and line[3]
    and line[2].text == " "
    and vim.fn.strdisplaywidth(line[1].text) <= 2
    and (line[1].text:match("^%s*$") or tostring(line[1].hl):find("GitStatus"))
  then
    local fff_insert_at = #line[1].text + #line[2].text
    table.insert(line, 3, { text = "   " })
    for _, overlay in ipairs(overlays) do
      overlay.fff_insert_at = fff_insert_at
    end
  end

  local function map_native(offset)
    for _, mapping in ipairs(offset_map) do
      if offset < mapping.native_finish then
        if mapping.native_finish == mapping.native_start then
          return mapping.display_start
        end
        if
          mapping.native_finish - mapping.native_start
            == mapping.display_finish - mapping.display_start
        then
          return mapping.display_start + offset - mapping.native_start
        end
        return mapping.display_start
      elseif offset == mapping.native_finish then
        return mapping.display_finish
      end
    end
    return display_offset
  end

  for _, overlay in ipairs(overlays) do
    local start = map_native(overlay.native_start)
    local finish = map_native(overlay.native_finish)
    if overlay.fff_insert_at and start >= overlay.fff_insert_at then
      start = start + 3
      finish = finish + 3
    end
    overlay.start = start
    overlay.finish = finish
  end
  local line_text = table.concat(vim.tbl_map(function(chunk)
    return chunk.text
  end, line))
  local matcher = picker.matcher
  if matcher and matcher.positions then
    local function add_positions(positions, offset, priority)
      for _, position in ipairs(positions or {}) do
        overlays[#overlays + 1] = {
          start = offset + position - 1,
          finish = offset + position,
          hl = "SnacksPickerMatch",
          priority = priority,
        }
      end
    end

    local full = {
      text = line_text:gsub("%s*$", ""),
      idx = 1,
      score = 0,
      file = item.file,
    }
    local ok, positions = pcall(matcher.positions, matcher, full)
    if ok then
      add_positions(positions and positions.text, 0, 1000)
    end

    local offset = 0
    for _, chunk in ipairs(line) do
      if chunk.field and chunk.text ~= "" then
        local field_item = {
          text = "",
          idx = 1,
          score = 0,
          file = item.file,
        }
        field_item[chunk.field] = chunk.text
        local field_ok, field_positions = pcall(matcher.positions, matcher, field_item)
        if field_ok then
          add_positions(field_positions and field_positions[chunk.field], offset, 1000)
        end
      end
      offset = offset + #chunk.text
    end
  end
  line = apply_overlays(line, overlays)
  for _, chunk in ipairs(line) do
    chunk.field = nil
  end
  if #line == 0 then
    line[1] = { text = item_text(item) }
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

local function clear(items)
  for key in pairs(items) do
    items[key] = nil
  end
end

local function contains(items, wanted)
  for _, item in ipairs(items) do
    if item == wanted then
      return true
    end
  end
  return false
end

local function action_spec(value)
  if type(value) ~= "table" then
    return value
  end
  if value.action ~= nil then
    local ret = vim.deepcopy(value)
    ret.mode = nil
    ret.desc = nil
    return ret
  end

  local ret = {}
  for i, entry in ipairs(value) do
    ret[i] = entry
  end
  return #ret == 1 and ret[1] or ret
end

local function action_modes(value)
  if type(value) ~= "table" or value.mode == nil then
    return true
  end
  if type(value.mode) == "string" then
    return value.mode == "i"
  end
  return vim.tbl_contains(value.mode, "i")
end

local ignored_input_actions = {
  cancel = true,
  confirm = true,
  list_down = true,
  list_up = true,
  select_and_next = true,
  select_and_prev = true,
}

local function action_name(spec)
  return type(spec) == "string" and spec or nil
end

local function start(source, user_opts)
  local Snacks = require("snacks")
  local config = Snacks.picker.config
  local requested_source = source
    or (type(user_opts) == "table" and user_opts.source)
  local canonical_source = (config.alias and config.alias[requested_source])
    or requested_source
    or "custom"
  local config_opts = vim.tbl_deep_extend("force", {
    -- Snacks' filename-first formatter has the same path order as fff.
    formatters = { file = { filename_first = true } },
  }, user_opts or {})
  config_opts.source = canonical_source
  local opts = config.get(config_opts)

  if active_task and active_task:running() then
    active_task:abort()
  end

  local found = {}
  local seen = {}
  local seen_paths = {}
  local current_items = {}
  local selected_items = {}
  local session
  local closed = false
  local task
  local run_generation = 0
  local latest_input = ""
  local latest_callback
  local update_pending = false
  local width_pending = false
  local started = false
  local loaded = false

  local picker = {
    closed = false,
    opts = opts,
    main = vim.api.nvim_get_current_win(),
    resolved_layout = { cycle = false },
    list = {},
    layout = {},
    preview = { state = {} },
    input = { mode = "i" },
  }
  local picker_ref = setmetatable({ value = picker }, {
    __call = function(ref)
      return ref.value
    end,
  })
  picker._main = { update = function() end }

  function picker:word()
    return vim.fn.expand("<cword>")
  end

  local filter = require("snacks.picker.core.filter").new(picker)
  local matcher = require("snacks.picker.core.matcher").new(opts.matcher)
  local sorter = config.sort(opts)
  local format = config.format(opts)
  picker.matcher = matcher
  matcher.task = {
    running = function()
      return not closed
    end,
    abort = function() end,
    on = function(_, event, callback)
      if event == "done" then
        vim.schedule(callback)
      end
      return matcher.task
    end,
  }

  local function current()
    return current_items[1]
  end

  function picker:cwd()
    return filter.cwd
  end

  function picker:count()
    return #found
  end

  function picker:set_cwd(cwd)
    filter:set_cwd(cwd)
    self.opts.cwd = cwd
  end

  function picker:current()
    return self._current_item or current()
  end

  function picker:selected(options)
    local items = {}
    if session and not session._closed then
      for _, index in ipairs(session._selected_indices) do
        if current_items[index] then
          items[#items + 1] = current_items[index]
        end
      end
    else
      items = vim.list_slice(selected_items)
    end
    if #items == 0 and options and options.fallback and picker:current() then
      items[1] = picker:current()
    end
    return items
  end

  function picker:items()
    return vim.list_slice(current_items)
  end

  function picker:iter()
    local index = 0
    local items = current_items
    return function()
      index = index + 1
      return items[index], index
    end
  end

  function picker:resolve(item)
    Snacks.picker.util.resolve(item)
    Snacks.picker.util.resolve_loc(item)
    return item
  end

  function picker:dir()
    local item = self:current()
    return item and Snacks.picker.util.dir(item) or self:cwd()
  end

  function picker:filter()
    return filter
  end

  function picker:ref()
    return picker_ref
  end

  function picker:on_current_tab()
    return true
  end

  function picker:norm(callback)
    return callback()
  end

  function picker:toggle()
    return false
  end

  function picker:focus()
    return false
  end

  function picker:set_layout()
    return false
  end

  function picker:hist()
    return false
  end

  function picker:show_preview()
    return false
  end

  function picker:update_titles()
    return false
  end

  local function deliver()
    if not closed and latest_callback then
      latest_callback(vim.list_slice(found))
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

  local function update_filename_width()
    if vim.in_fast_event() then
      if width_pending then
        return
      end
      width_pending = true
      vim.schedule(function()
        width_pending = false
        update_filename_width()
      end)
      return
    end
    local width = 0
    for _, item in ipairs(found) do
      local path = Snacks.picker.util.path(item)
      if path then
        width = math.max(width, vim.fn.strdisplaywidth(vim.fn.fnamemodify(path, ":t")))
      end
    end
    picker.list.filename_width = width
  end

  local ctx
  local transform = config.transform(opts)
  local transform_ctx = { meta = {} }
  local deduplicate_paths = canonical_source == "smart" or opts.transform == "unique_file"
  local function add(item)
    local limit = (opts.live and opts.limit_live or opts.limit) or math.huge
    if type(item) ~= "table" or #found >= limit or seen[item] then
      return
    end

    local context = opts.transform == "unique_file" and transform_ctx or ctx
    local transformed = transform and transform(item, context) or nil
    item = type(transformed) == "table" and transformed or item
    if transformed == false then
      return
    end
    if seen[item] then
      return
    end
    if deduplicate_paths then
      local path = Snacks.picker.util.path(item)
      if path and seen_paths[path] then
        return
      end
      if path then
        seen_paths[path] = true
      end
    end
    seen[item] = true
    item.idx = #found + 1
    item.score = item.score or matcher.DEFAULT_SCORE
    found[#found + 1] = item
    update_filename_width()
  end

  picker.list.items = found
  picker.list.add = function(_, item)
    add(item)
  end
  picker.list.update = function()
    if session and session.render then
      session:render()
    end
  end
  picker.list.set_target = function() end
  picker.list.count = function()
    return #current_items
  end
  picker.list.current = function()
    return picker:current()
  end
  picker.list.is_selected = function(_, item)
    return contains(picker:selected(), item)
  end
  picker.list.select = function(_, item)
    if session then
      if item then
        for index, current_item in ipairs(current_items) do
          if current_item == item then
            session._current_index = index
            break
          end
        end
      end
      session:toggle_selection()
    end
  end
  picker.list.select_all = function()
    if session then
      session:toggle_selection_all()
    end
  end
  picker.list.move = function(_, delta, absolute)
    if session then
      if absolute then
        session._current_index = math.max(1, math.min(#current_items, delta))
        session:render()
      else
        session:move(delta)
      end
    end
  end
  picker.list._move = picker.list.move
  picker.list.view = picker.list.move
  picker.list.height = function()
    return #current_items
  end
  picker.list.scroll = function() end
  picker.list.win = {
    win = vim.api.nvim_get_current_win(),
    focus = function() end,
    on = function() end,
    toggle_help = function() end,
  }

  picker.layout.maximize = function() end
  picker.layout.hide = function() end
  picker.layout.unhide = function() end
  picker.layout.split = false
  picker.preview.reset = function() end
  picker.preview.win = { valid = function() return false end }
  picker.input.filter = filter
  picker.input.win = { toggle_help = function() end }
  picker.input.get = function()
    return latest_input
  end
  picker.input.update = function() end
  picker.input.set = function(pattern, search)
    if pattern ~= nil then
      filter.pattern = pattern
    end
    if search ~= nil then
      filter.search = search
    end
    latest_input = opts.live and filter.search or filter.pattern
    if session and not closed then
      session._input = latest_input
      session:refresh_results()
    end
  end

  local find = config.finder(opts.finder)
    or function()
      return opts.items or {}
    end
  local finder = require("snacks.picker.core.finder").new(find)
  finder:init(filter)
  finder.items = found
  picker.finder = finder

  local function refresh_context()
    finder:init(filter)
    ctx = finder:ctx(picker)
  end
  refresh_context()

  matcher.cwd = vim.fs.normalize(opts.cwd or (vim.uv or vim.loop).cwd() or ".")
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

  local function abort_task()
    if task and task:running() then
      task:abort()
    end
    if active_task == task then
      active_task = nil
    end
  end

  local function run_finder(input, callback)
    run_generation = run_generation + 1
    local generation = run_generation
    abort_task()
    clear(found)
    clear(seen)
    clear(seen_paths)
    clear(transform_ctx.meta)
    clear(current_items)
    loaded = false
    started = true
    if opts.live then
      filter.search = input
    else
      filter.pattern = input
    end
    refresh_context()

    local result = find(opts, ctx)
    if type(result) == "table" then
      for _, item in ipairs(result) do
        add(item)
      end
      loaded = true
      callback(vim.list_slice(found))
      if opts.auto_confirm and #found == 1 and session then
        vim.schedule(function()
          if not closed then
            session:accept()
          end
        end)
      end
      return
    end
    if type(result) ~= "function" then
      loaded = true
      callback({})
      return
    end

    local Async = require("snacks.picker.util.async")
    task = Async.new(function()
      ctx.async = Async.running()
      result(function(item)
        if closed or generation ~= run_generation then
          return
        end
        add(item)
        request_delivery()
      end)
    end):on("done", function()
      if generation ~= run_generation or closed then
        return
      end
      loaded = true
      vim.schedule(deliver)
      if opts.auto_confirm and #found == 1 and session then
        vim.schedule(function()
          if not closed then
            session:accept()
          end
        end)
      end
    end)
    active_task = task
  end

  local function execute_action(spec, item)
    local Actions = require("snacks.picker.core.actions")
    local ok, err = pcall(function()
      local resolved = Actions.resolve(spec or "jump", picker, "confirm")
      resolved.action(picker, item, resolved)
    end)
    if not ok then
      vim.notify("Snacks picker action failed: " .. tostring(err), vim.log.levels.ERROR)
    end
    return ok
  end

  function picker:action(spec)
    return execute_action(spec, self:current())
  end

  function picker:refresh()
    if session and session.refresh_results and not closed then
      started = false
      loaded = false
      session:refresh_results()
    end
  end

  function picker:find(options)
    self:refresh()
    if options and options.on_done then
      vim.schedule(options.on_done)
    end
  end

  function picker:close()
    if closed then
      return
    end
    closed = true
    self.closed = true
    picker_ref.value = nil
    abort_task()
    if session and not session._closed then
      session:close()
    end
  end

  local input_actions = opts.win and opts.win.input and opts.win.input.keys or {}
  local function install_actions(keyset)
    for lhs, value in pairs(input_actions) do
      local spec = action_spec(value)
      if action_modes(value)
        and not (type(value) == "table" and value.expr)
        and not ignored_input_actions[action_name(spec)]
        and spec ~= nil
      then
        keyset("i", lhs, function()
          execute_action(spec, picker:current())
        end)
      end
    end
  end

  local initial_text = opts.live and filter.search or filter.pattern or ""
  local prompt = opts.title
    or (canonical_source == "smart" and "Smart" or canonical_source:gsub("_", " "))
  prompt = prompt:gsub("^%l", string.upper)
  local result = require("minibuffer").select({
    resumable = true,
    prompt = tostring(prompt):gsub("%s+$", "") .. ": ",
    initial_text = initial_text,
    multi = true,
    fetch_fn = function(input, callback)
      latest_input = input
      latest_callback = callback
      if opts.live then
        run_finder(input, callback)
      elseif loaded then
        deliver()
      elseif not started then
        run_finder(input, callback)
      else
        request_delivery()
      end
    end,
    format_fn = function(item)
      return format_item(format, picker, item)
    end,
    filter_fn = function(ctx_value)
      local items = opts.live and ctx_value.items or match_items(ctx_value.input)
      current_items = items
      picker.list.items = current_items
      picker._current_item = current_items[ctx_value.current_index]
      return items
    end,
    on_start = function(sess, keyset)
      session = sess
      picker.input.win.win = sess._entry.win
      picker.input.win.buf = sess._entry.buf
      install_actions(keyset)
      if opts.on_show then
        pcall(opts.on_show, picker)
      end
      if opts.on_start then
        pcall(opts.on_start, picker, keyset)
      end
    end,
    on_change = function(input, item)
      latest_input = input
      picker._current_item = item
      if opts.on_change then
        pcall(opts.on_change, picker, item)
      end
    end,
    on_select = function(selection)
      selected_items = vim.tbl_map(function(entry)
        return entry.item
      end, selection)
      picker._current_item = selected_items[1] or current()
      closed = true
      picker.closed = true
      picker_ref.value = nil
      abort_task()
      local spec = opts.actions and opts.actions.confirm
      if spec == nil and not opts.multi then
        spec = opts.confirm
      end
      spec = spec or "jump"
      if not execute_action(spec, picker:current()) then
        open_item(picker:current())
      end
    end,
    on_close = function()
      closed = true
      picker.closed = true
      picker_ref.value = nil
      matcher:close()
      abort_task()
      if opts.on_close then
        pcall(opts.on_close, picker)
      end
    end,
  })
  if type(session) ~= "table" then
    session = nil
  end
  return result
end

function M.smart(opts)
  return start("smart", opts)
end

function M.buffers(opts)
  return start("buffers", opts)
end

function M.pick(source, user_opts)
  if type(source) == "table" and user_opts == nil then
    user_opts = source
    source = nil
  end
  if not source and type(user_opts) == "table" then
    source = user_opts.source
  end
  if not source
    and not (
      type(user_opts) == "table"
      and (user_opts.items or user_opts.finder or user_opts.multi)
    )
  then
    source = "pickers"
  end
  return start(source or "custom", user_opts)
end

function M.setup()
  local picker = require("snacks.picker")
  local config = picker.config
  local resolved = config.get()
  for source, source_opts in pairs(resolved.sources or {}) do
    if
      source ~= "select"
      and source ~= "resume"
      and (source_opts.finder or source_opts.multi or source_opts.items or source == "smart")
    then
      M[source] = M[source] or function(opts)
        return start(source, opts)
      end
      picker[source] = M[source]
    end
  end

  for alias, source in pairs(config.alias or {}) do
    if resolved.sources[source] then
      M[alias] = M[alias] or function(opts)
        return start(source, opts)
      end
      picker[alias] = M[alias]
    end
  end
  picker.pick = M.pick
  return M
end

return M
