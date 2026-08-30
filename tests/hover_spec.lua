test("builtin hover redirects the native preview", function()
  local state = require("minibuffer.internal.state")
  local lsp_util = vim.lsp.util
  local old_initialized = state.initialized
  local old_hover = vim.lsp.buf.hover
  local old_open = lsp_util.open_floating_preview
  local old_make = lsp_util.make_floating_popup_options
  local old_marker = lsp_util._minibuffer_hover
  local captured

  state.initialized = true
  lsp_util._minibuffer_hover = nil
  lsp_util.make_floating_popup_options = function(width, height)
    return { relative = "cursor", width = width, height = height }
  end
  lsp_util.open_floating_preview = function(_, _, opts)
    captured = {
      opts = opts,
      win_opts = lsp_util.make_floating_popup_options(1, 1, opts),
    }
  end
  vim.lsp.buf.hover = function(opts)
    return lsp_util.open_floating_preview({}, "markdown", opts)
  end

  package.loaded["minibuffer.builtin.hover"] = nil
  vim.lsp.buf.hover = require("minibuffer.builtin.hover")
  vim.lsp.buf.hover()

  state.initialized = old_initialized
  vim.lsp.buf.hover = old_hover
  lsp_util.open_floating_preview = old_open
  lsp_util.make_floating_popup_options = old_make
  lsp_util._minibuffer_hover = old_marker
  package.loaded["minibuffer.builtin.hover"] = nil

  eq(true, captured.opts.use_minibuffer)
  eq("minibuffer", captured.win_opts.relative)
  eq(true, captured.win_opts.use_minibuffer)
end)
