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
      sec = tonumber(sec)
    })
  end
  
  return nil
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
---@return table[] comments
local function parse_comment_from_file(content, filename)
  -- Extract ID from filename
  local base_id = filename:match("^(.+)%.md$")
  if not base_id then
    return {}
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
  local comment_author = nil
  local comment_timestamp = nil

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
        comment_author = author or vim.fn.expand("$USER")
        
        -- Parse timestamp from string (format: "2025-07-08 10:43:54")
        if timestamp_str then
          local year, month, day, hour, min, sec = timestamp_str:match("(%d+)%-(%d+)%-(%d+) (%d+):(%d+):(%d+)")
          if year then
            comment_timestamp = os.time({
              year = tonumber(year),
              month = tonumber(month),
              day = tonumber(day),
              hour = tonumber(hour),
              min = tonumber(min),
              sec = tonumber(sec)
            })
          else
            comment_timestamp = os.time()
          end
        else
          comment_timestamp = os.time()
        end
        
        -- Start new comment
        current_comment = {
          id = base_id .. "_comment_" .. #comments,
          file = frontmatter.file or "",
          line_start = tonumber(frontmatter.line_start) or 0,
          line_end = tonumber(frontmatter.line_end) or 0,
          author = comment_author,
          timestamp = comment_timestamp,
          context_lines = context_lines,
          thread_id = frontmatter.thread_id,
          thread_status = frontmatter.thread_status or "open",
          resolved_by = frontmatter.resolved_by ~= "null" and frontmatter.resolved_by or nil,
          resolved_at = frontmatter.resolved_at ~= "null" and tonumber(frontmatter.resolved_at) or nil,
        }
      elseif line == "---" and in_comments_section then
        -- Comment separator, ignore
      elseif line == "" and not current_comment then
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
        parent_id = frontmatter.parent_id ~= "null" and frontmatter.parent_id or nil,
        thread_status = frontmatter.thread_status or "open",
        resolved_by = frontmatter.resolved_by ~= "null" and frontmatter.resolved_by or nil,
        resolved_at = frontmatter.resolved_at ~= "null" and tonumber(frontmatter.resolved_at) or nil,
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
      
      -- Update the root comment file with all thread comments
      local filename = root_comment.id .. ".md"
      local filepath = get_storage_dir() .. "/" .. filename
      local formatted_text = M.format_thread_as_markdown(thread_comments)
      
      if utils.save_to_file(filepath, formatted_text) then
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
  comment_data.id = filename:match("^(.+)%.md$")

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

  if comment_data.parent_id then
    table.insert(lines, "parent_id: " .. comment_data.parent_id)
  else
    table.insert(lines, "parent_id: null")
  end

  -- Thread status (only for root comments)
  if comment_data.thread_id and not comment_data.parent_id then
    table.insert(lines, "thread_status: " .. (comment_data.thread_status or "open"))

    if comment_data.resolved_by then
      table.insert(lines, "resolved_by: " .. comment_data.resolved_by)
    else
      table.insert(lines, "resolved_by: null")
    end

    if comment_data.resolved_at then
      table.insert(lines, "resolved_at: " .. comment_data.resolved_at)
    else
      table.insert(lines, "resolved_at: null")
    end
  end

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
  table.insert(lines, "### " .. (comment_data.author or vim.fn.expand("$USER")) .. " - " .. os.date(date_format, comment_data.timestamp))
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
    if comment.thread_id == thread_id and not comment.parent_id then
      return {
        id = thread_id,
        status = comment.thread_status or "open",
        root_comment_id = comment.id,
        resolved_by = comment.resolved_by,
        resolved_at = comment.resolved_at,
      }
    end
  end

  return nil
end

--- Reload comments from storage (invalidate cache)
function M.reload()
  invalidate_cache()
end

--- Update thread status by updating all comments in the thread
---@param thread_id string Thread ID
---@param status string New status
---@param resolved_by string|nil User who resolved
---@return boolean success
function M.update_thread_status(thread_id, status, resolved_by)
  local comments = load_comments()
  local updated = false

  -- Update all comments in this thread
  for _, comment in ipairs(comments) do
    if comment.thread_id == thread_id then
      comment.thread_status = status

      -- Only update resolved info on root comment
      if not comment.parent_id then
        if status == "resolved" and resolved_by then
          comment.resolved_by = resolved_by
          comment.resolved_at = os.time()
        elseif status == "open" then
          comment.resolved_by = nil
          comment.resolved_at = nil
        end
      end

      -- Save updated comment
      local filename = comment.id .. ".md"
      local filepath = get_storage_dir() .. "/" .. filename
      local formatted_text = M.format_comment_as_markdown(comment)

      if utils.save_to_file(filepath, formatted_text) then
        updated = true
      end
    end
  end

  if updated then
    invalidate_cache()
  end

  return updated
end

--- Get all threads by extracting from comments
---@return table<string, table>
function M.get_all_threads()
  local comments = load_comments()
  local threads = {}

  -- Extract thread info from root comments
  for _, comment in ipairs(comments) do
    if comment.thread_id and not comment.parent_id then
      threads[comment.thread_id] = {
        id = comment.thread_id,
        status = comment.thread_status or "open",
        root_comment_id = comment.id,
        resolved_by = comment.resolved_by,
        resolved_at = comment.resolved_at,
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
  
  table.insert(lines, "parent_id: null")
  table.insert(lines, "thread_status: " .. (root_comment.thread_status or "open"))
  
  if root_comment.resolved_by then
    table.insert(lines, "resolved_by: " .. root_comment.resolved_by)
  else
    table.insert(lines, "resolved_by: null")
  end
  
  if root_comment.resolved_at then
    table.insert(lines, "resolved_at: " .. root_comment.resolved_at)
  else
    table.insert(lines, "resolved_at: null")
  end
  
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
    table.insert(lines, "### " .. (comment.author or vim.fn.expand("$USER")) .. " - " .. os.date(date_format, comment.timestamp))
    table.insert(lines, "")
    
    -- Comment content
    table.insert(lines, comment.comment)
  end
  
  return table.concat(lines, "\n")
end

return M
