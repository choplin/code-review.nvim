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
  comment_data.id = vim.fn.localtime() .. "_" .. math.random(1000, 9999)
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

--- Reset internal state (for testing purposes)
---@private
function M._reset()
  session.active = false
  session.comments = {}
  session.start_time = nil
end

return M
