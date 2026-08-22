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

---@param name string
---@return string icon
---@return string hl
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
  local current_buf = vim.api.nvim_get_current_buf()
  local alternate_buf = vim.fn.bufnr("#")
  local items = {}
  local max_bufnr_width = 0
  local max_name_width = 0
  for _, info in ipairs(bufs) do
    if info.loaded == 1 then
      local path = info.name
      local name = path ~= "" and vim.fn.fnamemodify(path, ":t") or "[No Name]"
      local relative_path = path ~= "" and vim.fn.fnamemodify(path, ":.") or ""
      local directory = relative_path ~= ""
        and vim.fn.fnamemodify(relative_path, ":h")
        or ""
      if directory == "." then
        directory = ""
      end

      local status = " h"
      local status_hl = "Comment"
      if info.bufnr == current_buf then
        status = "%a"
        status_hl = "Special"
      elseif info.bufnr == alternate_buf then
        status = "#h"
        status_hl = "Identifier"
      elseif info.windows and #info.windows > 0 then
        status = " a"
      end

      local icon, icon_hl = get_file_icon(name)
      local name_width = vim.fn.strdisplaywidth(name)
      items[#items + 1] = {
        bufnr = info.bufnr,
        path = path,
        name = name,
        directory = directory,
        line = math.max(info.lnum or 1, 1),
        lastused = info.lastused or 0,
        changed = info.changed,
        status = status,
        status_hl = status_hl,
        icon = icon,
        icon_hl = icon_hl,
      }
      max_bufnr_width = math.max(max_bufnr_width, #tostring(info.bufnr))
      max_name_width = math.max(max_name_width, name_width)
    end
  end

  for _, item in ipairs(items) do
    local bufnr_label = "[" .. tostring(item.bufnr) .. "]"
    item.bufnr_label = bufnr_label
    item.bufnr_padding = max_bufnr_width + 6 - vim.fn.strdisplaywidth(bufnr_label)
    item.name_padding = max_name_width - vim.fn.strdisplaywidth(item.name)
  end

  table.sort(items, function(a, b)
    return a.lastused > b.lastused
  end)

  return items
end

local function format_fn(item)
  return {
    { text = item.bufnr_label, hl = "Comment" },
    { text = string.rep(" ", item.bufnr_padding), hl = "Normal" },
    { text = item.status, hl = item.status_hl },
    {
      text = item.changed == 1 and "+" or " ",
      hl = item.changed == 1 and "Changed" or "Comment",
    },
    { text = "    ", hl = "Normal" },
    { text = item.icon .. " ", hl = item.icon_hl },
    { text = item.name, hl = "Normal" },
    { text = string.rep(" ", item.name_padding), hl = "Normal" },
    { text = " " .. item.directory .. ":" .. item.line, hl = "Comment" },
  }
end

local function filter_fn(ctx)
  if ctx.input == "" then
    return ctx.items
  end

  local names = {}
  local lookup = {}
  for _, item in ipairs(ctx.items) do
    names[#names + 1] = item.name
    lookup[item.name] = item
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

return function()
  require("minibuffer.internal.guard").check()

  local active_win
  local buffers = gather_buffers()
  local minibuffer = require("minibuffer")
  local prev_buf = vim.api.nvim_get_current_buf()

  minibuffer.select({
    resumable = true,
    prompt = "Buffers: ",
    items = buffers,
    multi = true,
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

      keyset("i", "<C-s>", function()
        local selected = sess:get_selected()
        if selected then
          if selected then
            sess:close(function()
              vim.cmd("split")
              vim.api.nvim_set_current_buf(selected.bufnr)
            end)
          end
        end
      end)
      keyset("i", "<C-v>", function()
        local selected = sess:get_selected()
        if selected then
          if selected then
            sess:close(function()
              vim.cmd("vsplit")
              vim.api.nvim_set_current_buf(selected.bufnr)
            end)
          end
        end
      end)
      keyset("i", "<C-d>", function()
        local selected = sess:get_selected()
        if selected then
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
        end
      end)
    end,
    footer_fn = function(ctx)
      return {
        { #ctx.items .. " items", "Normal" },
        {
          " C-x toggle, C-a toggle-all, C-s split, C-v vsplit, C-d delete, C-y accept, C-n next, C-p prev",
          "Comment",
        },
      }
    end,
  })
end
