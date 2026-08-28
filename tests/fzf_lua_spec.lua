local function with_fake_fzf(run, fake_opts)
  fake_opts = fake_opts or {}
  local old_fzf = package.loaded["fzf-lua"]
  local old_files = package.loaded["fzf-lua.providers.files"]
  local old_integration = package.loaded["minibuffer.integrations.fzf_lua"]
  local old_notify = vim.notify
  local capture = {
    data_callbacks = {},
    finishes = {},
    fzf_exec_calls = 0,
    killed = 0,
    notifications = {},
    source_calls = 0,
  }
  local fake
  local toggle_ignore = function(_, opts)
    opts.__call_fn({ no_ignore = not opts.no_ignore, resume = true })
  end
  fake = {
    actions = { toggle_ignore = toggle_ignore },
    config = {
      normalize_opts = function(opts, provider)
        opts.cwd = opts.cwd or "/repo"
        opts.fzf_opts = opts.fzf_opts or {}
        opts._fzf_cli_args = opts._fzf_cli_args or {}
        opts.winopts = opts.winopts or {}
        opts.actions = opts.actions
          or {
            ["alt-i"] = { fn = toggle_ignore, reuse = true },
          }
        if opts.line_query then
          opts._fzf_cli_args[#opts._fzf_cli_args + 1] = "line-query-" .. provider
        end
        if provider == "global" then
          opts.pickers = opts.pickers
            or {
              { "files", desc = "Files" },
              { "buffers", desc = "Buffers", prefix = "$" },
            }
        end
        opts.fn_transform = opts.fn_transform
          or function(line)
            return line
          end
        opts._normalized = true
        return opts
      end,
    },
    core = {
      fzf_exec = function(contents, opts)
        return nil, contents, opts
      end,
      set_title_flags = function(opts)
        return opts
      end,
    },
    fzf_exec = function(contents, opts)
      capture.fzf_exec_calls = capture.fzf_exec_calls + 1
      capture.contents = contents
      capture.opts = opts
    end,
    defaults = { files = {} },
    global = function(opts)
      capture.global_opts = opts
      local provider = fake[opts.pickers[1][1]]
      capture.global_thread, capture.global_contents, capture.global_provider_opts =
        provider(opts)
    end,
    libuv = {
      load_fn = function()
        return nil
      end,
      shellescape = function(value)
        return value
      end,
      spawn = function(opts)
        capture.source_calls = capture.source_calls + 1
        capture.command = opts.cmd
        if fake_opts.fail_source then
          opts.cb_err("source failed")
          opts.cb_finish(1)
        else
          opts.cb_write_lines(
            fake_opts.lines or { "foo/src.lua", "src/foo.lua" },
            function() end
          )
        end
        if fake_opts.defer_source then
          capture.finishes[#capture.finishes + 1] = opts.cb_finish
        elseif not fake_opts.fail_source then
          opts.cb_finish(0)
        end
        return {
          kill = function()
            capture.killed = capture.killed + 1
          end,
        }
      end,
    },
    path = {
      is_absolute = function(path)
        return path:sub(1, 1) == "/"
      end,
      normalize = function(path)
        return vim.fs.normalize(path)
      end,
      relative_to = function(path, cwd)
        return path:gsub("^" .. vim.pesc(cwd .. "/"), "")
      end,
    },
    shell = {
      stringify_data = function(fn, _, field)
        capture.data_callbacks[#capture.data_callbacks + 1] = { fn = fn, field = field }
        if field == "{q}" then
          capture.reload = capture.reload or fn
          return "data-command-" .. #capture.data_callbacks
        end
        capture.initial = fn
        return "data-command-" .. #capture.data_callbacks
      end,
    },
    utils = {
      __IS_WINDOWS = fake_opts.windows == true,
      cwd = function()
        return "/repo"
      end,
      has = function()
        return true
      end,
      lua_regex_escape = vim.pesc,
      strip_ansi_coloring = function(line)
        return line
      end,
    },
  }
  fake.register_extension = function(name, fn)
    fake[name] = fn
    capture.extension = name
  end

  package.loaded["fzf-lua"] = fake
  package.loaded["fzf-lua.providers.files"] = {
    get_files_cmd = function()
      return "list-files"
    end,
  }
  package.loaded["minibuffer.integrations.fzf_lua"] = nil
  vim.notify = function(message, level)
    capture.notifications[#capture.notifications + 1] =
      { message = message, level = level }
  end

  local ok, err = xpcall(function()
    run(require("minibuffer.integrations.fzf_lua"), capture)
  end, debug.traceback)

  package.loaded["fzf-lua"] = old_fzf
  package.loaded["fzf-lua.providers.files"] = old_files
  package.loaded["minibuffer.integrations.fzf_lua"] = old_integration
  vim.notify = old_notify
  if not ok then
    error(err, 0)
  end
end

test("fzf-lua files loads once and reloads in smart order", function()
  with_fake_fzf(function(integration, capture)
    integration.files({
      cwd = "/repo",
      smart = { cwd_bonus = false, frecency = false, query_delay = 0 },
    })
    vim.wait(100, function()
      return capture.opts ~= nil
    end)

    eq(1, capture.source_calls)
    eq(true, capture.opts.fzf_opts["--no-sort"])
    eq(false, capture.opts.actions["alt-i"].reuse)
    eq("src/foo.lua\nfoo/src.lua", capture.reload({ "foo" }))
  end)
end)

test("fzf-lua files formats candidates once without changing match text", function()
  with_fake_fzf(function(integration, capture)
    local preprocess = 0
    local postprocess = 0
    integration.files({
      cwd = "/repo",
      fn_preprocess = function()
        preprocess = preprocess + 1
      end,
      fn_transform = function(line)
        return "icon " .. line
      end,
      fn_postprocess = function()
        postprocess = postprocess + 1
      end,
      smart = { cwd_bonus = false, frecency = false, query_delay = 0 },
    })

    eq(1, preprocess)
    eq(1, postprocess)
    eq("icon src/foo.lua\nicon foo/src.lua", capture.reload({ "foo" }))
    eq(nil, capture.opts.fn_transform)
    eq(nil, capture.opts.fn_preprocess)
    eq(nil, capture.opts.fn_postprocess)
  end)
end)

test("fzf-lua files aligns filename-first columns without changing paths", function()
  with_fake_fzf(function(integration, capture)
    integration.files({
      cwd = "/repo",
      formatter = "path.filename_first",
      _fmt = {
        from = function(line)
          local filename, directory = line:match("^([^\t]+)\t(.+)$")
          return filename and directory .. "/" .. filename or line
        end,
      },
      fn_transform = function(line)
        local directory, filename = line:match("^(.*)/([^/]+)$")
        return filename .. "\t" .. directory
      end,
      smart = { cwd_bonus = false, frecency = false, query_delay = 0 },
    })

    local lines = vim.split(capture.initial({}), "\n")
    local columns = vim.tbl_map(function(line)
      local separator = assert(line:find("│", 1, true))
      return vim.api.nvim_strwidth(line:sub(1, separator - 1))
    end, lines)
    eq(columns[1], columns[2])
    eq("src/文.lua", capture.opts._fmt.from(lines[1]))
    eq("lua/long_name.lua", capture.opts._fmt.from(lines[2]))
  end, { lines = { "src/文.lua", "lua/long_name.lua" } })
end)

test("fzf-lua files does not use a POSIX debounce command on Windows", function()
  with_fake_fzf(function(integration, capture)
    integration.files({
      cwd = "/repo",
      smart = { cwd_bonus = false, frecency = false },
    })

    eq(
      false,
      capture.opts._fzf_cli_args[#capture.opts._fzf_cli_args]:find("sleep", 1, true)
        ~= nil
    )
  end, { windows = true })
end)

test("fzf-lua files retains one closed session for restart resume", function()
  with_fake_fzf(function(integration, capture)
    local closed = 0
    integration.files({
      cwd = "/repo",
      winopts = {
        on_close = function()
          closed = closed + 1
        end,
      },
      smart = { cwd_bonus = false, frecency = false, query_delay = 0 },
    })
    local first_reload = capture.reload
    capture.opts.winopts.on_close()
    vim.wait(20, function()
      return false
    end)

    eq(1, closed)
    eq("src/foo.lua\nfoo/src.lua", first_reload({ "foo" }))

    integration.files({
      cwd = "/repo",
      smart = { cwd_bonus = false, frecency = false, query_delay = 0 },
    })
    eq({}, first_reload({ "foo" }))
    eq(2, capture.source_calls)
  end)
end)

test("fzf-lua file toggles reopen smart ranking with the current query", function()
  with_fake_fzf(function(integration, capture)
    integration.files({
      cwd = "/repo",
      smart = { cwd_bonus = false, frecency = false, query_delay = 0 },
    })
    local previous = capture.opts
    previous.last_query = "foo"
    previous.actions["alt-i"].fn({}, previous)

    eq(2, capture.source_calls)
    eq(true, capture.opts.no_ignore)
    eq("foo", capture.opts.query)
    eq(true, capture.opts.fzf_opts["--no-sort"])
  end)
end)

test("fzf-lua files cancels and ignores stale source discovery", function()
  with_fake_fzf(function(integration, capture)
    local opts = {
      cwd = "/repo",
      smart = { cwd_bonus = false, frecency = false, query_delay = 0 },
    }
    integration.files(opts)
    integration.files(opts)

    eq(1, capture.killed)
    capture.finishes[1](0)
    eq(0, capture.fzf_exec_calls)
    capture.finishes[2](0)
    eq(1, capture.fzf_exec_calls)
  end, { defer_source = true })
end)

test("fzf-lua files reports source failures without opening a picker", function()
  with_fake_fzf(function(integration, capture)
    integration.files({
      cwd = "/repo",
      smart = { cwd_bonus = false, frecency = false, query_delay = 0 },
    })

    eq(0, capture.fzf_exec_calls)
    eq(1, #capture.notifications)
    eq(true, capture.notifications[1].message:find("source failed", 1, true) ~= nil)
  end, { fail_source = true })
end)

test("fzf-lua global replaces only the default files provider", function()
  with_fake_fzf(function(integration, capture)
    integration.global({
      cwd = "/repo",
      line_query = true,
      pickers = {
        { "files", desc = "Files" },
        { "buffers", desc = "Buffers", prefix = "$" },
      },
      smart = { cwd_bonus = false, frecency = false, query_delay = 0 },
    })

    eq(1, capture.source_calls)
    eq(capture.extension, capture.global_opts.pickers[1][1])
    eq({ "buffers", desc = "Buffers", prefix = "$" }, capture.global_opts.pickers[2])
    eq("src/foo.lua\nfoo/src.lua", capture.data_callbacks[1].fn({ "foo" }))
    eq("", capture.data_callbacks[2].fn({ "foo" }))
    eq("toggle-sort", capture.data_callbacks[3].fn({ "$buf" }))
    eq("", capture.data_callbacks[3].fn({ "$buffer" }))
    eq("toggle-sort", capture.data_callbacks[2].fn({ "$buffer" }))
    eq("toggle-sort", capture.data_callbacks[3].fn({ "foo" }))
    eq("reload(data-command-1)", capture.data_callbacks[3].fn({ "foob" }))
    local line_query = 0
    for _, arg in ipairs(capture.global_provider_opts._fzf_cli_args) do
      if arg:find("line-query-", 1, true) then
        line_query = line_query + 1
      end
    end
    eq(1, line_query)
  end)
end)

test("fzf-lua global enables native sorting for an initial prefixed source", function()
  with_fake_fzf(function(integration, capture)
    integration.global({
      cwd = "/repo",
      query = "$buf",
      pickers = {
        { "files", desc = "Files" },
        { "buffers", desc = "Buffers", prefix = "$" },
      },
      smart = { cwd_bonus = false, frecency = false, query_delay = 0 },
    })

    eq("toggle-sort", capture.data_callbacks[2].fn({ "$buf" }))
  end)
end)
