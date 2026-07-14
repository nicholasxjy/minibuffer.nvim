local M = {}

local display = nil
local helpers = nil

local function get_helpers(miniclue)
  -- mini.clue does not expose its window implementation as public API.
  local index = 1
  while true do
    local name, value = debug.getupvalue(miniclue.setup, index)
    if not name then
      break
    end
    if name == "H" then
      return value
    end
    index = index + 1
  end

  error("minibuffer: unsupported mini.clue version (internal helpers not found)")
end

local function clues_to_lines()
  local keys = helpers.query_to_keys(helpers.state.query)
  local content = helpers.clues_to_buffer_content(helpers.state.clues, keys)
  local cell_width = 30
  local spacing = 3
  local num_cols = math.max(
    1,
    math.floor((vim.o.columns + spacing) / (cell_width + spacing))
  )
  local box_height = math.max(math.ceil(#content / num_cols), 1)
  local lines = {}

  local function truncate(text, width)
    if vim.fn.strdisplaywidth(text) <= width then
      return text
    end
    local result = ""
    for index = 0, vim.fn.strchars(text) - 1 do
      local char = vim.fn.strcharpart(text, index, 1)
      if vim.fn.strdisplaywidth(result .. char .. "…") > width then
        break
      end
      result = result .. char
    end
    return width > 0 and result .. "…" or ""
  end

  local max_key_width = 0
  for _, clue in ipairs(content) do
    local key = clue.next_key:gsub("%s+$", "")
    local w = vim.fn.strdisplaywidth(key)
    if w > max_key_width then
      max_key_width = w
    end
  end

  local function build_cell(clue)
    local key = clue.next_key:gsub("%s+$", "")
    local separator = ": "
    local key_width = vim.fn.strdisplaywidth(key)
    local padding = string.rep(" ", max_key_width - key_width)
    local available = cell_width - (max_key_width + 1 + vim.fn.strdisplaywidth(separator))
    local desc = truncate(clue.desc, available)

    local chunks = {
      { text = padding },
      {
        text = key,
        hl = clue.has_postkeys and "MiniClueNextKeyWithPostkeys"
          or "MiniClueNextKey",
      },
      { text = " " },
      { text = separator, hl = "MiniClueSeparator" },
      {
        text = desc,
        hl = clue.is_group and "MiniClueDescGroup" or "MiniClueDescSingle",
      },
    }
    local width = max_key_width + 1 + vim.fn.strdisplaywidth(separator .. desc)
    if width < cell_width then
      chunks[#chunks + 1] = { text = string.rep(" ", cell_width - width) }
    end
    return chunks
  end

  for line = 1, box_height do
    local chunks = {}
    for col = 1, num_cols do
      local clue = content[(col - 1) * box_height + line]
      if col > 1 then
        chunks[#chunks + 1] = { text = string.rep(" ", spacing) }
      end
      if clue then
        vim.list_extend(chunks, build_cell(clue))
      else
        chunks[#chunks + 1] = { text = string.rep(" ", cell_width) }
      end
    end
    lines[#lines + 1] = chunks
  end

  return lines
end

function M.show(same_content)
  if #helpers.state.query == 0 then
    return M.hide()
  end

  if display and not display.closed and same_content == true then
    return
  end

  local lines = clues_to_lines()
  if display and display:update_lines(lines) then
    return
  end

  display = nil
  helpers.state.win_id = nil
  local minibuffer = require("minibuffer")
  local active
  local started = minibuffer.display({
    lines = lines,
    timeout = 0,
    allow_shrink = true,
    on_close = function()
      if display == active then
        display = nil
        helpers.state.win_id = nil
      end
    end,
  })
  if not started then
    return
  end

  active = minibuffer.get_active_session()
  display = active
  helpers.state.win_id = require("minibuffer.util").get_cmd_win()
end

function M.hide()
  helpers.state.win_id = nil
  if display then
    display:close()
    display = nil
  end
end

function M.setup()
  local miniclue = require("mini.clue")
  helpers = helpers or get_helpers(miniclue)
  helpers.window_update = vim.schedule_wrap(M.show)
  helpers.window_close = M.hide
end

return M
