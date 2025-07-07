-- Simplified integration tests that work reliably
local T = MiniTest.new_set()
local helpers = require("tests.helpers")

-- Setup and teardown
T.hooks = {
  pre_once = function()
    -- Load plugin with memory backend to avoid file system
    require("code-review").setup({
      comment = {
        storage = { backend = "memory" },
      },
    })
  end,

  pre_case = function()
    -- Reset and reinitialize for clean state
    local state = require("code-review.state")
    local memory = require("code-review.storage.memory")

    -- Use _reset for complete cleanup
    state._reset()
    memory._reset()

    -- Reinitialize
    state.init()

    -- Clear any existing comments
    state.clear()
  end,
}

-- Test basic formatter integration
T["formatter integration"] = function()
  local formatter = require("code-review.formatter")

  -- Test data
  local test_comments = {
    {
      file = "test1.lua",
      line_start = 1,
      line_end = 5,
      comment = "First test comment",
      timestamp = os.time(),
    },
    {
      file = "test1.lua",
      line_start = 10,
      line_end = 10,
      comment = "Second test comment",
      timestamp = os.time(),
    },
    {
      file = "test2.lua",
      line_start = 20,
      line_end = 25,
      comment = "Third test comment",
      timestamp = os.time(),
    },
  }

  -- Format and parse
  local formatted = formatter.format(test_comments)
  local parsed = formatter.parse(formatted)

  -- Verify round-trip
  MiniTest.expect.equality(#parsed, 3)
  MiniTest.expect.equality(parsed[1].file, "test1.lua")
  MiniTest.expect.equality(parsed[1].comment, "First test comment")
  MiniTest.expect.equality(parsed[2].file, "test1.lua")
  MiniTest.expect.equality(parsed[2].comment, "Second test comment")
  MiniTest.expect.equality(parsed[3].file, "test2.lua")
  MiniTest.expect.equality(parsed[3].comment, "Third test comment")
end

-- Test comment formatting
T["comment formatting"] = function()
  local comment = require("code-review.comment")

  local test_data = {
    file = "test.lua",
    line_start = 10,
    line_end = 15,
    comment = "This is a test comment\nWith multiple lines",
    context_lines = { "function test()", "  return true", "end" },
  }

  -- Format as markdown
  local lines = comment.format_as_markdown(test_data, true, false)

  -- Verify format
  MiniTest.expect.equality(type(lines), "table")
  MiniTest.expect.equality(#lines > 0, true)

  -- Check content
  local content = table.concat(lines, "\n")
  helpers.expect.match(content, "test.lua:10%-15")
  helpers.expect.match(content, "This is a test comment")
  helpers.expect.match(content, "With multiple lines")
  helpers.expect.match(content, "function test")
end

-- Test utils functions
T["utils integration"] = function()
  local utils = require("code-review.utils")

  -- Test path normalization
  local paths = {
    "/absolute/path/file.lua",
    "relative/path/file.lua",
    "~/home/file.lua",
  }

  for _, path in ipairs(paths) do
    local normalized = utils.normalize_path(path)
    MiniTest.expect.equality(type(normalized), "string")
    MiniTest.expect.equality(#normalized > 0, true)
  end

  -- Test filename generation
  local filename = utils.generate_filename("markdown")
  helpers.expect.match(filename, "code%-review%-.*%.md")
end

return T
