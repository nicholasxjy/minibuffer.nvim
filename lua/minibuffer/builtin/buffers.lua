local function update_preview_win(win, buf)
  if not vim.api.nvim_win_is_valid(win) then
    return
  end
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  if vim.api.nvim_win_get_buf(win) ~= buf then
    vim.api.nvim_win_set_buf(win, buf)
  end
end

local function get_file_icon(name)
  local ok, icons = pcall(require, "mini.icons")
  if ok and type(icons.get) == "function" then
    local icon, hl = icons.get("file", name)
    if type(icon) == "string" and icon ~= "" then
      return icon, hl or "Normal"
    end
  end

  ok, icons = pcall(require, "nvim-web-devicons")
  if ok and type(icons.get_icon) == "function" then
    local icon, hl = icons.get_icon(name, nil, { default = true })
    if type(icon) == "string" and icon ~= "" then
      return icon, hl or "Normal"
    end
  end

  return "", "Comment"
end

-- Collect listed & loaded buffers (excluding special/unlisted)
local function gather_buffers()
  local bufs = vim.fn.getbufinfo({ buflisted = 1 })
  local current = vim.api.nvim_get_current_buf()
  local alternate = vim.fn.bufnr("#")
  local items = {}
  local max_bufnr = 0
  for _, info in ipairs(bufs) do
    if info.loaded == 1 then
      local path = info.name
      local name = path ~= "" and vim.fn.fnamemodify(path, ":~:.") or "[No Name]"
      local hidden = info.hidden == 1 and "h" or "a"
      local flag = info.bufnr == current and "%"
        or info.bufnr == alternate and "#"
        or " "
      local readonly = vim.bo[info.bufnr].readonly and "=" or " "
      local changed = info.changed == 1 and "+" or " "
      items[#items + 1] = {
        bufnr = info.bufnr,
        path = path,
        name = name,
        flag = flag,
        flags = hidden .. readonly .. changed,
        lastused = info.lastused or 0,
      }
      max_bufnr = math.max(max_bufnr, info.bufnr)
    end
  end

  local number_width = #tostring(max_bufnr) + 3
  for _, item in ipairs(items) do
    item.bufnr_label = "[" .. item.bufnr .. "]"
    item.bufnr_padding = number_width - #item.bufnr_label
    item.icon, item.icon_hl = get_file_icon(item.name)
  end

  table.sort(items, function(a, b)
    return a.lastused > b.lastused
  end)

  return items
end

local function format_fn(item)
  return {
    { text = item.bufnr_label, hl = "Number" },
    { text = string.rep(" ", item.bufnr_padding) .. " ", hl = "Normal" },
    {
      text = item.flag,
      hl = item.flag == "%" and "Special"
        or item.flag == "#" and "Identifier"
        or "Normal",
    },
    { text = item.flags, hl = "Comment" },
    { text = " ", hl = "Normal" },
    { text = item.icon .. " ", hl = item.icon_hl },
    { text = item.name, hl = "Normal" },
  }
end

local function filter_fn(ctx)
  if ctx.input == "" then
    return ctx.items
  end

  local names = {}
  local lookup = {}
  for _, item in ipairs(ctx.items) do
    local key = item.name .. " " .. item.path
    names[#names + 1] = key
    lookup[key] = item
  end

  local matches = vim.fn.matchfuzzy(names, ctx.input)
  local results = {}

  for _, name in ipairs(matches) do
    results[#results + 1] = lookup[name]
  end

  return results
end

local function get_replacement_buf(current)
  for _, info in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
    if info.bufnr ~= current and info.loaded == 1 then
      return info.bufnr
    end
  end
  return vim.api.nvim_create_buf(false, true)
end

local function bind(keyset, keys, callback)
  for _, key in ipairs(type(keys) == "string" and { keys } or keys or {}) do
    keyset("i", key, callback)
  end
end

---@class minibuffer.builtin.BuffersKeymaps
---@field split? string|string[]
---@field vsplit? string|string[]
---@field delete? string|string[]
---@field next? string|string[]
---@field previous? string|string[]

---@class minibuffer.builtin.BuffersOpts
---@field keymaps? minibuffer.builtin.BuffersKeymaps

---@param opts? minibuffer.builtin.BuffersOpts
return function(opts)
  require("minibuffer.internal.guard").check()

  local select_keymaps = require("minibuffer.config").select.keymaps
  local keymaps = vim.tbl_deep_extend(
    "force",
    {
      split = "<C-s>",
      vsplit = "<C-v>",
      delete = "<C-d>",
      next = select_keymaps.next,
      previous = select_keymaps.previous,
    },
    opts and opts.keymaps or {}
  )
  local active_win
  local buffers = gather_buffers()
  local minibuffer = require("minibuffer")
  local prev_buf = vim.api.nvim_get_current_buf()

  minibuffer.select({
    resumable = true,
    keymaps = { next = keymaps.next, previous = keymaps.previous },
    prompt = "Buffers: ",
    items = buffers,
    multi = true,
    dynamic_height = false,
    max_height = 15,
    fetch_fn = function(_, cb)
      cb(buffers)
    end,
    format_fn = format_fn,
    filter_fn = filter_fn,
    on_change = function(_, item)
      if not active_win then
        return
      end
      if item and vim.api.nvim_buf_is_valid(item.bufnr) then
        update_preview_win(active_win, item.bufnr)
      end
    end,
    on_accept = function(selection)
      if #selection == 1 then
        local item = selection[1].item
        if vim.api.nvim_buf_is_valid(item.bufnr) then
          vim.api.nvim_set_current_buf(item.bufnr)
        end
        return
      end

      local qf = {}
      for _, selected in ipairs(selection) do
        local item = selected.item
        qf[#qf + 1] = {
          filename = item.path ~= "" and item.path or item.name,
          text = "#" .. item.bufnr,
          lnum = 1,
          col = 1,
        }
      end
      vim.fn.setqflist({}, " ", { title = "Selected Buffers", items = qf })
      vim.cmd("copen")
    end,
    on_close = function()
      if active_win then
        update_preview_win(active_win, prev_buf)
      end
    end,
    on_start = function(sess, keyset)
      active_win = minibuffer.get_active_window()
      if not active_win then
        return
      end

      bind(keyset, keymaps.split, function()
        local selected = sess:get_selected()
        if selected then
          sess:close(function()
            vim.cmd("split")
            vim.api.nvim_set_current_buf(selected.bufnr)
          end)
        end
      end)
      bind(keyset, keymaps.vsplit, function()
        local selected = sess:get_selected()
        if selected then
          sess:close(function()
            vim.cmd("vsplit")
            vim.api.nvim_set_current_buf(selected.bufnr)
          end)
        end
      end)
      bind(keyset, keymaps.delete, function()
        local selected = sess:get_selected()
        if selected and vim.api.nvim_buf_is_valid(selected.bufnr) then
          update_preview_win(active_win, get_replacement_buf(selected.bufnr))
          vim.api.nvim_buf_delete(selected.bufnr, {})

          -- Remove buffer from list
          local new_buffer_list = {}
          for _, item in ipairs(buffers) do
            if item.bufnr ~= selected.bufnr then
              new_buffer_list[#new_buffer_list + 1] = item
            end
          end
          buffers = new_buffer_list

          sess:refresh_results()
        end
      end)
    end,
    footer_fn = function(ctx)
      local label = require("minibuffer.internal.util").keymap_label
      return {
        { #ctx.items .. " items", "Normal" },
        {
          " C-x toggle, C-a toggle-all, "
            .. label(keymaps.split)
            .. " split, "
            .. label(keymaps.vsplit)
            .. " vsplit, "
            .. label(keymaps.delete)
            .. " delete, C-y accept, "
            .. label(keymaps.next)
            .. " next, "
            .. label(keymaps.previous)
            .. " prev",
          "Comment",
        },
      }
    end,
  })
end
