local M = {}

local SETUP_FIELD = "__minibuffer_snacks_picker_setup"
local widths = setmetatable({}, { __mode = "k" })
local status_lookups = setmetatable({}, { __mode = "k" })

---@class minibuffer.integrations.SnacksPickerOpts
---@field pickers? boolean|table<string, boolean> Per-picker minibuffer overrides
---@field smart? boolean|{git_status?: boolean} Enable git-aware smart picker decorations

local git_statuses = {
  modified = {
    name = "modified",
    changed = true,
    hl = "FFFGitModified",
    sign = "┃",
    sign_hl = "FFFGitSignModified",
    sign_hl_selected = "FFFGitSignModifiedSelected",
  },
  staged_new = {
    name = "staged_new",
    changed = true,
    hl = "FFFGitStaged",
    sign = "┃",
    sign_hl = "FFFGitSignStaged",
    sign_hl_selected = "FFFGitSignStagedSelected",
  },
  staged_modified = {
    name = "staged_modified",
    changed = true,
    hl = "FFFGitStaged",
    sign = "┃",
    sign_hl = "FFFGitSignStaged",
    sign_hl_selected = "FFFGitSignStagedSelected",
  },
  staged_deleted = {
    name = "staged_deleted",
    changed = true,
    hl = "FFFGitStaged",
    sign = "▁",
    sign_hl = "FFFGitSignStaged",
    sign_hl_selected = "FFFGitSignStagedSelected",
  },
  deleted = {
    name = "deleted",
    changed = true,
    hl = "FFFGitDeleted",
    sign = "▁",
    sign_hl = "FFFGitSignDeleted",
    sign_hl_selected = "FFFGitSignDeletedSelected",
  },
  renamed = {
    name = "renamed",
    changed = true,
    hl = "FFFGitRenamed",
    sign = "┃",
    sign_hl = "FFFGitSignRenamed",
    sign_hl_selected = "FFFGitSignRenamedSelected",
  },
  untracked = {
    name = "untracked",
    changed = true,
    hl = "FFFGitUntracked",
    sign = "┆",
    sign_hl = "FFFGitSignUntracked",
    sign_hl_selected = "FFFGitSignUntrackedSelected",
  },
  ignored = {
    name = "ignored",
    changed = false,
    hl = "FFFGitIgnored",
    sign = "",
    sign_hl = "FFFGitSignIgnored",
    sign_hl_selected = "FFFGitSignIgnoredSelected",
  },
}

local git_status_aliases = {
  added = "staged_new",
  staged = "staged_modified",
}
local staged_status_codes = {
  A = "staged_new",
  C = "renamed",
  D = "staged_deleted",
  M = "staged_modified",
  R = "renamed",
  T = "staged_modified",
  U = "staged_modified",
}
local worktree_status_codes = {
  A = "untracked",
  C = "renamed",
  D = "deleted",
  M = "modified",
  R = "renamed",
  T = "modified",
  U = "modified",
}
local single_status_codes = {
  ["?"] = "untracked",
  ["!"] = "ignored",
  A = "staged_new",
  C = "renamed",
  D = "deleted",
  M = "modified",
  R = "renamed",
  T = "modified",
  U = "modified",
}
local git_status_names = {
  "staged_deleted",
  "staged_modified",
  "staged_new",
  "staged",
  "untracked",
  "renamed",
  "deleted",
  "added",
  "modified",
  "ignored",
}

local git_highlight_defaults = {
  FFFGitStaged = { fg = "#10B981", ctermfg = 2, default = true },
  FFFGitModified = { fg = "#F59E0B", ctermfg = 3, default = true },
  FFFGitDeleted = { fg = "#EF4444", ctermfg = 1, default = true },
  FFFGitRenamed = { fg = "#8B5CF6", ctermfg = 5, default = true },
  FFFGitUntracked = { fg = "#10B981", ctermfg = 2, default = true },
  FFFGitIgnored = { fg = "#4B5563", ctermfg = 8, default = true },
  FFFGitSignStaged = { fg = "#10B981", ctermfg = 2, default = true },
  FFFGitSignModified = { fg = "#F59E0B", ctermfg = 3, default = true },
  FFFGitSignDeleted = { fg = "#EF4444", ctermfg = 1, default = true },
  FFFGitSignRenamed = { fg = "#8B5CF6", ctermfg = 5, default = true },
  FFFGitSignUntracked = { fg = "#10B981", ctermfg = 2, default = true },
  FFFGitSignIgnored = { fg = "#4B5563", ctermfg = 8, default = true },
}
local git_highlights_ready = false
local fff_highlights

local function get_fff_highlights()
  if fff_highlights == false then
    if not package.loaded["fff.highlights"] then
      return
    end
    fff_highlights = nil
  end
  if fff_highlights then
    return fff_highlights
  end
  local ok, highlights = pcall(require, "fff.highlights")
  if not ok or type(highlights) ~= "table" then
    fff_highlights = false
    return
  end
  fff_highlights = highlights
  return highlights
end

local function ensure_git_highlights()
  if git_highlights_ready then
    return
  end
  git_highlights_ready = true
  for name, value in pairs(git_highlight_defaults) do
    pcall(vim.api.nvim_set_hl, 0, name, value)
  end
  local visual_id = vim.fn.synIDtrans(vim.fn.hlID("Visual"))
  local visual_bg = vim.fn.synIDattr(visual_id, "bg", "gui")
  local visual_cterm_bg = vim.fn.synIDattr(visual_id, "bg", "cterm")
  visual_cterm_bg = tonumber(visual_cterm_bg) or "NONE"
  local selected = {
    { "FFFGitSignStagedSelected", "#10B981", 2 },
    { "FFFGitSignModifiedSelected", "#F59E0B", 3 },
    { "FFFGitSignDeletedSelected", "#EF4444", 1 },
    { "FFFGitSignRenamedSelected", "#8B5CF6", 5 },
    { "FFFGitSignUntrackedSelected", "#10B981", 2 },
    { "FFFGitSignIgnoredSelected", "#4B5563", 8 },
  }
  for _, value in ipairs(selected) do
    pcall(vim.api.nvim_set_hl, 0, value[1], {
      fg = value[2],
      bg = visual_bg ~= "" and visual_bg or "NONE",
      ctermfg = value[3],
      ctermbg = visual_cterm_bg ~= "" and visual_cterm_bg or "NONE",
      default = true,
    })
  end
end

local function normalize_path(path)
  return (path or "")
    :gsub("\\", "/")
    :gsub("^%./", "")
    :gsub("/$", "")
end

local function status_kind(value)
  local staged
  if type(value) == "table" then
    staged = value.staged == true
    value = value.code
      or value.xy
      or value.status
      or value.git_status
      or (value.index and value.worktree and (value.index .. value.worktree))
      or value[1]
  end
  if type(value) ~= "string" then
    return
  end

  local first = value:sub(1, 1):upper()
  local second = value:sub(2, 2):upper()
  if #value == 2 then
    local name
    if first == "?" or second == "?" then
      name = "untracked"
    elseif first == "!" or second == "!" then
      name = "ignored"
    else
      name = worktree_status_codes[second] or staged_status_codes[first]
    end
    if name then
      return git_statuses[name]
    end
  end
  value = value:lower():gsub("^%s+", ""):gsub("%s+$", "")
  if value == "" or value == "clean" then
    return
  end
  if value == "unknown" then
    return git_statuses.untracked
  end
  if value:find("unstaged", 1, true) then
    return git_statuses.modified
  end
  for _, name in ipairs(git_status_names) do
    if value:find(name, 1, true) then
      name = git_status_aliases[name] or name
      if staged then
        name = name == "added" and "staged_new"
          or name == "modified" and "staged_modified"
          or name == "deleted" and "staged_deleted"
          or name
      end
      return git_statuses[name]
    end
  end

  local code = value:gsub("%s", ""):upper()
  local name = single_status_codes[code]
    or staged_status_codes[code:sub(1, 1)]
    or worktree_status_codes[code:sub(2, 2)]
    or worktree_status_codes[code:sub(1, 1)]
  return name and git_statuses[name]
end

local function item_status(item)
  local status = item and status_kind(item.status)
  return status or (item and status_kind(item.git_status))
end

local function is_current_item(picker, item)
  local list = picker and picker.list
  if type(list) ~= "table" or type(item) ~= "table" then
    return false
  end
  local current
  if type(list.current) == "function" then
    local ok, value = pcall(list.current, list)
    current = ok and value or nil
  end
  if not current and type(list.get) == "function" then
    local ok, value = pcall(list.get, list, list.cursor or 1)
    current = ok and value or nil
  end
  if current == item then
    return true
  end
  return current ~= nil
    and current.file == item.file
    and current.cwd == item.cwd
end

local function absolute_path(path)
  if vim.fs.abspath then
    return vim.fs.abspath(path)
  end
  return vim.fn.fnamemodify(path, ":p")
end

local function git_status_lookup(Snacks, opts)
  opts = type(opts) == "table" and opts or {}
  if status_lookups[opts] then
    return status_lookups[opts]
  end

  local repositories = {}
  local cwd = type(opts.cwd) == "string" and opts.cwd or (vim.uv or vim.loop).cwd()
  cwd = absolute_path(vim.fs.normalize(cwd or "."))

  local function load(root)
    if repositories[root] then
      return repositories[root]
    end
    -- Snacks sorts in fast events, where vim.system's Vim API calls cannot run.
    if vim.in_fast_event() then
      return require("snacks.picker.util.async").running():schedule(function()
        return load(root)
      end)
    end
    local statuses = {}
    repositories[root] = statuses
    -- ponytail: one synchronous status scan per repository per picker; make it
    -- async if large repos stall UI.
    local ok, result = pcall(function()
      return vim.system({
        "git",
        "-C",
        root,
        "status",
        "--porcelain=v1",
        "-z",
        "--untracked-files=all",
        "--ignored=matching",
      }, { text = true }):wait()
    end)
    if not ok or not result or result.code ~= 0 then
      return statuses
    end

    local parts = vim.split(result.stdout or "", "\0", { plain = true, trimempty = true })
    local index = 1
    while index <= #parts do
      local entry = parts[index]
      local code = entry:sub(1, 2)
      local status = status_kind(code)
      local path = entry:sub(4)
      if status and path ~= "" then
        statuses[normalize_path(path)] = status
        if code:sub(1, 1) == "R" or code:sub(1, 1) == "C" then
          local other = parts[index + 1]
          if other then
            statuses[normalize_path(other)] = status
            index = index + 1
          end
        end
      end
      index = index + 1
    end
    return statuses
  end

  local function lookup(item)
    local direct = item_status(item)
    if direct then
      return direct
    end
    local file = item and (item.file or item.text or item.relative_path)
    if type(file) ~= "string" or file == "" then
      return
    end
    local item_cwd = type(item.cwd) == "string"
      and absolute_path(vim.fs.normalize(item.cwd))
      or cwd
    local path = file
    if not path:match("^/") and not path:match("^%a:[/\\]") then
      path = item_cwd .. "/" .. path
    end
    path = absolute_path(vim.fs.normalize(path))
    local root = cwd
    if Snacks.git and type(Snacks.git.get_root) == "function" then
      local ok, git_root = pcall(Snacks.git.get_root, path)
      if not ok or type(git_root) ~= "string" or git_root == "" then
        return
      end
      root = absolute_path(vim.fs.normalize(git_root))
    end
    local statuses = load(root)
    local relative_root = vim.fs.relpath(root, path)
    return statuses[normalize_path(relative_root)]
  end

  status_lookups[opts] = lookup
  return lookup
end

local function smart_git_status(opts)
  local smart = opts.smart
  if smart == nil then
    return false
  end
  if type(smart) == "boolean" then
    return smart
  end
  if type(smart) ~= "table" then
    error("`smart` must be a boolean or a table.", 3)
  end
  if smart.git_status ~= nil and type(smart.git_status) ~= "boolean" then
    error("`smart.git_status` must be a boolean.", 3)
  end
  return smart.git_status == true
end

local function picker_selection(opts)
  local pickers = opts.pickers
  if pickers == nil or type(pickers) == "boolean" then
    return pickers == nil and true or pickers
  end
  if type(pickers) ~= "table" then
    error("`pickers` must be a boolean or a table of picker API names.", 3)
  end
  for source, enabled in pairs(pickers) do
    if type(source) ~= "string" or type(enabled) ~= "boolean" then
      error("`pickers` entries must map picker API names to booleans.", 3)
    end
  end
  return pickers
end

local function uses_minibuffer(state, source)
  source = source or "custom"
  if type(state.pickers) == "table" and state.pickers[source] ~= nil then
    return state.pickers[source]
  end
  return state.pickers ~= false
end

local function decorate_filename(chunks, status, picker, item)
  if not status then
    return chunks
  end
  local current = is_current_item(picker, item)
  local highlights = get_fff_highlights()
  local show_sign = status.sign ~= ""
  if highlights then
    local ok, value = pcall(highlights.get_git_text_highlight, status.name)
    if ok and type(value) == "string" and value ~= "" then
      status = vim.tbl_extend("force", {}, status, { hl = value })
    end
    local ok_sign, sign = pcall(highlights.get_git_border_char, status.name)
    if ok_sign and type(sign) == "string" then
      status = vim.tbl_extend("force", {}, status, { sign = sign })
    end
    if type(highlights.should_show_git_border) == "function" then
      local ok_show, value_show = pcall(highlights.should_show_git_border, status.name)
      if ok_show then
        show_sign = value_show == true
      end
    end
    local sign_hl
    if current then
      local ok_selected, value_selected = pcall(
        highlights.get_git_sign_highlight,
        status.name,
        true,
        "SnacksPickerListCursorLine"
      )
      sign_hl = ok_selected and value_selected or nil
    else
      local ok_normal, value_normal = pcall(highlights.get_git_border_highlight, status.name)
      sign_hl = ok_normal and value_normal or nil
    end
    if type(sign_hl) == "string" and sign_hl ~= "" then
      status = vim.tbl_extend(
        "force",
        {},
        status,
        current and { sign_hl_selected = sign_hl } or { sign_hl = sign_hl }
      )
    end
  end
  for _, chunk in ipairs(chunks) do
    if
      type(chunk) == "table"
      and chunk.field == "file"
      and type(chunk[1]) == "string"
    then
      chunk[2] = status.hl
      break
    end
  end
  if show_sign and status.sign ~= "" then
    table.insert(chunks, 1, {
      col = 0,
      priority = 1000,
      sign_hl_group = current and status.sign_hl_selected or status.sign_hl,
      sign_text = status.sign,
    })
  end
  return chunks
end

local function basename(Snacks, item)
  local path = Snacks.picker.util.path(item) or item.file or ""
  path = path:gsub("[/\\]+$", "")
  return path:match("([^/\\]+)$") or path
end

local function filename_width(Snacks, picker, item)
  local list = picker.list
  local items = (list and list.items)
    or (picker.finder and picker.finder.items)
    or {}
  local count = #items
  local cached = widths[picker]
  if not cached or cached.items ~= items or cached.count ~= count then
    cached = { items = items, count = count, width = 0 }
    widths[picker] = cached
    for index = 1, count do
      local candidate = items[index]
      if candidate then
        cached.width = math.max(
          cached.width,
          vim.api.nvim_strwidth(basename(Snacks, candidate))
        )
      end
    end
  end
  return cached.width > 0 and cached.width
    or vim.api.nvim_strwidth(basename(Snacks, item))
end

local function align_filename(chunks, width, max_width)
  local filename_index
  local directory_index
  for index, chunk in ipairs(chunks) do
    if chunk.field == "file" and type(chunk[1]) == "string" then
      if filename_index then
        directory_index = index
        break
      end
      filename_index = index
    end
  end
  if not filename_index or not directory_index then
    return chunks
  end
  for index = filename_index + 1, directory_index - 1 do
    if type(chunks[index][1]) ~= "string" or chunks[index][1]:find("%S") then
      return chunks
    end
  end

  local ret = {}
  local current_width = vim.api.nvim_strwidth(chunks[filename_index][1])
  width = math.max(current_width, math.min(width, math.max(max_width - 3, 0)))
  for index = 1, filename_index do
    ret[#ret + 1] = chunks[index]
  end
  ret[#ret + 1] = {
    string.rep(" ", width - current_width + 2),
  }
  ret[#ret + 1] = { "│", "SnacksPickerDelim" }
  ret[#ret + 1] = { " " }
  for index = directory_index, #chunks do
    ret[#ret + 1] = chunks[index]
  end
  return ret
end

local function register_loaded_todo_comments(picker)
  if rawget(picker, "todo_comments") then
    return
  end
  local todo_config = package.loaded["todo-comments.config"]
  if
    type(todo_config) ~= "table"
    or todo_config.loaded ~= true
    or type(picker.config.wrap) ~= "function"
  then
    return
  end
  local ok, todo = pcall(require, "todo-comments.snacks")
  if not ok or type(todo) ~= "table" or type(todo.source) ~= "table" then
    return
  end
  local sources = picker.sources
  if type(sources) ~= "table" then
    return
  end
  if sources.todo_comments == false then
    return
  elseif sources.todo_comments == nil then
    sources.todo_comments = todo.source
  end
  picker.config.wrap("todo_comments")
end

---@param opts? minibuffer.integrations.SnacksPickerOpts
function M.setup(opts)
  if opts ~= nil and type(opts) ~= "table" then
    error("Snacks picker setup options must be a table.", 2)
  end
  local ok, Snacks = pcall(require, "snacks")
  if not ok then
    error("Make sure snacks.nvim is installed and loaded.", 2)
  end
  local picker_ok, picker = pcall(function()
    return Snacks.picker
  end)
  if
    not picker_ok
    or type(picker) ~= "table"
    or type(picker.config) ~= "table"
    or type(picker.config.layout) ~= "function"
    or type(picker.format) ~= "table"
    or type(picker.format.file) ~= "function"
    or type(picker.util) ~= "table"
    or type(picker.util.path) ~= "function"
  then
    error("Your version of snacks.nvim is missing required picker interfaces.", 2)
  end
  register_loaded_todo_comments(picker)
  local state = rawget(picker, SETUP_FIELD)
  if state then
    if opts ~= nil then
      state.pickers = picker_selection(opts)
      if opts.smart ~= nil then
        state.smart_git_status = smart_git_status(opts)
        if state.smart_git_status then
          ensure_git_highlights()
        end
      end
    end
    return
  end
  state = {
    pickers = picker_selection(opts or {}),
    smart_git_status = smart_git_status(opts or {}),
  }
  if state.smart_git_status then
    ensure_git_highlights()
  end

  local native_layout = picker.config.layout
  picker.config.layout = function(...)
    local input = select(1, ...)
    if
      type(input) == "table"
      and input.source == "smart"
      and state.smart_git_status
      and uses_minibuffer(state, input.source)
    then
      input.win = type(input.win) == "table" and input.win or {}
      input.win.list = type(input.win.list) == "table" and input.win.list or {}
      input.win.list.wo = type(input.win.list.wo) == "table" and input.win.list.wo or {}
      input.win.list.wo.signcolumn = "yes"
      input.win.list.wo.statuscolumn = ""
    end
    local layout = native_layout(...)
    if type(layout) ~= "table" or type(layout.layout) ~= "table" then
      error("Snacks picker returned an invalid layout.", 2)
    end
    if not uses_minibuffer(state, type(input) == "table" and input.source) then
      return layout
    end
    layout.layout.relative = "minibuffer"
    layout.layout.position = "float"
    layout.layout.fixbuf = false
    local cmd_win = require("minibuffer.internal.util").get_cmd_win()
    if cmd_win then
      layout.layout.zindex = math.max(
        layout.layout.zindex or 0,
        vim.api.nvim_win_get_config(cmd_win).zindex + 1
      )
    end
    return layout
  end

  local native_sort = picker.config.sort
  if type(native_sort) == "function" then
    picker.config.sort = function(...)
      local sort_opts = select(1, ...)
      local sort = native_sort(...)
      if
        not state.smart_git_status
        or type(sort_opts) ~= "table"
        or sort_opts.source ~= "smart"
        or not uses_minibuffer(state, sort_opts.source)
        or type(sort) ~= "function"
      then
        return sort
      end
      local status = git_status_lookup(Snacks, sort_opts)
      return function(a, b)
        local a_status = status(a)
        local b_status = status(b)
        local a_changed = a_status and a_status.changed or false
        local b_changed = b_status and b_status.changed or false
        if a_changed ~= b_changed then
          return a_changed
        end
        return sort(a, b)
      end
    end
  end

  local native_file = picker.format.file
  picker.format.file = function(item, active_picker, ...)
    local picker_opts = active_picker and active_picker.opts
    local opts = picker_opts
      and picker_opts.formatters
      and picker_opts.formatters.file
    local source = picker_opts and picker_opts.source
    local align = uses_minibuffer(state, source)
      and (source == "files" or source == "smart")
      and opts
      and opts.filename_only ~= true
    local git = uses_minibuffer(state, source)
      and source == "smart"
      and state.smart_git_status
    local status = git and item_status(item)
    if git and not status then
      local source_ok, source_files = pcall(require, "snacks.picker.source.files")
      if source_ok and type(source_files.git_status) == "function" then
        local status_ok, native_status = pcall(source_files.git_status, item, active_picker)
        if status_ok then
          status = status_kind(native_status)
        end
      end
    end
    if git and not status then
      status = git_status_lookup(Snacks, picker_opts)(item)
    end
    local format_item = item
    if git and item and item.status ~= nil then
      format_item = vim.tbl_extend("force", {}, item)
      format_item.status = nil
    end
    local previous_filename_first = opts and opts.filename_first
    if git and opts then
      -- Let the wrapper own Git decorations. Snacks' async status formatter
      -- otherwise adds its own inline icon/highlight before we can decorate.
      opts.filename_first = false
    end
    local ok, formatted = pcall(native_file, format_item, active_picker, ...)
    if git and opts then
      opts.filename_first = previous_filename_first
    end
    if not ok then
      error(formatted, 0)
    end
    if type(formatted) ~= "table" or (not align and not status) then
      return formatted
    end

    local width = align and filename_width(Snacks, active_picker, item)
    local has_resolver = false
    for _, chunk in ipairs(formatted) do
      if type(chunk) == "table" and type(chunk.resolve) == "function" then
        has_resolver = true
        local native_resolve = chunk.resolve
        chunk.resolve = function(max_width)
          local ok, resolved
          if align or (git and opts) then
            local previous_filename_first = opts.filename_first
            opts.filename_first = true
            ok, resolved = pcall(native_resolve, max_width)
            opts.filename_first = previous_filename_first
          else
            ok, resolved = pcall(native_resolve, max_width)
          end
          if not ok then
            error(resolved, 0)
          end
          if align then
            resolved = align_filename(resolved, width, max_width)
          end
          return decorate_filename(resolved, status, active_picker, item)
        end
      end
    end
    if status and not has_resolver then
      return decorate_filename(formatted, status, active_picker, item)
    end
    return formatted
  end

  rawset(picker, SETUP_FIELD, state)
end

return M
