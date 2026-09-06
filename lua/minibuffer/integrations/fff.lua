local ok, fff = pcall(require, "fff")
if not ok then
  error("Make sure fff.nvim is installed and loaded.")
end
if not fff.file_search then
  error("Your version of fff.nvim is missing the `file_search` api. Can't proceed.")
end
if not fff.content_search then
  error("Your version of fff.nvim is missing the `content_search` api. Can't proceed.")
end

local function string_value(value)
  if type(value) == "string" then
    return value
  end
  if value == nil then
    return ""
  end
  return tostring(value)
end

local function normalize_cwd(cwd)
  if cwd == nil then
    return nil
  end
  return vim.fn.fnamemodify(cwd, ":p"):gsub("(.)/$", "%1")
end

local function normalize_search_args(query, opts)
  if type(query) == "table" and opts == nil then
    opts = query
    query = nil
  end
  if query ~= nil and type(query) ~= "string" then
    error("fff search query must be a string or nil")
  end
  return query or "", opts
end

local function append_chunks(destination, source)
  for _, chunk in ipairs(source) do
    if chunk.text ~= "" then
      destination[#destination + 1] = chunk
    end
  end
end

---@param keys string|string[]|nil
---@param callback fun(key: string)
local function each_key(keys, callback)
  if type(keys) == "string" then
    callback(keys)
    return
  end
  for _, key in ipairs(keys or {}) do
    callback(key)
  end
end

---@param keyset minibuffer.util.Keyset
---@param keys string|string[]|nil
---@param callback function
local function set_keymaps(keyset, keys, callback)
  each_key(keys, function(key)
    keyset("i", key, callback)
  end)
end

---@param keys string|string[]|nil
---@return string
local function keymap_label(keys)
  local labels = {}
  each_key(keys, function(key)
    labels[#labels + 1] = key:match("^<(.+)>$") or key
  end)
  return #labels > 0 and table.concat(labels, "/") or "disabled"
end

---@param keymaps minibuffer.integrations.FFFKeymaps
---@return minibuffer.config.select.keymaps
local function select_keymap_overrides(keymaps)
  local overrides = {}
  if keymaps.next ~= nil then
    overrides.next = keymaps.next
  end
  if keymaps.previous ~= nil then
    overrides.previous = keymaps.previous
  end
  return overrides
end

---@param action "next"|"previous"
---@param keymaps minibuffer.integrations.FFFKeymaps
---@return string
local function select_keymap_label(action, keymaps)
  local keys = keymaps[action]
  if keys == nil then
    keys = require("minibuffer.config").select.keymaps[action]
  end
  return keymap_label(keys)
end

-- Build text chunks from overlapping byte ranges. fff and Tree-sitter both
-- report byte offsets, which is also what nvim_buf_set_extmark uses.
local function make_chunks(text, default_hl, spans, separate_at)
  text = string_value(text)
  if text == "" then
    return {}
  end

  local boundaries = { 0, #text }
  local valid_spans = {}
  for _, span in ipairs(spans or {}) do
    local start = math.max(0, math.min(#text, tonumber(span.start) or 0))
    local finish = math.max(0, math.min(#text, tonumber(span.finish) or 0))
    if finish > start and span.hl then
      valid_spans[#valid_spans + 1] = {
        start = start,
        finish = finish,
        hl = span.hl,
        priority = span.priority or 0,
      }
      boundaries[#boundaries + 1] = start
      boundaries[#boundaries + 1] = finish
    end
  end

  table.sort(boundaries)
  local unique_boundaries = {}
  for _, boundary in ipairs(boundaries) do
    if unique_boundaries[#unique_boundaries] ~= boundary then
      unique_boundaries[#unique_boundaries + 1] = boundary
    end
  end

  local chunks = {}
  for i = 1, #unique_boundaries - 1 do
    local start = unique_boundaries[i]
    local finish = unique_boundaries[i + 1]
    if finish > start then
      local hl = default_hl
      local priority = -math.huge
      for _, span in ipairs(valid_spans) do
        if
          span.start <= start
          and span.finish >= finish
          and span.priority >= priority
        then
          hl = span.hl
          priority = span.priority
        end
      end

      local chunk = { text = text:sub(start + 1, finish), hl = hl }
      local previous = chunks[#chunks]
      if
        previous
        and previous.hl == chunk.hl
        and not (separate_at and separate_at[start])
      then
        previous.text = previous.text .. chunk.text
      else
        chunks[#chunks + 1] = chunk
      end
    end
  end

  return chunks
end

local function range_bounds(range)
  if type(range) ~= "table" then
    return nil, nil
  end

  local start = range[1] or range.start or range.col
  local finish = range[2] or range.finish or range["end"] or range.end_col
  return tonumber(start), tonumber(finish)
end

local function add_match_spans(spans, ranges, match_hl)
  for _, range in ipairs(ranges or {}) do
    local start, finish = range_bounds(range)
    if start and finish and finish > start then
      spans[#spans + 1] = {
        start = start,
        finish = finish,
        hl = match_hl,
        priority = 100,
      }
    end
  end
end

local function add_filename_first_match_spans(
  spans,
  ranges,
  match_hl,
  name_length,
  directory_length,
  display_directory_length,
  separator_length,
  name_padding
)
  name_padding = name_padding or 0
  for _, range in ipairs(ranges or {}) do
    local start, finish = range_bounds(range)
    if start and finish and finish > start then
      local filename_start = math.max(start, directory_length)
      local filename_finish = math.min(finish, directory_length + name_length)
      if filename_finish > filename_start then
        spans[#spans + 1] = {
          start = filename_start - directory_length,
          finish = filename_finish - directory_length,
          hl = match_hl,
          priority = 100,
        }
      end

      local directory_start = math.max(start, 0)
      local directory_finish = math.min(finish, display_directory_length)
      if directory_finish > directory_start then
        spans[#spans + 1] = {
          start = name_length + name_padding + separator_length + directory_start,
          finish = name_length + name_padding + separator_length + directory_finish,
          hl = match_hl,
          priority = 100,
        }
      end
    end
  end
end

local function fff_highlight(name, fallback, overrides)
  if overrides and overrides[name] then
    return overrides[name]
  end

  local conf_ok, conf = pcall(require, "fff.conf")
  if conf_ok and conf.get then
    local config_ok, config = pcall(conf.get)
    if config_ok and config.hl and config.hl[name] then
      return config.hl[name]
    end
  end
  return fallback
end

local function configured_highlight(name, fallback, overrides)
  return overrides and overrides[name] or fallback
end

local function highlight_group_name(name)
  local suffix = name:sub(1, 1):upper()
    .. name:sub(2):gsub("_(%l)", function(char)
      return char:upper()
    end)
  return "MinibufferFFF" .. suffix
end

---@param opts table
---@return table<string, string>
local function create_highlight_overrides(opts)
  local overrides = {}
  for name, spec in pairs(opts.highlights or {}) do
    if type(spec) == "string" and spec ~= "" then
      overrides[name] = spec
    elseif type(spec) == "table" then
      local group = highlight_group_name(name)
      local set_ok = pcall(vim.api.nvim_set_hl, 0, group, vim.deepcopy(spec))
      if set_ok then
        overrides[name] = group
      end
    end
  end
  return overrides
end

local function item_name(item, path)
  local name = string_value(item.name or item.file_name)
  if name ~= "" then
    return name
  end
  return vim.fn.fnamemodify(path, ":t")
end

local function item_is_directory(item)
  return item.type == "directory" or item.is_dir == true
end

local function get_icon(item, path)
  local icons_ok, icons = pcall(require, "fff.file_picker.icons")
  if not icons_ok or not icons.get_icon then
    return nil, nil
  end

  local name = item_name(item, path)
  local extension = string_value(item.extension)
  if extension == "" then
    extension = vim.fn.fnamemodify(name, ":e")
  end

  local icon_ok, icon, hl =
    pcall(icons.get_icon, name, extension, item_is_directory(item))
  if icon_ok and type(icon) == "string" and icon ~= "" then
    return icon, hl
  end
  return nil, nil
end

local git_status_aliases = {
  ["??"] = "untracked",
  ["!!"] = "ignored",
  ["m"] = "modified",
  ["a"] = "staged_new",
  ["d"] = "deleted",
  ["r"] = "renamed",
  ["mm"] = "staged_modified",
  ["am"] = "staged_modified",
  ["rm"] = "renamed",
  ["dm"] = "staged_deleted",
  ["ad"] = "staged_deleted",
  modified = "modified",
  staged_new = "staged_new",
  staged_modified = "staged_modified",
  staged_deleted = "staged_deleted",
  deleted = "deleted",
  renamed = "renamed",
  untracked = "untracked",
  ignored = "ignored",
  unknown = "unknown",
}

local git_status_highlight_names = {
  staged_new = "staged",
  staged_modified = "staged",
  staged_deleted = "staged",
  modified = "modified",
  deleted = "deleted",
  renamed = "renamed",
  untracked = "untracked",
  ignored = "ignored",
  unknown = "untracked",
}

local fallback_git_chars = {
  untracked = "┆",
  ignored = "┆",
  unknown = "┆",
  modified = "┃",
  deleted = "▁",
  renamed = "┃",
  staged_new = "┃",
  staged_modified = "┃",
  staged_deleted = "▁",
}

local function normalize_git_status(status)
  status = string_value(status)
  if status == "" then
    return nil
  end

  local compact = status:gsub("%s", ""):lower()
  return git_status_aliases[status:lower()]
    or git_status_aliases[compact]
    or git_status_aliases[status]
end

local function get_git_info(item, enabled, overrides)
  if not enabled then
    return nil
  end

  local status = normalize_git_status(item.git_status)
  if not status then
    return nil
  end

  local border_char = fallback_git_chars[status] or "┆"
  local border_hl = "Comment"
  local text_hl
  local highlights_ok, highlights = pcall(require, "fff.highlights")
  if highlights_ok then
    local char_ok, fff_char = pcall(highlights.get_git_border_char, status)
    if char_ok and fff_char and fff_char ~= "" then
      border_char = fff_char
    end

    local border_hl_ok, fff_border_hl = pcall(highlights.get_git_border_highlight, status)
    if border_hl_ok and fff_border_hl and fff_border_hl ~= "" then
      border_hl = fff_border_hl
    end

    local text_hl_ok, fff_text_hl = pcall(highlights.get_git_text_highlight, status)
    if text_hl_ok and fff_text_hl and fff_text_hl ~= "" then
      text_hl = fff_text_hl
    end
  end

  local highlight_name = git_status_highlight_names[status] or "untracked"
  text_hl = fff_highlight("git_" .. highlight_name, text_hl, overrides)
  border_hl = fff_highlight("git_sign_" .. highlight_name, border_hl, overrides)

  return {
    char = border_char,
    border_hl = border_hl,
    text_hl = text_hl,
  }
end

local function path_chunks(
  path,
  match_ranges,
  git_info,
  overrides,
  filename_first,
  name_padding
)
  local name = vim.fn.fnamemodify(path, ":t")
  if name == "" then
    name = path
  end
  local directory = path:sub(1, #path - #name)
  local normal_hl = configured_highlight("normal", "Normal", overrides)
  local directory_hl = fff_highlight("directory_path", "Comment", overrides)
  local filename_hl = git_info and git_info.text_hl or normal_hl
  local spans = {}

  if filename_first == false then
    if directory ~= "" then
      spans[#spans + 1] = {
        start = 0,
        finish = #directory,
        hl = directory_hl,
        priority = 10,
      }
    end
    if name ~= "" then
      spans[#spans + 1] = {
        start = #directory,
        finish = #path,
        hl = filename_hl,
        priority = 10,
      }
    end
    add_match_spans(spans, match_ranges, fff_highlight("matched", "IncSearch", overrides))
    return make_chunks(path, normal_hl, spans)
  end

  local display_directory = directory ~= "" and directory:sub(1, -2) or ""
  name_padding = name_padding or 0
  local padding = string.rep(" ", name_padding)
  local separator = display_directory ~= "" and " " or ""
  local transformed_path = name .. padding .. separator .. display_directory
  local separator_hl = configured_highlight("separator", "Comment", overrides)
  local separate_at = {}

  if name ~= "" then
    spans[#spans + 1] = {
      start = 0,
      finish = #name,
      hl = filename_hl,
      priority = 10,
    }
  end
  if separator ~= "" then
    spans[#spans + 1] = {
      start = #name + name_padding,
      finish = #name + name_padding + #separator,
      hl = separator_hl,
      priority = 10,
    }
    separate_at[#name] = true
    separate_at[#name + name_padding] = true
    separate_at[#name + name_padding + #separator] = true
  end
  if display_directory ~= "" then
    spans[#spans + 1] = {
      start = #name + name_padding + #separator,
      finish = #transformed_path,
      hl = directory_hl,
      priority = 10,
    }
  end
  add_filename_first_match_spans(
    spans,
    match_ranges,
    fff_highlight("matched", "IncSearch", overrides),
    #name,
    #directory,
    #display_directory,
    #separator,
    name_padding
  )
  return make_chunks(transformed_path, normal_hl, spans, separate_at)
end

local function content_chunks(item, content, overrides, treesitter_enabled)
  local spans = {}
  if
    treesitter_enabled ~= false
    and not item.is_binary
    and not item.is_binary_content
  then
    local treesitter_ok, treesitter = pcall(require, "fff.treesitter_hl")
    if treesitter_ok then
      local path = string_value(item.relative_path)
      local name = item_name(item, path)
      local lang_ok, lang = pcall(treesitter.lang_from_filename, name)
      if lang_ok and lang then
        local highlights_ok, highlights =
          pcall(treesitter.get_line_highlights, content, lang)
        if highlights_ok then
          for _, highlight in ipairs(highlights) do
            local start = tonumber(highlight.col)
            local finish = tonumber(highlight.end_col)
            if start and finish and finish > start and highlight.hl_group then
              spans[#spans + 1] = {
                start = start,
                finish = finish,
                hl = highlight.hl_group,
                priority = 10,
              }
            end
          end
        end
      end
    end
  end

  add_match_spans(
    spans,
    item.match_ranges,
    fff_highlight("grep_match", "IncSearch", overrides)
  )
  local content_hl = configured_highlight(
    "content",
    configured_highlight("normal", "Normal", overrides),
    overrides
  )
  return make_chunks(content, content_hl, spans)
end

local function format_file_item(item, opts, overrides, layout)
  if not item then
    return {}
  end

  local path = string_value(item.relative_path)
  local git_info = get_git_info(item, opts.show_git_status, overrides)
  local entry = (layout and layout[item]) or {
    name_padding = 0,
  }
  local normal_hl = configured_highlight("normal", "Normal", overrides)
  local data = {
    {
      text = git_info and git_info.char or " ",
      hl = git_info and git_info.border_hl or "Comment",
    },
    { text = " ", hl = "Comment" },
    { text = "    ", hl = normal_hl },
  }

  local icon, icon_hl = get_icon(item, path)
  data[#data + 1] = {
    text = icon and (icon .. " ") or "  ",
    hl = configured_highlight("icon", icon_hl or normal_hl, overrides),
  }
  append_chunks(
    data,
    path_chunks(
      path,
      item.match_ranges,
      git_info,
      overrides,
      opts.filename_first,
      entry.name_padding
    )
  )
  if opts.show_score and item.total_frecency_score then
    data[#data + 1] = {
      text = ": " .. item.total_frecency_score,
      hl = configured_highlight("score", "Comment", overrides),
    }
  end
  return data
end

local function format_content_item(item, opts, overrides)
  if not item then
    return {}
  end

  local path = string_value(item.relative_path)
  local content = string_value(item.line_content)
  local git_info = get_git_info(item, opts.show_git_status, overrides)
  local data = {}

  if git_info then
    data[#data + 1] = { text = git_info.char .. " ", hl = git_info.border_hl }
  end

  local icon, icon_hl = get_icon(item, path)
  if icon then
    data[#data + 1] = {
      text = icon .. " ",
      hl = configured_highlight("icon", icon_hl or "Normal", overrides),
    }
  end

  append_chunks(data, path_chunks(path, nil, git_info, overrides, opts.filename_first))
  data[#data + 1] = {
    text = ": ",
    hl = configured_highlight("separator", "Comment", overrides),
  }
  append_chunks(data, content_chunks(item, content, overrides, opts.treesitter))
  return data
end

local function cleanup_treesitter()
  local treesitter_ok, treesitter = pcall(require, "fff.treesitter_hl")
  if treesitter_ok and treesitter.cleanup then
    pcall(treesitter.cleanup)
  end
end

local function toggle_value(current, values)
  for i, value in ipairs(values) do
    if value == current then
      return values[(i % #values) + 1]
    end
  end
  return values[1]
end

local M = {}

---@class minibuffer.integrations.FFFKeymaps
---@field split string|string[]?
---@field vsplit string|string[]?
---@field toggle_mode string|string[]?
---@field next string|string[]?
---@field previous string|string[]?

---@class minibuffer.integrations.FFFindOpts
---@field cwd string?
---@field mode 'files'|'directories'|'mixed'|nil
---@field max_results integer?
---@field page integer?
---@field current_file string?
---@field max_threads integer?
---@field combo_boost_score_multiplier number?
---@field min_combo_count number?
---@field wait_for_index_ms number?
---@field show_score boolean?
---@field show_git_status boolean?
---@field filename_first boolean?
---@field highlights table<string, string|table>?
---@field keymaps minibuffer.integrations.FFFKeymaps?

--- Run fff file search
---@param query string|nil
---@param opts minibuffer.integrations.FFFindOpts|nil
function M.file_search(query, opts)
  require("minibuffer.internal.guard").check()
  query, opts = normalize_search_args(query, opts)
  local current_file
  local win = vim.api.nvim_get_current_win()
  if win and vim.api.nvim_win_is_valid(win) then
    local buf = vim.api.nvim_win_get_buf(win)
    current_file = vim.api.nvim_buf_get_name(buf)
  end
  if current_file == "" then
    current_file = nil
  end

  opts = vim.tbl_deep_extend("force", {
    cwd = nil,
    mode = "files",
    show_score = false,
    show_git_status = false,
    filename_first = true,
    wait_for_index_ms = 10000,
    keymaps = {
      split = "<C-s>",
      vsplit = "<C-v>",
      toggle_mode = "<C-t>",
    },
  }, opts or {})
  opts.cwd = normalize_cwd(opts.cwd)
  local open_cwd = opts.cwd or vim.fn.getcwd()
  if opts.current_file == nil then
    opts.current_file = current_file
  end
  local highlight_overrides = create_highlight_overrides(opts)
  local file_layout = {}
  local fetch_generation = 0

  require("minibuffer").select({
    resumable = true,
    prompt = "FFFiles: ",
    initial_text = query,
    keymaps = select_keymap_overrides(opts.keymaps),
    fetch_fn = function(input, cb)
      fetch_generation = fetch_generation + 1
      local generation = fetch_generation
      local deadline = vim.uv.hrtime() + opts.wait_for_index_ms * 1000000

      local function search()
        if generation ~= fetch_generation then
          return
        end

        local result = fff.file_search(input, {
          mode = opts.mode,
          max_results = opts.max_results,
          page = opts.page,
          current_file = opts.current_file,
          max_threads = opts.max_threads,
          combo_boost_score_multiplier = opts.combo_boost_score_multiplier,
          min_combo_count = opts.min_combo_count,
          cwd = opts.cwd,
          wait_for_index_ms = 0,
        })
        local items = result.items or {}
        local progress_ok, progress = pcall(require("fff.rust").get_scan_progress)
        local indexing = progress_ok
          and progress
          and (progress.is_scanning or (progress.scanned_files_count or 0) == 0)
        if indexing and vim.uv.hrtime() < deadline then
          vim.defer_fn(search, 100)
          return
        end

        file_layout = {}
        local max_name_width = 0
        for _, item in ipairs(items) do
          local path = string_value(item.relative_path)
          local name = item_name(item, path)
          file_layout[item] = {
            name_padding = 0,
          }
          max_name_width = math.max(max_name_width, vim.fn.strdisplaywidth(name))
        end
        for _, item in ipairs(items) do
          local path = string_value(item.relative_path)
          local name = item_name(item, path)
          file_layout[item].name_padding = max_name_width - vim.fn.strdisplaywidth(name)
        end
        cb(items)
      end

      search()
    end,
    multi = true,
    format_fn = function(item)
      return format_file_item(item, opts, highlight_overrides, file_layout)
    end,
    filter_fn = function(ctx)
      return vim.tbl_filter(function(item)
        return item.relative_path and item.relative_path:len() > 0
      end, ctx.items)
    end,
    on_accept = function(selection)
      if #selection == 1 then
        local item = selection[1].item
        vim.cmd(
          "edit " .. vim.fn.fnameescape(vim.fs.joinpath(open_cwd, item.relative_path))
        )
        return
      end

      local qf = {}
      for _, selected in ipairs(selection) do
        local item = selected.item
        qf[#qf + 1] = {
          filename = vim.fs.joinpath(open_cwd, item.relative_path),
          lnum = 1,
          col = 1,
        }
      end
      vim.fn.setqflist({}, " ", { title = "Selected Files", items = qf })
      vim.cmd("copen")
    end,
    on_start = function(sess, keyset)
      set_keymaps(keyset, opts.keymaps.split, function()
        local selected = sess:get_selected()
        if selected then
          sess:close(function()
            vim.cmd(
              "split "
                .. vim.fn.fnameescape(vim.fs.joinpath(open_cwd, selected.relative_path))
            )
          end)
        end
      end)
      set_keymaps(keyset, opts.keymaps.vsplit, function()
        local selected = sess:get_selected()
        if selected then
          sess:close(function()
            vim.cmd(
              "vsplit "
                .. vim.fn.fnameescape(vim.fs.joinpath(open_cwd, selected.relative_path))
            )
          end)
        end
      end)
      set_keymaps(keyset, opts.keymaps.toggle_mode, function()
        opts.mode = toggle_value(opts.mode, { "files", "directories", "mixed" })
        sess:refresh_results()
        sess:render()
      end)
    end,
    footer_fn = function(ctx)
      return {
        { #ctx.items .. " items, " .. opts.mode .. " mode", "Normal" },
        {
          " C-x toggle, C-a toggle-all, "
            .. keymap_label(opts.keymaps.toggle_mode)
            .. " toggle-mode, C-a toggle-all, C-y accept, "
            .. select_keymap_label("next", opts.keymaps)
            .. " next, "
            .. select_keymap_label("previous", opts.keymaps)
            .. " prev",
          "Comment",
        },
      }
    end,
  })
end

---@class minibuffer.integrations.FFFGrepOpts
---@field cwd string|nil
---@field mode 'plain'|'regex'|'fuzzy'|nil
---@field max_file_size number?
---@field max_matches_per_file number?
---@field smart_case boolean|nil
---@field page_size number?
---@field file_offset number?
---@field time_budget_ms number?
---@field trim_whitespace boolean|nil
---@field wait_for_index_ms number?
---@field show_git_status boolean?
---@field filename_first boolean?
---@field treesitter boolean? Enable Treesitter syntax highlighting for matched lines.
---@field highlights table<string, string|table>?
---@field keymaps minibuffer.integrations.FFFKeymaps?

--- Run fff grep
---@param query string|nil
---@param opts minibuffer.integrations.FFFGrepOpts|nil
function M.content_search(query, opts)
  require("minibuffer.internal.guard").check()
  query, opts = normalize_search_args(query, opts)
  opts = vim.tbl_deep_extend("force", {
    cwd = nil,
    mode = "plain",
    smart_case = true,
    show_git_status = false,
    filename_first = true,
    treesitter = true,
    keymaps = {
      split = "<C-s>",
      vsplit = "<C-v>",
      toggle_mode = "<C-t>",
    },
  }, opts or {})
  opts.cwd = normalize_cwd(opts.cwd)
  local open_cwd = opts.cwd or vim.fn.getcwd()
  local highlight_overrides = create_highlight_overrides(opts)

  require("minibuffer").select({
    resumable = true,
    prompt = "FFFGrep: ",
    initial_text = query,
    keymaps = select_keymap_overrides(opts.keymaps),
    fetch_fn = function(input, cb)
      local result = fff.content_search(input, {
        mode = opts.mode,
        max_file_size = opts.max_file_size,
        max_matches_per_file = opts.max_matches_per_file,
        smart_case = opts.smart_case,
        page_size = opts.page_size,
        file_offset = opts.file_offset,
        time_budget_ms = opts.time_budget_ms,
        trim_whitespace = opts.trim_whitespace,
        cwd = opts.cwd,
        wait_for_index_ms = opts.wait_for_index_ms,
      })
      cb(result.items)
    end,
    multi = true,
    format_fn = function(item)
      return format_content_item(item, opts, highlight_overrides)
    end,
    filter_fn = function(ctx)
      return vim.tbl_filter(function(item)
        return item.relative_path and item.relative_path:len() > 0 and item.line_number
      end, ctx.items)
    end,
    on_accept = function(selection)
      if #selection == 1 then
        local item = selection[1].item
        vim.cmd(
          "edit " .. vim.fn.fnameescape(vim.fs.joinpath(open_cwd, item.relative_path))
        )
        pcall(vim.api.nvim_win_set_cursor, 0, { item.line_number, 0 })
        vim.cmd("normal! zz")
        return
      end

      local qf = {}
      for _, selected in ipairs(selection) do
        local item = selected.item
        qf[#qf + 1] = {
          filename = vim.fs.joinpath(open_cwd, item.relative_path),
          lnum = item.line_number,
          col = item.col or 1,
          text = item.line_content,
        }
      end
      vim.fn.setqflist({}, " ", { title = "Grep Results", items = qf })
      vim.cmd("copen")
    end,
    on_start = function(sess, keyset)
      set_keymaps(keyset, opts.keymaps.split, function()
        local selected = sess:get_selected()
        if selected then
          sess:close(function()
            vim.cmd(
              "split "
                .. vim.fn.fnameescape(vim.fs.joinpath(open_cwd, selected.relative_path))
            )
            pcall(vim.api.nvim_win_set_cursor, 0, { selected.line_number, 0 })
            vim.cmd("normal! zz")
          end)
        end
      end)
      set_keymaps(keyset, opts.keymaps.vsplit, function()
        local selected = sess:get_selected()
        if selected then
          if selected then
            sess:close(function()
              vim.cmd(
                "vsplit "
                  .. vim.fn.fnameescape(vim.fs.joinpath(open_cwd, selected.relative_path))
              )
              pcall(vim.api.nvim_win_set_cursor, 0, { selected.line_number, 0 })
              vim.cmd("normal! zz")
            end)
          end
        end
      end)
      set_keymaps(keyset, opts.keymaps.toggle_mode, function()
        opts.mode = toggle_value(opts.mode, { "plain", "regex", "fuzzy" })
        sess:refresh_results()
        sess:render()
      end)
    end,
    on_close = opts.treesitter and cleanup_treesitter or nil,
    footer_fn = function(ctx)
      return {
        { #ctx.items .. " items, " .. opts.mode .. " mode", "Normal" },
        {
          " C-x toggle, C-a toggle-all, "
            .. keymap_label(opts.keymaps.toggle_mode)
            .. " toggle-mode, C-a toggle-all, C-y accept, "
            .. select_keymap_label("next", opts.keymaps)
            .. " next, "
            .. select_keymap_label("previous", opts.keymaps)
            .. " prev",
          "Comment",
        },
      }
    end,
  })
end

return M
