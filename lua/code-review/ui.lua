local M = {}

local config = require("code-review.config")

--- Show generic input window
---@param opts table Options: title, on_submit, initial_text
function M.get_input(opts)
  opts = opts or {}
  local conf = config.get("ui.input_window")

  -- Create buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(buf, "filetype", "markdown")
  vim.api.nvim_buf_set_option(buf, "wrap", true)
  vim.api.nvim_buf_set_option(buf, "linebreak", true)
  vim.api.nvim_buf_set_option(buf, "breakindent", true)

  -- Set initial text if provided
  if opts.initial_text then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(opts.initial_text, "\n"))
  end

  -- Calculate window size and position
  local width = conf.width
  local height = conf.height or 10

  -- Create window centered
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = height,
    style = "minimal",
    border = conf.border,
    title = opts.title or "Input",
    title_pos = "center",
  })

  -- Setup keymaps
  local function submit()
    -- Leave insert mode before closing
    if vim.fn.mode() == "i" then
      vim.cmd("stopinsert")
    end
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local text = table.concat(lines, "\n")
    vim.api.nvim_win_close(win, true)
    if opts.on_submit then
      opts.on_submit(text)
    end
  end

  local function cancel()
    -- Leave insert mode before closing
    if vim.fn.mode() == "i" then
      vim.cmd("stopinsert")
    end
    vim.api.nvim_win_close(win, true)
    if opts.on_cancel then
      opts.on_cancel()
    end
  end

  -- Buffer-local keymaps
  vim.keymap.set("n", "<CR>", submit, { buffer = buf, nowait = true })
  vim.keymap.set("n", "<C-CR>", submit, { buffer = buf, nowait = true })
  vim.keymap.set("n", "q", cancel, { buffer = buf, nowait = true })
  vim.keymap.set("n", "<Esc>", cancel, { buffer = buf, nowait = true })
  vim.keymap.set("i", "<C-CR>", submit, { buffer = buf, nowait = true })
  vim.keymap.set("i", "<C-c>", cancel, { buffer = buf, nowait = true })

  -- Start in insert mode
  vim.cmd("startinsert")
end

--- Select from a list of comments
---@param comments table[] List of comments
---@param callback function(comment?) Called with selected comment or nil
function M.select_comment(comments, callback)
  if #comments == 0 then
    callback(nil)
    return
  end

  local items = {}
  for i, comment in ipairs(comments) do
    local preview = comment.comment:sub(1, 50)
    if #comment.comment > 50 then
      preview = preview .. "..."
    end
    table.insert(items, string.format("%d. %s", i, preview))
  end

  vim.ui.select(items, {
    prompt = "Select comment:",
  }, function(choice, idx)
    if choice and idx then
      callback(comments[idx])
    else
      callback(nil)
    end
  end)
end

--- Show comment input window
---@param callback function(string?) Called with the comment text or nil if cancelled
---@param context table? Optional context with line_start and line_end
---@param title string? Optional window title (defaults to config)
function M.show_comment_input(callback, context, title)
  local conf = config.get("ui.input_window")

  -- Create buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(buf, "filetype", "markdown")
  -- Enable word wrap
  vim.api.nvim_buf_set_option(buf, "wrap", true)
  vim.api.nvim_buf_set_option(buf, "linebreak", true)
  vim.api.nvim_buf_set_option(buf, "breakindent", true)
  -- Set unique buffer name for identification
  vim.api.nvim_buf_set_name(buf, string.format("codereview://input/%d", buf))

  -- Variables to track window and dynamic height
  local win
  local current_height = conf.height

  -- Get cursor and window info
  local win_id = vim.api.nvim_get_current_win()
  local cursor = vim.api.nvim_win_get_cursor(win_id)
  local win_height = vim.api.nvim_win_get_height(win_id)
  local win_row = vim.fn.winline()

  -- Get selection range to position below it
  local mode = vim.fn.mode()
  local target_line = cursor[1]

  if context and context.line_end then
    -- Use context end line if provided
    target_line = context.line_end
  elseif mode:match("[vV]") then
    -- In visual mode, get the end of selection
    local _, _, end_line, _ = require("code-review.utils").get_visual_range()
    target_line = end_line
  end

  -- Calculate window size and position
  local width = conf.width
  local height = current_height

  -- Calculate absolute position
  local screen_row = win_row + (target_line - cursor[1]) + 1 -- +1 for basic UI (less space needed)

  -- Adjust if popup would go off screen
  if screen_row + height > win_height then
    -- Show above the selection instead
    screen_row = win_row + (target_line - cursor[1]) - height - 1
  end

  -- Create window
  win = vim.api.nvim_open_win(buf, true, {
    relative = "win",
    row = screen_row - 1, -- Convert to 0-indexed
    col = vim.fn.wincol() - 1,
    width = width,
    height = height,
    style = "minimal",
    border = conf.border,
    title = title or conf.title,
    title_pos = conf.title_pos,
  })

  -- Ensure wrap options are set for the window
  vim.api.nvim_win_set_option(win, "wrap", true)
  vim.api.nvim_win_set_option(win, "linebreak", true)

  -- Setup keymaps
  local function close_with_text()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local text = table.concat(lines, "\n")
    -- Leave insert mode before closing
    if vim.fn.mode() == "i" then
      vim.cmd("stopinsert")
    end
    vim.api.nvim_win_close(win, true)
    callback(text)
  end

  local function close_cancelled()
    -- Leave insert mode before closing
    if vim.fn.mode() == "i" then
      vim.cmd("stopinsert")
    end
    vim.api.nvim_win_close(win, true)
    callback(nil)
  end

  -- Normal mode mappings
  vim.api.nvim_buf_set_keymap(buf, "n", "<C-CR>", "", {
    noremap = true,
    callback = close_with_text,
  })

  vim.api.nvim_buf_set_keymap(buf, "n", "<Esc>", "", {
    noremap = true,
    callback = close_cancelled,
  })

  vim.api.nvim_buf_set_keymap(buf, "n", "q", "", {
    noremap = true,
    callback = close_cancelled,
  })

  -- Insert mode mappings
  vim.api.nvim_buf_set_keymap(buf, "i", "<C-CR>", "", {
    noremap = true,
    callback = close_with_text,
  })

  -- Function to adjust window height based on content
  local function adjust_window_height()
    if not vim.api.nvim_win_is_valid(win) then
      return
    end

    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    -- Get actual line count from buffer (includes empty lines)
    local line_count = vim.api.nvim_buf_line_count(buf)

    -- Account for wrapped lines
    local total_lines = 0
    for i = 1, line_count do
      local line = lines[i] or ""
      local line_width = vim.fn.strdisplaywidth(line)
      local wrapped_lines = math.max(1, math.ceil(line_width / width))
      total_lines = total_lines + wrapped_lines
    end

    -- Calculate new height (minimum conf.height, maximum conf.max_height)
    local max_height = conf.max_height or 20
    local new_height = math.max(conf.height, math.min(total_lines, max_height))

    -- Update window height if changed
    if new_height ~= current_height then
      current_height = new_height
      -- Save cursor position before resizing
      local cursor_pos = vim.api.nvim_win_get_cursor(win)
      vim.api.nvim_win_set_config(win, {
        height = new_height,
      })
      -- Ensure first line is visible after resize
      if cursor_pos[1] > 1 then
        vim.api.nvim_win_set_cursor(win, { 1, 0 })
        vim.api.nvim_win_set_cursor(win, cursor_pos)
      end
    end
  end

  -- Set up autocmd to adjust height on text change
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "InsertEnter", "InsertLeave" }, {
    buffer = buf,
    callback = adjust_window_height,
  })

  -- Also trigger on cursor movement in insert mode to catch new lines immediately
  vim.api.nvim_buf_set_keymap(buf, "i", "<CR>", "", {
    noremap = true,
    callback = function()
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "n", false)
      vim.schedule(adjust_window_height)
    end,
  })

  -- Initial adjustment
  adjust_window_height()

  -- Store callback functions for external access
  vim.b[buf]._code_review_submit = close_with_text
  vim.b[buf]._code_review_cancel = close_cancelled

  -- Trigger User event after everything is set up
  vim.api.nvim_exec_autocmds("User", {
    pattern = "CodeReviewInputEnter",
    data = { buf = buf, win = win },
  })

  -- Start in insert mode
  vim.cmd("startinsert")
end

--- Show preview window
---@param content string The formatted content
---@param format string Deprecated, always uses markdown
function M.show_preview(content, format)
  local conf = config.get("ui.preview")
  local buf

  -- Create split
  if conf.split == "vertical" then
    -- Create new buffer for the split
    buf = vim.api.nvim_create_buf(false, true)
    vim.cmd(string.format("vsplit | vertical resize %d", conf.vertical_width))
    vim.api.nvim_win_set_buf(0, buf)
  elseif conf.split == "horizontal" then
    -- Create new buffer for the split
    buf = vim.api.nvim_create_buf(false, true)
    vim.cmd(string.format("split | resize %d", conf.horizontal_height))
    vim.api.nvim_win_set_buf(0, buf)
  else
    -- Float window
    buf = vim.api.nvim_create_buf(false, true)
    local float_conf = conf.float
    local width = math.floor(vim.o.columns * float_conf.width)
    local height = math.floor(vim.o.lines * float_conf.height)
    local row = math.floor((vim.o.lines - height) / 2)
    local col = math.floor((vim.o.columns - width) / 2)

    vim.api.nvim_open_win(buf, true, {
      relative = "editor",
      row = row,
      col = col,
      width = width,
      height = height,
      style = "minimal",
      border = float_conf.border,
      title = float_conf.title,
      title_pos = float_conf.title_pos,
    })
  end

  -- Set buffer content and options
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(content, "\n"))
  vim.api.nvim_buf_set_option(buf, "filetype", "markdown")
  vim.api.nvim_buf_set_option(buf, "buftype", "acwrite")
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
  -- Set unique buffer name for identification
  vim.api.nvim_buf_set_name(buf, string.format("codereview://preview/%d", buf))
  -- Trigger User event
  vim.api.nvim_exec_autocmds("User", {
    pattern = "CodeReviewPreviewEnter",
    data = { buf = buf },
  })
  -- Mark as not modified after setting content
  vim.api.nvim_buf_set_option(buf, "modified", false)

  -- Add keymap to close with q
  vim.api.nvim_buf_set_keymap(buf, "n", "q", "<cmd>close<CR>", {
    noremap = true,
    silent = true,
    desc = "Close preview",
  })

  -- Save handler
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf,
    callback = function()
      M.handle_preview_save(buf)
      vim.api.nvim_buf_set_option(buf, "modified", false)
    end,
  })
end

--- Handle saving preview buffer
---@param bufnr number
function M.handle_preview_save(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local content = table.concat(lines, "\n")

  -- Parse content back to comments
  local formatter = require("code-review.formatter")
  local success, comments = pcall(formatter.parse, content)

  if not success then
    vim.notify("Failed to parse preview content: " .. tostring(comments), vim.log.levels.ERROR)
    return
  end

  -- Update state
  local state = require("code-review.state")
  state.replace_comments(comments)

  vim.notify("Reviews updated from preview")
end

--- Show comment list in floating window
---@param comments table[] List of comments to show
function M.show_comment_list(comments)
  local lines = {}

  -- Group comments by thread
  local threads = {}
  for _, comment in ipairs(comments) do
    local thread_id = comment.thread_id or comment.id
    if not threads[thread_id] then
      threads[thread_id] = {}
    end
    table.insert(threads[thread_id], comment)
  end

  -- Sort comments within each thread by timestamp
  for _, thread_comments in pairs(threads) do
    table.sort(thread_comments, function(a, b)
      return (a.timestamp or 0) < (b.timestamp or 0)
    end)
  end

  -- Format each thread as in storage format (## Comments section only)
  local first_thread = true
  for _, thread_comments in pairs(threads) do
    if not first_thread then
      table.insert(lines, "")
      table.insert(lines, "---")
      table.insert(lines, "")
    end
    first_thread = false

    -- Add thread comments in the same format as the file (without ## Comments header)
    for i, comment in ipairs(thread_comments) do
      if i > 1 then
        table.insert(lines, "")
        table.insert(lines, "---")
        table.insert(lines, "")
      end

      -- Comment metadata
      local cfg = require("code-review.config")
      local date_format = cfg.get("output.date_format")
      table.insert(
        lines,
        "### " .. (comment.author or vim.fn.expand("$USER")) .. " - " .. os.date(date_format, comment.timestamp)
      )
      table.insert(lines, "")

      -- Comment content (split by lines to avoid newline issues)
      for line in comment.comment:gmatch("[^\n]+") do
        table.insert(lines, line)
      end
    end
  end

  -- Calculate window size
  local width = 80
  local height = math.min(#lines + 2, 20)

  -- Create buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(buf, "filetype", "markdown")
  -- Set unique buffer name for identification
  vim.api.nvim_buf_set_name(buf, string.format("codereview://comments/%d", buf))
  -- Trigger User event
  vim.api.nvim_exec_autocmds("User", {
    pattern = "CodeReviewCommentsEnter",
    data = { buf = buf },
  })

  -- Get cursor position
  local cursor = vim.api.nvim_win_get_cursor(0)
  local win_height = vim.api.nvim_win_get_height(0)

  -- Calculate position
  local row_offset = 1
  if cursor[1] + height + row_offset > win_height then
    row_offset = -(height + 1)
  end

  -- Create window
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "cursor",
    row = row_offset,
    col = 0,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " Review Comments ",
    title_pos = "center",
  })
  
  -- Enable word wrap in the floating window
  vim.api.nvim_win_set_option(win, "wrap", true)
  vim.api.nvim_win_set_option(win, "linebreak", true)

  -- Setup keymaps
  vim.api.nvim_buf_set_keymap(buf, "n", "q", "<cmd>close<CR>", {
    noremap = true,
    silent = true,
    desc = "Close comment window",
  })

  vim.api.nvim_buf_set_keymap(buf, "n", "<Esc>", "<cmd>close<CR>", {
    noremap = true,
    silent = true,
    desc = "Close comment window",
  })
end

return M
