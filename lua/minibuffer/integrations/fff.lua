local ok, fff = pcall(require, "fff")
if not ok then
  error("Make sure fff.nvim is installed and loaded.")
end
if not fff.file_search then
  error("Your version of fff.nvim is missing the `file_search` api. Can't proceed.")
end

local function toggle_value(current, values)
  for i, value in ipairs(values) do
    if value == current then
      return values[(i % #values) + 1]
    end
  end
  return values[1]
end

local function search(kind, query, opts)
  require("minibuffer.internal.guard").check()
  -- Keep existing opts-only keymaps working.
  if type(query) == "table" and opts == nil then
    opts, query = query, ""
  end
  vim.validate("query", query, "string", true)
  vim.validate("opts", opts, "table", true)
  opts = vim.deepcopy(opts or {})
  local config = vim.deepcopy(require("fff.conf").get())
  -- Only presentation/configuration fields are removed; search API options pass through.
  for _, name in ipairs({
    "layout",
    "git",
    "hl",
    "file_picker",
    "debug",
    "grep",
    "keymaps",
    "mappings",
    "select",
    "prompt",
    "wrap_around",
    "git_status_signs",
    "show_git_status",
  }) do
    if opts[name] ~= nil then
      config[name] = type(opts[name]) == "table"
          and vim.tbl_deep_extend("force", config[name] or {}, opts[name])
        or opts[name]
      opts[name] = nil
    end
  end
  config.git_status_signs = config.git_status_signs or {}
  local overrides = opts.highlights or {}
  opts.highlights = nil
  require("fff.highlights").setup()
  for name, spec in pairs(overrides) do
    vim.validate("highlights." .. name, spec, { "string", "table" })
    if type(spec) == "table" then
      local group = "MinibufferFFF"
        .. name:gsub("^%l", string.upper):gsub("_(%l)", string.upper)
      vim.api.nvim_set_hl(0, group, spec)
      config.hl[name] = group
    else
      config.hl[name] = spec
    end
  end
  for status, sign in pairs(config.git_status_signs) do
    vim.validate("git_status_signs." .. status, sign, "string")
    assert(vim.fn.strdisplaywidth(sign) <= 2, "Git signs must fit in two cells")
  end
  local grep = kind == "content_search"
  local modes = grep and config.grep.modes or { "files", "directories", "mixed" }
  if grep then
    for _, name in ipairs({
      "max_file_size",
      "max_matches_per_file",
      "smart_case",
      "time_budget_ms",
      "trim_whitespace",
    }) do
      if opts[name] == nil then
        opts[name] = config.grep[name]
      end
    end
    opts.mode = opts.mode or modes[1]
  end
  local keys = config.keymaps
  local keymaps =
    { next = keys.next or keys.move_down, previous = keys.previous or keys.move_up }
  local cwd = vim.fn.fnamemodify(vim.fn.expand(opts.cwd or config.base_path), ":p")
  local current_file = opts.current_file or vim.api.nvim_buf_get_name(0)
  local session
  local render = require("minibuffer.integrations.fff-render").render

  local function path(item)
    return vim.fs.joinpath(cwd, item.relative_path)
  end

  local function open(item, command)
    local target = config.select.select_window(
      vim.api.nvim_get_current_buf(),
      command == "tabedit" and "tab" or command
    )
    if target and vim.api.nvim_win_is_valid(target) then
      vim.api.nvim_set_current_win(target)
    end
    vim.cmd(command .. " " .. vim.fn.fnameescape(path(item)))
    if grep then
      pcall(vim.api.nvim_win_set_cursor, 0, { item.line_number, item.col or 0 })
      vim.cmd("normal! zz")
    end
  end

  local function quickfix(selection)
    local qf = {}
    for _, selected in ipairs(selection) do
      local item = selected.item
      qf[#qf + 1] = {
        filename = path(item),
        lnum = item.line_number or 1,
        col = (item.col or 0) + 1,
        text = item.line_content,
      }
    end
    vim.fn.setqflist(
      {},
      " ",
      { title = grep and "Grep Results" or "Selected Files", items = qf }
    )
    vim.cmd("copen")
  end

  return require("minibuffer").select({
    resumable = true,
    keymaps = keymaps,
    prompt = config.prompt,
    fetch_fn = function(input, cb)
      cb(fff[kind](input, opts).items)
    end,
    multi = true,
    dynamic_height = false,
    max_height = 15,
    filter_fn = function(ctx)
      return vim.tbl_filter(function(item)
        if
          not item.relative_path
          or item.relative_path == ""
          or (grep and not item.line_number)
        then
          return false
        end
        item.name = item.name or vim.fn.fnamemodify(item.relative_path, ":t")
        item.extension = item.extension or vim.fn.fnamemodify(item.name, ":e")
        item.path = item.path or path(item)
        return true
      end, ctx.items)
    end,
    format_fn = function()
      return {}
    end,
    on_close = function()
      if grep then
        require("fff.treesitter_hl").cleanup()
      end
    end,
    on_change = function()
      if session then
        render(session, config, grep, current_file)
      end
    end,
    on_accept = function(selection)
      if #selection == 1 then
        open(selection[1].item, "edit")
        return
      end
      quickfix(selection)
    end,
    on_start = function(sess, keyset)
      if query then
        sess._input = query
        query = nil
      end
      session = sess
      local winhl = config.hl.winhl
      vim.wo[sess._entry.win].winhighlight = (type(winhl) == "table" and winhl.prompt)
        or (type(winhl) == "string" and winhl)
        or (
          "Normal:"
          .. config.hl.normal
          .. ",NormalFloat:"
          .. config.hl.normal
          .. ",Prompt:"
          .. config.hl.prompt
        )
      local function bind(action, callback)
        local bindings = keys[action] or {}
        for _, key in ipairs(type(bindings) == "string" and { bindings } or bindings) do
          keyset("i", key, callback)
        end
      end
      for action, command in pairs({
        select_split = "split",
        select_vsplit = "vsplit",
        select_tab = "tabedit",
      }) do
        bind(action, function()
          local selected = sess:get_selected()
          if selected then
            sess:close(function()
              open(selected, command)
            end)
          end
        end)
      end
      bind("close", function()
        sess:cancel()
      end)
      bind("select", function()
        sess:accept()
      end)
      bind("toggle_select", function()
        sess:toggle_selection()
      end)
      bind("send_to_quickfix", function()
        local selected = {}
        for index, item in ipairs(sess._items) do
          if #sess._selected_indices == 0 or sess:is_selected(index) then
            selected[#selected + 1] = { item = item }
          end
        end
        if #selected > 0 then
          sess:close(function()
            quickfix(selected)
          end)
        end
      end)
      if grep then
        bind("cycle_grep_modes", function()
          opts.mode = toggle_value(opts.mode, modes)
          sess:refresh_results()
          sess:render()
        end)
      end
      -- Navigation overrides win over fff action defaults sharing the same key.
      for action, delta in pairs({ next = 1, previous = -1 }) do
        local bindings = keymaps[action]
        for _, key in ipairs(type(bindings) == "string" and { bindings } or bindings) do
          keyset("i", key, function()
            sess:move(delta)
          end)
        end
      end
      for mode, mappings in pairs(config.mappings or {}) do
        for key, callback in pairs(mappings) do
          keyset(mode, key, callback)
        end
      end
      if not config.wrap_around then
        local move = getmetatable(sess).move
        sess.move = function(self, delta)
          local target = math.max(1, math.min(#self._items, self._current_index + delta))
          move(self, target - self._current_index)
        end
      end
      sess:render()
    end,
    footer_fn = function(ctx)
      local label = require("minibuffer.internal.util").keymap_label
      return {
        {
          #ctx.items .. " items, " .. (opts.mode or modes[1]) .. " mode",
          config.hl.normal,
        },
        {
          " "
            .. label(keys.select)
            .. " accept, "
            .. label(keymaps.next)
            .. " next, "
            .. label(keymaps.previous)
            .. " prev"
            .. (grep and (", " .. label(keys.cycle_grep_modes) .. " toggle-mode") or ""),
          config.hl.directory_path,
        },
      }
    end,
  })
end

local M = {}

---@class minibuffer.integrations.FFFDisplayOpts
---@field highlights table<string, string|table>?
---@field git_status_signs table<string, string>?
---@field show_git_status boolean?
---@field keymaps (FffKeymapsConfig|minibuffer.config.select.keymaps)?
---@field layout FffLayoutConfig?
---@field git table?
---@field hl table?
---@field file_picker table?
---@field debug table?
---@field grep FffGrepConfig?
---@field prompt string?
---@field wrap_around boolean?
---@field mappings table?
---@field select FffSelectConfig?

--- Open file search with fff's query and options format.
---@param query string? Initial search query
---@param opts (fff.FileSearchOpts|minibuffer.integrations.FFFDisplayOpts)?
function M.file_search(query, opts)
  return search("file_search", query, opts)
end

--- Open content search with fff's query and options format.
---@param query string? Initial search query
---@param opts (fff.ContentSearchOpts|minibuffer.integrations.FFFDisplayOpts)?
function M.content_search(query, opts)
  return search("content_search", query, opts)
end

return M
