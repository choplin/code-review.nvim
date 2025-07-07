-- Edge case tests
local T = MiniTest.new_set()

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
  end,
}

-- Large data tests
T["large data"] = MiniTest.new_set()

T["large data"]["handles very large comments"] = function()
  -- Create a very large comment (10KB)
  local large_comment = string.rep("This is a long comment line. ", 350)
  local state = require("code-review.state")

  local id = state.add_comment({
    file = "test.lua",
    line_start = 1,
    line_end = 1,
    comment = large_comment,
  })

  MiniTest.expect.equality(type(id), "string")

  local retrieved = state.get_comment(id)
  MiniTest.expect.equality(retrieved.comment, large_comment)
end

T["large data"]["handles many comments"] = function()
  local state = require("code-review.state")

  -- Add 100 comments
  local ids = {}
  for i = 1, 100 do
    local id = state.add_comment({
      file = string.format("file%d.lua", i),
      line_start = i,
      line_end = i,
      comment = string.format("Comment number %d", i),
    })
    table.insert(ids, id)
  end

  -- Verify all comments exist
  local all_comments = state.get_comments()
  MiniTest.expect.equality(#all_comments, 100)

  -- Verify we can retrieve specific comments
  local comment50 = state.get_comment(ids[50])
  MiniTest.expect.equality(comment50.comment, "Comment number 50")
end

-- Special characters tests
T["special characters"] = MiniTest.new_set()

T["special characters"]["handles quotes and escapes in comments"] = function()
  local state = require("code-review.state")

  local special_comments = {
    [[This has "double quotes"]],
    [[This has 'single quotes']],
    [[This has `backticks`]],
    [[This has \backslashes\]],
    [[This has
newlines
in it]],
    [[This has	tabs	in	it]],
  }

  for i, comment_text in ipairs(special_comments) do
    local id = state.add_comment({
      file = "test.lua",
      line_start = i,
      line_end = i,
      comment = comment_text,
    })

    local retrieved = state.get_comment(id)
    MiniTest.expect.equality(retrieved.comment, comment_text)
  end
end

T["special characters"]["handles unicode characters"] = function()
  local state = require("code-review.state")

  local unicode_comments = {
    "This has emojis 🚀 ✨ 🎉",
    "これは日本語のコメントです",
    "这是中文评论",
    "Это русский комментарий",
    "هذا تعليق عربي",
  }

  for i, comment_text in ipairs(unicode_comments) do
    local id = state.add_comment({
      file = "test.lua",
      line_start = i,
      line_end = i,
      comment = comment_text,
    })

    local retrieved = state.get_comment(id)
    MiniTest.expect.equality(retrieved.comment, comment_text)
  end
end

T["special characters"]["handles special file names"] = function()
  local state = require("code-review.state")

  local special_files = {
    "file with spaces.lua",
    "file-with-dashes.lua",
    "file_with_underscores.lua",
    "file.with.dots.lua",
    "файл.lua", -- Cyrillic
    "文件.lua", -- Chinese
    "path/to/nested/file.lua",
    "/absolute/path/to/file.lua",
    "~/home/path/file.lua",
  }

  for _, filename in ipairs(special_files) do
    local id = state.add_comment({
      file = filename,
      line_start = 1,
      line_end = 1,
      comment = "Test comment",
    })

    local retrieved = state.get_comment(id)
    MiniTest.expect.equality(retrieved.file, filename)
  end
end

-- Boundary tests
T["boundary conditions"] = MiniTest.new_set()

T["boundary conditions"]["handles empty comment"] = function()
  local state = require("code-review.state")

  local id = state.add_comment({
    file = "test.lua",
    line_start = 1,
    line_end = 1,
    comment = "",
  })

  MiniTest.expect.equality(type(id), "string")

  local retrieved = state.get_comment(id)
  MiniTest.expect.equality(retrieved.comment, "")
end

T["boundary conditions"]["handles whitespace-only comment"] = function()
  local state = require("code-review.state")

  local whitespace_comments = {
    " ",
    "   ",
    "\t",
    "\n",
    "\n\n\n",
    " \t\n ",
  }

  for i, comment_text in ipairs(whitespace_comments) do
    local id = state.add_comment({
      file = "test.lua",
      line_start = i,
      line_end = i,
      comment = comment_text,
    })

    local retrieved = state.get_comment(id)
    MiniTest.expect.equality(retrieved.comment, comment_text)
  end
end

T["boundary conditions"]["handles single-line file"] = function()
  local state = require("code-review.state")

  -- Create buffer with single line
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "single line" })
  vim.api.nvim_buf_set_name(buf, "single.lua")

  local id = state.add_comment({
    file = "single.lua",
    line_start = 1,
    line_end = 1,
    comment = "Comment on single line",
  })

  MiniTest.expect.equality(type(id), "string")

  -- Cleanup
  pcall(vim.api.nvim_buf_delete, buf, { force = true })
end

T["boundary conditions"]["handles comment spanning entire file"] = function()
  local state = require("code-review.state")

  -- Create buffer with multiple lines
  local buf = vim.api.nvim_create_buf(false, true)
  local lines = {}
  for i = 1, 100 do
    table.insert(lines, string.format("line %d", i))
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_name(buf, "large.lua")

  local id = state.add_comment({
    file = "large.lua",
    line_start = 1,
    line_end = 100,
    comment = "Comment spanning entire file",
    context_lines = lines,
  })

  MiniTest.expect.equality(type(id), "string")

  local retrieved = state.get_comment(id)
  MiniTest.expect.equality(retrieved.line_start, 1)
  MiniTest.expect.equality(retrieved.line_end, 100)
  MiniTest.expect.equality(#retrieved.context_lines, 100)

  -- Cleanup
  pcall(vim.api.nvim_buf_delete, buf, { force = true })
end

-- Multiple comments tests
T["multiple comments"] = MiniTest.new_set()

T["multiple comments"]["handles multiple comments on same line"] = function()
  local state = require("code-review.state")

  -- Add multiple comments on the same line
  local ids = {}
  for i = 1, 5 do
    local id = state.add_comment({
      file = "test.lua",
      line_start = 10,
      line_end = 10,
      comment = string.format("Comment %d on line 10", i),
    })
    table.insert(ids, id)
  end

  -- Verify all comments exist
  local comments_at_line = state.get_comments_at_location("test.lua", 10)
  MiniTest.expect.equality(#comments_at_line, 5)

  -- Verify each comment
  for i = 1, 5 do
    local found = false
    for _, comment in ipairs(comments_at_line) do
      if comment.comment == string.format("Comment %d on line 10", i) then
        found = true
        break
      end
    end
    MiniTest.expect.equality(found, true)
  end
end

T["multiple comments"]["handles overlapping comment ranges"] = function()
  local state = require("code-review.state")

  -- Add overlapping comments
  state.add_comment({
    file = "test.lua",
    line_start = 5,
    line_end = 10,
    comment = "Comment 1: lines 5-10",
  })

  state.add_comment({
    file = "test.lua",
    line_start = 8,
    line_end = 15,
    comment = "Comment 2: lines 8-15",
  })

  state.add_comment({
    file = "test.lua",
    line_start = 7,
    line_end = 12,
    comment = "Comment 3: lines 7-12",
  })

  -- Check comments at overlapping lines
  local comments_at_8 = state.get_comments_at_location("test.lua", 8)
  MiniTest.expect.equality(#comments_at_8, 3) -- All three comments include line 8

  local comments_at_5 = state.get_comments_at_location("test.lua", 5)
  MiniTest.expect.equality(#comments_at_5, 1) -- Only comment 1

  local comments_at_15 = state.get_comments_at_location("test.lua", 15)
  MiniTest.expect.equality(#comments_at_15, 1) -- Only comment 2
end

-- File handling tests
T["file handling"] = MiniTest.new_set()

T["file handling"]["handles files without extensions"] = function()
  local state = require("code-review.state")

  local files_without_ext = {
    "Makefile",
    "Dockerfile",
    "LICENSE",
    "README",
    ".gitignore",
    ".env",
  }

  for _, filename in ipairs(files_without_ext) do
    local id = state.add_comment({
      file = filename,
      line_start = 1,
      line_end = 1,
      comment = "Comment on " .. filename,
    })

    local retrieved = state.get_comment(id)
    MiniTest.expect.equality(retrieved.file, filename)
  end
end

T["file handling"]["handles very long file paths"] = function()
  local state = require("code-review.state")

  -- Create a very long path (300+ chars)
  local long_path = "/very/long/path/" .. string.rep("subdir/", 40) .. "file.lua"

  local id = state.add_comment({
    file = long_path,
    line_start = 1,
    line_end = 1,
    comment = "Comment on file with long path",
  })

  local retrieved = state.get_comment(id)
  MiniTest.expect.equality(retrieved.file, long_path)
  MiniTest.expect.equality(#retrieved.file > 300, true)
end

-- Performance tests
T["performance"] = MiniTest.new_set()

T["performance"]["handles rapid add/delete operations"] = function()
  local state = require("code-review.state")

  local start_time = vim.loop.hrtime()

  -- Rapidly add and delete comments
  for i = 1, 50 do
    local id = state.add_comment({
      file = "test.lua",
      line_start = i,
      line_end = i,
      comment = "Rapid comment " .. i,
    })

    if i % 2 == 0 then
      -- Delete every other comment immediately
      state.delete_comment(id)
    end
  end

  local elapsed = (vim.loop.hrtime() - start_time) / 1e6 -- Convert to milliseconds

  -- Should complete in reasonable time (less than 1 second)
  MiniTest.expect.equality(elapsed < 1000, true)

  -- Verify final state
  local remaining = state.get_comments()
  MiniTest.expect.equality(#remaining, 25) -- Half should remain
end

return T
