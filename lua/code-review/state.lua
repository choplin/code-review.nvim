local M = {}

-- Storage backend
local storage = nil
local initialized = false

--- Initialize storage backend
function M.init()
  if initialized then
    return
  end

  local config = require("code-review.config")
  local backend = config.get("comment.storage.backend")

  if backend == "file" then
    storage = require("code-review.storage.file")
  else
    storage = require("code-review.storage.memory")
  end

  storage.init()
  initialized = true
end

--- Get storage backend
---@return table
local function get_storage()
  assert(initialized, "State not initialized. Call require('code-review').setup() first.")
  return storage
end

--- Check if review session is active
---@return boolean
function M.is_active()
  return get_storage().is_active()
end

--- Refresh UI elements (markers, etc.) after state changes
function M.refresh_ui()
  -- Update visual indicators (signs and virtual text)
  require("code-review.comment").update_indicators()

  -- Future: Update other UI elements like statusline, floating windows, etc.
end

--- Sync state from storage (for file backend)
function M.sync_from_storage()
  -- Explicitly reload storage if it has reload method
  if storage and storage.reload then
    storage.reload()
  end

  -- Refresh UI to reflect any changes
  M.refresh_ui()
end

--- Clear all comments but keep session active
function M.clear()
  get_storage().clear()
  M.refresh_ui()
  vim.notify("All comments cleared")
end

--- Add a comment to the session
---@param comment_data table Comment data
function M.add_comment(comment_data)
  local storage_backend = get_storage()

  -- Prepare metadata for root comments
  if not comment_data.parent_id then
    comment_data.author = comment_data.author or vim.fn.expand("$USER")
    comment_data.replies = {}
  end

  -- Add comment to storage (this will generate the real ID)
  local id = storage_backend.add(comment_data)

  -- For root comments, set thread_id
  if not comment_data.parent_id then
    local thread_id = id .. "_thread"

    -- Get the comment and update it with thread info
    local comment = storage_backend.get(id)
    if comment then
      comment.thread_id = thread_id
      -- Status is now managed by filename (if status_management is enabled), not in data

      -- Re-save with thread info
      storage_backend.delete(id)
      storage_backend.add(comment)
    end
  end

  M.refresh_ui()
  return id
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
    M.refresh_ui()
    return true
  end
  return false
end

--- Delete a comment
---@param id string Comment ID
---@return boolean success
function M.delete_comment(id)
  local success = get_storage().delete(id)
  if success then
    M.refresh_ui()
  end
  return success
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

  -- Refresh UI after replacing all comments
  M.refresh_ui()
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

--- Add a reply to a comment
---@param parent_id string Parent comment ID (can be any comment in the thread)
---@param reply_text string Reply text
---@return string|nil reply_id
function M.add_reply(parent_id, reply_text)
  local parent = M.get_comment(parent_id)
  if not parent then
    vim.notify("Parent comment not found", vim.log.levels.ERROR)
    return nil
  end

  local thread = require("code-review.thread")

  -- Always create a reply to the thread, not nested under specific comment
  local reply = thread.create_reply(parent, reply_text)

  -- Add the reply
  local id = get_storage().add(reply)

  M.refresh_ui()
  return id
end

--- Get all comments in a thread
---@param thread_id string Thread ID
---@return table[] comments
function M.get_thread_comments(thread_id)
  local all_comments = M.get_comments()
  local thread = require("code-review.thread")
  return thread.get_thread_comments(thread_id, all_comments)
end

--- Resolve a thread
---@param thread_id string Thread ID
---@return boolean success
function M.resolve_thread(thread_id)
  local storage_backend = get_storage()
  local resolved_by = vim.fn.expand("$USER")
  local success = storage_backend.update_thread_status(thread_id, "resolved", resolved_by)

  if success then
    M.refresh_ui()
    vim.notify("Thread resolved", vim.log.levels.INFO)
  else
    -- Check if status management is disabled
    local config = require("code-review.config")
    if config.get("comment.storage.backend") == "file" and not config.get("comment.status_management") then
      vim.notify("Status management is disabled. Enable 'status_management' to resolve threads.", vim.log.levels.WARN)
    end
  end

  return success
end

--- Reopen a thread
---@param thread_id string Thread ID
---@return boolean success
function M.reopen_thread(thread_id)
  local storage_backend = get_storage()
  local success = storage_backend.update_thread_status(thread_id, "open", nil)

  if success then
    M.refresh_ui()
    vim.notify("Thread reopened", vim.log.levels.INFO)
  else
    -- Check if status management is disabled
    local config = require("code-review.config")
    if config.get("comment.storage.backend") == "file" and not config.get("comment.status_management") then
      vim.notify("Status management is disabled. Enable 'status_management' to reopen threads.", vim.log.levels.WARN)
    end
  end

  return success
end

--- Get all thread statuses
---@return table<string, table>
function M.get_all_threads()
  local storage_backend = get_storage()
  if storage_backend.get_all_threads then
    return storage_backend.get_all_threads()
  end
  return {}
end

--- Get storage backend (for internal use)
---@return table storage
function M.get_storage()
  return get_storage()
end

--- Reset internal state (for testing purposes)
---@private
function M._reset()
  initialized = false
  storage = nil
end

return M
