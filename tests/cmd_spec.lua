test("disabled command completion does not autotrigger native completion", function()
  local old_config = vim.g.minibuffer
  local old_mode = vim.fn.mode
  local old_wildtrigger = vim.fn.wildtrigger
  local old_wildmode = vim.o.wildmode
  local wildtrigger_calls = 0

  vim.g.minibuffer = { cmd = { enabled = false } }
  vim.fn.mode = function()
    return "c"
  end
  vim.fn.wildtrigger = function()
    wildtrigger_calls = wildtrigger_calls + 1
  end

  require("minibuffer").initialize()
  vim.api.nvim_exec_autocmds("CmdlineChanged", {})

  eq(0, wildtrigger_calls)
  eq(old_wildmode, vim.o.wildmode)
  eq(false, require("minibuffer.internal.cmd").is_active())

  vim.g.minibuffer = old_config
  vim.fn.mode = old_mode
  vim.fn.wildtrigger = old_wildtrigger
end)
