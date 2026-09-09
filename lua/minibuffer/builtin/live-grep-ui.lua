local M = {}
local buffers_ui = require("minibuffer.builtin.buffers-ui")

function M.setup()
  buffers_ui.setup()
  local light = vim.o.background == "light"
  for name, definition in pairs({
    FzfLuaLivePrompt = { fg = "PaleVioletRed1" },
    FzfLuaPathColNr = { fg = light and "CadetBlue4" or "CadetBlue1" },
    FzfLuaFzfSpinner = { link = "FzfLuaFzfPointer" },
    -- Live grep matches are rg's bold ANSI red, not fzf fuzzy matches.
    MinibufferGrepMatch = { fg = vim.g.terminal_color_1 or "#800000", bold = true },
  }) do
    vim.api.nvim_set_hl(0, name, vim.tbl_extend("force", definition, { default = true }))
  end
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("MinibufferGrepHighlights", { clear = true }),
    callback = M.setup,
  })
end

function M.group(item, previous, filename_first)
  if previous and previous.file == item.file then return nil end
  local chunks = { { text = "  " } }
  local ok, icons = pcall(require, "nvim-web-devicons")
  local icon, icon_hl
  if ok then
    icon, icon_hl = icons.get_icon(vim.fs.basename(item.file), nil, { default = true })
  else
    ok, icons = pcall(require, "mini.icons")
    if ok then
      icon, icon_hl = icons.get("file", item.file)
    end
  end
  icon = icon or ""
  chunks[#chunks + 1] = {
    text = icon .. string.rep(" ", math.max(0, 2 - vim.fn.strdisplaywidth(icon)) + 1),
    hl = icon_hl,
  }
  local directory, filename = item.file:match("^(.*[/])([^/]+)$")
  if filename_first == false then
    chunks[#chunks + 1] = { text = directory or "", hl = "FzfLuaDirPart" }
  end
  chunks[#chunks + 1] = { text = filename or item.file, hl = "FzfLuaFilePart" }
  if filename_first ~= false and directory then
    chunks[#chunks + 1] = { text = "  " .. directory:sub(1, -2), hl = "FzfLuaDirPart" }
  end
  return chunks
end

function M.format(item, ctx, index)
  local chunks = {
    { text = ctx.current_index == index and ">" or " ", hl = "FzfLuaFzfPointer" },
    { text = vim.tbl_contains(ctx.selected_indices, index) and ">" or " ", hl = "FzfLuaFzfMarker" },
    { text = " " },
  }
  chunks[#chunks + 1] = { text = tostring(item.line), hl = "FzfLuaPathLineNr" }
  chunks[#chunks + 1] = { text = ":" }
  chunks[#chunks + 1] = { text = tostring(item.col), hl = "FzfLuaPathColNr" }
  chunks[#chunks + 1] = { text = string.rep(" ", item.location_width - #tostring(item.line) - #tostring(item.col) - 1) .. " │ " }
  local offset = 0
  for _, match in ipairs(item.matches) do
    chunks[#chunks + 1] = { text = item.text:sub(offset + 1, match.start) }
    chunks[#chunks + 1] = {
      text = item.text:sub(match.start + 1, match["end"]),
      hl = "MinibufferGrepMatch",
    }
    offset = match["end"]
  end
  chunks[#chunks + 1] = { text = item.text:sub(offset + 1) }
  return chunks
end

function M.header(ctx, width, cwd, navigation)
  -- Reuse the buffers picker's wrapping and key labels; info belongs to input.
  local lines = buffers_ui.hints(ctx, {
    split = "<C-s>",
    vsplit = "<C-v>",
    delete = {},
    next = navigation.next,
    previous = navigation.previous,
  }, nil, width)
  if cwd ~= vim.fn.getcwd() then
    lines[#lines + 1] = {
      { text = "cwd: ", hl = "FzfLuaHeaderText" },
      { text = vim.fn.fnamemodify(cwd, ":~"), hl = "FzfLuaFzfInfo" },
    }
  end
  return lines
end

function M.info(sess)
  local count = #sess._items
  local text = (" %d/%d%s "):format(
    count,
    count,
    #sess._selected_indices > 0 and (" (" .. #sess._selected_indices .. ")") or ""
  )
  local chunks = {}
  if sess._loading then
    chunks[#chunks + 1] = { "⠋", "FzfLuaFzfSpinner" }
  end
  chunks[#chunks + 1] = { text, "FzfLuaFzfInfo" }
  -- Hide inline info when the query needs the entire input row.
  if
    vim.fn.strdisplaywidth(sess.prompt .. sess._input .. text) + 2
    < vim.api.nvim_win_get_width(sess._entry.win)
  then
    vim.api.nvim_buf_set_extmark(
      sess._entry.buf,
      require("minibuffer.internal.state").ns,
      0,
      0,
      {
        virt_text = chunks,
        virt_text_pos = "right_align",
      }
    )
  end
end

return M
