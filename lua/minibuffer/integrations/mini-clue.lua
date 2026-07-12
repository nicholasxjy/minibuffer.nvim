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
  local lines = {}

  for _, clue in ipairs(content) do
    lines[#lines + 1] = {
      {
        text = " " .. clue.next_key,
        hl = clue.has_postkeys and "MiniClueNextKeyWithPostkeys"
          or "MiniClueNextKey",
      },
      { text = " │ ", hl = "MiniClueSeparator" },
      {
        text = clue.desc,
        hl = clue.is_group and "MiniClueDescGroup" or "MiniClueDescSingle",
      },
    }
  end

  return lines
end

function M.show(same_content)
  if #helpers.state.query == 0 then
    return M.hide()
  end

  if display and not display.closed and same_content then
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
