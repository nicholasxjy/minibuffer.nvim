local M = {}

local file_groups = {
  selection = "cursor",
  directory_path = "directory_path",
  matched = "matched",
  normal = "normal",
  prompt = "prompt",
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
      defaults and defaults.keymaps or {},
      config.builtin.keymaps,
      opts and opts.keymaps or {}
    )
  )
  for _, layer in ipairs({ config.builtin, opts or {} }) do
    for key, value in pairs(layer.highlights or {}) do
      local name = file_groups[key]
      if name then
        resolved.hl[name] = value
      end
    end
    resolved.hl = vim.tbl_extend("force", resolved.hl, layer.hl or {})
  end
  return resolved
end

-- Compatibility for callers using the former shared binding helper.
M.bind = require("minibuffer.builtin.actions").bind

-- Keep picker-specific rendering defaults unless explicitly overridden.
function M.select(opts, session)
  session.keymaps = opts.keymaps
  session.highlights =
    vim.tbl_extend("force", {}, session.highlights or {}, opts.highlights)
  for _, key in ipairs({ "dynamic_height", "max_height", "prompt_position", "prompt" }) do
    if opts[key] ~= nil then
      session[key] = opts[key]
    end
  end
  require("minibuffer.builtin.render").configure(opts, session)
  return require("minibuffer").select(session)
end

return M
