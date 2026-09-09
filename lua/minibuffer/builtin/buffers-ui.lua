local M = {}
local initialized = false

-- Use the same groups and standalone defaults as fzf-lua. Existing theme
-- definitions win, and no fzf-lua module needs to be loaded by this picker.
function M.setup()
  if not initialized then
    initialized = true
    vim.api.nvim_create_autocmd("ColorScheme", {
      group = vim.api.nvim_create_augroup(
        "MinibufferBuffersHighlights",
        { clear = true }
      ),
      callback = M.setup,
    })
  end
  local light = vim.o.background == "light"
  local groups = {
    FzfLuaNormal = { link = "Normal" },
    FzfLuaCursorLine = { link = "CursorLine" },
    FzfLuaFzfNormal = { link = "FzfLuaNormal" },
    FzfLuaFzfQuery = { link = "FzfLuaNormal" },
    FzfLuaFzfCursorLine = { link = "FzfLuaCursorLine" },
    FzfLuaFzfMatch = { link = "Special" },
    FzfLuaFzfPrompt = { link = "Special" },
    FzfLuaFzfPointer = { link = "Special" },
    FzfLuaFzfMarker = { link = "FzfLuaFzfPointer" },
    FzfLuaFzfInfo = { link = "NonText" },
    FzfLuaHeaderBind = { fg = light and "MediumSpringGreen" or "BlanchedAlmond" },
    FzfLuaHeaderText = { fg = light and "Brown4" or "Brown1" },
    FzfLuaBufNr = { fg = light and "AquaMarine3" or "BlanchedAlmond" },
    FzfLuaBufFlagCur = { fg = light and "Brown4" or "Brown1" },
    FzfLuaBufFlagAlt = { fg = light and "CadetBlue4" or "CadetBlue1" },
    FzfLuaPathLineNr = { fg = light and "MediumSpringGreen" or "LightGreen" },
    FzfLuaDirPart = { link = "Comment" },
    FzfLuaFilePart = { link = "@none" },
  }
  for name, definition in pairs(groups) do
    vim.api.nvim_set_hl(0, name, vim.tbl_extend("force", definition, { default = true }))
  end
  vim.api.nvim_set_hl(0, "MinibufferBuffersBold", { bold = true })
  local selection = vim.api.nvim_get_hl(0, { name = "FzfLuaFzfCursorLine", link = false })
  selection.bold = true
  vim.api.nvim_set_hl(0, "MinibufferBuffersSelection", selection)
end

function M.prepare(items)
  local width = 0
  for _, item in ipairs(items) do
    item.directory, item.filename = item.name:match("^(.*[/])([^/]+)$")
    item.directory = item.directory or ""
    item.filename = item.filename or item.name
    item.file_width = vim.fn.strdisplaywidth(item.filename)
      + (item.path ~= "" and vim.fn.strdisplaywidth(item.icon .. " :" .. item.lnum) or 0)
    width = math.max(width, item.file_width)
  end
  for _, item in ipairs(items) do
    item.file_padding = width - item.file_width
  end
end

function M.format(item, ctx, index, filename_first)
  local current = ctx and ctx.current_index == index
  local chunks = {
    { text = ctx and ctx.current_index == index and ">" or " ", hl = "FzfLuaFzfPointer" },
    {
      text = ctx and vim.tbl_contains(ctx.selected_indices, index) and ">" or " ",
      hl = "FzfLuaFzfMarker",
    },
    { text = "[" },
    { text = tostring(item.bufnr), hl = "FzfLuaBufNr" },
    { text = "]" .. string.rep(" ", item.bufnr_padding) .. " " },
    {
      text = item.flag,
      hl = item.flag == "%" and "FzfLuaBufFlagCur"
        or item.flag == "#" and "FzfLuaBufFlagAlt"
        or nil,
    },
    { text = item.flags .. "  " },
  }
  if item.path ~= "" then
    chunks[#chunks + 1] = { text = item.icon .. " ", hl = item.icon_hl }
  end
  local matches = {}
  for _, pos in ipairs(item.match_positions or {}) do
    matches[pos] = true
  end
  -- Match offsets refer to the original path, even when its parts move.
  local directory_length = vim.fn.strchars(item.directory)
  local function append_path(text, offset, hl)
    for pos, char in ipairs(vim.fn.split(text, "\\zs")) do
      chunks[#chunks + 1] = {
        text = char,
        hl = matches[offset + pos - 1] and "FzfLuaFzfMatch" or hl,
      }
    end
  end
  if filename_first == false then
    append_path(item.directory, 0, "FzfLuaDirPart")
  end
  append_path(item.filename, directory_length, "FzfLuaFilePart")
  if item.path ~= "" then
    chunks[#chunks + 1] = { text = ":" }
    chunks[#chunks + 1] = { text = tostring(item.lnum), hl = "FzfLuaPathLineNr" }
  end
  if filename_first ~= false and item.directory ~= "" then
    chunks[#chunks + 1] = { text = string.rep(" ", item.file_padding + 2) }
    local directory = item.directory == "/" and "/" or item.directory:sub(1, -2)
    append_path(directory, 0, "FzfLuaDirPart")
  end
  if current then
    for _, chunk in ipairs(chunks) do
      chunk.hl = chunk.hl and { chunk.hl, "MinibufferBuffersBold" }
        or "MinibufferBuffersBold"
    end
  end
  return chunks
end

function M.footer(ctx, keymaps, total)
  local chunks = { { ":: ", "FzfLuaFzfInfo" } }
  local actions = {
    { keymaps.split, "split" },
    { keymaps.vsplit, "vsplit" },
    { keymaps.delete, "delete" },
    { "<C-x>", "toggle" },
    { "<C-a>", "toggle-all" },
    { "<CR>", "accept" },
    { keymaps.next, "next" },
    { keymaps.previous, "prev" },
  }
  local first = true
  for _, action in ipairs(actions) do
    local keys = type(action[1]) == "string" and { action[1] } or action[1]
    if #keys > 0 then
      if not first then
        chunks[#chunks + 1] = { "|", "FzfLuaFzfInfo" }
      end
      first = false
      local labels = {}
      for _, key in ipairs(keys) do
        labels[#labels + 1] = key
          :lower()
          :gsub("<c%-", "ctrl-")
          :gsub("<s%-", "shift-")
          :gsub("<cr>", "enter ")
          :gsub("<", "")
          :gsub(">", " ")
          :gsub("%s+$", "")
      end
      chunks[#chunks + 1] = { "<", "FzfLuaFzfInfo" }
      chunks[#chunks + 1] = { table.concat(labels, "/"), "FzfLuaHeaderBind" }
      chunks[#chunks + 1] = { "> to ", "FzfLuaFzfInfo" }
      chunks[#chunks + 1] = { action[2], "FzfLuaHeaderText" }
    end
  end
  if total ~= nil then
    chunks[#chunks + 1] = {
      ("  %d/%d%s"):format(
        #ctx.items,
        total,
        #ctx.selected_indices > 0 and (" (%d)"):format(#ctx.selected_indices) or ""
      ),
      "FzfLuaFzfInfo",
    }
  end
  return chunks
end

-- Keep complete actions together where possible. Long key sequences still wrap
-- by display cells, preserving all text and its highlight across lines.
function M.hints(ctx, keymaps, total, width)
  width = math.max(1, width)
  local blocks = { {} }
  for _, chunk in ipairs(M.footer(ctx, keymaps, total)) do
    if chunk[1] == "|" then
      blocks[#blocks + 1] = {}
    else
      local block = blocks[#blocks]
      block[#block + 1] = { text = chunk[1], hl = chunk[2] }
    end
  end
  local lines, used = { {} }, 0
  local function append(chunks)
    for _, chunk in ipairs(chunks) do
      for _, char in ipairs(vim.fn.split(chunk.text, "\\zs")) do
        local cells = vim.fn.strdisplaywidth(char, used)
        if used > 0 and used + cells > width then
          lines[#lines + 1], used = {}, 0
        end
        local line = lines[#lines]
        local previous = line[#line]
        if previous and previous.hl == chunk.hl then
          previous.text = previous.text .. char
        else
          line[#line + 1] = { text = char, hl = chunk.hl }
        end
        used = used + cells
      end
    end
  end
  for _, block in ipairs(blocks) do
    local block_width = 0
    for _, chunk in ipairs(block) do
      block_width = block_width + vim.fn.strdisplaywidth(chunk.text)
    end
    if used > 0 then
      if used + 3 + block_width > width then
        lines[#lines + 1], used = {}, 0
      else
        append({ { text = " | ", hl = "FzfLuaFzfInfo" } })
      end
    end
    append(block)
  end
  return lines
end

return M
