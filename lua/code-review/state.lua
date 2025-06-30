local M = {}

-- Review session state
local session = {
  active = false,
  comments = {},
  start_time = nil,
}

--- Check if review session is active
---@return boolean
function M.is_active()
  return session.active
end

--- Initialize or ensure session is active
function M.ensure_active()
  if not session.active then
    session.active = true
    session.comments = session.comments or {}
    session.start_time = session.start_time or os.time()
  end
end

--- Clear all comments but keep session active
function M.clear()
  session.comments = {}
  vim.notify("All comments cleared")
end

--- Add a comment to the session
---@param comment_data table Comment data
function M.add_comment(comment_data)
  if not session.active then
    error("No active review session")
  end

  -- Add metadata
  comment_data.id = vim.fn.localtime() .. "_" .. math.random(1000, 9999)
  comment_data.timestamp = os.time()

  table.insert(session.comments, comment_data)
  return comment_data.id
end

--- Get all comments
---@return table[]
function M.get_comments()
  return vim.deepcopy(session.comments)
end

--- Get a specific comment by ID
---@param id string Comment ID
---@return table?
function M.get_comment(id)
  for _, comment in ipairs(session.comments) do
    if comment.id == id then
      return vim.deepcopy(comment)
    end
  end
  return nil
end

--- Update a comment
---@param id string Comment ID
---@param updates table Fields to update
---@return boolean success
function M.update_comment(id, updates)
  for i, comment in ipairs(session.comments) do
    if comment.id == id then
      -- Preserve id and timestamp
      updates.id = comment.id
      updates.timestamp = comment.timestamp
      session.comments[i] = vim.tbl_extend("force", comment, updates)
      return true
    end
  end
  return false
end

--- Delete a comment
---@param id string Comment ID
---@return boolean success
function M.delete_comment(id)
  for i, comment in ipairs(session.comments) do
    if comment.id == id then
      table.remove(session.comments, i)
      return true
    end
  end
  return false
end

--- Replace all comments (used for preview editing)
---@param new_comments table[] New comments array
function M.replace_comments(new_comments)
  session.comments = new_comments
end

--- Get session metadata
---@return table
function M.get_metadata()
  return {
    start_time = session.start_time,
    comment_count = #session.comments,
  }
end

return M
