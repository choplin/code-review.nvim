local M = {}

-- Storage backend
local storage = nil

--- Get storage backend based on config
---@return table
local function get_storage()
  if storage then
    return storage
  end

  local config = require("code-review.config")
  local backend = config.get("comment.storage.backend") or "memory"

  if backend == "file" then
    storage = require("code-review.storage.file")
  else
    storage = require("code-review.storage.memory")
  end

  storage.init()
  return storage
end

--- Check if review session is active
---@return boolean
function M.is_active()
  return get_storage().is_active()
end

--- Initialize or ensure session is active
function M.ensure_active()
  get_storage().init()
end

--- Clear all comments but keep session active
function M.clear()
  get_storage().clear()
  vim.notify("All comments cleared")
end

--- Add a comment to the session
---@param comment_data table Comment data
function M.add_comment(comment_data)
  return get_storage().add(comment_data)
end

--- Get all comments
---@return table[]
function M.get_comments()
  return get_storage().get_all()
end

--- Get a specific comment by ID
---@param id string Comment ID
---@return table?
function M.get_comment(id)
  return get_storage().get(id)
end

--- Update a comment
---@param id string Comment ID
---@param updates table Fields to update
---@return boolean success
function M.update_comment(id, updates)
  -- For file storage, we need to delete and re-add
  local storage_backend = get_storage()
  local comment = storage_backend.get(id)
  if not comment then
    return false
  end

  -- Merge updates
  local updated_comment = vim.tbl_extend("force", comment, updates)
  -- Preserve id and timestamp
  updated_comment.id = comment.id
  updated_comment.timestamp = comment.timestamp

  -- Delete old and add new
  if storage_backend.delete(id) then
    storage_backend.add(updated_comment)
    return true
  end
  return false
end

--- Delete a comment
---@param id string Comment ID
---@return boolean success
function M.delete_comment(id)
  return get_storage().delete(id)
end

--- Replace all comments (used for preview editing)
---@param new_comments table[] New comments array
function M.replace_comments(new_comments)
  local storage_backend = get_storage()

  -- Clear existing comments
  storage_backend.clear()

  -- Add all new comments
  for _, comment in ipairs(new_comments) do
    storage_backend.add(comment)
  end
end

--- Get session metadata
---@return table
function M.get_metadata()
  local comments = get_storage().get_all()
  return {
    start_time = os.time(), -- For file storage, we don't track session start time
    comment_count = #comments,
  }
end

--- Get comments at specific location
---@param file string
---@param line number
---@return table[]
function M.get_comments_at_location(file, line)
  return get_storage().get_at_location(file, line)
end

return M
