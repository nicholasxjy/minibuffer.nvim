local lsp_util = vim.lsp.util
local native_open_floating_preview = lsp_util.open_floating_preview
local native_hover = vim.lsp.buf.hover

-- Keep Neovim's hover implementation and redirect only its preview window.
if not lsp_util._minibuffer_hover then
  lsp_util._minibuffer_hover = true
  lsp_util.open_floating_preview = function(contents, syntax, opts)
    if not opts or not opts.use_minibuffer then
      return native_open_floating_preview(contents, syntax, opts)
    end

    local native_make_popup_options = lsp_util.make_floating_popup_options
    lsp_util.make_floating_popup_options = function(width, height, popup_opts)
      local win_opts = native_make_popup_options(width, height, popup_opts)
      win_opts.relative = "minibuffer"
      win_opts.use_minibuffer = true
      return win_opts
    end

    local ok, bufnr, winid = pcall(native_open_floating_preview, contents, syntax, opts)
    lsp_util.make_floating_popup_options = native_make_popup_options
    if not ok then
      error(bufnr)
    end
    return bufnr, winid
  end
end

---@param config? vim.lsp.buf.hover.Opts
return function(config)
  require("minibuffer.internal.guard").check()
  if config ~= nil and type(config) ~= "table" then
    return native_hover(config)
  end
  config = vim.tbl_extend("force", config or {}, { use_minibuffer = true })
  return native_hover(config)
end
