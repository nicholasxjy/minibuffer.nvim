local function resolve(chunks, max_width)
  local ret = {}
  for _, chunk in ipairs(chunks) do
    if chunk.resolve then
      vim.list_extend(ret, chunk.resolve(max_width or 80))
    else
      ret[#ret + 1] = chunk
    end
  end
  return ret
end

local function text(chunks)
  return table.concat(vim.tbl_map(function(chunk)
    return chunk[1] or ""
  end, chunks))
end

local function with_fake_snacks(run)
  local old_snacks = package.loaded["snacks"]
  local old_integration = package.loaded["minibuffer.integrations.snacks-picker"]
  local old_todo_config = package.loaded["todo-comments.config"]
  local old_todo_snacks = package.loaded["todo-comments.snacks"]
  local capture = { layout_calls = 0, calls = {} }

  local function native_file(item, picker)
    capture.file_calls = (capture.file_calls or 0) + 1
    local path = item.file
    local directory, filename = path:match("^(.*)/([^/]+)$")
    filename = filename or path
    if picker.opts.formatters.file.filename_only then
      return { { filename, "FileHL", field = "file" } }
    end
    return {
      {
        "",
        resolve = function()
          if picker.opts.formatters.file.filename_first and directory then
            return {
              { filename, "FileHL", field = "file" },
              { " " },
              { directory, "DirHL", field = "file" },
            }
          end
          return {
            { directory and directory .. "/" or "", "DirHL", field = "file" },
            { filename, "FileHL", field = "file" },
          }
        end,
      },
      { " tail", "TailHL" },
    }
  end

  local fake
  fake = {
    picker = {
      config = {
        layout = function(opts)
          capture.layout_calls = capture.layout_calls + 1
          return vim.deepcopy(opts.layout)
        end,
        wrap = function(source)
          local wrapped = function(opts)
            return fake.picker.pick(source, opts)
          end
          fake.picker[source] = wrapped
          return wrapped
        end,
        sort = function()
          capture.sort_calls = (capture.sort_calls or 0) + 1
          return function(a, b)
            return (a.file or a.text or "") < (b.file or b.text or "")
          end
        end,
      },
      format = { file = native_file },
      util = {
        path = function(item)
          capture.path_calls = (capture.path_calls or 0) + 1
          return item.file
        end,
      },
      sources = {},
    },
  }

  local function picker(source)
    return function(opts)
      capture.calls[#capture.calls + 1] = { source = source, opts = opts }
      return fake.picker.config.layout(vim.tbl_deep_extend(
        "force",
        { source = source },
        opts or {}
      ))
    end
  end
  fake.picker.files = picker("files")
  fake.picker.custom_source = picker("custom_source")

  package.loaded["snacks"] = fake
  package.loaded["minibuffer.integrations.snacks-picker"] = nil

  local ok, err = xpcall(function()
    run(require("minibuffer.integrations.snacks-picker"), fake, capture, native_file)
  end, debug.traceback)

  package.loaded["snacks"] = old_snacks
  package.loaded["minibuffer.integrations.snacks-picker"] = old_integration
  package.loaded["todo-comments.config"] = old_todo_config
  package.loaded["todo-comments.snacks"] = old_todo_snacks
  if not ok then
    error(err, 0)
  end
end

test("Snacks picker setup is idempotent and preserves picker APIs and options", function()
  with_fake_snacks(function(integration, Snacks, capture)
    local files = Snacks.picker.files
    local custom_source = Snacks.picker.custom_source
    integration.setup()
    local layout = Snacks.picker.config.layout
    local formatter = Snacks.picker.format.file
    integration.setup()

    eq(files, Snacks.picker.files)
    eq(custom_source, Snacks.picker.custom_source)
    eq(layout, Snacks.picker.config.layout)
    eq(formatter, Snacks.picker.format.file)

    local callback = function() end
    local actions = { confirm = callback }
    local keys = { q = "cancel" }
    local opts = {
      actions = actions,
      callback = callback,
      layout = {
        preview = "main",
        layout = {
          box = "vertical",
          height = 0.4,
          { win = "input", height = 1 },
          { win = "list", keys = keys },
          { win = "preview", height = 0.5 },
        },
      },
    }
    local resolved = Snacks.picker.files(opts)

    eq(opts, capture.calls[1].opts)
    eq(actions, opts.actions)
    eq(callback, opts.callback)
    eq("main", resolved.preview)
    eq(0.4, resolved.layout.height)
    eq("vertical", resolved.layout.box)
    eq("input", resolved.layout[1].win)
    eq(keys, resolved.layout[2].keys)
    eq("preview", resolved.layout[3].win)
    eq("minibuffer", resolved.layout.relative)
    eq("float", resolved.layout.position)
    eq(false, resolved.layout.fixbuf)
    local cmd_win = require("minibuffer.internal.util").get_cmd_win()
    if cmd_win then
      eq(vim.api.nvim_win_get_config(cmd_win).zindex + 1, resolved.layout.zindex)
    end
    eq(1, capture.layout_calls)
  end)
end)

test("Snacks picker setup stays idempotent across module reloads", function()
  with_fake_snacks(function(integration, Snacks, capture)
    integration.setup()
    local layout = Snacks.picker.config.layout
    local formatter = Snacks.picker.format.file
    package.loaded["minibuffer.integrations.snacks-picker"] = nil
    require("minibuffer.integrations.snacks-picker").setup()

    eq(layout, Snacks.picker.config.layout)
    eq(formatter, Snacks.picker.format.file)
    Snacks.picker.config.layout({ layout = { layout = {} } })
    eq(1, capture.layout_calls)
  end)
end)

test("Snacks picker setup disables APIs and restores native behavior", function()
  with_fake_snacks(function(integration, Snacks, _, native_file)
    integration.setup({ pickers = { custom_source = false } })

    local files = Snacks.picker.files({ layout = { layout = { height = 6 } } })
    local custom = Snacks.picker.custom_source({
      layout = { layout = { height = 7 } },
    })
    eq("minibuffer", files.layout.relative)
    eq(nil, custom.layout.relative)
    eq(7, custom.layout.height)

    integration.setup({ pickers = { files = false } })
    local restored = Snacks.picker.files({
      layout = { layout = { height = 8, position = "bottom" } },
    })
    eq(nil, restored.layout.relative)
    eq("bottom", restored.layout.position)
    local custom_enabled = Snacks.picker.custom_source({
      layout = { layout = { height = 9 } },
    })
    eq("minibuffer", custom_enabled.layout.relative)

    local item = { file = "src/file.lua" }
    local picker = {
      opts = {
        source = "files",
        formatters = { file = { filename_first = true, filename_only = false } },
      },
      list = { items = { item } },
    }
    eq(
      text(resolve(native_file(item, picker))),
      text(resolve(Snacks.picker.format.file(item, picker)))
    )

    integration.setup({ pickers = false })
    local all_restored = Snacks.picker.custom_source({
      layout = { layout = { height = 10 } },
    })
    eq(nil, all_restored.layout.relative)
  end)
end)

test("Snacks files and smart use filename-first formatting by default", function()
  with_fake_snacks(function(integration, Snacks)
    integration.setup()
    local items = {
      { file = "src/file.lua" },
      { file = "src/long_file.lua" },
    }
    for _, source in ipairs({ "files", "smart" }) do
      local picker = {
        opts = {
          source = source,
          formatters = { file = { filename_only = false } },
        },
        list = { items = items },
      }
      local rendered = vim.tbl_map(function(item)
        return text(resolve(Snacks.picker.format.file(item, picker)))
      end, items)
      local first_separator = assert(rendered[1]:find("│", 1, true))
      local second_separator = assert(rendered[2]:find("│", 1, true))
      eq(first_separator, second_separator)
      eq(true, rendered[1]:find("file.lua", 1, true) == 1)
      eq(true, rendered[2]:find("long_file.lua", 1, true) == 1)
      eq(nil, picker.opts.formatters.file.filename_first)
    end
  end)
end)

test("Snacks smart can prioritize and decorate git changes", function()
  with_fake_snacks(function(integration, Snacks)
    integration.setup({ smart = { git_status = true } })

    local sort = Snacks.picker.config.sort({ source = "smart" })
    local changed = { file = "src/changed.lua", status = "modified" }
    local clean = { status = "clean" }
    eq(true, sort(changed, clean))
    eq(false, sort(clean, changed))

    local picker = {
      opts = {
        source = "smart",
        formatters = { file = { filename_only = false } },
      },
      list = { items = { changed, clean } },
    }
    local chunks = resolve(Snacks.picker.format.file(changed, picker))
    local filename
    local sign
    local signs = 0
    for _, chunk in ipairs(chunks) do
      if chunk.field == "file" and not filename then
        filename = chunk
      elseif chunk.sign_text then
        sign = chunk
        signs = signs + 1
      end
    end
    eq("FFFGitModified", filename[2])
    eq(1, signs)
    eq("┃", sign.sign_text)
    eq("FFFGitSignModified", sign.sign_hl_group)

    local selected_picker = vim.tbl_extend("force", {}, picker, {
      list = {
        current = function()
          return changed
        end,
      },
    })
    local selected_chunks = resolve(Snacks.picker.format.file(changed, selected_picker))
    local selected_sign
    for _, chunk in ipairs(selected_chunks) do
      if chunk.sign_text then
        selected_sign = chunk
        break
      end
    end
    eq("FFFGitSignModifiedSelected", selected_sign.sign_hl_group)

    local direct_status = { file = "src/direct.lua", git_status = "modified" }
    local direct_chunks = resolve(Snacks.picker.format.file(direct_status, picker))
    local direct_filename
    for _, chunk in ipairs(direct_chunks) do
      if chunk.field == "file" and not direct_filename then
        direct_filename = chunk
      end
    end
    eq("FFFGitModified", direct_filename[2])

    local staged_deleted = { file = "src/staged.lua", status = "D " }
    local staged_chunks = resolve(Snacks.picker.format.file(staged_deleted, picker))
    local staged_filename
    local staged_sign
    for _, chunk in ipairs(staged_chunks) do
      if chunk.field == "file" and not staged_filename then
        staged_filename = chunk
      elseif chunk.sign_text then
        staged_sign = chunk
      end
    end
    eq("FFFGitStaged", staged_filename[2])
    eq("▁", staged_sign.sign_text)
    eq("FFFGitSignStaged", staged_sign.sign_hl_group)

    local staged_and_modified = { file = "src/mixed.lua", status = "MM" }
    local mixed_chunks = resolve(Snacks.picker.format.file(staged_and_modified, picker))
    local mixed_filename
    for _, chunk in ipairs(mixed_chunks) do
      if chunk.field == "file" then
        mixed_filename = chunk
        break
      end
    end
    eq("FFFGitModified", mixed_filename[2])

    local opts = {
      source = "smart",
      win = { list = { wo = {} } },
      layout = { layout = {} },
    }
    Snacks.picker.config.layout(opts)
    eq("yes", opts.win.list.wo.signcolumn)
    eq("", opts.win.list.wo.statuscolumn)
  end)
end)

test("Snacks picker adapts custom sources and every resolved layout", function()
  with_fake_snacks(function(integration, Snacks, capture)
    integration.setup()

    local first = Snacks.picker.custom_source({
      finder = function() end,
      layout = { hidden = { "preview" }, layout = { box = "horizontal", height = 12 } },
    })
    local second = Snacks.picker.config.layout({
      source = "custom_source",
      layout = { preview = false, layout = { box = "vertical", height = 6 } },
    })

    eq("horizontal", first.layout.box)
    eq(12, first.layout.height)
    eq({ "preview" }, first.hidden)
    eq("vertical", second.layout.box)
    eq(6, second.layout.height)
    eq(false, second.preview)
    for _, resolved in ipairs({ first, second }) do
      eq("minibuffer", resolved.layout.relative)
      eq("float", resolved.layout.position)
      eq(false, resolved.layout.fixbuf)
    end
    eq(2, capture.layout_calls)
  end)
end)

test("Snacks picker restores a loaded todo-comments source", function()
  with_fake_snacks(function(integration, Snacks)
    package.loaded["todo-comments.config"] = { loaded = true }
    package.loaded["todo-comments.snacks"] = { source = { finder = "todo" } }

    integration.setup()

    eq(true, Snacks.picker.sources.todo_comments ~= nil)
    eq("function", type(Snacks.picker.todo_comments))
  end)
end)

test("Snacks filename alignment uses the longest filename in the list", function()
  with_fake_snacks(function(integration, Snacks, capture)
    integration.setup()
    local items = {}
    for index = 1, 1000 do
      items[index] = { file = ("dir/file_%04d.lua"):format(index) }
    end
    items[1].file = "dir/an_offscreen_filename_that_sets_the_width.lua"
    items[110].file = "dir/long_visible_name.lua"
    local list = { items = items, top = 101, state = { height = 20 } }
    function list:count()
      return #self.items
    end
    function list:height()
      return math.min(self.state.height, self:count())
    end
    function list:get(index)
      return self.items[index]
    end
    local picker = {
      opts = {
        source = "files",
        formatters = { file = { filename_first = true, filename_only = false } },
      },
      list = list,
    }

    local line = text(resolve(Snacks.picker.format.file(items[101], picker)))
    local separator = assert(line:find("│", 1, true))
    local longest = vim.api.nvim_strwidth("an_offscreen_filename_that_sets_the_width.lua")
    eq(longest + 2, vim.api.nvim_strwidth(line:sub(1, separator - 1)))
    eq(1000, capture.path_calls)

    Snacks.picker.format.file(items[102], picker)
    eq(1000, capture.path_calls)

    list.top = 201
    Snacks.picker.format.file(items[201], picker)
    eq(1000, capture.path_calls)
  end)
end)

test("Snacks filename alignment caps padding to the resolved width", function()
  with_fake_snacks(function(integration, Snacks)
    integration.setup()
    local items = {
      { file = "dir/short.lua" },
      { file = "dir/" .. string.rep("x", 200) .. ".lua" },
    }
    local picker = {
      opts = {
        source = "files",
        formatters = { file = { filename_first = true, filename_only = false } },
      },
      list = { items = items },
    }
    local line = text(resolve(Snacks.picker.format.file(items[1], picker), 20))
    local separator = assert(line:find("│", 1, true))
    eq(true, vim.api.nvim_strwidth(line:sub(1, separator - 1)) <= 20)
  end)
end)

test("Snacks files and smart align filename-first paths by display width", function()
  with_fake_snacks(function(integration, Snacks)
    integration.setup()
    local items = {
      { file = "src/文档.lua", text = "src/文档.lua" },
      { file = "lua/long_name.lua", text = "lua/long_name.lua" },
    }

    for _, source in ipairs({ "files", "smart" }) do
      local picker = {
        opts = {
          source = source,
          formatters = { file = { filename_first = true, filename_only = false } },
        },
        list = { items = items },
      }
      local lines = vim.tbl_map(function(item)
        return resolve(Snacks.picker.format.file(item, picker))
      end, items)
      local rendered = vim.tbl_map(text, lines)
      local columns = vim.tbl_map(function(line)
        local separator = assert(line:find("│", 1, true))
        return vim.api.nvim_strwidth(line:sub(1, separator - 1))
      end, rendered)

      eq(columns[1], columns[2])
      eq("文档.lua       │ src tail", rendered[1])
      eq("long_name.lua  │ lua tail", rendered[2])
      eq("FileHL", lines[1][1][2])
      eq("file", lines[1][1].field)
      eq("SnacksPickerDelim", lines[1][3][2])
      eq("DirHL", lines[1][5][2])
      eq("TailHL", lines[1][6][2])
      eq("src/文档.lua", items[1].file)
      eq("src/文档.lua", items[1].text)
    end
  end)
end)

test("Snacks filename alignment leaves other formatter scenarios native", function()
  with_fake_snacks(function(integration, Snacks, _, native_file)
    integration.setup()
    local item = { file = "src/文档.lua", text = "match text" }
    local cases = {
      { source = "buffers", filename_first = true, filename_only = false },
      { source = "files", filename_first = true, filename_only = true },
    }
    for _, case in ipairs(cases) do
      local picker = {
        opts = { source = case.source, formatters = { file = case } },
        list = { items = { item } },
      }
      eq(text(resolve(native_file(item, picker))), text(resolve(Snacks.picker.format.file(item, picker))))
    end

    local picker = {
      opts = {
        source = "files",
        formatters = { file = { filename_first = false, filename_only = false } },
      },
      list = { items = { item } },
    }
    eq("file.lua  │ src tail", text(resolve(Snacks.picker.format.file(item, picker))))

    local custom = function(value)
      return { { value.text, "CustomHL" } }
    end
    local picker = {
      opts = {
        source = "files",
        format = custom,
        formatters = { file = { filename_first = true } },
      },
    }
    eq({ { "match text", "CustomHL" } }, picker.opts.format(item, picker))
  end)
end)

test("Snacks picker setup reports a missing dependency", function()
  local old_snacks = package.loaded["snacks"]
  local old_preload = package.preload["snacks"]
  local old_integration = package.loaded["minibuffer.integrations.snacks-picker"]
  package.loaded["snacks"] = nil
  package.loaded["minibuffer.integrations.snacks-picker"] = nil
  package.preload["snacks"] = function()
    error("missing snacks")
  end

  local integration = require("minibuffer.integrations.snacks-picker")
  local ok, err = pcall(integration.setup)

  package.loaded["snacks"] = old_snacks
  package.preload["snacks"] = old_preload
  package.loaded["minibuffer.integrations.snacks-picker"] = old_integration
  eq(false, ok)
  eq(true, tostring(err):find("snacks.nvim", 1, true) ~= nil)
end)
