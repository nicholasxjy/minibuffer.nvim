local config = require("minibuffer.builtin.config")
---@class minibuffer.builtin.Mark
---@field mark string
---@field file string
---@field lnum integer
---@field col integer
---@field text string

local function gather_marks()
  local seen = {}
  local items = {}

  local function add_marks(list)
    for _, mark in ipairs(list) do
      if mark.pos[2] > 0 and not seen[mark.mark] then
        seen[mark.mark] = true

        local file = mark.file ~= "" and mark.file
          or vim.api.nvim_buf_get_name(mark.pos[1])
        local line = vim.fn.getbufline(file, mark.pos[2])[1] or ""
        items[#items + 1] = {
          mark = mark.mark:sub(2), -- a, A, 0, ...
          file = file,
          lnum = mark.pos[2],
          col = mark.pos[3],
          text = vim.trim(line),
          search_text = table.concat({ mark.mark:sub(2), file, vim.trim(line) }, " "),
        }
      end
    end
  end

  add_marks(vim.fn.getmarklist())
  add_marks(vim.fn.getmarklist(vim.api.nvim_get_current_buf()))

  return items
end

local function format_fn(item)
  return {
    { text = item.mark, hl = "Identifier" },
    { text = "  " .. vim.fn.fnamemodify(item.file, ":."), hl = "Comment" },
    { text = ":" .. item.lnum, hl = "Number" },
    { text = "  " .. item.text, hl = "Normal" },
  }
end

local filter_fn = require("minibuffer.builtin.match").fuzzy("search_text")

return function(opts)
  require("minibuffer.internal.guard").check()
  opts = config.resolve(opts)

  local marks = gather_marks()
  config.select(opts, {
    resumable = true,
    prompt = "Marks: ",
    multi = false,
    dynamic_height = false,
    max_height = 15,
    fetch_fn = function(_, cb)
      cb(marks)
    end,
    format_fn = format_fn,
    filter_fn = filter_fn,
    on_accept = function(selection)
      local item = selection[1] and selection[1].item
      if not item then
        return
      end
      vim.cmd("edit " .. vim.fn.fnameescape(item.file))
      vim.api.nvim_win_set_cursor(0, { item.lnum, item.col - 1 })
      vim.cmd("normal! zvzz")
    end,
  })
end
