local M = {}

local state = require("code-review.state")
local utils = require("code-review.utils")
local ui = require("code-review.ui")

-- Create namespaces once at module load
local ns_virtual_text = vim.api.nvim_create_namespace("CodeReviewVirtualText")
local ns_context = vim.api.nvim_create_namespace("code_review_context")

--- Add a comment at the current location
---@param context_lines number? Number of context lines
function M.add(context_lines)
  -- Get the current selection context
  local context = utils.get_selection_context(context_lines)

  -- Create namespace for highlighting
  local bufnr = vim.api.nvim_get_current_buf()

  -- Clear previous highlights
  vim.api.nvim_buf_clear_namespace(bufnr, ns_context, 0, -1)

  -- Highlight the context range (always highlight at least the current line/selection)
  for line = context.line_start - 1, context.line_end - 1 do
    vim.api.nvim_buf_add_highlight(bufnr, ns_context, "Visual", line, 0, -1)
  end

  -- Show input UI and get comment text
  ui.show_comment_input(function(comment_text)
    -- Clear highlights when done
    vim.api.nvim_buf_clear_namespace(bufnr, ns_context, 0, -1)

    if not comment_text or comment_text == "" then
      return
    end

    -- Always create a new comment (new thread)
    local comment_data = {
      file = context.file,
      line_start = context.line_start,
      line_end = context.line_end,
      comment = comment_text,
      context_lines = context.lines,
    }

    -- Add to state (state will handle UI refresh)
    state.add_comment(comment_data)

    -- Copy to clipboard if enabled
    local config = require("code-review.config")
    if config.get("comment.auto_copy_on_add") and comment_data then
      -- Format the comment with full context (like <leader>rs shows)
      local formatted_lines = M.format_as_markdown(comment_data, true, false)
      local formatted_text = table.concat(formatted_lines, "\n")
      utils.copy_to_clipboard(formatted_text)
    end

    vim.notify(
      string.format(
        "Comment added to %s:%d%s",
        context.file,
        context.line_start,
        context.line_start ~= context.line_end and "-" .. context.line_end or ""
      )
    )
  end, context)
end

-- Forward declarations
local add_signs
local add_virtual_text

--- Update visual indicators (signs and virtual text)
function M.update_indicators()
  local config = require("code-review.config")
  local comments = state.get_comments()

  -- Clear existing indicators
  M.clear_indicators()

  -- Group comments by buffer
  local comments_by_buf = {}
  for _, comment in ipairs(comments) do
    local bufnr = vim.fn.bufnr(comment.file)
    if bufnr ~= -1 then
      comments_by_buf[bufnr] = comments_by_buf[bufnr] or {}
      table.insert(comments_by_buf[bufnr], comment)
    end
  end

  -- Add indicators for each buffer
  for bufnr, buf_comments in pairs(comments_by_buf) do
    if config.get("ui.signs.enabled") then
      add_signs(bufnr, buf_comments)
    end
    if config.get("ui.virtual_text.enabled") then
      add_virtual_text(bufnr, buf_comments)
    end
  end
end

--- Clear all indicators
function M.clear_indicators()
  -- Clear signs from all buffers
  -- Using pcall to handle different Neovim versions
  local ok, _ = pcall(vim.fn.sign_unplace, "CodeReviewSigns", {})
  if not ok then
    -- Fallback: clear signs buffer by buffer
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(buf) then
        pcall(vim.fn.sign_unplace, "CodeReviewSigns", { buffer = buf })
      end
    end
  end

  -- Clear virtual text
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_clear_namespace(buf, ns_virtual_text, 0, -1)
    end
  end
end

--- Add signs to buffer
---@param bufnr number
---@param comments table[]
add_signs = function(bufnr, comments)
  local config = require("code-review.config").get("ui.signs")
  
  -- Remove existing signs first
  vim.fn.sign_unplace("CodeReviewSigns", { buffer = bufnr })

  -- Define signs for each status (using same text but different colors)
  vim.fn.sign_define("CodeReviewWaitingReview", {
    text = config.text,
    texthl = "CodeReviewWaitingReview",
    linehl = config.linehl,
    numhl = config.numhl,
  })
  
  vim.fn.sign_define("CodeReviewActionRequired", {
    text = config.text,
    texthl = "CodeReviewActionRequired",
    linehl = config.linehl,
    numhl = config.numhl,
  })
  
  vim.fn.sign_define("CodeReviewResolved", {
    text = config.text,
    texthl = "CodeReviewResolved",
    linehl = config.linehl,
    numhl = config.numhl,
  })
  
  -- Default sign for unknown status
  vim.fn.sign_define("CodeReviewComment", {
    text = config.text,
    texthl = config.texthl,
    linehl = config.linehl,
    numhl = config.numhl,
  })

  -- Group comments by line to determine thread status
  local status_by_line = {}
  for _, comment in ipairs(comments) do
    for line = comment.line_start, comment.line_end do
      -- Determine status based on thread_status or thread info
      local status = comment.thread_status or "open"
      
      -- If resolved thread, mark as resolved
      if comment.thread_id then
        local state = require("code-review.state")
        local thread_data = state.get_all_threads()[comment.thread_id]
        if thread_data and thread_data.status == "resolved" then
          status = "resolved"
        end
      end
      -- Priority: resolved < action-required < waiting-review
      if not status_by_line[line] then
        status_by_line[line] = status
      elseif status == "waiting-review" then
        status_by_line[line] = status
      elseif status == "action-required" and status_by_line[line] ~= "waiting-review" then
        status_by_line[line] = status
      end
    end
  end

  -- Place signs based on status
  for line, status in pairs(status_by_line) do
    local sign_name = "CodeReviewComment"
    if status == "waiting-review" then
      sign_name = "CodeReviewWaitingReview"
    elseif status == "action-required" then
      sign_name = "CodeReviewActionRequired"
    elseif status == "resolved" then
      sign_name = "CodeReviewResolved"
    end
    
    vim.fn.sign_place(0, "CodeReviewSigns", sign_name, bufnr, { lnum = line, priority = 100 })
  end
end

--- Add virtual text to buffer
---@param bufnr number
---@param comments table[]
add_virtual_text = function(bufnr, comments)
  local config = require("code-review.config").get("ui.virtual_text")

  -- Group comments by line and thread for virtual text
  local threads_by_line = {}
  for _, comment in ipairs(comments) do
    -- Only show on first line of range
    local line = comment.line_start
    if not threads_by_line[line] then
      threads_by_line[line] = {}
    end

    -- Group by thread
    local thread_id = comment.thread_id or comment.id
    if not threads_by_line[line][thread_id] then
      threads_by_line[line][thread_id] = {}
    end
    table.insert(threads_by_line[line][thread_id], comment)
  end

  -- Add virtual text
  for line, line_threads in pairs(threads_by_line) do
    local thread_count = vim.tbl_count(line_threads)
    local text = ""
    local highlight = config.hl
    local show_virt_text = true

    if thread_count > 1 then
      -- Multiple threads on same line
      text = config.prefix .. string.format("(%d threads)", thread_count)
    else
      -- Single thread - find the latest comment
      local thread_id, thread_comments = next(line_threads)
      
      -- Determine thread status
      local status = "open"
      if thread_comments[1].thread_status then
        status = thread_comments[1].thread_status
      end
      
      -- Check if thread is resolved
      local state = require("code-review.state")
      local thread_data = state.get_all_threads()[thread_id]
      if thread_data and thread_data.status == "resolved" then
        status = "resolved"
        show_virt_text = false  -- Don't show virtual text for resolved
      end

      if show_virt_text then
        -- Find the latest comment (last in thread)
        local latest_comment = thread_comments[#thread_comments]

        -- If no timestamp, assume comments are in chronological order
        if thread_comments[1].timestamp then
          -- Sort by timestamp to find the latest
          table.sort(thread_comments, function(a, b)
            return (a.timestamp or 0) < (b.timestamp or 0)
          end)
          latest_comment = thread_comments[#thread_comments]
        end
        
        -- Set prefix based on status
        local prefix = config.prefix
        if status == "waiting-review" then
          prefix = "󰇮 "  -- Mail icon for waiting review (Nerd Font)
          highlight = "CodeReviewWaitingReview"
        elseif status == "action-required" then
          prefix = "○ "
          highlight = "CodeReviewActionRequired"
        end
        
        local first_line = latest_comment.comment:match("^[^\n]*") or latest_comment.comment

        -- Truncate if too long
        if #first_line > 40 then
          first_line = first_line:sub(1, 37) .. "..."
        end
        text = prefix .. first_line
      end
    end

    -- Ensure buffer is loaded and line is valid
    if show_virt_text and text ~= "" and vim.api.nvim_buf_is_loaded(bufnr) then
      local line_count = vim.api.nvim_buf_line_count(bufnr)
      if line <= line_count then
        pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_virtual_text, line - 1, 0, {
          virt_text = { { text, highlight } },
          virt_text_pos = "eol",
        })
      end
    end
  end
end

--- Format a single comment as markdown lines
---@param comment_data table The comment object
---@param include_header boolean Whether to include file/line header
---@param use_ansi boolean Whether to use ANSI color codes for fzf
---@return table Lines of formatted markdown
function M.format_as_markdown(comment_data, include_header, use_ansi)
  local lines = {}

  -- ANSI color codes for fzf
  local colors = {
    header = use_ansi and "\x1b[1;34m" or "", -- Bold blue
    section = use_ansi and "\x1b[1;33m" or "", -- Bold yellow
    code = use_ansi and "\x1b[36m" or "", -- Cyan
    reset = use_ansi and "\x1b[0m" or "", -- Reset
  }

  if include_header then
    -- Header with file and line info
    table.insert(
      lines,
      string.format(
        "%s## %s:%d-%d%s",
        colors.header,
        comment_data.file,
        comment_data.line_start,
        comment_data.line_end,
        colors.reset
      )
    )
    table.insert(lines, "")
  end

  -- Code context if available
  if comment_data.context_lines and #comment_data.context_lines > 0 then
    table.insert(lines, colors.section .. "### Context" .. colors.reset)
    table.insert(lines, "")
    table.insert(lines, colors.code .. "```" .. vim.fn.fnamemodify(comment_data.file, ":e"))
    for _, line in ipairs(comment_data.context_lines) do
      table.insert(lines, line)
    end
    table.insert(lines, "```" .. colors.reset)
    table.insert(lines, "")
  end

  -- Comment content
  table.insert(lines, colors.section .. "### Comment" .. colors.reset)
  table.insert(lines, "")
  -- Split comment by lines and add each line
  for line in comment_data.comment:gmatch("[^\n]+") do
    table.insert(lines, line)
  end

  return lines
end

return M
