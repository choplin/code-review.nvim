local M = {}

local utils = require("code-review.utils")

local storage_dir = nil
local comments_cache = nil
local cache_timestamp = 0

--- Parse timestamp from frontmatter format
---@param time_str string? Timestamp string
---@return number? timestamp
local function parse_timestamp_from_frontmatter(time_str)
  if not time_str then
    return nil
  end

  -- Try to parse "2025-07-08 10:43:54" format
  local year, month, day, hour, min, sec = time_str:match("(%d+)%-(%d+)%-(%d+) (%d+):(%d+):(%d+)")
  if year then
    return os.time({
      year = tonumber(year),
      month = tonumber(month),
      day = tonumber(day),
      hour = tonumber(hour),
      min = tonumber(min),
      sec = tonumber(sec),
    })
  end

  return nil
end

--- Parse status from filename
---@param filename string
---@return string status, string id
local function parse_filename(filename)
  -- Pattern: status_timestamp_thread.md
  local status, id = filename:match("^([^_]+)_(.+)%.md$")
  if status and id then
    return status, id
  end
  
  -- Legacy format: timestamp_thread.md
  local legacy_id = filename:match("^(.+)%.md$")
  if legacy_id then
    return "action-required", legacy_id
  end
  
  return nil, nil
end

--- Generate filename with status
---@param id string
---@param status string
---@return string
local function make_filename(id, status)
  return status .. "_" .. id .. ".md"
end

--- Determine thread status based on latest author
---@param thread_comments table[]
---@return string status
local function determine_thread_status(thread_comments)
  if #thread_comments == 0 then
    return "action-required"
  end
  
  -- Get the latest comment
  local latest_comment = thread_comments[#thread_comments]
  local config = require("code-review.config")
  local claude_code_author = config.get("comment.claude_code_author")
  
  -- If latest author is Claude Code, status is "waiting-review"
  -- Otherwise, status is "action-required"
  if latest_comment.author == claude_code_author then
    return "waiting-review"
  else
    return "action-required"
  end
end

--- Get storage directory
---@return string
local function get_storage_dir()
  if storage_dir then
    return storage_dir
  end

  local config = require("code-review.config")
  local dir = config.get("comment.storage.file.dir")
  storage_dir = utils.get_storage_dir(dir)
  return storage_dir
end

--- Generate filename for a comment
---@param comment_data table
---@param status string? Optional status override
---@return string
local function get_comment_filename(comment_data, status)
  local id
  if comment_data.id then
    -- Extract ID from existing filename if needed
    local _, parsed_id = parse_filename(comment_data.id .. ".md")
    id = parsed_id or comment_data.id
  else
    -- Generate new ID
    local filename = utils.generate_auto_save_filename()
    id = filename:match("^(.+)%.md$")
  end
  
  -- Default status for new comments is "action-required"
  status = status or "action-required"
  return make_filename(id, status)
end

--- Parse comment from file content
---@param content string
---@param filename string
---@return table[] comments
local function parse_comment_from_file(content, filename)
  -- Parse status and ID from filename
  local status, base_id = parse_filename(filename)
  if not base_id then
    -- Fallback for legacy format
    base_id = filename:match("^(.+)%.md$")
    if not base_id then
      return {}
    end
  end

  local lines = vim.split(content, "\n", { plain = true })
  local state = "start"
  local frontmatter = {}
  local context_lines = {}
  local in_context_code = false
  local comments = {}

  -- Variables for parsing multiple comments
  local current_comment = nil
  local current_comment_lines = {}
  local in_comments_section = false

  for _, line in ipairs(lines) do
    if state == "start" and line == "---" then
      state = "frontmatter"
    elseif state == "frontmatter" and line == "---" then
      state = "content"
    elseif state == "frontmatter" then
      -- Parse YAML line
      local key, value = line:match("^([^:]+):%s*(.+)$")
      if key and value then
        frontmatter[key] = value
      end
    elseif state == "content" then
      if line == "## Context" then
        state = "context"
      elseif line == "## Comment" then
        -- Old single-comment format
        state = "comment"
      elseif line == "## Comments" then
        -- New multi-comment format
        state = "comments"
        in_comments_section = true
      end
    elseif state == "context" then
      if line == "## Comment" or line == "## Comments" then
        state = line == "## Comment" and "comment" or "comments"
        in_comments_section = line == "## Comments"
      elseif line:match("^```") then
        in_context_code = not in_context_code
      elseif in_context_code then
        table.insert(context_lines, line)
      end
    elseif state == "comment" then
      -- Old format: single comment
      table.insert(current_comment_lines, line)
    elseif state == "comments" then
      -- New format: multiple comments
      if line:match("^### ") then
        -- Save previous comment if exists
        if current_comment and #current_comment_lines > 0 then
          current_comment.comment = vim.trim(table.concat(current_comment_lines, "\n"))
          table.insert(comments, current_comment)
          current_comment_lines = {}
        end

        -- Parse comment header: "### Author - Timestamp"
        local header = line:sub(5) -- Remove "### "
        local author, timestamp_str = header:match("^(.+) %- (.+)$")
        local parsed_author = author or vim.fn.expand("$USER")

        -- Parse timestamp from string (format: "2025-07-08 10:43:54")
        local parsed_timestamp
        if timestamp_str then
          local year, month, day, hour, min, sec = timestamp_str:match("(%d+)%-(%d+)%-(%d+) (%d+):(%d+):(%d+)")
          if year then
            parsed_timestamp = os.time({
              year = tonumber(year),
              month = tonumber(month),
              day = tonumber(day),
              hour = tonumber(hour),
              min = tonumber(min),
              sec = tonumber(sec),
            })
          else
            parsed_timestamp = os.time()
          end
        else
          parsed_timestamp = os.time()
        end

        -- Start new comment
        current_comment = {
          id = base_id .. "_comment_" .. #comments,
          file = frontmatter.file or "",
          line_start = tonumber(frontmatter.line_start) or 0,
          line_end = tonumber(frontmatter.line_end) or 0,
          author = parsed_author,
          timestamp = parsed_timestamp,
          context_lines = context_lines,
          thread_id = frontmatter.thread_id,
          -- Status is now derived from filename
        }
      elseif line == "---" and in_comments_section then -- luacheck: ignore 542
        -- Comment separator, ignore
      elseif line == "" and not current_comment then -- luacheck: ignore 542
        -- Empty line before first comment, ignore
      else
        -- Comment content
        table.insert(current_comment_lines, line)
      end
    end
  end

  -- Handle last comment or old format
  if state == "comment" or (current_comment and #current_comment_lines > 0) then
    if state == "comment" then
      -- Old single-comment format
      local comment_data = {
        id = base_id,
        file = frontmatter.file or "",
        line_start = tonumber(frontmatter.line_start) or 0,
        line_end = tonumber(frontmatter.line_end) or 0,
        comment = table.concat(current_comment_lines, "\n"),
        context_lines = context_lines,
        timestamp = parse_timestamp_from_frontmatter(frontmatter.time) or os.time(),
        author = frontmatter.author,
        thread_id = frontmatter.thread_id,
        -- Removed: parent_id, thread_status, resolved_by, resolved_at
      }
      return { comment_data }
    else
      -- Save last comment in multi-comment format
      current_comment.comment = vim.trim(table.concat(current_comment_lines, "\n"))
      table.insert(comments, current_comment)
    end
  end

  -- For multi-comment format, ensure root comment has correct ID
  if #comments > 0 and comments[1] and not comments[1].parent_id then
    comments[1].id = base_id
  end

  return comments
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
    -- Use io.open to preserve trailing newlines
    local file = io.open(filepath, "r")
    if file then
      local content = file:read("*a")
      file:close()

      if content and #content > 0 then
        local filename = vim.fn.fnamemodify(filepath, ":t")
        local parsed_comments = parse_comment_from_file(content, filename)
        -- parse_comment_from_file now returns an array of comments
        for _, comment_data in ipairs(parsed_comments) do
          table.insert(comments, comment_data)
        end
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

  -- Migrate comments from comments/ subdirectory back to root
  local comments_dir = dir .. "/comments"
  if vim.fn.isdirectory(comments_dir) == 1 then
    local comment_files = vim.fn.glob(comments_dir .. "/*.md", false, true)
    for _, filepath in ipairs(comment_files) do
      local filename = vim.fn.fnamemodify(filepath, ":t")
      local new_filepath = dir .. "/" .. filename
      -- Move file to root directory
      if vim.fn.filereadable(new_filepath) == 0 then
        vim.fn.rename(filepath, new_filepath)
      end
    end
    -- Remove empty comments directory
    vim.fn.delete(comments_dir, "d")
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

  -- If this is a reply, update the root comment's file instead
  if comment_data.parent_id and comment_data.thread_id then
    -- Find the root comment of this thread
    local comments = load_comments()
    local root_comment = nil

    for _, comment in ipairs(comments) do
      if comment.thread_id == comment_data.thread_id and not comment.parent_id then
        root_comment = comment
        break
      elseif not comment.parent_id and comment.id .. "_thread" == comment_data.thread_id then
        -- Fallback: check if comment ID + "_thread" matches thread_id
        root_comment = comment
        break
      end
    end

    if root_comment then
      -- Get all comments in this thread
      local thread_comments = {}
      for _, comment in ipairs(comments) do
        if comment.thread_id == comment_data.thread_id then
          table.insert(thread_comments, comment)
        end
      end

      -- Add the new reply
      table.insert(thread_comments, comment_data)

      -- Sort by timestamp to maintain chronological order
      table.sort(thread_comments, function(a, b)
        return (a.timestamp or 0) < (b.timestamp or 0)
      end)

      -- Determine new status based on latest author
      local new_status = determine_thread_status(thread_comments)
      
      -- Get current filename from existing file
      local old_files = vim.fn.glob(get_storage_dir() .. "/*_" .. root_comment.id .. ".md", false, true)
      local old_filepath = old_files[1]
      
      -- Generate new filename with updated status
      local new_filename = make_filename(root_comment.id, new_status)
      local new_filepath = get_storage_dir() .. "/" .. new_filename
      
      -- Format content
      local formatted_text = M.format_thread_as_markdown(thread_comments)
      
      -- If filename needs to change, delete old file first
      if old_filepath and old_filepath ~= new_filepath then
        vim.fn.delete(old_filepath)
      end
      
      -- Save to new/same file
      if utils.save_to_file(new_filepath, formatted_text) then
        invalidate_cache()
        return comment_data.id
      else
        error("Failed to save reply to file")
      end
    end
  end

  -- For new comments (not replies), create a new file
  local dir = get_storage_dir()
  local filename = get_comment_filename(comment_data)
  -- Extract ID without status prefix
  local _, id = parse_filename(filename)
  comment_data.id = id or filename:match("^(.+)%.md$")

  local filepath = dir .. "/" .. filename

  -- Format the comment with full context
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
  
  -- Find file with any status prefix
  local files = vim.fn.glob(dir .. "/*_" .. id .. ".md", false, true)
  if #files > 0 then
    vim.fn.delete(files[1])
    invalidate_cache()
    return true
  end
  
  -- Fallback for legacy format
  local legacy_filepath = dir .. "/" .. id .. ".md"
  if vim.fn.filereadable(legacy_filepath) == 1 then
    vim.fn.delete(legacy_filepath)
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

  -- YAML frontmatter
  table.insert(lines, "---")
  table.insert(lines, "file: " .. comment_data.file)
  table.insert(lines, "line_start: " .. comment_data.line_start)
  table.insert(lines, "line_end: " .. comment_data.line_end)
  table.insert(lines, "time: " .. os.date(date_format, comment_data.timestamp))

  if comment_data.author then
    table.insert(lines, "author: " .. comment_data.author)
  end

  if comment_data.thread_id then
    table.insert(lines, "thread_id: " .. comment_data.thread_id)
  end
  
  -- Removed: parent_id, thread_status, resolved_by, resolved_at
  -- Status is now derived from filename

  table.insert(lines, "---")
  table.insert(lines, "")

  -- Code context if available
  if comment_data.context_lines and #comment_data.context_lines > 0 then
    table.insert(lines, "## Context")
    table.insert(lines, "")
    table.insert(lines, "```" .. vim.fn.fnamemodify(comment_data.file, ":e"))
    for _, line in ipairs(comment_data.context_lines) do
      table.insert(lines, line)
    end
    table.insert(lines, "```")
    table.insert(lines, "")
  end

  -- Comments section (even for single comment, use consistent format)
  table.insert(lines, "## Comments")
  table.insert(lines, "")
  table.insert(
    lines,
    "### " .. (comment_data.author or vim.fn.expand("$USER")) .. " - " .. os.date(date_format, comment_data.timestamp)
  )
  table.insert(lines, "")
  table.insert(lines, comment_data.comment)

  return table.concat(lines, "\n")
end

--- Get thread information from comments
---@param thread_id string
---@return table|nil
function M.get_thread(thread_id)
  local comments = load_comments()

  -- Find the root comment of this thread
  for _, comment in ipairs(comments) do
    if comment.thread_id == thread_id and (not comment.parent_id or comment.id == thread_id:match("^(.+)_thread$")) then
      -- Find the file to get status
      local files = vim.fn.glob(get_storage_dir() .. "/*_" .. comment.id .. ".md", false, true)
      local status = "action-required"
      
      if files[1] then
        local filename = vim.fn.fnamemodify(files[1], ":t")
        local parsed_status = parse_filename(filename)
        if parsed_status then
          status = parsed_status
        end
      end
      
      return {
        id = thread_id,
        status = status,
        root_comment_id = comment.id,
      }
    end
  end

  return nil
end

--- Reload comments from storage (invalidate cache)
function M.reload()
  invalidate_cache()
end

--- Update thread status by renaming the file
---@param thread_id string Thread ID
---@param status string New status ("resolved", "open", etc.)
---@param resolved_by string|nil User who resolved (unused now)
---@return boolean success
function M.update_thread_status(thread_id, status, resolved_by)
  local comments = load_comments()
  
  -- Find root comment of this thread
  local root_comment = nil
  local thread_comments = {}
  
  for _, comment in ipairs(comments) do
    if comment.thread_id == thread_id then
      table.insert(thread_comments, comment)
      if not root_comment or not comment.parent_id then
        root_comment = comment
      end
    end
  end
  
  if not root_comment then
    return false
  end
  
  -- Map generic status to filename status
  local filename_status
  if status == "resolved" then
    filename_status = "resolved"
  elseif status == "open" then
    -- Determine based on latest author
    filename_status = determine_thread_status(thread_comments)
  else
    filename_status = status
  end
  
  -- Find current file
  local old_files = vim.fn.glob(get_storage_dir() .. "/*_" .. root_comment.id .. ".md", false, true)
  local old_filepath = old_files[1]
  
  if not old_filepath then
    return false
  end
  
  -- Generate new filename
  local new_filename = make_filename(root_comment.id, filename_status)
  local new_filepath = get_storage_dir() .. "/" .. new_filename
  
  -- Rename file if needed
  if old_filepath ~= new_filepath then
    vim.fn.rename(old_filepath, new_filepath)
    invalidate_cache()
  end
  
  return true
end

--- Get all threads by extracting from comments
---@return table<string, table>
function M.get_all_threads()
  local comments = load_comments()
  local threads = {}
  local thread_files = {}

  -- First, map files to thread IDs
  local files = vim.fn.glob(get_storage_dir() .. "/*.md", false, true)
  for _, filepath in ipairs(files) do
    local filename = vim.fn.fnamemodify(filepath, ":t")
    local status, id = parse_filename(filename)
    if status and id then
      thread_files[id] = status
    end
  end

  -- Extract thread info from root comments
  for _, comment in ipairs(comments) do
    if comment.thread_id and (not comment.parent_id or comment.id == comment.thread_id:match("^(.+)_thread$")) then
      local status = thread_files[comment.id] or "action-required"
      threads[comment.thread_id] = {
        id = comment.thread_id,
        status = status,
        root_comment_id = comment.id,
      }
    end
  end

  return threads
end

--- Format a thread (multiple comments) as markdown
---@param thread_comments table[] Comments in the thread, sorted by timestamp
---@return string
function M.format_thread_as_markdown(thread_comments)
  if #thread_comments == 0 then
    return ""
  end

  local lines = {}
  local config = require("code-review.config")
  local date_format = config.get("output.date_format")

  -- Find the root comment (should be the first one)
  local root_comment = thread_comments[1]

  -- YAML frontmatter from root comment
  table.insert(lines, "---")
  table.insert(lines, "file: " .. root_comment.file)
  table.insert(lines, "line_start: " .. root_comment.line_start)
  table.insert(lines, "line_end: " .. root_comment.line_end)
  table.insert(lines, "time: " .. os.date(date_format, root_comment.timestamp))

  if root_comment.author then
    table.insert(lines, "author: " .. root_comment.author)
  end

  if root_comment.thread_id then
    table.insert(lines, "thread_id: " .. root_comment.thread_id)
  end
  
  -- Removed: parent_id, thread_status, resolved_by, resolved_at
  -- Status is now derived from filename

  table.insert(lines, "---")
  table.insert(lines, "")

  -- Code context (from root comment)
  if root_comment.context_lines and #root_comment.context_lines > 0 then
    table.insert(lines, "## Context")
    table.insert(lines, "")
    table.insert(lines, "```" .. vim.fn.fnamemodify(root_comment.file, ":e"))
    for _, line in ipairs(root_comment.context_lines) do
      table.insert(lines, line)
    end
    table.insert(lines, "```")
    table.insert(lines, "")
  end

  -- Comments section
  table.insert(lines, "## Comments")
  table.insert(lines, "")

  -- Add each comment in the thread
  for i, comment in ipairs(thread_comments) do
    if i > 1 then
      table.insert(lines, "")
      table.insert(lines, "---")
      table.insert(lines, "")
    end

    -- Comment metadata
    table.insert(
      lines,
      "### " .. (comment.author or vim.fn.expand("$USER")) .. " - " .. os.date(date_format, comment.timestamp)
    )
    table.insert(lines, "")

    -- Comment content
    table.insert(lines, comment.comment)
  end

  return table.concat(lines, "\n")
end

-- Export internal functions for testing
M.parse_filename = parse_filename
M.make_filename = make_filename
M.determine_thread_status = determine_thread_status

return M
