local M = {}

-- Match records directly so equal text cannot overwrite a different item.
function M.fuzzy(key)
  return function(ctx)
    if ctx.input == "" then
      return ctx.items
    end
    return vim.fn.matchfuzzy(ctx.items, ctx.input, key and { key = key } or {})
  end
end

return M
