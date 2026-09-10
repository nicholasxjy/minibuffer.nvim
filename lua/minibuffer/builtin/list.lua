local config = require("minibuffer.builtin.config")
local function gather_items(kind)
  local list = kind == "loclist" and vim.fn.getloclist(0) or vim.fn.getqflist()
  local items = {}
  for _, entry in ipairs(list) do
    if entry.valid == 1 then
      local file = entry.bufnr > 0 and vim.api.nvim_buf_get_name(entry.bufnr)
        or entry.filename
        or ""
      items[#items + 1] = {
        bufnr = entry.bufnr,
        file = file,
        lnum = entry.lnum,
        col = entry.col,
        text = entry.text or "",
        search_text = table.concat({ file, tostring(entry.lnum), entry.text or "" }, " "),
      }
    end
  end
  return items
end

local function format_fn(item)
  return {
    {
      text = vim.fn.fnamemodify(item.file, ":."),
      hl = "Comment",
    },
    {
      text = ":" .. item.lnum,
      hl = "Number",
    },
    {
      text = ":" .. item.col,
      hl = "Number",
    },
    {
      text = "  " .. item.text,
      hl = "Normal",
    },
  }
end

local filter_fn = require("minibuffer.builtin.match").fuzzy("search_text")

---@class minibuffer.builtin.ListOpts: minibuffer.builtin.Opts
---@field type? "quickfix"|"loclist"

---@param opts? minibuffer.builtin.ListOpts
return function(opts)
  require("minibuffer.internal.guard").check()

  opts = config.resolve(opts, { type = "quickfix" })
  assert(
    opts.type == "quickfix" or opts.type == "loclist",
    "type must be quickfix or loclist"
  )
  local items = gather_items(opts.type)

  config.select(opts, {
    resumable = true,
    prompt = opts.type == "loclist" and "Location List: " or "Quickfix List: ",
    multi = false,
    dynamic_height = false,
    max_height = 15,
    fetch_fn = function(_, cb)
      cb(items)
    end,
    format_fn = format_fn,
    filter_fn = filter_fn,
    on_accept = function(selection)
      local item = selection[1] and selection[1].item
      if not item then
        return
      end
      vim.cmd("edit " .. vim.fn.fnameescape(item.file))
      vim.api.nvim_win_set_cursor(0, {
        item.lnum,
        math.max(item.col - 1, 0),
      })
      vim.cmd("normal! zvzz")
    end,
  })
end
