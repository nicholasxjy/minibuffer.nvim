local actions = require("minibuffer.builtin.actions")
local config = require("minibuffer.builtin.config")
local ui = require("minibuffer.builtin.files-ui")

---@class minibuffer.builtin.FilesOpts: minibuffer.builtin.Opts
---@field filter? {cwd?: boolean} Restrict all sources to cwd (default true).
---@field cwd? string
---@field query? string
---@field rg_opts? string[]
---@field matcher? minibuffer.fuzzy.Opts Snacks-style scoring options.
---@field filename_first? boolean Default true.
---@field keymaps? table<string, string|string[]> next, previous, split, vsplit, accept, toggle, toggle_all, close.
---@field git? {status_text_color?: boolean}
---@field git_changed_first? boolean Put Git changes before other matches (default false).
---@field show_git_status? boolean
---@field hl? table<string,string> fff-style highlight names.
---@field current_file_label? string Default "(current)".
---@field fuzzy_query_highlighting? boolean Default false, like fff.
---@param opts? minibuffer.builtin.FilesOpts
return function(opts)
  require("minibuffer.internal.guard").check()
  assert(vim.fn.executable("rg") == 1, "rg is required for the files picker")
  local cursor_hl = next(vim.api.nvim_get_hl(0, { name = "CursorLine", link = false }))
      and "CursorLine"
    or "Visual"
  opts = config.resolve(opts, {
    filter = { cwd = true },
    git = { status_text_color = false },
    show_git_status = true,
    git_changed_first = false,
    current_file_label = "(current)",
    fuzzy_query_highlighting = false,
    matcher = {
      filename_bonus = true,
      cwd_bonus = true,
      frecency = true,
      history_bonus = false,
    },
    hl = {
      normal = "NormalFloat",
      prompt = "Question",
      cursor = cursor_hl,
      matched = "IncSearch",
      directory_path = "Comment",
      selected = "FFFSelected",
      selected_active = "FFFSelectedActive",
    },
    rg_opts = { "rg", "--files", "--hidden", "--color", "never", "-g", "!.git" },
  })
  for _, name in ipairs({
    "filename_first",
    "show_git_status",
    "git_changed_first",
    "fuzzy_query_highlighting",
  }) do
    vim.validate(name, opts[name], "boolean")
  end
  for _, name in ipairs({ "filename_bonus", "cwd_bonus", "frecency", "history_bonus" }) do
    vim.validate("matcher." .. name, opts.matcher[name], "boolean")
  end
  vim.validate("git.status_text_color", opts.git.status_text_color, "boolean")
  vim.validate("filter.cwd", opts.filter.cwd, "boolean")
  opts.cwd = vim.fs.normalize(vim.fn.fnamemodify(opts.cwd or vim.fn.getcwd(), ":p"))
  local current_file = vim.fs.normalize(vim.api.nvim_buf_get_name(0))
  local ranker = require("minibuffer.fuzzy").new_snacks(
    vim.tbl_extend("force", opts.matcher, { cwd = opts.cwd })
  )
  local keymaps = opts.keymaps
  local icon = ui.icon_provider()
  local cwd_prefix = opts.cwd:gsub("/$", "") .. "/"
  local buffers, recent = {}, vim.deepcopy(vim.v.oldfiles)
  for _, info in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
    if info.name ~= "" and vim.bo[info.bufnr].buftype == "" then
      buffers[#buffers + 1] = info
    end
  end
  table.sort(buffers, function(a, b)
    return a.lastused > b.lastused
  end)
  local cache, waiting, loading = nil, {}, false
  local function load(cb)
    if cache then
      return cb(cache)
    end
    waiting[#waiting + 1] = cb
    if loading then
      return
    end
    loading = true
    local remaining, file_output, git_status, failure = 2, "", {}, nil
    local function complete()
      remaining = remaining - 1
      if remaining ~= 0 then
        return
      end
      vim.schedule(function()
        local items, seen, directory_status = {}, {}, {}
        local function inherited_status(directory)
          if directory_status[directory] ~= nil then
            return directory_status[directory] or nil
          end
          local status = git_status[directory]
          local parent = not status and vim.fs.dirname(directory)
          if parent and parent ~= directory then
            status = inherited_status(parent)
          end
          directory_status[directory] = status or false
          return status
        end
        local function add(path, info, is_recent, normalized)
          if not normalized then
            path = vim.fs.normalize(path)
          end
          if seen[path] then
            return
          end
          local relative = path:sub(1, #cwd_prefix) == cwd_prefix
              and path:sub(#cwd_prefix + 1)
            or vim.fs.relpath(opts.cwd, path)
          if opts.filter.cwd and not relative then
            return
          end
          if info or is_recent then
            local stat = vim.uv.fs_stat(path)
            if not stat or stat.type ~= "file" then
              return
            end
          end
          seen[path] = true
          relative = (relative or path)
            :gsub("\n", "↵")
            :gsub("\r", "␍")
            :gsub("\t", "⇥")
          local directory, name = relative:match("^(.*)/([^/]+)$")
          local parent = path:match("^(.*)/")
          local status = git_status[path]
            or inherited_status(parent == "" and "/" or parent or "/")
          local item = {
            path = path,
            text = relative,
            relative_path = relative,
            file = relative,
            name = name or relative,
            directory = directory or "",
            git_status = status or "clean",
            idx = #items + 1,
            info = info,
            recent = is_recent,
          }
          item.icon, item.icon_hl = icon(item)
          items[#items + 1] = item
        end
        -- Snacks smart combines buffers, recent files and the file finder, in that order.
        for _, info in ipairs(buffers) do
          add(info.name, info, false)
        end
        for _, path in ipairs(recent) do
          add(path, nil, true)
        end
        for path in file_output:gmatch("[^%z]+") do
          local absolute = path:match("^/") or path:match("^%a:[/\\]")
          -- rg's ordinary paths are already canonical. Keep normalization for
          -- custom scan arguments, dot segments, expansion and Windows paths.
          local normalized = path:sub(1, 1) ~= "."
            and not path:find("[\\$~]")
            and not path:find("//", 1, true)
            and not path:find("/%.%.?/")
          add(absolute and path or cwd_prefix .. path, nil, nil, normalized)
        end
        ui.prepare(items)
        cache = not failure and items or nil
        loading = false
        local callbacks = waiting
        waiting = {}
        for _, callback in ipairs(callbacks) do
          callback(cache, failure)
        end
      end)
    end
    local cmd = vim.list_extend(vim.deepcopy(opts.rg_opts), { "--null" })
    vim.system(cmd, { cwd = opts.cwd }, function(res)
      file_output = res.stdout or ""
      if res.code ~= 0 and res.code ~= 1 then
        failure = res.stderr or "file scan failed"
      end
      complete()
    end)
    if opts.show_git_status or opts.git.status_text_color or opts.git_changed_first then
      require("minibuffer.builtin.files-git").load(opts.cwd, function(status)
        git_status = status
        complete()
      end)
    else
      complete()
    end
  end
  ui.setup()
  local function open(item, command)
    actions.open_file(item.path, command)
  end
  local session
  return config.select(opts, {
    query = opts.query,
    resumable = true,
    prompt = "Files> ",
    prompt_position = "top",
    multi = true,
    dynamic_height = false,
    max_height = 15,
    highlights = {
      normal = opts.hl.normal,
      query = opts.hl.normal,
      prompt = opts.hl.prompt,
      selection = opts.hl.cursor,
      multi_selection = opts.hl.normal,
    },
    header_position = "bottom",
    header_fn = function(ctx, width)
      return require("minibuffer.builtin.buffers-ui").hints(ctx, {
        split = keymaps.split,
        vsplit = keymaps.vsplit,
        delete = {},
        accept = keymaps.accept,
        toggle = keymaps.toggle,
        toggle_all = keymaps.toggle_all,
        next = keymaps.next,
        previous = keymaps.previous,
      }, cache and #cache or 0, math.max(1, width - 2))
    end,
    fetch_fn = function(_, cb)
      load(cb)
    end,
    filter_fn = function(ctx)
      local result = ranker:rank(ctx.input, ctx.items)
      if opts.git_changed_first then
        -- Stable partition after matching: preserve ranking within both groups.
        local changed, other = {}, {}
        for _, item in ipairs(result) do
          local status = item.git_status
          local group = status and status ~= "clean" and status ~= "ignored" and changed
            or other
          group[#group + 1] = item
        end
        return vim.list_extend(changed, other)
      end
      return result
    end,
    format_fn = function(item, ctx)
      if opts.fuzzy_query_highlighting and item._match_query ~= ctx.input then
        item._match_query = ctx.input
        item.matches = ranker:positions(ctx.input, item)
      end
      return ui.format(item, ctx, opts, current_file)
    end,
    on_change = function()
      if session then
        ui.decorate(session, opts, current_file)
      end
    end,
    on_start = function(sess, keyset)
      session = sess
      vim.wo[sess._display.win].signcolumn = "yes:1"
      vim.wo[sess._display.win].winhighlight = vim.wo[sess._display.win].winhighlight
        .. ",SignColumn:"
        .. opts.hl.normal
      actions.bind_open(sess, keyset, keymaps, open)
      sess:render()
    end,
    on_accept = function(selection)
      if #selection == 1 then
        return open(selection[1].item, "edit")
      end
      actions.quickfix(selection, "Selected Files", function(item)
        return { filename = item.path, lnum = 1, col = 1 }
      end)
    end,
  })
end
