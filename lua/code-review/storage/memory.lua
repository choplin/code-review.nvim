local M = {}

-- In-memory storage implementation
local session = {
  active = false,
  comments = {},
  start_time = nil,
}

--- Initialize storage
function M.init()
  session.active = true
  session.comments = session.comments or {}
  session.start_time = session.start_time or os.time()
end

--- Check if storage is active
---@return boolean
function M.is_active()
  return session.active
end

--- Add a comment
---@param comment_data table
---@return string id
function M.add(comment_data)
  if not session.active then
    error("Storage not active")
  end

  -- Add metadata
  if not comment_data.id then
    -- Use a more reliable ID generation to avoid collisions
    local ms = vim.fn.reltimefloat(vim.fn.reltime()) * 1000
    comment_data.id = string.format("%d_%03d_%04d", vim.fn.localtime(), ms % 1000, math.random(1000, 9999))
  end
  comment_data.timestamp = comment_data.timestamp or os.time()

  table.insert(session.comments, comment_data)
  return comment_data.id
end

--- Get all comments
---@return table[]
function M.get_all()
  return vim.deepcopy(session.comments)
end

--- Get a specific comment by ID
---@param id string
---@return table|nil
function M.get(id)
  for _, comment in ipairs(session.comments) do
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
  for i, comment in ipairs(session.comments) do
    if comment.id == id then
      table.remove(session.comments, i)
      return true
    end
  end
  return false
end

--- Clear all comments
function M.clear()
  session.comments = {}
end

--- Get comments for a specific file and line range
---@param file string
---@param line number
---@return table[]
function M.get_at_location(file, line)
  local results = {}
  for _, comment in ipairs(session.comments) do
    if comment.file == file and line >= comment.line_start and line <= comment.line_end then
      table.insert(results, vim.deepcopy(comment))
    end
  end
  return results
end

--- Update thread status by updating comments
---@param thread_id string Thread ID
---@param status string New status
---@param resolved_by string|nil User who resolved
---@return boolean success
function M.update_thread_status(thread_id, status, resolved_by)
  local updated = false

  for _, comment in ipairs(session.comments) do
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

      updated = true
    end
  end

  return updated
end

--- Get thread by ID from comments
---@param thread_id string
---@return table|nil
function M.get_thread(thread_id)
  for _, comment in ipairs(session.comments) do
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

--- Get all threads from comments
---@return table<string, table>
function M.get_all_threads()
  local threads = {}

  for _, comment in ipairs(session.comments) do
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

--- Reset internal state (for testing purposes)
---@private
function M._reset()
  session.active = false
  session.comments = {}
  session.start_time = nil
end

return M
