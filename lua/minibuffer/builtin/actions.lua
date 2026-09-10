local M = {}

function M.bind(keyset, keys, callback)
  for _, key in ipairs(type(keys) == "string" and { keys } or keys or {}) do
    keyset("i", key, callback)
  end
end

-- Resolve selection before closing; open only after the picker restores its window.
function M.bind_open(session, keyset, keymaps, open)
  for _, command in ipairs({ "split", "vsplit" }) do
    M.bind(keyset, keymaps[command], function()
      local item = session:get_selected()
      if item then
        session:close(function()
          open(item, command)
        end)
      end
    end)
  end
end

function M.open_file(path, command)
  vim.cmd((command or "edit") .. " " .. vim.fn.fnameescape(path))
end

-- Quickfix filenames are data, not Ex commands; never fnameescape them.
function M.quickfix(selection, title, entry)
  local items = {}
  for _, selected in ipairs(selection) do
    items[#items + 1] = entry(selected.item)
  end
  vim.fn.setqflist({}, " ", { title = title, items = items })
  vim.cmd("copen")
end

return M
