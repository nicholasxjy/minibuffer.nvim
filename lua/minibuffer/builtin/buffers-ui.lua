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
  }
  for name, definition in pairs(groups) do
    vim.api.nvim_set_hl(0, name, vim.tbl_extend("force", definition, { default = true }))
  end
end

function M.format(item, ctx, index)
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
  -- matchfuzzypos uses character offsets; extmarks use byte offsets. Chunks
  -- keep multibyte filenames and icon widths out of the offset calculation.
  for pos, char in ipairs(vim.fn.split(item.name, "\\zs")) do
    chunks[#chunks + 1] = {
      text = char,
      hl = matches[pos - 1] and "FzfLuaFzfMatch" or nil,
    }
  end
  if item.path ~= "" then
    chunks[#chunks + 1] = { text = ":" }
    chunks[#chunks + 1] = { text = tostring(item.lnum), hl = "FzfLuaPathLineNr" }
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
  chunks[#chunks + 1] = {
    ("  %d/%d%s"):format(
      #ctx.items,
      total,
      #ctx.selected_indices > 0 and (" (%d)"):format(#ctx.selected_indices) or ""
    ),
    "FzfLuaFzfInfo",
  }
  return chunks
end

return M
