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

-- Merge maps by field, but replace lists (including {}) as a whole.
function M.resolve(opts, defaults)
  local config = require("minibuffer.config")
  local resolved = vim.deepcopy(
    vim.tbl_deep_extend("force", {}, defaults or {}, config.builtin, opts or {})
  )
  local valid, err = require("minibuffer.config.validate").validate_builtin(resolved)
  assert(valid, err)
  for _, key in ipairs({ "filter", "highlights", "hl" }) do
    resolved[key] = vim.deepcopy(
      vim.tbl_extend(
        "force",
        {},
        defaults and defaults[key] or {},
        config.builtin[key],
        opts and opts[key] or {}
      )
    )
  end
  resolved.keymaps = vim.deepcopy(
    vim.tbl_extend(
      "force",
      {},
      config.select.keymaps,
      config.builtin.keymaps,
      opts and opts.keymaps or {}
    )
  )
  for _, layer in ipairs({ config.builtin, opts or {} }) do
    for key, value in pairs(layer.highlights or {}) do
      local name = ({
        selection = "cursor",
        directory_path = "directory_path",
        matched = "matched",
        normal = "normal",
        prompt = "prompt",
      })[key]
      if name then
        resolved.hl[name] = value
      end
    end
    resolved.hl = vim.tbl_extend("force", resolved.hl, layer.hl or {})
  end
  return resolved
end

function M.bind(keyset, keys, callback)
  for _, key in ipairs(type(keys) == "string" and { keys } or keys or {}) do
    keyset("i", key, callback)
  end
end

-- Keep picker-specific rendering defaults unless explicitly overridden.
function M.select(opts, session)
  session.keymaps = opts.keymaps
  session.highlights =
    vim.tbl_extend("force", {}, session.highlights or {}, opts.highlights)
  for _, key in ipairs({ "dynamic_height", "max_height", "prompt_position" }) do
    if opts[key] ~= nil then
      session[key] = opts[key]
    end
  end
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
    local result = vim.deepcopy(value)
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
  for _, key in ipairs({ "format_fn", "group_fn", "header_fn", "footer_fn" }) do
    local render = session[key]
    if render and next(opts.highlights) then
      session[key] = function(...)
        return decorate(render(...))
      end
    end
  end
  return require("minibuffer").select(session)
end

return M
