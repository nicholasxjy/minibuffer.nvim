local M = {}

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
    select = {
      config.select,
      "table",
    },
  })

  if not ok then
    return false, err
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

  ok, err = validate_path("vim.g.minibuffer.select", {
    dynamic_height = {
      config.select.dynamic_height,
      "boolean",
    },
    max_height = {
      config.select.max_height,
      "number",
    },
    keymaps = {
      config.select.keymaps,
      "table",
    },
  })

  if not ok then
    return false, err
  end

  if config.select.max_height < 1 then
    return false, "vim.g.minibuffer.select.max_height: expected positive integer"
  end

  if config.select.max_height % 1 ~= 0 then
    return false, "vim.g.minibuffer.select.max_height: expected integer"
  end

  return true, nil
end

return M
