---@mod minibuffer.config Configuration
---
---@brief [[
---
---To configure minibuffer, set the variable `vim.g.minibuffer`,
---which is a |minibuffer.Opts| table, in your Neovim configuration.
---
---Example:
---
--->lua
------@type minibuffer.Opts
---vim.g.minibuffer = {
---   ---@type minibuffer.cmd.Opts
---   cmd = {
---     -- ...
---   },
--- }
---<
---
---Notes:
---
--- - `vim.g.minibuffer` can also be a function that returns a |minibuffer.Opts| table.
---
---@brief ]]

---@class minibuffer.cmd.Opts
---Enable command line wildmenu replacement through the minibuffer
---@field enabled? boolean
---Display completion suggestions as you type
---@field autotrigger? boolean
---Whether the completion window should shrink as items disappear.
---@field dynamic_height? boolean
---Maximum height when using the command line
---@field max_height? integer

---@class minibuffer.config.select.keymaps
---@field next? string|string[]
---@field previous? string|string[]
---@field accept? string|string[]
---@field close? string|string[]
---@field toggle? string|string[]
---@field toggle_all? string|string[]

---@class minibuffer.builtin.Opts
---@field prompt? string Input prefix; empty string hides it. Defaults to the picker prompt.
---@field pointer? string Current-row icon; empty string hides it. Defaults to the picker icon.
---@field filename_first? boolean
---@field filter? { cwd?: boolean } Restrict file-backed candidates to cwd.
---@field keymaps? table<string, string|string[]> Empty lists disable actions.
---@field highlights? table<string, string> Session highlight groups; prompt and pointer style the input prefix and current-row icon.
---@field hl? table<string, string> Files row highlight groups (fff-style names).
---@field dynamic_height? boolean
---@field max_height? integer
---@field prompt_position? "top"|"bottom"

---@class minibuffer.Opts
---Global content height bounds in rows; input, hints and borders are additional.
---@field ui? { min_height?: integer, max_height?: integer }
---Shrink other windows when the minibuffer is expanded
---@field dynamic_window_resize? boolean
---Opts for cmdline
---@field cmd? minibuffer.cmd.Opts
---@field select? { keymaps: minibuffer.config.select.keymaps }
---@field builtin? minibuffer.builtin.Opts Shared defaults for builtin pickers; call options take precedence.

---@type minibuffer.Opts|fun():minibuffer.Opts|nil
vim.g.minibuffer = vim.g.minibuffer

local config = require("minibuffer.config.internal")

return config
