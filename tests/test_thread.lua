local state = require("code-review.state")
local thread = require("code-review.thread")

-- Initialize plugin
require("code-review").setup({
  comment = {
    storage = { backend = "memory" },
  },
})

local T = MiniTest.new_set()

-- Setup and teardown hooks
T["thread management"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      -- Reset and reinitialize for clean state
      local memory = require("code-review.storage.memory")

      -- Use _reset for complete cleanup
      state._reset()
      memory._reset()

      -- Reinitialize
      state.init()

      -- Clear any existing comments
      state.clear()
    end,
  },
})

T["thread management"]["creates thread for root comment"] = function()
  -- Add a root comment
  local comment_id = state.add_comment({
    file = "test.lua",
    line_start = 1,
    line_end = 5,
    comment = "This needs refactoring",
  })

  -- Check that thread was created
  local threads = state.get_all_threads()
  local thread_count = vim.tbl_count(threads)
  MiniTest.expect.equality(thread_count, 1)

  -- Verify thread properties
  local thread_id = comment_id .. "_thread"
  local thread_data = threads[thread_id]
  MiniTest.expect.equality(thread_data ~= nil, true)
  MiniTest.expect.equality(thread_data.status, "open")
  MiniTest.expect.equality(thread_data.root_comment_id, comment_id)
end

T["thread management"]["adds replies to thread"] = function()
  -- Add root comment
  local root_id = state.add_comment({
    file = "test.lua",
    line_start = 10,
    line_end = 10,
    comment = "Original comment",
  })

  -- Add reply
  local reply_id = state.add_reply(root_id, "I agree with this")
  MiniTest.expect.equality(reply_id ~= nil, true)

  -- Check that reply has correct thread_id
  local reply_comment = state.get_comment(reply_id)
  MiniTest.expect.equality(reply_comment.thread_id, root_id .. "_thread")
  MiniTest.expect.equality(reply_comment.parent_id, root_id)
end

T["thread management"]["resolves and reopens threads"] = function()
  -- Add comment to create thread
  local comment_id = state.add_comment({
    file = "test.lua",
    line_start = 1,
    line_end = 1,
    comment = "Fix this bug",
  })

  local thread_id = comment_id .. "_thread"

  -- Resolve thread
  local success = state.resolve_thread(thread_id)
  MiniTest.expect.equality(success, true)

  -- Check thread status
  local threads = state.get_all_threads()
  MiniTest.expect.equality(threads[thread_id].status, "resolved")
  MiniTest.expect.equality(threads[thread_id].resolved_by ~= nil, true)
  MiniTest.expect.equality(threads[thread_id].resolved_at ~= nil, true)

  -- Reopen thread
  success = state.reopen_thread(thread_id)
  MiniTest.expect.equality(success, true)

  -- Check thread status again
  threads = state.get_all_threads()
  MiniTest.expect.equality(threads[thread_id].status, "open")
  MiniTest.expect.equality(threads[thread_id].resolved_by, nil)
  MiniTest.expect.equality(threads[thread_id].resolved_at, nil)
end

T["thread management"]["builds thread tree from comments"] = function()
  -- Create a thread with multiple comments
  local root_id = state.add_comment({
    file = "test.lua",
    line_start = 1,
    line_end = 1,
    comment = "Root comment",
  })

  -- Add replies
  state.add_reply(root_id, "First reply")
  state.add_reply(root_id, "Second reply")

  -- Get all comments and build thread tree
  local comments = state.get_comments()
  local threads = thread.build_thread_tree(comments)

  -- Verify thread structure
  local thread_id = root_id .. "_thread"
  MiniTest.expect.equality(threads[thread_id] ~= nil, true)
  MiniTest.expect.equality(threads[thread_id].root_comment.id, root_id)
  MiniTest.expect.equality(#threads[thread_id].replies, 2)
end

T["thread management"]["gets thread comments"] = function()
  -- Create thread
  local root_id = state.add_comment({
    file = "test.lua",
    line_start = 5,
    line_end = 5,
    comment = "Thread root",
  })

  local thread_id = root_id .. "_thread"

  -- Add replies
  state.add_reply(root_id, "Reply 1")
  state.add_reply(root_id, "Reply 2")

  -- Get thread comments
  local thread_comments = state.get_thread_comments(thread_id)
  MiniTest.expect.equality(#thread_comments, 3) -- root + 2 replies

  -- Verify all have same thread_id
  for _, comment in ipairs(thread_comments) do
    MiniTest.expect.equality(comment.thread_id, thread_id)
  end
end

T["thread management"]["handles multiple threads"] = function()
  -- Create multiple threads
  local thread_ids = {}
  for i = 1, 3 do
    local id = state.add_comment({
      file = "test" .. i .. ".lua",
      line_start = i,
      line_end = i,
      comment = "Thread " .. i,
    })
    table.insert(thread_ids, id .. "_thread")
  end

  -- Check all threads exist
  local threads = state.get_all_threads()
  MiniTest.expect.equality(vim.tbl_count(threads), 3)

  for _, thread_id in ipairs(thread_ids) do
    MiniTest.expect.equality(threads[thread_id] ~= nil, true)
    MiniTest.expect.equality(threads[thread_id].status, "open")
  end
end

T["thread management"]["preserves thread state across storage backends"] = function()
  -- Test with file storage - reinitialize with file backend
  state._reset()
  require("code-review.storage.memory")._reset()
  require("code-review").setup({
    comment = {
      storage = { backend = "file" },
    },
  })
  state.init()

  local comment_id = state.add_comment({
    file = "test.lua",
    line_start = 1,
    line_end = 1,
    comment = "Test thread persistence",
  })

  local thread_id = comment_id .. "_thread"
  state.resolve_thread(thread_id)

  -- Simulate reloading
  state.sync_from_storage()

  -- Check thread state is preserved
  local threads = state.get_all_threads()
  MiniTest.expect.equality(threads[thread_id].status, "resolved")
end

return T
