local M = {}

local state = require("code-review.state")
local utils = require("code-review.utils")
local ui = require("code-review.ui")

--- Add a comment at the current location
---@param context_lines number? Number of context lines
function M.add(context_lines)
  -- Get the current selection context
  local context = utils.get_selection_context(context_lines)

  -- Create namespace for highlighting
  local ns_id = vim.api.nvim_create_namespace("code_review_context")
  local bufnr = vim.api.nvim_get_current_buf()

  -- Clear previous highlights
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)

  -- Highlight the context range (always highlight at least the current line/selection)
  for line = context.line_start - 1, context.line_end - 1 do
    vim.api.nvim_buf_add_highlight(bufnr, ns_id, "Visual", line, 0, -1)
  end

  -- Show input UI and get comment text
  ui.show_comment_input(function(comment_text)
    -- Clear highlights when done
    vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)

    if not comment_text or comment_text == "" then
      return
    end

    -- Create comment data
    local comment_data = {
      file = context.file,
      line_start = context.line_start,
      line_end = context.line_end,
      comment = comment_text,
      context_lines = context.lines,
    }

    -- Add to state
    state.add_comment(comment_data)

    -- Show visual indicator if enabled
    M.update_indicators()

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
  -- Clear signs
  vim.fn.sign_unplace("CodeReviewSigns")

  -- Clear virtual text
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_clear_namespace(buf, vim.api.nvim_create_namespace("CodeReviewVirtualText"), 0, -1)
    end
  end
end

--- Add signs to buffer
---@param bufnr number
---@param comments table[]
add_signs = function(bufnr, comments)
  local config = require("code-review.config").get("ui.signs")

  -- Define sign if not already defined
  vim.fn.sign_define("CodeReviewComment", {
    text = config.text,
    texthl = config.texthl,
    linehl = config.linehl,
    numhl = config.numhl,
  })

  -- Place signs
  for _, comment in ipairs(comments) do
    for line = comment.line_start, comment.line_end do
      vim.fn.sign_place(0, "CodeReviewSigns", "CodeReviewComment", bufnr, { lnum = line, priority = 100 })
    end
  end
end

--- Add virtual text to buffer
---@param bufnr number
---@param comments table[]
add_virtual_text = function(bufnr, comments)
  local config = require("code-review.config").get("ui.virtual_text")
  local ns_id = vim.api.nvim_create_namespace("CodeReviewVirtualText")

  -- Group comments by line for virtual text
  local comments_by_line = {}
  for _, comment in ipairs(comments) do
    -- Only show on first line of range
    local line = comment.line_start
    comments_by_line[line] = comments_by_line[line] or 0
    comments_by_line[line] = comments_by_line[line] + 1
  end

  -- Add virtual text
  for line, count in pairs(comments_by_line) do
    local text = config.prefix
    if count > 1 then
      text = text .. string.format("(%d comments)", count)
    else
      text = text .. "Comment"
    end

    vim.api.nvim_buf_set_extmark(bufnr, ns_id, line - 1, 0, {
      virt_text = { { text, config.hl } },
      virt_text_pos = "eol",
    })
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
