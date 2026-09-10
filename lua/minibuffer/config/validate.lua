local M = {}

function M.validate_builtin(opts)
  if type(opts) ~= "table" then
    return false, "builtin: expected table"
  end
  for _, key in ipairs({ "prompt", "pointer" }) do
    if opts[key] ~= nil and (type(opts[key]) ~= "string" or opts[key]:find("[%c]")) then
      return false, "builtin." .. key .. ": expected single-line text without control characters"
    end
  end
  for _, key in ipairs({ "filename_first", "dynamic_height" }) do
    if opts[key] ~= nil and type(opts[key]) ~= "boolean" then
      return false, "builtin." .. key .. ": expected boolean"
    end
  end
  for _, key in ipairs({ "filter", "keymaps", "highlights", "hl" }) do
    if type(opts[key]) ~= "table" then
      return false, "builtin." .. key .. ": expected table"
    end
  end
  if opts.filter.cwd ~= nil and type(opts.filter.cwd) ~= "boolean" then
    return false, "builtin.filter.cwd: expected boolean"
  end
  for action, keys in pairs(opts.keymaps) do
    if type(keys) ~= "string" and (type(keys) ~= "table" or not vim.islist(keys)) then
      return false, "builtin.keymaps." .. action .. ": expected string or list"
    end
    for _, key in ipairs(type(keys) == "string" and { keys } or keys) do
      if type(key) ~= "string" or key == "" then
        return false, "builtin.keymaps." .. action .. ": expected non-empty keys"
      end
    end
  end
  for _, name in ipairs({ "highlights", "hl" }) do
    for key, value in pairs(opts[name]) do
      if type(value) ~= "string" or value == "" then
        return false,
          "builtin." .. name .. "." .. key .. ": expected highlight group name"
      end
    end
  end
  if
    opts.max_height ~= nil
    and (
      type(opts.max_height) ~= "number"
      or opts.max_height < 1
      or opts.max_height % 1 ~= 0
    )
  then
    return false, "builtin.max_height: expected positive integer"
  end
  if
    opts.prompt_position ~= nil
    and opts.prompt_position ~= "top"
    and opts.prompt_position ~= "bottom"
  then
    return false, "builtin.prompt_position: expected top or bottom"
  end
  return true
end

---@param path string
---@param fields table
---@return boolean is_valid
---@return string|nil error_message
local function validate_path(path, fields)
  local ok, err = pcall(vim.validate, fields)
  if ok then
    return true, nil
  end
  return false, ("%s.%s"):format(path, err)
end

---@param config minibuffer.Config
---@return boolean is_valid
---@return string|nil error_message
function M.validate(config)
  local builtin_ok, builtin_err = M.validate_builtin(config.builtin)
  if not builtin_ok then
    return false, "vim.g.minibuffer." .. builtin_err
  end
  -- Validate the merged internal configuration.
  local ok, err = validate_path("vim.g.minibuffer", {
    dynamic_window_resize = {
      config.dynamic_window_resize,
      "boolean",
    },
    cmd = {
      config.cmd,
      "table",
    },
    ui = { config.ui, "table" },
  })

  if not ok then
    return false, err
  end

  for _, key in ipairs({ "min_height", "max_height" }) do
    local value = config.ui[key]
    if value ~= nil and (type(value) ~= "number" or value < 1 or value % 1 ~= 0) then
      return false, "vim.g.minibuffer.ui." .. key .. ": expected positive integer"
    end
  end
  if config.ui.max_height and config.ui.min_height > config.ui.max_height then
    return false, "vim.g.minibuffer.ui.min_height must not exceed max_height"
  end

  ok, err = validate_path("vim.g.minibuffer.cmd", {
    enabled = {
      config.cmd.enabled,
      "boolean",
    },
    autotrigger = {
      config.cmd.autotrigger,
      "boolean",
    },
    dynamic_height = {
      config.cmd.dynamic_height,
      "boolean",
    },
    max_height = {
      config.cmd.max_height,
      "number",
    },
  })

  if not ok then
    return false, err
  end

  -- vim.validate()'s "number" check isn't sufficient for an integer.
  if config.cmd.max_height < 1 then
    return false, "vim.g.minibuffer.cmd.max_height: expected positive integer"
  end

  if config.cmd.max_height % 1 ~= 0 then
    return false, "vim.g.minibuffer.cmd.max_height: expected integer"
  end

  return true, nil
end

return M
