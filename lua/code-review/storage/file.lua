local M = {}

local utils = require("code-review.utils")

local storage_dir = nil
local comments_cache = nil
local cache_timestamp = 0

--- Get storage directory
---@return string
local function get_storage_dir()
  if storage_dir then
    return storage_dir
  end

  local config = require("code-review.config")
  local dir = config.get("comment.storage.file.dir") or ".code-review"
  storage_dir = utils.get_storage_dir(dir)
  return storage_dir
end

--- Generate filename for a comment
---@param comment_data table
---@return string
local function get_comment_filename(comment_data)
  if comment_data.id then
    -- Use existing ID for filename
    return comment_data.id .. ".md"
  else
    -- Generate new filename
    return utils.generate_auto_save_filename()
  end
end

--- Parse comment from file content
---@param content string
---@param filename string
---@return table|nil
local function parse_comment_from_file(content, filename)
  -- Extract ID from filename
  local id = filename:match("^(.+)%.md$")
  if not id then
    return nil
  end

  -- Parse the markdown content
  local comment_data = {
    id = id,
    file = "",
    line_start = 0,
    line_end = 0,
    comment = "",
    context_lines = {},
    timestamp = 0,
  }

  -- Simple parser for our markdown format
  local lines = vim.split(content, "\n", { plain = true })
  local state = "header"
  local context_lines = {}
  local comment_lines = {}

  for _, line in ipairs(lines) do
    if state == "header" and line:match("^## (.+):(%d+)-(%d+)$") then
      local file, start_line, end_line = line:match("^## (.+):(%d+)-(%d+)$")
      comment_data.file = file
      comment_data.line_start = tonumber(start_line)
      comment_data.line_end = tonumber(end_line)
    elseif state == "header" and line:match("^%*%*Time%*%*: (.+)$") then
      -- Try to parse timestamp (this is simplified, might need better parsing)
      comment_data.timestamp = os.time()
    elseif line == "### Context" then
      state = "context"
    elseif line == "### Comment" then
      state = "comment"
    elseif state == "context" and not line:match("^```") and not line:match("^###") then
      table.insert(context_lines, line)
    elseif state == "comment" and line ~= "" then
      table.insert(comment_lines, line)
    end
  end

  comment_data.context_lines = context_lines
  comment_data.comment = table.concat(comment_lines, "\n")

  return comment_data
end

--- Load all comments from storage directory
---@return table[]
local function load_comments()
  local dir = get_storage_dir()

  -- Check if directory exists
  if vim.fn.isdirectory(dir) == 0 then
    return {}
  end

  -- Check cache validity
  local dir_mtime = vim.fn.getftime(dir)
  if comments_cache and dir_mtime <= cache_timestamp then
    return comments_cache
  end

  local comments = {}

  -- Read all .md files in the directory
  local files = vim.fn.glob(dir .. "/*.md", false, true)
  for _, filepath in ipairs(files) do
    local content = vim.fn.readfile(filepath)
    if #content > 0 then
      local filename = vim.fn.fnamemodify(filepath, ":t")
      local comment_data = parse_comment_from_file(table.concat(content, "\n"), filename)
      if comment_data then
        table.insert(comments, comment_data)
      end
    end
  end

  -- Update cache
  comments_cache = comments
  cache_timestamp = dir_mtime

  return comments
end

--- Invalidate cache
local function invalidate_cache()
  comments_cache = nil
  cache_timestamp = 0
end

--- Initialize storage
function M.init()
  -- Ensure storage directory exists
  local dir = get_storage_dir()
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, "p")
  end
end

--- Check if storage is active
---@return boolean
function M.is_active()
  return true -- File storage is always active once initialized
end

--- Add a comment
---@param comment_data table
---@return string id
function M.add(comment_data)
  -- Add metadata
  comment_data.timestamp = comment_data.timestamp or os.time()

  local dir = get_storage_dir()
  local filename = get_comment_filename(comment_data)
  comment_data.id = filename:match("^(.+)%.md$")

  local filepath = dir .. "/" .. filename

  -- Format the comment with full context
  -- We need to format it ourselves to avoid circular dependency
  local formatted_text = M.format_comment_as_markdown(comment_data)

  if utils.save_to_file(filepath, formatted_text) then
    invalidate_cache()
    return comment_data.id
  else
    error("Failed to save comment to file")
  end
end

--- Get all comments
---@return table[]
function M.get_all()
  return load_comments()
end

--- Get a specific comment by ID
---@param id string
---@return table|nil
function M.get(id)
  local comments = load_comments()
  for _, comment in ipairs(comments) do
    if comment.id == id then
      return vim.deepcopy(comment)
    end
  end
  return nil
end

--- Delete a comment by ID
---@param id string
---@return boolean success
function M.delete(id)
  local dir = get_storage_dir()
  local filepath = dir .. "/" .. id .. ".md"

  if vim.fn.filereadable(filepath) == 1 then
    vim.fn.delete(filepath)
    invalidate_cache()
    return true
  end

  return false
end

--- Clear all comments
function M.clear()
  local dir = get_storage_dir()
  local files = vim.fn.glob(dir .. "/*.md", false, true)

  for _, filepath in ipairs(files) do
    vim.fn.delete(filepath)
  end

  invalidate_cache()
end

--- Get comments for a specific file and line range
---@param file string
---@param line number
---@return table[]
function M.get_at_location(file, line)
  local results = {}
  local comments = load_comments()

  for _, comment in ipairs(comments) do
    if comment.file == file and line >= comment.line_start and line <= comment.line_end then
      table.insert(results, vim.deepcopy(comment))
    end
  end

  return results
end

--- Format a comment as markdown (simplified version to avoid circular dependency)
---@param comment_data table
---@return string
function M.format_comment_as_markdown(comment_data)
  local lines = {}
  local config = require("code-review.config")
  local date_format = config.get("output.date_format")

  -- Header with file and line info
  table.insert(lines, string.format("## %s:%d-%d", comment_data.file, comment_data.line_start, comment_data.line_end))
  table.insert(lines, "")

  -- Timestamp
  table.insert(lines, string.format("**Time**: %s", os.date(date_format, comment_data.timestamp)))
  table.insert(lines, "")

  -- Code context if available
  if comment_data.context_lines and #comment_data.context_lines > 0 then
    table.insert(lines, "### Context")
    table.insert(lines, "")
    table.insert(lines, "```" .. vim.fn.fnamemodify(comment_data.file, ":e"))
    for _, line in ipairs(comment_data.context_lines) do
      table.insert(lines, line)
    end
    table.insert(lines, "```")
    table.insert(lines, "")
  end

  -- Comment content
  table.insert(lines, "### Comment")
  table.insert(lines, "")
  table.insert(lines, comment_data.comment)

  return table.concat(lines, "\n")
end

return M
