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
---@field show_git_status? boolean
---@field hl? table<string,string> fff-style highlight names.
---@field current_file_label? string Default "(current)".
---@field fuzzy_query_highlighting? boolean Default false, like fff.
---@param opts? minibuffer.builtin.FilesOpts
return function(opts)
  require("minibuffer.internal.guard").check()
  assert(vim.fn.executable("rg") == 1, "rg is required for the files picker")
  local cursor_hl = next(vim.api.nvim_get_hl(0, { name = "CursorLine", link = false }))
    and "CursorLine" or "Visual"
  opts = require("minibuffer.builtin.config").resolve(opts, {
    filter = { cwd = true },
    git = { status_text_color = false }, show_git_status = true,
    current_file_label = "(current)", fuzzy_query_highlighting = false,
    matcher = { filename_bonus = true, cwd_bonus = true, frecency = true, history_bonus = false },
    hl = { normal = "NormalFloat", prompt = "Question", cursor = cursor_hl,
      matched = "IncSearch", directory_path = "Comment", selected = "FFFSelected",
      selected_active = "FFFSelectedActive" },
    rg_opts = { "rg", "--files", "--hidden", "--color", "never", "-g", "!.git" },
  })
  for _, name in ipairs({ "filename_first", "show_git_status", "fuzzy_query_highlighting" }) do
    vim.validate(name, opts[name], "boolean")
  end
  for _, name in ipairs({ "filename_bonus", "cwd_bonus", "frecency", "history_bonus" }) do
    vim.validate("matcher." .. name, opts.matcher[name], "boolean")
  end
  vim.validate("git.status_text_color", opts.git.status_text_color, "boolean")
  vim.validate("filter.cwd", opts.filter.cwd, "boolean")
  opts.cwd = vim.fs.normalize(vim.fn.fnamemodify(opts.cwd or vim.fn.getcwd(), ":p"))
  local current_file = vim.fs.normalize(vim.api.nvim_buf_get_name(0))
  local ranker = require("minibuffer.fuzzy").new(vim.tbl_extend("force", opts.matcher, { cwd = opts.cwd }))
  local keymaps = opts.keymaps
  local buffers, recent = {}, vim.deepcopy(vim.v.oldfiles)
  for _, info in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
    if info.name ~= "" and vim.bo[info.bufnr].buftype == "" then buffers[#buffers + 1] = info end
  end
  table.sort(buffers, function(a, b) return a.lastused > b.lastused end)
  local cache, waiting, loading = nil, {}, false
  local function load(cb)
    if cache then return cb(cache) end
    waiting[#waiting + 1] = cb
    if loading then return end
    loading = true
    local remaining, file_output, git_status, failure = 2, "", {}, nil
    local function complete()
      remaining = remaining - 1
      if remaining ~= 0 then return end
      vim.schedule(function()
        local items, seen = {}, {}
        local function add(path, info, is_recent)
          path = vim.fs.normalize(path)
          if seen[path] then return end
          if opts.filter.cwd and not vim.fs.relpath(opts.cwd, path) then return end
          if info or is_recent then
            local stat = vim.uv.fs_stat(path)
            if not stat or stat.type ~= "file" then return end
          end
          seen[path] = true
          local relative = vim.fs.relpath(opts.cwd, path) or path
          relative = relative:gsub("\n", "↵"):gsub("\r", "␍"):gsub("\t", "⇥")
          local directory = vim.fs.dirname(relative) or ""
          if directory == "." then directory = "" end
          local status = git_status[path]
          if not status then
            local parent = vim.fs.dirname(path)
            while parent and parent ~= vim.fs.dirname(parent) do
              status = git_status[parent]
              if status then break end
              parent = vim.fs.dirname(parent)
            end
          end
          local item = {
            path = path, text = relative, relative_path = relative, name = vim.fs.basename(relative),
            directory = directory, git_status = status or "clean", idx = #items + 1,
            info = info, recent = is_recent,
          }
          item.icon, item.icon_hl = ui.icon(item)
          items[#items + 1] = item
        end
        -- Snacks smart combines buffers, recent files and the file finder, in that order.
        for _, info in ipairs(buffers) do add(info.name, info, false) end
        for _, path in ipairs(recent) do add(path, nil, true) end
        for _, path in ipairs(vim.split(file_output, "\0", { plain = true, trimempty = true })) do
          local absolute = path:match("^/") or path:match("^%a:[/\\]")
          add(absolute and path or vim.fs.joinpath(opts.cwd, path))
        end
        ui.prepare(items)
        cache = not failure and items or nil
        loading = false
        local callbacks = waiting
        waiting = {}
        for _, callback in ipairs(callbacks) do callback(cache, failure) end
      end)
    end
    local cmd = vim.list_extend(vim.deepcopy(opts.rg_opts), { "--null" })
    vim.system(cmd, { cwd = opts.cwd }, function(res)
      file_output = res.stdout or ""
      if res.code ~= 0 and res.code ~= 1 then failure = res.stderr or "file scan failed" end
      complete()
    end)
    if opts.show_git_status or opts.git.status_text_color then
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
    vim.cmd(command .. " " .. vim.fn.fnameescape(item.path))
  end
  local session
  return require("minibuffer.builtin.config").select(opts, {
    query = opts.query, resumable = true, prompt = "Files> ", prompt_position = "top",
    multi = true, dynamic_height = false, max_height = 15, keymaps = keymaps,
    highlights = {
      normal = opts.hl.normal, query = opts.hl.normal, prompt = opts.hl.prompt,
      selection = opts.hl.cursor, multi_selection = opts.hl.normal,
    },
    header_position = "bottom",
    header_fn = function(ctx, width)
      return require("minibuffer.builtin.buffers-ui").hints(ctx, {
        split = keymaps.split, vsplit = keymaps.vsplit, delete = {},
        accept = keymaps.accept, toggle = keymaps.toggle, toggle_all = keymaps.toggle_all,
        next = keymaps.next, previous = keymaps.previous,
      }, cache and #cache or 0, math.max(1, width - 2))
    end,
    fetch_fn = function(_, cb) load(cb) end,
    filter_fn = function(ctx)
      local result = ranker:rank(ctx.input, ctx.items)
      for _, item in ipairs(result) do
        item.matches = nil
        if opts.fuzzy_query_highlighting and ctx.input ~= "" then
          local positions = vim.fn.matchfuzzypos({ item.text }, ctx.input)[2][1]
          item.matches = {}
          for _, position in ipairs(positions or {}) do item.matches[position] = true end
        end
      end
      return result
    end,
    format_fn = function(item, ctx) return ui.format(item, ctx, opts, current_file) end,
    on_change = function()
      if session then ui.decorate(session, opts, current_file) end
    end,
    on_start = function(sess, keyset)
      session = sess
      vim.wo[sess._display.win].signcolumn = "yes:1"
      vim.wo[sess._display.win].winhighlight = vim.wo[sess._display.win].winhighlight
        .. ",SignColumn:" .. opts.hl.normal
      for action, command in pairs({ split = "split", vsplit = "vsplit" }) do
        require("minibuffer.builtin.config").bind(keyset, keymaps[action], function()
          local item = sess:get_selected()
          if item then sess:close(function() open(item, command) end) end
        end)
      end
      sess:render()
    end,
    on_accept = function(selection)
      if #selection == 1 then return open(selection[1].item, "edit") end
      local qf = {}
      for _, selected in ipairs(selection) do
        qf[#qf + 1] = { filename = selected.item.path, lnum = 1, col = 1 }
      end
      vim.fn.setqflist({}, " ", { title = "Selected Files", items = qf })
      vim.cmd("copen")
    end,
  })
end
