# Minibuffer

![Lua](https://img.shields.io/badge/Made%20with%20Lua-blueviolet.svg?style=for-the-badge&logo=lua)

An **experimental** general purpose interactive interface for neovim.

https://github.com/user-attachments/assets/5d6dea18-9f13-460e-954c-413ff4f4d302

**NOTE**:

- This plugin is still under development and will see some breaking changes (feel free to pin to a commit)
- It depends on an experimental feature in neovim (`vim._core.ui2`)

This plugin provides an API for an optional unified interactive buffer interface.
Instead of having one plugin open a floating pop-up for fuzzy file search, another showing a completion menu at the bottom, another drawing commandline completions above the status bar and yet another drawing a general purpose picker in a different location, you can choose to have one place where interactive input can be shown that feels native to the editor and is predictable.
This includes:

- Running commands with completion.
- Fuzzy finding files or buffers.
- Searching text across a project.
- Input prompts for LSP or Git actions.
- Even interactive plugin UIs (think Telescope, fzf, mini.pick, etc).
- Display timely content (think which-key.nvim or mini.clue)

For Neovim, something like this could replace the ad-hoc popup/floating windows many plugins use, giving us a consistent workflow: a single expandable buffer for all kinds of input and interactive tasks.

# Goal

The goal of this plugin is to eventually put some simple version of this into neovim core if desired by the maintainers. See [this issue](https://github.com/neovim/neovim/issues/35456)

I have integration implementations in `lua/minibuffer/integrations` with existing plugins.

# Prerequisites

- `neovim >= 0.12`
- ui2 enable somewhere early in your init.lua:

```lua
require("vim._core.ui2").enable({ enable = true, msg = { targets = "msg" } })
```

# Installation

**NOTE:** You will want to load minibuffer.nvim as one of your earliest plugins (DO NOT LAZY LOAD).

- vim.pack

```lua
vim.pack.add({
  {
    src = "https://github.com/simifalaye/minibuffer.nvim",
  },
})

local minibuffer = require("minibuffer")

vim.ui.select = require("minibuffer.builtin.ui_select")
vim.ui.input = require("minibuffer.builtin.ui_input")

vim.keymap.set("n", "<leader><CR>", function()
  minibuffer.resume(true)
end)
```

- [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "simifalaye/minibuffer.nvim",
  init = function()
    local minibuffer = require("minibuffer")

    vim.ui.select = require("minibuffer.builtin.ui_select")
    vim.ui.input = require("minibuffer.builtin.ui_input")

    vim.keymap.set("n", "<leader><CR>", function()
      minibuffer.resume(true)
    end)
  end,
}
```

# Configuration

This plugin can be configured by using `vim.g.minibuffer` (preferably set before the plugin loads).

```lua
-- Default configuration
vim.g.minibuffer = {
  dynamic_window_resize = true, -- Shrink other windows when the minibuffer is expanded
  select = {
    keymaps = {
      next = { "<C-n>", "<Down>", "<Tab>" },
      previous = { "<C-p>", "<Up>", "<S-Tab>" },
    },
  },
  cmd = {
    -- NOTE: minibuffer cmd is not compatible with command line plugins that force `wildtrigger()` each `wildchar` such as mini.cmdline
    enabled = true, -- Enable command line wildmenu replacement through the minibuffer
    autotrigger = true, -- Display completion suggestions as you type
    dynamic_height = false, -- Whether the completion window should shrink as items disappear.
    max_height = 15, -- Maximum height when using the command line
  },
}
```

# Builtin

## Custom Pickers

```lua
vim.keymap.set("n", "<leader>;", function()
  require("minibuffer.builtin.history")({ type = "cmd" })
end, { desc = "Find command history" })
vim.keymap.set("n", "<leader>?", function()
  require("minibuffer.builtin.history")({ type = "search" })
end, { desc = "Find command history" })
vim.keymap.set("n", "<leader>'", function()
  require("minibuffer.builtin.marks")()
end, { desc = "Find mark" })
vim.keymap.set(
  "n",
  "<leader>/",
  require("minibuffer.builtin.live-grep"),
  { desc = "Live grep" }
)

vim.keymap.set(
  "n",
  "<leader>fb",
  require("minibuffer.builtin.buffers"),
  { desc = "Find buffers" }
)

vim.keymap.set(
  "n",
  "<leader>ff",
  require("minibuffer.builtin.files"),
  { desc = "Find files" }
)
vim.keymap.set("n", "<leader>fd", function()
  require("minibuffer.builtin.diagnostics")({ scope = "buffer" })
end, { desc = "Find diagnostics" })
vim.keymap.set("n", "<leader>fD", function()
  require("minibuffer.builtin.diagnostics")({ scope = "workspace" })
end, { desc = "Find diagnostics (workspace)" })
vim.keymap.set(
  "n",
  "<leader>fg",
  require("minibuffer.builtin.git-files"),
  { desc = "Find gitfiles" }
)
vim.keymap.set("n", "<leader>fl", function()
  require("minibuffer.builtin.list")({ type = "loclist" })
end, { desc = "Find in loclist" })
vim.keymap.set(
  "n",
  "<leader>fm",
  require("minibuffer.builtin.manpages"),
  { desc = "Find manpages" }
)
vim.keymap.set("n", "<leader>fo", function()
  require("minibuffer.builtin.oldfiles")({ cwd = vim.fn.getcwd() })
end, { desc = "Find oldfiles (cwd)" })
vim.keymap.set(
  "n",
  "<leader>fO",
  require("minibuffer.builtin.oldfiles"),
  { desc = "Find oldfiles (all)" }
)
vim.keymap.set("n", "<leader>fq", function()
  require("minibuffer.builtin.list")({ type = "quickfix" })
end, { desc = "Find in quickfix" })
```

The buffers picker uses fzf-lua's buffer layout: `[number]` followed by the
current/alternate, loaded, read-only, and modified flags, an optional file icon,
and the path. Split, vertical split, delete, next, and previous actions accept
one key or a list of keys:

```lua
require("minibuffer.builtin.buffers")({
  keymaps = {
    split = { "<C-s>", "<C-w>s" },
    vsplit = { "<C-v>", "<C-w>v" },
    delete = { "<C-d>", "<C-w>d" },
    next = { "<C-n>", "<Down>" },
    previous = { "<C-p>", "<Up>" },
  },
})
```

Use `{}` to disable an action's mappings. When `next` or `previous` is omitted,
the picker uses the global `select.keymaps` values.

## Interesting things you can do when using the minibuffer command line

**Doom-emacs M-x file explorer picker**

```lua
vim.keymap.set("n", "<leader>.", function()
  local buf_path = vim.api.nvim_buf_get_name(0)
  local dir = vim.fn.fnamemodify(buf_path, ":p:h")
  if dir == "" then
    dir = "."
  end
  local cmd = ":e " .. vim.fn.fnameescape(dir) .. "/"
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(cmd, true, false, true), "n", true)
end, { desc = "Find file" })
```

**Pick help-tags**

```lua
vim.keymap.set("n", "<leader>hh", ":h ", { desc = "Help" })
```

# Integrations with existing plugins

Two integration types can be seen below:

- Using the backend of a plugin with the minibuffer frontend APIs (as seen in the fff.nvim example below)
- Allowing each plugin to draw their own window but configuring the window settings to put it into the minibuffer container (as seen in the which-key.nvim, mini.pick and fzf integration examples below)

When possible, the first option is preferred.
Some plugins don't expose their data fetching code through their public APIs and in such cases the second option can be used.

In the case of the second option, I have provided some wrappers for the `setup` functions for each plugin which ensures we have the necessary options set for minibuffer to integrate with the plugin.
Feel free to take a look at what options are used in the `lua/minibuffer/integrations` files.

**NOTE**: When using `lazy.nvim`, use `config` instead of `opts` to setup your options

## FFF.nvim

<img width="2560" height="1440" alt="fff nvim-integration" src="https://github.com/user-attachments/assets/2595ab60-e77c-4695-b26d-61b01b09d456" />

```lua
-- NOTE: after loading plugin
local fff_mb = require("minibuffer.integrations.fff")

vim.keymap.set("n", "<leader><leader>", function()
  fff_mb.file_search("", { mode = "files" })
end, { desc = "FFFind" })

vim.keymap.set("n", "<leader>/", function()
  fff_mb.content_search("", { mode = "regex", smart_case = true })
end, { desc = "FFFGrep" })
```

Both functions accept `(query, opts)` using [fff's search API options](https://github.com/dmtrKovalenko/fff/blob/main/lua/fff/main.lua).
The query prefills the minibuffer; existing opts-only calls still work.

The list uses fff's native row renderers: Git signs in the left sign column,
file icons from fff's icon provider, filename/directory layout, shortened paths,
and grep results grouped under file headers. Selection skips the headers.
In filename-first layout, directory names share a left-aligned column after a
` │ ` separator. Alignment includes icon widths and Unicode display widths,
and also applies to grep file headers. The separator uses `hl.separator`
(or `hl.directory_path` when unset). Explicit `layout.show_path_first = true`
keeps the native path-first layout.
This requires a recent fff version with `fff.picker_ui.file_name_renderer`.

Configuration inherits `require("fff.conf").get()`. Per-call options override
the corresponding global settings without changing them:

```lua
fff_mb.file_search("", {
  layout = {
    show_path_first = false,
    path_shorten_strategy = "middle",
    prompt_position = "bottom",
  },
  git = { status_text_color = true },
  hl = { directory_path = "Comment", cursor = "Visual" },
  file_picker = { fuzzy_query_highlighting = true },
  debug = { show_scores = false },
  keymaps = {
    move_down = { "<C-n>", "<C-j>" },
    move_up = { "<C-p>", "<C-k>" },
  },
  -- Integration-specific overrides:
  highlights = { git_sign_modified = { fg = "#e5c07b" } },
  git_status_signs = { modified = "M", untracked = "?" },
})
```

Supported list settings include `layout.show_path_first`,
`layout.path_shorten_strategy`, `layout.prompt_position` (result order),
`git.status_text_color`, `hl` (including list/prompt `winhl`),
`file_picker.current_file_label`, `file_picker.fuzzy_query_highlighting`,
`debug.show_scores`, `prompt`, and `wrap_around`.
Minibuffer owns the window geometry and keeps its bottom input and 15-row maximum;
fff preview, scrollbar, and separate debug-panel settings do not apply.

The integration inherits fff's navigation, close, select, split/vsplit/tab,
multi-select, quickfix, and grep-mode cycling keys, plus `mappings`.
The earlier `keymaps.next` / `keymaps.previous` options remain aliases that
take precedence over `move_down` / `move_up`. Each accepts a string, a list,
or `{}` to disable the action. fff navigation defaults take precedence over
`vim.g.minibuffer.select.keymaps` for this integration.
`select.select_window` is used when opening results.

Grep inherits `grep.modes`, `grep.location_format`, and its search defaults.
Per-call `grep` overrides the global block; explicit top-level search options
(such as `smart_case = false`) take precedence over both.
Display settings are not passed to the search backend.

`highlights` overrides `hl` and accepts group names or `nvim_set_hl`
attribute tables. Git text/sign groups use `git_<status>` and
`git_sign_<status>`; all staged statuses use `staged`, and `unknown`
uses `untracked`. Cursor-row signs use the corresponding
`git_sign_<status>_selected` group. `git_status_signs` is keyed by raw
status (`modified`, `staged_new`, etc.); signs must fit in two display cells.
An empty string hides a sign. `show_git_status = false` hides Git signs and
filename colors. Unspecified signs use fff's defaults.

## Which-key.nvim

<img width="2560" height="1440" alt="which-key nvim-integration" src="https://github.com/user-attachments/assets/993b040f-dcd9-4fb3-b861-1ad1f8fc2824" />

```lua
local opts = {}
local ok, mb_wk = pcall(require, "minibuffer.integrations.which-key")
if ok then
  mb_wk(opts)
else
  require("which-key").setup(opts)
end
```

## mini-pick.nvim

<img width="2560" height="1440" alt="mini pick-integration" src="https://github.com/user-attachments/assets/0fe78407-f95f-4223-85e7-bad07484a781" />

```lua
local opts = {}
local ok, mb_pick = pcall(require, "minibuffer.integrations.mini-pick")
if ok then
  mb_pick(opts)
else
  require("mini.pick").setup(opts)
end
```

## fzf

Minibuffer provides a single integration for
[fzf-lua](https://github.com/ibhagwan/fzf-lua). It keeps fzf-lua's window,
preview, formatting and actions, while ranking file candidates with the same
strategy as `Snacks.picker.smart`.

This integration requires `fzf-lua` and `fzf`. The `global` wrapper requires
`fzf >= 0.59`. `snacks.nvim` is not required.

`minibuffer.integrations.fzf_lua` remains as a compatibility alias.

Configure fzf-lua through the integration so its window uses the minibuffer:

```lua
local fzf_mb = require("minibuffer.integrations.fzf")

fzf_mb({
  fzf_opts = {
    ["--no-separator"] = true,
  },
  winopts = function()
    return {
      height = 0.35,
      width = 1,
      row = 0.35,
      col = 0.50,
      border = "none",
      backdrop = 100,
      relative = "minibuffer",
      use_minibuffer = true,
      winhl = true,
    }
  end,
  hls = {
    normal = "Normal",
  },
})
```

Grep results share a filename-first header for each file, with matching line
numbers and content beneath it, similar to fff. Every match remains individually
selectable for preview, opening, and quickfix. Results keep the search command's
file order; custom commands should emit each file's matches together.
This requires `fzf >= 0.53`.
Call `fzf_mb.live_grep()` directly, or use `require("fzf-lua").live_grep()`
after the setup above. Set `grep = { multiline = false, formatter = false }`
in setup to restore the native single-line layout.

The `files` and `global` wrappers enable fzf-lua's builtin previewer hidden by
default, with a vertical preview above the results (`up:40%`) at the top of the
editor by default (an explicit `winopts.row` still wins). Press fzf-lua's
default `toggle-preview` key (`<F4>` in the builtin window or `f4` in fzf) to
open and close it. Existing `keymap.builtin` and
`keymap.fzf` settings are preserved; add the following to your fzf-lua setup to
use another key if needed:

```lua
keymap = {
  builtin = { ["<C-p>"] = "toggle-preview" },
  fzf = { ["ctrl-p"] = "toggle-preview" },
},
```

Then call the minibuffer integration instead of the corresponding fzf-lua
picker:

```lua
local fzf_mb = require("minibuffer.integrations.fzf")

vim.keymap.set("n", "<leader><leader>", function()
  fzf_mb.files()
end, { desc = "Smart files" })

vim.keymap.set("n", "<leader>fg", function()
  fzf_mb.global()
end, { desc = "Smart global" })
```

The default smart options match `Snacks.picker.smart`: filename, cwd and
frecency bonuses are enabled, while history weighting is disabled. They can be
overridden per call alongside normal fzf-lua options:

```lua
fzf_mb.files({
  cwd = vim.uv.cwd(),
  smart = {
    filename_bonus = true,
    cwd_bonus = true,
    frecency = true,
    history_bonus = false,
    query_delay = 30,
  },
})
```

`fzf_mb.global()` preserves fzf-lua's global picker behavior. Its default files
branch is smart-ranked; `$`, `@` and `#` still switch to buffers, document
symbols and workspace symbols. Custom `global.pickers` descriptors are retained,
with only the first unprefixed/default provider replaced.

fzf remains responsible for filtering and match highlighting after candidates
are ranked. Custom formatters, path shortening, `--nth`, or raw `--sort` flags
can therefore further filter the ranked results or override their order.

The most recently closed smart picker retains its candidate cache for up to five
minutes so `FzfLua resume` can restart it; a new smart picker replaces that cache.
On Windows, `query_delay` does not add the POSIX `sleep` command and rapid queries
instead rely on fzf cancelling superseded reload processes.

Frecency is stored independently under Neovim's data directory. It uses a
30-day half-life and records visits to listed file buffers. The cwd bonus follows
Snacks exactly, so it is a constant when every candidate belongs to the picker
cwd; it becomes relevant when search paths include files outside that directory.

The ranking module can also be used without fzf-lua:

```lua
local ranker = require("minibuffer.fuzzy").new({ cwd = "/project" })
local ranked = ranker:rank("init", {
  { text = "lua/minibuffer/init.lua", path = "/project/lua/minibuffer/init.lua" },
  { text = "plugin/minibuffer.lua", path = "/project/plugin/minibuffer.lua" },
})
```

Candidate paths should be normalized and absolute. Returned candidates contain
their computed `score` and are ordered by score, text length and original index.

# Statusline Integration

You may notice that when the minibuffer is open in an interactive session (such as select or input), the 'inactive' statusline is shown.
This is because you are focussed on the minibuffer window (which doesn't draw another statusline) and so you need to tell your statusline code which window to draw the active statusline for.
Here's a simple function you can use to determine whether to draw the active or inactive statusline for a given window:

```lua
local function win_is_active()
  local ok, mb = pcall(require, "minibuffer")
  local winid = vim.api.nvim_get_current_win()
  local curwin = (ok and mb.get_active_window()) or tonumber(vim.g.actual_curwin)
  return winid == curwin
end
```

You can use the function like this in your custom statusline:

```lua
local function statusline()
  if win_is_active() then
    -- Display your active statusline
    return "%f %m %= %l:%c"
  else
    -- Display your inactive statusline
    return "%f %m"
  end
end

_G.my_statusline = statusline

vim.go.statusline = "%!v:lua.my_statusline()"
```

# Developer Notes

Find all information and API using: `:h minibuffer`
For examples on how the API can be used, see `lua/minibuffer/builtin/*`
