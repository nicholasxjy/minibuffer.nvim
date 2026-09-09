---@class minibuffer.cmd.Config
---@field enabled boolean
---@field autotrigger boolean
---@field dynamic_height boolean
---@field max_height integer

---@class minibuffer.Config
---@field ui { min_height: integer, max_height?: integer }
---@field dynamic_window_resize boolean
---@field cmd minibuffer.cmd.Config
---@field select { keymaps: minibuffer.config.select.keymaps }
---@field builtin minibuffer.builtin.Opts

---@type minibuffer.Config
local default_config = {
  ui = { min_height = 1 },
  dynamic_window_resize = true,
  builtin = {
    filename_first = true,
    filter = {},
    highlights = {},
    hl = {},
    keymaps = {
      split = "<C-s>",
      vsplit = "<C-v>",
      delete = "<C-d>",
      accept = { "<CR>", "<C-y>" },
      close = { "<Esc>", "<C-c>" },
      toggle = "<C-x>",
      toggle_all = "<C-a>",
    },
  },
  select = {
    keymaps = {
      next = { "<C-n>", "<Down>", "<Tab>" },
      previous = { "<C-p>", "<Up>", "<S-Tab>" },
    },
  },
  cmd = {
    enabled = true,
    autotrigger = true,
    dynamic_height = false,
    max_height = 15,
  },
}

local user_config = type(vim.g.minibuffer) == "function" and vim.g.minibuffer()
  or vim.g.minibuffer
  or {}

---@type minibuffer.Config
local config = vim.tbl_deep_extend("force", default_config, user_config)

-- These are option maps, even when empty; only individual key lists replace.
if type(config.builtin) == "table" then
  config.builtin = vim.tbl_extend("force", {}, default_config.builtin, config.builtin)
  for _, key in ipairs({ "keymaps", "filter", "highlights", "hl" }) do
    if type(config.builtin[key]) == "table" then
      config.builtin[key] =
        vim.tbl_extend("force", {}, default_config.builtin[key], config.builtin[key])
    end
  end
end

local valid, err = require("minibuffer.config.validate").validate(config)
if not valid then
  error(err)
end

return config
