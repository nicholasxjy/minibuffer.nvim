local ui = require("minibuffer.builtin.live-grep-ui")
local names = { "Error", "Warn", "Info", "Hint" }

local function severity(value, key)
  if value == nil then return nil end
  local level = type(value) == "string" and vim.diagnostic.severity[value:upper()] or value
  assert(type(level) == "number" and level % 1 == 0 and level >= 1 and level <= 4,
    key .. " must be ERROR, WARN, INFO, HINT or 1..4")
  return level
end

local function format(item, ctx, index)
  local chunks = {
    { text = ctx.current_index == index and ">" or " ", hl = "FzfLuaFzfPointer" },
    { text = vim.tbl_contains(ctx.selected_indices, index) and ">" or " ", hl = "FzfLuaFzfMarker" },
  }
  local matches = {}
  for _, position in ipairs(item.matches or {}) do matches[position] = true end
  local offset = 0
  for _, chunk in ipairs(item.chunks) do
    for _, char in ipairs(vim.fn.split(chunk.text, "\\zs")) do
      chunks[#chunks + 1] = { text = char, hl = matches[offset] and "FzfLuaFzfMatch" or chunk.hl }
      offset = offset + 1
    end
  end
  if ctx.current_index == index then
    for _, chunk in ipairs(chunks) do
      chunk.hl = chunk.hl and { chunk.hl, "MinibufferBuffersBold" } or "MinibufferBuffersBold"
    end
  end
  return chunks
end

---@class minibuffer.builtin.DiagnosticsOpts: minibuffer.builtin.Opts
---@field cwd? string
---@field scope? "buffer"|"workspace"
---@field sort? boolean|1|2|"severity"|"reverse" False keeps provider order; default true sorts ERROR first.
---@field severity_only? integer|string Exact severity.
---@field severity_limit? integer|string Include this severity and more severe diagnostics.
---@field severity_bound? integer|string Include this severity and less severe diagnostics.
---@field diag_source? boolean Show source (default true).
---@field diag_code? boolean Show diagnostic code (default true).
---@field keymaps? minibuffer.config.select.keymaps
---@field filename_first? boolean Show filename before directory (default true).
---@param opts? minibuffer.builtin.DiagnosticsOpts
return function(opts)
  require("minibuffer.internal.guard").check()
  opts = require("minibuffer.builtin.config").resolve(opts)
  vim.validate("filename_first", opts.filename_first, "boolean", true)
  local scope = opts.scope or "workspace"
  assert(scope == "buffer" or scope == "workspace", "scope must be buffer or workspace")
  assert(opts.sort == nil or opts.sort == true or opts.sort == false or opts.sort == 1
    or opts.sort == 2 or opts.sort == "severity" or opts.sort == "reverse", "invalid diagnostic sort")
  local only = severity(opts.severity_only, "severity_only")
  local limit = severity(opts.severity_limit, "severity_limit")
  local bound = severity(opts.severity_bound, "severity_bound")
  assert(not only or not (limit or bound), "severity_only cannot be combined with severity_limit/bound")
  assert(not limit or not bound or bound <= limit, "severity_bound must not exceed severity_limit")
  local filter = only or { min = limit or 4, max = bound or 1 }
  local items = vim.diagnostic.get(scope == "buffer" and 0 or nil, { severity = filter })
  if opts.filter.cwd then
    local cwd = vim.fn.fnamemodify(opts.cwd or vim.fn.getcwd(), ":p")
    items = vim.tbl_filter(function(item)
      local path = vim.api.nvim_buf_get_name(item.bufnr)
      return path ~= "" and vim.fs.relpath(cwd, path) ~= nil
    end, items)
  end
  if opts.sort ~= false then
    local reverse = opts.sort == 2 or opts.sort == "reverse"
    table.sort(items, function(a, b)
      if a.severity ~= b.severity then
        if reverse then return a.severity > b.severity end
        return a.severity < b.severity
      end
      if a.bufnr ~= b.bufnr then return a.bufnr < b.bufnr end
      if a.lnum ~= b.lnum then return a.lnum < b.lnum end
      return a.col < b.col
    end)
  end
  local signs = vim.diagnostic.config().signs
  for _, item in ipairs(items) do
    local hl = "DiagnosticSign" .. names[item.severity]
    local icon = type(signs) == "table" and signs.text and signs.text[item.severity]
      or names[item.severity]:sub(1, 1)
    local path = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(item.bufnr), ":.")
    local directory, filename = path:match("^(.*[/])([^/]+)$")
    item.chunks = {
      { text = vim.trim(icon) .. " ", hl = hl },
    }
    if opts.diag_source ~= false and item.source then
      table.insert(item.chunks, { text = "[" .. item.source .. "] ", hl = hl })
    end
    vim.list_extend(item.chunks, {
      { text = opts.filename_first == false and path or filename or path, hl = hl },
      { text = ":" },
      { text = tostring(item.lnum + 1), hl = "FzfLuaPathLineNr" },
      { text = ":" },
      { text = tostring(item.col + 1), hl = "FzfLuaPathColNr" },
    })
    if opts.filename_first ~= false and directory then
      table.insert(item.chunks, { text = "  " .. directory:gsub("(.)/$", "%1"), hl = "FzfLuaDirPart" })
    end
    table.insert(item.chunks, { text = ": " .. vim.trim(item.message):gsub("[\r\n]+", " ") })
    if opts.diag_code ~= false and item.code ~= nil then
      table.insert(item.chunks, { text = " [" .. tostring(item.code) .. "]", hl = "Comment" })
    end
    local text = {}
    for _, chunk in ipairs(item.chunks) do text[#text + 1] = chunk.text end
    item.search_text = table.concat(text)
  end
  ui.setup()
  local keymaps = opts.keymaps
  local session
  local function open(item, command)
    if command then vim.cmd(command) end
    vim.api.nvim_set_current_buf(item.bufnr)
    vim.api.nvim_win_set_cursor(0, { item.lnum + 1, item.col })
    vim.cmd("normal! zvzz")
  end
  return require("minibuffer.builtin.config").select(opts, {
    resumable = true, prompt = "> ", prompt_position = "top", multi = true,
    dynamic_height = false, max_height = 15, keymaps = keymaps,
    highlights = {
      normal = "FzfLuaFzfNormal", query = "FzfLuaFzfQuery", prompt = "FzfLuaFzfPrompt",
      selection = "MinibufferBuffersSelection", multi_selection = "FzfLuaFzfNormal",
    },
    header_fn = function(ctx, width) return ui.header(ctx, width, vim.fn.getcwd(), keymaps) end,
    on_change = function() if session then ui.info(session) end end,
    fetch_fn = function(_, cb) cb(items) end,
    filter_fn = function(ctx)
      for _, item in ipairs(ctx.items) do item.matches = nil end
      if ctx.input == "" then return ctx.items end
      local result = vim.fn.matchfuzzypos(ctx.items, ctx.input, { key = "search_text" })
      for i, item in ipairs(result[1]) do item.matches = result[2][i] end
      return result[1]
    end,
    format_fn = format,
    on_accept = function(selection)
      if #selection == 1 then return open(selection[1].item) end
      local qf = {}
      for _, selected in ipairs(selection) do
        local item = selected.item
        qf[#qf + 1] = { bufnr = item.bufnr, lnum = item.lnum + 1, col = item.col + 1,
          text = item.message, type = names[item.severity]:sub(1, 1) }
      end
      vim.fn.setqflist({}, " ", { title = "Diagnostics", items = qf })
      vim.cmd("copen")
    end,
    on_start = function(sess, keyset)
      session = sess
      ui.info(sess)
      for _, command in ipairs({ "split", "vsplit" }) do
        require("minibuffer.builtin.config").bind(keyset, keymaps[command], function()
          local item = sess:get_selected()
          if item then sess:close(function() open(item, command) end) end
        end)
      end
    end,
  })
end
