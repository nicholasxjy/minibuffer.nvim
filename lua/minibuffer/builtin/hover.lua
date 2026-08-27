local lsp_util = vim.lsp.util
local native_make_popup_options = lsp_util.make_floating_popup_options
local native_hover = vim.lsp.buf.hover

-- Keep Neovim's hover implementation and redirect only its preview window.
if not lsp_util._minibuffer_hover then
  lsp_util._minibuffer_hover = true
  lsp_util.make_floating_popup_options = function(width, height, opts)
    local win_opts = native_make_popup_options(width, height, opts)
    if opts and opts.use_minibuffer then
      win_opts.relative = "minibuffer"
      win_opts.use_minibuffer = true
    end
    return win_opts
  end
end

---@param config? vim.lsp.buf.hover.Opts
---@param ... any
return function(config, ...)
  require("minibuffer.internal.guard").check()
  if config ~= nil and type(config) ~= "table" then
    return native_hover(config, ...)
  end
  config = vim.tbl_extend("force", config or {}, { use_minibuffer = true })
  return native_hover(config, ...)
end
