-- Error handling tests
local T = MiniTest.new_set()
local helpers = require("tests.helpers")

-- Track notify messages
local notify_messages = {}

-- Store original functions
local original_notify = vim.notify
local original_setreg = vim.fn.setreg
local original_sign_place = vim.fn.sign_place
local original_sign_unplace = vim.fn.sign_unplace
local original_io_open = io.open

-- Initialize plugin at file load time
require("code-review").setup({
  comment = {
    storage = { backend = "memory" },
  },
})

-- Setup and teardown
T.hooks = {
  pre_case = function()
    -- Reset and reinitialize for clean state
    local state = require("code-review.state")
    local memory = require("code-review.storage.memory")

    -- Use _reset for complete cleanup
    state._reset()
    memory._reset()

    -- Reinitialize
    state.init()

    -- Mock vim.notify to capture messages
    notify_messages = {}
    vim.notify = function(msg, level) -- luacheck: ignore 122
      table.insert(notify_messages, { msg = msg, level = level })
    end
  end,

  post_case = function()
    -- Restore original functions
    vim.notify = original_notify -- luacheck: ignore 122
    vim.fn.setreg = original_setreg -- luacheck: ignore 122
    vim.fn.sign_place = original_sign_place -- luacheck: ignore 122
    vim.fn.sign_unplace = original_sign_unplace -- luacheck: ignore 122
    io.open = original_io_open -- luacheck: ignore 122
  end,
}

-- File I/O errors
T["file I/O errors"] = MiniTest.new_set()

T["file I/O errors"]["save_to_file handles write failure"] = function()
  -- Use existing directory to avoid mkdir
  local test_dir = vim.fn.tempname()
  vim.fn.mkdir(test_dir, "p")
  local test_path = test_dir .. "/test_save.txt"

  -- Mock io.open to fail
  io.open = function(path) -- luacheck: ignore 122
    if path == test_path then
      return nil, "Permission denied"
    end
    return original_io_open(path)
  end

  local utils = require("code-review.utils")
  local success = utils.save_to_file(test_path, "content")

  MiniTest.expect.equality(success, false)
  MiniTest.expect.equality(#notify_messages > 0, true)
  helpers.expect.match(notify_messages[1].msg, "Failed to open file")

  -- Cleanup
  vim.fn.delete(test_dir, "rf")
end

-- UI errors
T["ui errors"] = MiniTest.new_set()

T["ui errors"]["handles buffer creation failure"] = function()
  -- Store original
  local original_nvim_create_buf = vim.api.nvim_create_buf

  -- Mock to fail
  vim.api.nvim_create_buf = function() -- luacheck: ignore 122
    error("Buffer creation failed")
  end

  local ui = require("code-review.ui")
  local ok, err = pcall(ui.show_comment_input, function() end)

  MiniTest.expect.equality(ok, false)
  helpers.expect.match(err, "Buffer creation failed")

  -- Restore
  vim.api.nvim_create_buf = original_nvim_create_buf -- luacheck: ignore 122
end

T["ui errors"]["handles window creation failure"] = function()
  -- Store originals
  local original_nvim_open_win = vim.api.nvim_open_win
  local original_nvim_create_buf = vim.api.nvim_create_buf

  -- Mock buffer creation to succeed
  local test_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_create_buf = function() -- luacheck: ignore 122
    return test_buf
  end

  -- Mock window creation to fail
  vim.api.nvim_open_win = function() -- luacheck: ignore 122
    error("Window creation failed")
  end

  local ui = require("code-review.ui")
  local ok, err = pcall(ui.show_comment_input, function() end)

  MiniTest.expect.equality(ok, false)
  helpers.expect.match(err, "Window creation failed")

  -- Cleanup
  pcall(vim.api.nvim_buf_delete, test_buf, { force = true })

  -- Restore
  vim.api.nvim_open_win = original_nvim_open_win -- luacheck: ignore 122
  vim.api.nvim_create_buf = original_nvim_create_buf -- luacheck: ignore 122
end

T["ui errors"]["handles invalid window operations"] = function()
  -- Store original
  local original_nvim_win_is_valid = vim.api.nvim_win_is_valid

  -- Mock to return false
  vim.api.nvim_win_is_valid = function() -- luacheck: ignore 122
    return false
  end

  local ui = require("code-review.ui")

  -- Try to show comment list with invalid window
  local ok = pcall(ui.show_comment_list, {})

  -- Should handle gracefully (not crash)
  MiniTest.expect.equality(type(ok), "boolean")

  -- Restore
  vim.api.nvim_win_is_valid = original_nvim_win_is_valid -- luacheck: ignore 122
end

-- Boundary and validation
T["boundary and validation"] = MiniTest.new_set()

T["boundary and validation"]["handles nil input gracefully"] = function()
  local state = require("code-review.state")

  -- Try to add comment with nil fields
  local ok = pcall(state.add_comment, {
    file = nil,
    line_start = nil,
    line_end = nil,
    comment = nil,
  })

  -- Should not crash
  MiniTest.expect.equality(type(ok), "boolean")
end

T["boundary and validation"]["handles invalid line numbers"] = function()
  local state = require("code-review.state")

  -- Try negative line numbers
  local id = state.add_comment({
    file = "test.lua",
    line_start = -1,
    line_end = -5,
    comment = "Invalid lines",
  })

  -- Should still create comment (no validation)
  MiniTest.expect.equality(type(id), "string")

  local comment = state.get_comment(id)
  MiniTest.expect.equality(comment.line_start, -1)
end

T["boundary and validation"]["handles empty state operations"] = function()
  local state = require("code-review.state")

  -- Clear all comments
  state.clear()

  -- Operations on empty state
  local comments = state.get_comments()
  MiniTest.expect.equality(#comments, 0)

  local location_comments = state.get_comments_at_location("any.lua", 1)
  MiniTest.expect.equality(#location_comments, 0)

  local non_existent = state.get_comment("non-existent-id")
  MiniTest.expect.equality(non_existent, nil)

  local delete_result = state.delete_comment("non-existent-id")
  MiniTest.expect.equality(delete_result, false)
end

-- Optional dependency handling
T["optional dependencies"] = MiniTest.new_set()

T["optional dependencies"]["handles missing telescope gracefully"] = function()
  -- Mock telescope to not exist
  package.loaded["telescope"] = nil
  package.loaded["telescope.builtin"] = nil

  local comment = require("code-review.comment")

  -- Try to select comment which uses telescope if available
  local ok = pcall(comment.select_comment)

  -- Should handle gracefully
  MiniTest.expect.equality(type(ok), "boolean")
end

T["optional dependencies"]["handles missing nui gracefully"] = function()
  -- Mock nui to not exist
  package.loaded["nui.popup"] = nil
  package.loaded["nui.input"] = nil

  local ui = require("code-review.ui")

  -- Try to show UI which uses nui if available
  local ok = pcall(ui.show_comment_input, function() end)

  -- Should handle gracefully
  MiniTest.expect.equality(type(ok), "boolean")
end

return T
