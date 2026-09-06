-- Keep fff's row layout, grouping and path shortening without its global picker state.
local M = {}
local files = require("fff.picker_ui.file_renderer")
local icons = require("fff.file_picker.icons")
local names = require("fff.picker_ui.file_name_renderer")

function M.render(sess, config, grep, current_file)
  local buf, win = sess._display.buf, sess._display.win
  local ns = require("minibuffer.internal.state").ns
  local hl = config.hl
  local width = vim.api.nvim_win_get_width(win)
  local name_width = 0
  for _, item in ipairs(sess._items) do
    local icon = icons.get_icon(item.name, item.extension, item.type == "directory")
    local prefix = icon and (icon .. " ") or ""
    name_width = math.max(name_width, vim.fn.strdisplaywidth(prefix .. item.name))
  end
  local count, previous = #sess._items, nil
  if grep then
    for _, item in ipairs(sess._items) do
      if item.relative_path ~= previous then
        count = count + 1
      end
      previous = item.relative_path
    end
  end
  if not sess.dynamic_height then
    count = math.max(count, vim.api.nvim_win_get_height(win))
  end
  local height = math.max(1, math.min(sess.max_height, count))
  local util = require("minibuffer.internal.util")
  util.set_win_height(win, height)
  util.set_win_height(sess._entry.win, height + 2)
  util.set_cmdheight(
    require("minibuffer.internal.state").win_states,
    require("minibuffer.config").dynamic_window_resize,
    height + 2
  )
  local ctx = {
    config = config,
    items = sess._items,
    cursor = sess._current_index,
    win_width = width,
    win_height = vim.api.nvim_win_get_height(win),
    max_path_width = width - 2,
    debug_enabled = config.debug.show_scores,
    prompt_position = config.layout.prompt_position,
    display_start = 1,
    display_end = #sess._items,
    query = sess._input,
  }
  local bottom = ctx.prompt_position == "bottom"
  ctx.iter_start, ctx.iter_end, ctx.iter_step = 1, #ctx.items, 1
  if bottom then
    ctx.iter_start, ctx.iter_end, ctx.iter_step = #ctx.items, 1, -1
  end
  ctx.format_file_display = function(item, available)
    local directory = item.directory or vim.fn.fnamemodify(item.relative_path, ":h")
    if directory == "." then
      directory = ""
    end
    local space = math.max(0, available - vim.fn.strdisplaywidth(item.name) - 1)
    if not config.layout.show_path_first then
      space = math.max(0, ctx.max_path_width - name_width - 3)
    end
    return item.name,
      space == 0 and "" or require("fff.rust").shorten_path(
        directory,
        space,
        config.layout.path_shorten_strategy
      )
  end

  local function name_layout(item, render_ctx, icon)
    local layout = names.build(item, render_ctx, icon)
    if not layout.path_first then
      local prefix = layout.text:sub(1, layout.filename_col + #layout.filename)
      local padding = string.rep(" ", name_width - vim.fn.strdisplaywidth(prefix))
      local separator = padding .. " │ "
      layout.text = prefix .. separator .. layout.dir_path
      layout.dir_col = #prefix + #separator
      layout.dir_end_col = layout.dir_col + #layout.dir_path
    end
    return layout
  end

  local function mark(row, first, last, group, priority)
    if group and group ~= "" and last > first then
      vim.api.nvim_buf_set_extmark(buf, ns, row, first, {
        end_col = last,
        hl_group = group,
        priority = priority or 150,
      })
    end
  end
  local function sign(row, text, group)
    if text and text ~= "" then
      vim.api.nvim_buf_set_extmark(buf, ns, row, 0, {
        sign_text = text,
        sign_hl_group = group or hl.normal,
        priority = 1001,
      })
    end
  end
  local function file_highlights(item, row, line, active)
    local icon, icon_hl =
      icons.get_icon(item.name, item.extension, item.type == "directory")
    local layout = name_layout(item, ctx, icon)
    if not layout.path_first then
      mark(
        row,
        layout.filename_col + #layout.filename,
        layout.dir_col,
        hl.separator or hl.directory_path
      )
    end
    mark(row, 0, #(icon or ""), hl.icon or icon_hl)
    mark(row, layout.dir_col, layout.dir_end_col, hl.directory_path)
    local status = item.git_status or "clean"
    local category = status:match("^staged_") and "staged" or status
    if category == "unknown" then
      category = "untracked"
    end
    if config.show_git_status ~= false then
      local git = require("fff.highlights")
      local char = config.git_status_signs[status]
      if char == nil and git.should_show_git_border(status) then
        char = git.get_git_border_char(status)
      end
      sign(
        row,
        char,
        hl["git_sign_" .. category .. (active and "_selected" or "")]
          or hl["git_sign_" .. category]
      )
      if config.git.status_text_color then
        mark(
          row,
          layout.filename_col,
          layout.filename_col + #layout.filename,
          hl["git_" .. category]
        )
      end
    end
    if current_file == item.path and config.file_picker.current_file_label ~= "" then
      vim.api.nvim_buf_set_extmark(buf, ns, row, 0, {
        virt_text = { { " " .. config.file_picker.current_file_label, "Comment" } },
        virt_text_pos = "right_align",
      })
    end
    if ctx.debug_enabled then
      mark(row, #layout.text, #line:gsub("%s+$", ""), hl.score or hl.frecency)
    end
    if not grep and ctx.query ~= "" then
      if config.file_picker.fuzzy_query_highlighting then
        for _, range in ipairs(item.match_ranges or {}) do
          for _, segment in ipairs(names.fuzzy_segments(item, layout)) do
            local first, last =
              math.max(range[1], segment[1]), math.min(range[2], segment[2])
            mark(
              row,
              segment[3] + first - segment[1],
              segment[3] + last - segment[1],
              hl.matched,
              200
            )
          end
        end
      else
        local first, last = line:find(ctx.query, 1, true)
        if first then
          mark(row, first - 1, last, hl.matched, 200)
        end
      end
    end
  end

  local native = grep and require("fff.picker_ui.grep_renderer") or files
  ctx.renderer = {
    render_line = function(item, render_ctx, index)
      if not grep and item.type == "directory" then
        local icon = icons.get_icon(item.name, item.extension, true)
        return { name_layout(item, render_ctx, icon).text }
      end
      local lines = native.render_line(item, render_ctx, index)
      if not grep or item._has_group_header then
        local icon = icons.get_icon(item.name, item.extension, false)
        local original = names.build(item, render_ctx, icon)
        local layout = name_layout(item, render_ctx, icon)
        lines[1] = layout.text .. lines[1]:sub(#original.text + 1)
      end
      return lines
    end,
    apply_highlights = function(item, _, index, _, _, line_index, line)
      local row, active = line_index - 1, index == ctx.cursor
      if active then
        vim.api.nvim_buf_set_extmark(buf, ns, row, 0, {
          line_hl_group = hl.cursor,
          priority = 100,
        })
      end
      if grep then
        if item._has_group_header then
          file_highlights(
            item,
            row - 1,
            vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1],
            false
          )
        end
        local offset = item._content_offset
        local content = item._trimmed_content or ""
        mark(row, item._match_indent, offset - 2, hl.grep_line_number)
        mark(
          row,
          offset,
          offset + #content,
          item.is_binary_content and "Comment" or hl.content
        )
        if not item.is_binary_content then
          local ts = require("fff.treesitter_hl")
          local lang = ts.lang_from_filename(item.name)
          if lang then
            for _, span in ipairs(ts.get_line_highlights(content, lang)) do
              mark(
                row,
                offset + span.col,
                offset + math.min(span.end_col, #content),
                span.hl_group,
                160
              )
            end
          end
          for _, range in ipairs(item.match_ranges or {}) do
            mark(
              row,
              offset + math.max(0, range[1]),
              offset + math.min(range[2], #content),
              hl.grep_match,
              200
            )
          end
        end
      else
        file_highlights(item, row, line, active)
      end
      if sess:is_selected(index) then
        sign(row, "▊", active and hl.selected_active or hl.selected)
      end
    end,
  }
  vim.wo[win].signcolumn = "yes:1"
  local winhl = hl.winhl
  vim.wo[win].winhighlight = (type(winhl) == "table" and winhl.list)
    or (type(winhl) == "string" and winhl)
    or (
      "Normal:"
      .. hl.normal
      .. ",NormalFloat:"
      .. hl.normal
      .. ",FloatBorder:"
      .. hl.border
    )
  require("fff.picker_ui.list_renderer").render(ctx, buf, win, ns)
  -- SelectSession writes its loading/default rows before on_change on the next render.
  vim.bo[buf].modifiable = true
end

return M
