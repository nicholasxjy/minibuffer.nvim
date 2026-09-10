local M = {}

local row_groups = {
  FzfLuaDirPart = "directory_path",
  FzfLuaFilePart = "file",
  FzfLuaFzfMatch = "matched",
  MinibufferGrepMatch = "matched",
  FzfLuaFzfPointer = "pointer",
  FzfLuaFzfMarker = "marker",
  FzfLuaPathLineNr = "line_number",
  FzfLuaPathColNr = "column_number",
  FzfLuaFzfInfo = "info",
  FzfLuaHeaderBind = "header_bind",
  FzfLuaHeaderText = "header_text",
}

-- Renderers may return cached chunks. Copy once before applying session overrides.
function M.configure(opts, session)
  local function highlight(group)
    if type(group) == "table" then
      return vim.tbl_map(highlight, group)
    end
    return opts.highlights[row_groups[group]] or group
  end
  local function decorate(value)
    if type(value) ~= "table" then
      return value
    end
    local result = value
    if result.text then
      result.hl = highlight(result.hl)
    elseif type(result[1]) == "string" then
      result[2] = highlight(result[2])
    else
      for key, child in pairs(result) do
        result[key] = decorate(child)
      end
    end
    return result
  end
  local function is_pointer(group)
    if type(group) == "table" then
      for _, child in ipairs(group) do
        if is_pointer(child) then
          return true
        end
      end
    end
    return group == "FzfLuaFzfPointer"
  end
  local blank = opts.pointer and string.rep(" ", vim.fn.strdisplaywidth(opts.pointer))
  for _, key in ipairs({ "format_fn", "group_fn", "header_fn", "footer_fn" }) do
    local render = session[key]
    local pointer = key == "format_fn" and opts.pointer ~= nil
    if render and (pointer or next(opts.highlights)) then
      session[key] = function(...)
        local result = vim.deepcopy(render(...))
        local _, ctx, index = ...
        if pointer and type(result) == "table" then
          local text = ctx and index and ctx.current_index == index and opts.pointer
            or blank
          if result[1] and is_pointer(result[1].hl) then
            result[1].text = text
          elseif opts.pointer ~= "" then
            table.insert(result, 1, { text = text .. " ", hl = "FzfLuaFzfPointer" })
          end
        end
        return decorate(result)
      end
    end
  end
end

return M
