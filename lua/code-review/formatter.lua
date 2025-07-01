local M = {}

local config = require("code-review.config")

--- Format comments to markdown
---@param comments table[]
---@return string
local function format_markdown(comments)
  local lines = {}
  local date_format = config.get("output.date_format")

  -- Header
  table.insert(lines, "# Code Review")
  table.insert(lines, "")
  table.insert(lines, string.format("**Date**: %s", os.date(date_format)))
  table.insert(lines, string.format("**Total Comments**: %d", #comments))
  table.insert(lines, "")

  -- Group comments by file
  local by_file = {}
  for _, comment in ipairs(comments) do
    by_file[comment.file] = by_file[comment.file] or {}
    table.insert(by_file[comment.file], comment)
  end

  -- Sort files
  local files = vim.tbl_keys(by_file)
  table.sort(files)

  -- Format each file's comments
  for _, file in ipairs(files) do
    table.insert(lines, string.format("## %s", file))
    table.insert(lines, "")

    local file_comments = by_file[file]
    -- Sort by line number
    table.sort(file_comments, function(a, b)
      return a.line_start < b.line_start
    end)

    for _, comment in ipairs(file_comments) do
      -- Location header
      if comment.line_start == comment.line_end then
        table.insert(lines, string.format("### Line %d", comment.line_start))
      else
        table.insert(lines, string.format("### Lines %d-%d", comment.line_start, comment.line_end))
      end

      -- Add timestamp
      table.insert(lines, string.format("**Time**: %s", os.date(date_format, comment.timestamp)))
      table.insert(lines, "")

      -- Context code if available
      if comment.context_lines and #comment.context_lines > 0 then
        table.insert(lines, "```")
        for i, line in ipairs(comment.context_lines) do
          local line_num = comment.line_start + i - 1
          table.insert(lines, string.format("%d: %s", line_num, line))
        end
        table.insert(lines, "```")
        table.insert(lines, "")
      end

      -- Comment text
      table.insert(lines, comment.comment)
      table.insert(lines, "")
    end
  end

  return table.concat(lines, "\n")
end

--- Format comments to JSON
---@param comments table[]
---@return string
local function format_json(comments)
  local date_format = config.get("output.date_format")

  local data = {
    date = os.date(date_format),
    comment_count = #comments,
    comments = {},
  }

  -- Sort comments by file and line number
  local sorted_comments = vim.deepcopy(comments)
  table.sort(sorted_comments, function(a, b)
    if a.file ~= b.file then
      return a.file < b.file
    end
    return a.line_start < b.line_start
  end)

  -- Add comments with clean structure
  for _, comment in ipairs(sorted_comments) do
    table.insert(data.comments, {
      id = comment.id,
      file = comment.file,
      line_start = comment.line_start,
      line_end = comment.line_end,
      comment = comment.comment,
      timestamp = comment.timestamp,
      context_lines = comment.context_lines,
    })
  end

  -- Pretty print JSON with indentation
  local json = vim.fn.json_encode(data)
  -- Neovim 0.9+ has built-in JSON formatting
  if vim.fn.exists("*json_decode") == 1 and vim.fn.exists("*json_encode") == 1 then
    local decoded = vim.fn.json_decode(json)
    if decoded then
      -- Re-encode with formatting
      json = vim.json.encode(decoded)
    end
  end
  return json
end

--- Format comments based on output format
---@param comments table[]
---@param format string? 'markdown' or 'json'
---@return string
function M.format(comments, format)
  format = format or config.get("output.format")

  if format == "json" then
    return format_json(comments)
  else
    return format_markdown(comments)
  end
end

--- Parse formatted content back to comments
---@param content string
---@param format string 'markdown' or 'json'
---@return table[] comments
function M.parse(content, format)
  if format == "json" then
    return M.parse_json(content)
  else
    return M.parse_markdown(content)
  end
end

--- Parse JSON content
---@param content string
---@return table[]
function M.parse_json(content)
  local ok, data = pcall(vim.fn.json_decode, content)
  if not ok then
    error("Invalid JSON content")
  end

  if not data.comments then
    error("No comments found in JSON")
  end

  return data.comments
end

--- Parse markdown content
---@param content string
---@return table[]
function M.parse_markdown(content)
  local lines = vim.split(content, "\n")
  local comments = {}
  local current_comment = nil
  local in_code_block = false
  local i = 1

  while i <= #lines do
    local line = lines[i]

    -- Skip empty lines and header
    if line:match("^#%s+Code Review") or line:match("^%*%*Date%*%*:") or line:match("^%*%*Total Comments%*%*:") then
      i = i + 1
      goto continue
    end

    -- File header
    if line:match("^##%s+(.+)") then
      local file = line:match("^##%s+(.+)")
      current_comment = { file = file }
      i = i + 1
      goto continue
    end

    -- Line/Lines header
    if line:match("^###%s+Line[s]?%s+") then
      if current_comment and current_comment.comment then
        -- Save previous comment
        table.insert(comments, current_comment)
      end

      local single = line:match("^###%s+Line%s+(%d+)")
      if single then
        current_comment = {
          file = current_comment and current_comment.file,
          line_start = tonumber(single),
          line_end = tonumber(single),
          context_lines = {},
          comment = "",
        }
      else
        local start, end_ = line:match("^###%s+Lines%s+(%d+)%-(%d+)")
        if start and end_ then
          current_comment = {
            file = current_comment and current_comment.file,
            line_start = tonumber(start),
            line_end = tonumber(end_),
            context_lines = {},
            comment = "",
          }
        end
      end
      i = i + 1
      goto continue
    end

    -- Code block markers
    if line == "```" then
      in_code_block = not in_code_block
      i = i + 1
      goto continue
    end

    -- Inside code block
    if in_code_block and current_comment then
      -- Parse context line (format: "123: code here")
      local num, code = line:match("^(%d+):%s(.*)$")
      if num and code then
        table.insert(current_comment.context_lines, code)
      end
      i = i + 1
      goto continue
    end

    -- Comment text
    if current_comment and not in_code_block and line ~= "" then
      if current_comment.comment == "" then
        current_comment.comment = line
      else
        current_comment.comment = current_comment.comment .. "\n" .. line
      end
    end

    ::continue::
    i = i + 1
  end

  -- Save last comment
  if current_comment and current_comment.comment and current_comment.comment ~= "" then
    table.insert(comments, current_comment)
  end

  -- Restore IDs and timestamps
  for i, comment in ipairs(comments) do
    comment.id = comment.id or (vim.fn.localtime() .. "_" .. i)
    comment.timestamp = comment.timestamp or os.time()
  end

  return comments
end

--- Save formatted content to file
---@param content string
---@param path string?
---@param format string
function M.save_to_file(content, path, format)
  local utils = require("code-review.utils")

  if not path then
    local save_dir = config.get("output.save_dir") or vim.fn.getcwd()
    local filename = utils.generate_filename(format)
    path = vim.fn.fnamemodify(save_dir .. "/" .. filename, ":p")
  else
    path = vim.fn.fnamemodify(path, ":p")
  end

  -- Ensure directory exists
  local dir = vim.fn.fnamemodify(path, ":h")
  vim.fn.mkdir(dir, "p")

  -- Write file
  local file = io.open(path, "w")
  if not file then
    error("Failed to open file: " .. path)
  end

  file:write(content)
  file:close()

  vim.notify("Reviews saved to: " .. path)
end

return M
