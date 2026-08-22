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

---@alias minibuffer.config.Keymap string|string[]

---@class minibuffer.config.select.keymaps
---@field cancel minibuffer.config.Keymap|nil
---@field accept minibuffer.config.Keymap|nil
---@field previous minibuffer.config.Keymap|nil
---@field next minibuffer.config.Keymap|nil
---@field delete_word minibuffer.config.Keymap|nil
---@field toggle minibuffer.config.Keymap|nil
---@field toggle_all minibuffer.config.Keymap|nil

---@class minibuffer.config.select
---Opts for select sessions
---@field dynamic_height? boolean
---@field max_height? integer
---@field keymaps? minibuffer.config.select.keymaps

---@class minibuffer.Opts
---Shrink other windows when the minibuffer is expanded
---@field dynamic_window_resize? boolean
---Opts for cmdline
---@field cmd? minibuffer.cmd.Opts
---@field select? minibuffer.config.select

---@type minibuffer.Opts|fun():minibuffer.Opts|nil
vim.g.minibuffer = vim.g.minibuffer

local config = require("minibuffer.config.internal")

return config
