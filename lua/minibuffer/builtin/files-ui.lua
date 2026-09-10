-- Standalone presentation following fff's file renderer and highlight defaults.
-- Reference: https://github.com/dmtrKovalenko/fff (MIT).
local M = {}
local colors = {
  Staged = { "#10B981", 2 },
  Modified = { "#F59E0B", 3 },
  Deleted = { "#EF4444", 1 },
  Renamed = { "#8B5CF6", 5 },
  Untracked = { "#10B981", 2 },
  Ignored = { "#4B5563", 8 },
}
local signs = {
  untracked = "┆",
  modified = "┃",
  deleted = "▁",
  renamed = "┃",
  staged_new = "┃",
  staged_modified = "┃",
  staged_deleted = "▁",
}

local function category(status)
  if status == "unknown" then
    return "Untracked"
  end
  local value = status:match("^staged") and "staged" or status
  return value:sub(1, 1):upper() .. value:sub(2)
end

-- fff's default middle_number layout, measured in display cells for Unicode.
function M.shorten(path, width)
  local function size(text)
    return vim.fn.strdisplaywidth(text)
  end
  local function truncate(text, limit)
    local result = ""
    for _, char in ipairs(vim.fn.split(text, "\\zs")) do
      if size(result .. char) > limit then
        break
      end
      result = result .. char
    end
    return result
  end
  if width <= 0 then
    return ""
  end
  if size(path) <= width then
    return path
  end
  local parts = vim.split(path, "/", { plain = true })
  local left, right = 1, #parts
  local function middle(a, b)
    local hidden = b - a - 1
    local marker = hidden > 3 and ("." .. hidden .. ".") or string.rep(".", hidden)
    return table.concat(parts, "/", 1, a)
      .. "/"
      .. marker
      .. "/"
      .. table.concat(parts, "/", b)
  end
  if #parts > 2 and size(middle(left, right)) <= width then
    while right > left + 2 do
      local changed = false
      if size(middle(left, right - 1)) <= width then
        right, changed = right - 1, true
      end
      if right > left + 2 and size(middle(left + 1, right)) <= width then
        left, changed = left + 1, true
      end
      if not changed then
        break
      end
    end
    return middle(left, right)
  end
  local tail = parts[#parts]
  if #parts > 2 then
    local hidden = #parts - 2
    local marker = hidden > 3 and ("." .. hidden .. ".") or string.rep(".", hidden)
    if size(marker .. "/" .. tail) <= width then
      local room = width - size(marker .. "/" .. tail) - 1
      return (room >= 0 and (truncate(parts[1], room) .. "/") or "")
        .. marker
        .. "/"
        .. tail
    end
  elseif #parts == 2 and size(tail) + 1 < width then
    return truncate(parts[1], width - size(tail) - 1) .. "/" .. tail
  end
  return truncate(tail, width)
end

function M.setup()
  require("minibuffer.builtin.buffers-ui").setup()
  local visual = vim.api.nvim_get_hl(0, { name = "Visual", link = false })
  for name, color in pairs(colors) do
    for _, prefix in ipairs({ "FFFGit", "FFFGitSign" }) do
      vim.api.nvim_set_hl(
        0,
        prefix .. name,
        { fg = color[1], ctermfg = color[2], default = true }
      )
    end
    vim.api.nvim_set_hl(0, "FFFGitSign" .. name .. "Selected", {
      fg = color[1],
      ctermfg = color[2],
      bg = visual.bg,
      ctermbg = visual.ctermbg,
      default = true,
    })
  end
  vim.api.nvim_set_hl(0, "FFFSelected", { link = "Directory", default = true })
  local selected = vim.api.nvim_get_hl(0, { name = "Directory", link = false })
  if not selected.fg then
    selected = vim.api.nvim_get_hl(0, { name = "Number", link = false })
  end
  vim.api.nvim_set_hl(0, "FFFSelectedActive", {
    fg = selected.fg or (vim.o.background == "dark" and "#60A5FA" or "#0369A1"),
    ctermfg = selected.ctermfg or (vim.o.background == "dark" and 12 or 4),
    bg = visual.bg,
    ctermbg = visual.ctermbg,
    default = true,
  })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("MinibufferFilesHighlights", { clear = true }),
    callback = M.setup,
  })
end

-- Resolve optional providers once per picker, including the no-provider case.
-- A later invocation can still discover a provider loaded in the meantime.
function M.icon_provider()
  local ok, icons = pcall(require, "nvim-web-devicons")
  if ok and type(icons.get_icon) == "function" then
    return function(item)
      return icons.get_icon(item.name, nil, { default = true })
    end
  end
  ok, icons = pcall(require, "mini.icons")
  if ok and type(icons.get) == "function" then
    return function(item)
      return icons.get("file", item.path)
    end
  end
  return function() end
end

function M.icon(item)
  return M.icon_provider()(item)
end

function M.prepare(items)
  local width, icon_widths = 0, {}
  for _, item in ipairs(items) do
    local prefix = item.icon and item.icon .. " " or ""
    if not item.name:find("[^ -~]") then
      local icon_width = icon_widths[prefix]
      if not icon_width then
        icon_width = vim.fn.strdisplaywidth(prefix)
        icon_widths[prefix] = icon_width
      end
      item.name_width = icon_width + #item.name
    else
      item.name_width = vim.fn.strdisplaywidth(prefix .. item.name)
    end
    width = math.max(width, item.name_width)
  end
  for _, item in ipairs(items) do
    item.name_padding = width - item.name_width
  end
end

function M.format(item, ctx, opts, current_file)
  local current = item.path == current_file
  local chunks = {}
  if item.icon then
    chunks[#chunks + 1] =
      { text = item.icon .. " ", hl = current and "Comment" or item.icon_hl }
  end
  local name_hl
  if opts.git.status_text_color and not current and colors[category(item.git_status)] then
    name_hl = opts.hl["git_" .. (item.git_status:match("^staged") and "staged" or item.git_status)]
      or "FFFGit" .. category(item.git_status)
  end
  local function append(text, offset, hl, matchable)
    for i, char in ipairs(vim.fn.split(text, "\\zs")) do
      chunks[#chunks + 1] = {
        text = char,
        hl = matchable ~= false
            and item.matches
            and item.matches[offset + i - 1]
            and opts.hl.matched
          or hl,
      }
    end
  end
  local dirname = item.directory ~= "" and item.directory:gsub("/$", "") .. "/" or ""
  local width = math.max(
    0,
    vim.o.columns - 4 - (item.icon and vim.fn.strdisplaywidth(item.icon) + 1 or 0)
  )
  local directory = M.shorten(
    item.directory,
    width
      - vim.fn.strdisplaywidth(item.name)
      - (opts.filename_first ~= false and item.name_padding + 3 or 1)
  )
  if opts.filename_first == false and directory ~= "" then
    append(
      directory:gsub("/$", "") .. "/",
      0,
      opts.hl.directory_path,
      directory == item.directory
    )
  end
  append(item.name, vim.fn.strchars(dirname), name_hl)
  if opts.filename_first ~= false then
    chunks[#chunks + 1] = {
      text = string.rep(" ", item.name_padding + 1) .. "│",
      hl = opts.hl.directory_path,
    }
    if directory ~= "" then
      chunks[#chunks + 1] = { text = " " }
      append(directory, 0, opts.hl.directory_path, directory == item.directory)
    end
  end
  -- fff defaults to a literal match in the rendered row, with optional fuzzy ranges.
  if not opts.fuzzy_query_highlighting and ctx.input ~= "" then
    local line = ""
    for _, chunk in ipairs(chunks) do
      line = line .. chunk.text
    end
    local first, last = line:find(ctx.input, 1, true)
    if first then
      local offset = 0
      for _, chunk in ipairs(chunks) do
        if offset >= first - 1 and offset < last then
          chunk.hl = opts.hl.matched
        end
        offset = offset + #chunk.text
      end
    end
  end
  return chunks
end

function M.decorate(sess, opts, current_file)
  local buf, ns = sess._display.buf, require("minibuffer.internal.state").ns
  local height = vim.api.nvim_win_get_height(sess._display.win) - sess._header_height
  for i = sess._scroll_offset + 1, math.min(#sess._items, sess._scroll_offset + height) do
    local item = sess._items[i]
    local active = i == sess._current_index
    local row = (sess.header_position == "top" and sess._header_height or 0)
      + i
      - sess._scroll_offset
      - 1
    local char = signs[item.git_status]
    local group = opts.hl["git_sign_" .. (item.git_status:match("^staged") and "staged" or item.git_status) .. (active and "_selected" or "")]
      or "FFFGitSign" .. category(item.git_status) .. (active and "Selected" or "")
    if opts.show_git_status == false then
      char = nil
    end
    if active and char then
      local color = vim.api.nvim_get_hl(0, { name = group, link = false })
      local cursor = vim.api.nvim_get_hl(0, { name = opts.hl.cursor, link = false })
      color.bg, color.ctermbg = cursor.bg, cursor.ctermbg
      group = "MinibufferFilesGitCursor" .. category(item.git_status)
      vim.api.nvim_set_hl(0, group, color)
    end
    if vim.tbl_contains(sess._selected_indices, i) then
      char, group = "▊", active and opts.hl.selected_active or opts.hl.selected
    elseif active and not char then
      char, group = " ", opts.hl.cursor
    end
    if char then
      vim.api.nvim_buf_set_extmark(
        buf,
        ns,
        row,
        0,
        { sign_text = char, sign_hl_group = group, priority = 1001 }
      )
    end
    if item.path == current_file and opts.current_file_label ~= "" then
      vim.api.nvim_buf_set_extmark(buf, ns, row, 0, {
        virt_text = {
          { " " .. opts.current_file_label, active and opts.hl.cursor or "Comment" },
        },
        virt_text_pos = "right_align",
      })
    end
  end
end

return M
