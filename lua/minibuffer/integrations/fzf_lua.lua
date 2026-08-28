local ok, FzfLua = pcall(require, "fzf-lua")
if not ok then
  error("Make sure fzf-lua is installed and loaded.")
end

for _, interface in ipairs({
  "actions",
  "config",
  "core",
  "fzf_exec",
  "libuv",
  "path",
  "shell",
  "utils",
}) do
  if FzfLua[interface] == nil then
    error(("Your version of fzf-lua is missing the `%s` interface."):format(interface))
  end
end
if type(FzfLua.shell.stringify_data) ~= "function" then
  error("Your version of fzf-lua is missing `shell.stringify_data`.")
end
local files_provider = require("fzf-lua.providers.files")
if type(files_provider.get_files_cmd) ~= "function" then
  error("Your version of fzf-lua is missing `providers.files.get_files_cmd`.")
end

local DEFAULT_SMART = {
  filename_bonus = true,
  cwd_bonus = true,
  frecency = true,
  history_bonus = false,
  query_delay = 30,
}
local RESUME_RETENTION_MS = 5 * 60 * 1000

local M = {}
local SESSION_KEY = "__minibuffer_smart_session"
local extension_name
local next_session = 0
local sessions = {}
local active_session
local retained_session
local invocation = 0
local pending_process
local retention_generation = 0

local function retire(session)
  if not session or session.closed then
    return
  end
  session.closed = true
  for index = #session.candidates, 1, -1 do
    session.candidates[index] = nil
  end
  if session.cleanup then
    session.cleanup()
  end
  if active_session == session then
    active_session = nil
  end
  if retained_session == session then
    retained_session = nil
  end
end

local function activate(session)
  if session.closed then
    return false
  end
  if retained_session == session then
    retained_session = nil
    retention_generation = retention_generation + 1
  end
  active_session = session
  return true
end

local function begin_invocation()
  invocation = invocation + 1
  if pending_process then
    pcall(pending_process.kill, pending_process, "sigterm")
    pending_process = nil
  end
  retire(active_session)
  retire(retained_session)
  return invocation
end

local function resolve_fn(value)
  return type(value) == "function" and value or FzfLua.libuv.load_fn(value)
end

local function absolute_path(path, cwd)
  path = FzfLua.path.normalize(path)
  local absolute = type(FzfLua.path.is_absolute) == "function"
      and FzfLua.path.is_absolute(path)
    or path:sub(1, 1) == "/"
    or path:match("^%a:[/\\]") ~= nil
  if not absolute then
    path = vim.fs.joinpath(cwd, path)
  end
  return FzfLua.path.normalize(vim.fs.normalize(path))
end

local function lines_for(ranker, query, candidates)
  local lines = vim.tbl_map(function(candidate)
    return candidate.display
  end, ranker:rank(query, candidates))
  return #lines == 0 and {} or table.concat(lines, "\n")
end

local function candidate_path(raw, opts, cwd)
  local path = FzfLua.utils.strip_ansi_coloring(raw)
  if opts.strip_cwd_prefix and type(FzfLua.path.strip_cwd_prefix) == "function" then
    path = FzfLua.path.strip_cwd_prefix(path)
  end
  return absolute_path(path, cwd)
end

local function align_filename_first(candidates, opts)
  if
    opts.formatter ~= "path.filename_first"
    or not opts._fmt
    or type(opts._fmt.from) ~= "function"
  then
    return
  end

  local width = 0
  for _, candidate in ipairs(candidates) do
    local filename = candidate.display:match("^(.-)\t") or candidate.display
    width = math.max(
      width,
      vim.api.nvim_strwidth(FzfLua.utils.strip_ansi_coloring(filename))
    )
  end
  for _, candidate in ipairs(candidates) do
    local filename, directory = candidate.display:match("^(.-)\t(.*)$")
    filename = filename or candidate.display
    local padding = width
      - vim.api.nvim_strwidth(FzfLua.utils.strip_ansi_coloring(filename))
      + 1
    candidate.display = filename
      .. string.rep(" ", padding)
      .. "│"
      .. (directory and "\t" .. directory or "")
  end

  local from = opts._fmt.from
  opts._fmt.from = function(line, ...)
    line = line:gsub(" +│\t", "\t", 1):gsub(" +│$", "", 1)
    return from(line, ...)
  end
end

local function load_candidates(opts, callback)
  local preprocess = resolve_fn(opts.fn_preprocess)
  local transform = resolve_fn(opts.fn_transform)
  local postprocess = resolve_fn(opts.fn_postprocess)
  if preprocess then
    local preprocess_ok, preprocess_error = pcall(preprocess, opts)
    if not preprocess_ok then
      if postprocess then
        pcall(postprocess, opts)
      end
      callback(nil, preprocess_error)
      return
    end
  end

  local candidates = {}
  local source_index = 0
  local stderr = ""
  local transform_error
  local finished = false
  local cwd =
    FzfLua.path.normalize(opts.cwd or opts._cwd or (vim.uv or vim.loop).cwd() or ".")

  return FzfLua.libuv.spawn({
    cmd = opts.cmd,
    cwd = opts.cwd,
    cb_write_lines = function(lines, done)
      local chunk_ok, chunk_error = xpcall(function()
        for _, raw in ipairs(lines) do
          source_index = source_index + 1
          local display = raw
          if transform then
            local transform_ok
            transform_ok, display = pcall(transform, raw, opts)
            if not transform_ok then
              transform_error = display
              display = nil
            end
          end
          if display then
            local path = candidate_path(raw, opts, cwd)
            candidates[#candidates + 1] = {
              text = opts.absolute_path and path or FzfLua.path.relative_to(path, cwd),
              path = path,
              display = display,
              idx = source_index,
            }
          end
        end
      end, debug.traceback)
      if not chunk_ok then
        transform_error = chunk_error
      end
      done()
    end,
    cb_err = function(data)
      if #stderr < 4096 then
        stderr = (stderr .. data):sub(1, 4096)
      end
    end,
    cb_finish = function(code)
      if finished then
        return
      end
      finished = true
      local complete = function()
        if postprocess then
          pcall(postprocess, opts)
        end
        if code ~= 0 or transform_error then
          callback(
            nil,
            transform_error or (stderr ~= "" and stderr or "file command failed")
          )
        else
          align_filename_first(candidates, opts)
          callback(candidates)
        end
      end
      if vim.in_fast_event() then
        vim.schedule(complete)
      else
        complete()
      end
    end,
  }, true)
end

local function load_for_invocation(generation, opts, callback)
  local completed = false
  local process = load_candidates(opts, function(candidates, err)
    completed = true
    if generation ~= invocation then
      return
    end
    pending_process = nil
    callback(candidates, err)
  end)
  if not completed and generation == invocation then
    pending_process = process
  end
  return process
end

local function compose_close(opts, session)
  opts.winopts = opts.winopts or {}
  local previous = opts.winopts.on_close
  opts.winopts.on_close = function(...)
    local win = type(FzfLua.utils.fzf_winobj) == "function" and FzfLua.utils.fzf_winobj()
      or nil
    vim.schedule(function()
      if session.closed then
        return
      end
      if win and type(win.hidden) == "function" and win:hidden() then
        return
      end
      if active_session == session then
        active_session = nil
      end
      if retained_session ~= session then
        retire(retained_session)
      end
      retained_session = session
      retention_generation = retention_generation + 1
      local generation = retention_generation
      vim.defer_fn(function()
        if generation == retention_generation and retained_session == session then
          retire(session)
        end
      end, RESUME_RETENTION_MS)
    end)
    if previous then
      previous(...)
    end
  end
end

local function add_history_metadata(candidates)
  local recent = {}
  for _, path in ipairs(vim.v.oldfiles or {}) do
    recent[absolute_path(path, (vim.uv or vim.loop).cwd() or ".")] = true
  end
  local buffers = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local path = vim.api.nvim_buf_get_name(buf)
    if path ~= "" then
      buffers[absolute_path(path, (vim.uv or vim.loop).cwd() or ".")] =
        vim.fn.getbufinfo(buf)[1]
    end
  end
  for _, candidate in ipairs(candidates) do
    candidate.recent = recent[candidate.path]
    candidate.info = buffers[candidate.path]
  end
end

local function query_for(opts, query)
  if type(opts.line_query) == "function" then
    local _, transformed = opts.line_query(query)
    return transformed or query
  end
  return query
end

local function preserve_toggle_actions(opts)
  local toggles = {}
  if FzfLua.actions.toggle_ignore then
    toggles[FzfLua.actions.toggle_ignore] = true
  end
  if FzfLua.actions.toggle_hidden then
    toggles[FzfLua.actions.toggle_hidden] = true
  end
  if FzfLua.actions.toggle_follow then
    toggles[FzfLua.actions.toggle_follow] = true
  end
  for _, action in pairs(opts.actions or {}) do
    if type(action) == "table" and toggles[action.fn] then
      action.reuse = false
    end
  end
end

local function clear_processing(opts)
  opts.fn_transform = nil
  opts.fn_preprocess = nil
  opts.fn_postprocess = nil
  opts.multiprocess = false
  opts.__stringified = nil
end

local function start_files(candidates, opts, smart, call_opts)
  local cwd = vim.fs.normalize(opts.cwd or (vim.uv or vim.loop).cwd() or ".")
  local ranker_opts = vim.tbl_extend("force", {}, smart, { cwd = cwd })
  ranker_opts.query_delay = nil
  local session = {
    candidates = candidates,
    closed = false,
  }
  add_history_metadata(candidates)
  local ranker = require("minibuffer.fuzzy").new(ranker_opts)
  local reload = FzfLua.shell.stringify_data(function(args)
    if not activate(session) then
      return {}
    end
    local query = query_for(opts, args[1] or "")
    return lines_for(ranker, query, session.candidates)
  end, opts, "{q}")
  local delay = tonumber(smart.query_delay)
  if delay and delay > 0 and not FzfLua.utils.__IS_WINDOWS then
    reload = ("sleep %.3f; %s"):format(delay / 1000, reload)
  end

  opts._start = nil
  opts.fzf_opts = opts.fzf_opts or {}
  opts.fzf_opts["--no-sort"] = true
  opts.fzf_opts["--track"] = true
  opts._fzf_cli_args = opts._fzf_cli_args or {}
  table.insert(
    opts._fzf_cli_args,
    "--bind=" .. FzfLua.libuv.shellescape("change:+reload:" .. reload)
  )

  -- The discovery command already applied fzf-lua's entry formatting.
  clear_processing(opts)
  opts.__call_fn = function(reopen_opts)
    local merged = vim.tbl_deep_extend("force", {}, call_opts, reopen_opts or {})
    local query = opts.last_query
    if not query and type(FzfLua.config.resume_get) == "function" then
      local query_ok, saved = pcall(FzfLua.config.resume_get, "query", opts)
      query = query_ok and saved or nil
    end
    merged.query = query or merged.query
    merged.smart = vim.deepcopy(smart)
    M.files(merged)
  end
  preserve_toggle_actions(opts)
  compose_close(opts, session)
  activate(session)

  local initial = FzfLua.shell.stringify_data(function()
    if not activate(session) then
      return {}
    end
    return lines_for(ranker, query_for(opts, opts.query or ""), candidates)
  end, opts)
  return FzfLua.fzf_exec(initial, opts)
end

local function ensure_extension()
  if extension_name then
    return extension_name
  end
  if
    type(FzfLua.register_extension) ~= "function"
    or type(FzfLua.core.fzf_exec) ~= "function"
    or not FzfLua.defaults
    or not FzfLua.defaults.files
  then
    error("Your version of fzf-lua cannot register a smart files provider.")
  end

  local base = "minibuffer_smart_files"
  local suffix = 0
  local name = base
  while FzfLua[name] do
    suffix = suffix + 1
    name = base .. "_" .. suffix
  end
  FzfLua.register_extension(name, function(opts)
    local session = sessions[opts[SESSION_KEY]]
    if not session then
      error("minibuffer smart files session is no longer available")
    end
    local provider_opts = vim.tbl_deep_extend("force", {}, opts, session.opts)
    provider_opts[SESSION_KEY] = opts[SESSION_KEY]
    provider_opts.pickers = opts.pickers
    provider_opts._normalized = true
    provider_opts._start = false
    return FzfLua.core.fzf_exec(session.contents, provider_opts)
  end, FzfLua.defaults.files)
  if type(FzfLua[name]) ~= "function" then
    error(("Failed to register fzf-lua extension `%s`."):format(name))
  end
  extension_name = name
  return name
end

local function has_prefix(query, pickers)
  for _, picker in ipairs(pickers) do
    if
      type(picker) == "table"
      and type(picker.prefix) == "string"
      and picker.prefix ~= ""
      and query:sub(1, #picker.prefix) == picker.prefix
    then
      return true
    end
  end
  return false
end

local function start_global(candidates, file_opts, global_opts, smart, call_opts, pickers)
  local cwd = vim.fs.normalize(file_opts.cwd or (vim.uv or vim.loop).cwd() or ".")
  local ranker_opts = vim.tbl_extend("force", {}, smart, { cwd = cwd })
  ranker_opts.query_delay = nil
  add_history_metadata(candidates)

  next_session = next_session + 1
  local token = next_session
  local session = {
    candidates = candidates,
    closed = false,
  }
  local ranker = require("minibuffer.fuzzy").new(ranker_opts)
  local rank_command = FzfLua.shell.stringify_data(function(args)
    if not activate(session) then
      return {}
    end
    return lines_for(ranker, query_for(file_opts, args[1] or ""), session.candidates)
  end, file_opts, "{q}")
  local delay = tonumber(smart.query_delay)
  if delay and delay > 0 and not FzfLua.utils.__IS_WINDOWS then
    rank_command = ("sleep %.3f; %s"):format(delay / 1000, rank_command)
  end

  clear_processing(file_opts)
  file_opts.fzf_opts = file_opts.fzf_opts or {}
  file_opts.fzf_opts["--no-sort"] = true
  file_opts.fzf_opts["--track"] = true
  file_opts.__call_fn = function(reopen_opts)
    local merged = vim.tbl_deep_extend("force", {}, call_opts, reopen_opts or {})
    merged.smart = vim.deepcopy(smart)
    M.global(merged)
  end
  preserve_toggle_actions(file_opts)

  local default_active = true
  local function gate_action(args, starting)
    if starting then
      -- Every fzf process starts with --no-sort, including restart resume.
      default_active = true
    end
    local prefixed = has_prefix(args[1] or "", pickers)
    if prefixed then
      if default_active then
        default_active = false
        return "toggle-sort"
      end
      return ""
    end
    if not default_active then
      default_active = true
      return "toggle-sort"
    end
    if starting then
      return ""
    end
    return "reload(" .. rank_command .. ")"
  end
  local start_gate = FzfLua.shell.stringify_data(function(args)
    if not activate(session) then
      return ""
    end
    return gate_action(args, true)
  end, global_opts, "{q}")
  local change_gate = FzfLua.shell.stringify_data(function(args)
    if not activate(session) then
      return ""
    end
    return gate_action(args, false)
  end, global_opts, "{q}")
  file_opts._fzf_cli_args = file_opts._fzf_cli_args or {}
  table.insert(
    file_opts._fzf_cli_args,
    "--bind=" .. FzfLua.libuv.shellescape("start:+transform:" .. start_gate)
  )
  table.insert(
    file_opts._fzf_cli_args,
    "--bind=" .. FzfLua.libuv.shellescape("change:+transform:" .. change_gate)
  )

  session.opts = file_opts
  session.contents = rank_command
  session.cleanup = function()
    if sessions[token] == session then
      sessions[token] = nil
    end
  end
  sessions[token] = session
  compose_close(file_opts, session)
  activate(session)

  global_opts[SESSION_KEY] = token
  global_opts.pickers = pickers
  return FzfLua.global(global_opts)
end

local function normalize_files(opts, resume_key)
  opts = FzfLua.config.normalize_opts(opts, "files", resume_key)
  if not opts then
    return
  end
  if opts.ignore_current_file then
    local current = vim.api.nvim_buf_get_name(0)
    if current ~= "" then
      current = FzfLua.path.relative_to(current, opts.cwd or FzfLua.utils.cwd())
      opts.file_ignore_patterns = opts.file_ignore_patterns or {}
      table.insert(
        opts.file_ignore_patterns,
        "^" .. FzfLua.utils.lua_regex_escape(current) .. "$"
      )
    end
  end
  opts.cmd = files_provider.get_files_cmd(opts)
  if FzfLua.utils.__IS_WINDOWS and opts.cmd:match("^dir") and not opts.cwd then
    opts.cwd = FzfLua.utils.cwd()
  end
  return FzfLua.core.set_title_flags(opts, { "cmd" })
end

---@class minibuffer.integrations.FzfLuaSmartOpts
---@field filename_bonus? boolean
---@field cwd_bonus? boolean
---@field frecency? boolean
---@field history_bonus? boolean
---@field query_delay? number

---@class minibuffer.integrations.FzfLuaFilesOpts: fzf-lua.config.Files
---@field smart? minibuffer.integrations.FzfLuaSmartOpts

---Open fzf-lua files with Snacks-style smart ranking.
---@param opts? minibuffer.integrations.FzfLuaFilesOpts
function M.files(opts)
  local generation = begin_invocation()
  opts = vim.deepcopy(opts or {})
  local call_opts = vim.deepcopy(opts)
  local smart = vim.tbl_deep_extend("force", {}, DEFAULT_SMART, opts.smart or {})
  opts.smart = nil
  local resolved = normalize_files(opts, "minibuffer.smart_files")
  if not resolved then
    return
  end
  resolved.__call_fn = M.files
  return load_for_invocation(generation, resolved, function(candidates, err)
    if not candidates then
      vim.notify("[minibuffer] fzf-lua files: " .. tostring(err), vim.log.levels.ERROR)
      return
    end
    start_files(candidates, resolved, smart, call_opts)
  end)
end

---@class minibuffer.integrations.FzfLuaGlobalOpts: fzf-lua.config.Global
---@field smart? minibuffer.integrations.FzfLuaSmartOpts

---Open fzf-lua global with smart ranking for its default files provider.
---@param opts? minibuffer.integrations.FzfLuaGlobalOpts
function M.global(opts)
  if type(FzfLua.global) ~= "function" then
    error("Your version of fzf-lua is missing the `global` picker.")
  end
  local generation = begin_invocation()
  opts = vim.deepcopy(opts or {})
  local call_opts = vim.deepcopy(opts)
  local smart = vim.tbl_deep_extend("force", {}, DEFAULT_SMART, opts.smart or {})
  opts.smart = nil

  local global_opts =
    FzfLua.config.normalize_opts(opts, "global", "minibuffer.smart_global")
  if not global_opts then
    return
  end
  if
    type(FzfLua.utils.has) == "function"
    and not FzfLua.utils.has(global_opts, "fzf", { 0, 59 })
  then
    vim.notify("[minibuffer] fzf-lua global requires fzf >= 0.59", vim.log.levels.ERROR)
    return
  end
  local pickers = type(global_opts.pickers) == "function" and global_opts.pickers()
    or global_opts.pickers
  pickers = vim.deepcopy(pickers or {})
  local default
  for _, picker in ipairs(pickers) do
    if type(picker) == "table" and not picker.prefix then
      default = picker
      break
    end
  end
  if not default then
    vim.notify("[minibuffer] fzf-lua global has no default picker", vim.log.levels.ERROR)
    return
  end
  default[1] = ensure_extension()

  local file_input = vim.deepcopy(global_opts)
  file_input._normalized = nil
  -- Rebuild provider-generated flags once under the files defaults.
  file_input._fzf_cli_args = {}
  file_input.pickers = nil
  file_input[SESSION_KEY] = nil
  local file_opts = normalize_files(file_input, "minibuffer.smart_global")
  if not file_opts then
    return
  end
  file_opts.__call_fn = M.global
  return load_for_invocation(generation, file_opts, function(candidates, err)
    if not candidates then
      vim.notify("[minibuffer] fzf-lua global: " .. tostring(err), vim.log.levels.ERROR)
      return
    end
    start_global(candidates, file_opts, global_opts, smart, call_opts, pickers)
  end)
end

return M
