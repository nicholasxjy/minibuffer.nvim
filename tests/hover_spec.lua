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
    captured = vim.tbl_extend("force", captured or {}, {
      opts = opts,
      win_opts = lsp_util.make_floating_popup_options(1, 1, opts),
    })
  end
  vim.lsp.buf.hover = function(opts, extra)
    captured = { opts = opts, extra = extra }
    return lsp_util.open_floating_preview({}, "markdown", opts)
  end

  package.loaded["minibuffer.builtin.hover"] = nil
  vim.lsp.buf.hover = require("minibuffer.builtin.hover")
  vim.lsp.buf.hover({ border = "rounded", max_width = 80 }, "extra")

  state.initialized = old_initialized
  vim.lsp.buf.hover = old_hover
  lsp_util.open_floating_preview = old_open
  lsp_util.make_floating_popup_options = old_make
  lsp_util._minibuffer_hover = old_marker
  package.loaded["minibuffer.builtin.hover"] = nil

  eq("rounded", captured.opts.border)
  eq(80, captured.opts.max_width)
  eq(true, captured.opts.use_minibuffer)
  eq("extra", captured.extra)
  eq("minibuffer", captured.win_opts.relative)
  eq(true, captured.win_opts.use_minibuffer)
end)

test("builtin hover closes without invalid window callbacks", function()
  local state = require("minibuffer.internal.state")
  local mbutil = require("minibuffer.internal.util")
  local old_get_cmd_win = mbutil.get_cmd_win
  local old_get_cmd_buf = mbutil.get_cmd_buf
  local old_ready = mbutil.ready
  local cmd_buf = vim.api.nvim_create_buf(false, true)
  local cmd_win = state.default_nvim_open_win(cmd_buf, false, {
    relative = "editor",
    row = vim.o.lines - 2,
    col = 0,
    width = vim.o.columns,
    height = 1,
    style = "minimal",
    zindex = 100,
  })

  mbutil.get_cmd_win = function()
    return cmd_win
  end
  mbutil.get_cmd_buf = function()
    return cmd_buf
  end
  mbutil.ready = function()
    return true
  end

  package.loaded["minibuffer.builtin.hover"] = nil
  require("minibuffer.builtin.hover")
  local _, hover_win = vim.lsp.util.open_floating_preview({ "hover" }, "", {
    use_minibuffer = true,
    focus_id = "textDocument/hover",
  })
  vim.api.nvim_set_current_win(hover_win)
  local ok, err = pcall(vim.cmd, "bdelete!")
  vim.wait(50)

  mbutil.get_cmd_win = old_get_cmd_win
  mbutil.get_cmd_buf = old_get_cmd_buf
  mbutil.ready = old_ready
  if vim.api.nvim_win_is_valid(cmd_win) then
    state.default_nvim_win_close(cmd_win, true)
  end
  if vim.api.nvim_buf_is_valid(cmd_buf) then
    vim.api.nvim_buf_delete(cmd_buf, { force = true })
  end

  if not ok then
    error(err)
  end
  eq(false, vim.api.nvim_win_is_valid(hover_win))
end)
