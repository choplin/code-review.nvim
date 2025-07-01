local M = {}

local comment = require("code-review.comment")

--- Create a custom previewer for Telescope that shows comment content
function M.telescope_comment_previewer()
  local previewers = require("telescope.previewers")

  return previewers.new_buffer_previewer({
    title = "Comment Details",
    get_buffer_by_name = function(_, entry)
      return entry.value.id or tostring(entry.value)
    end,
    define_preview = function(self, entry, status)
      local comment_data = entry.value
      local bufnr = self.state.bufnr

      -- Use common formatter (no ANSI for Telescope)
      local lines = comment.format_as_markdown(comment_data, true, false)

      -- Make buffer modifiable before setting content
      vim.api.nvim_buf_set_option(bufnr, "modifiable", true)
      
      -- Set buffer content
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
      vim.api.nvim_buf_set_option(bufnr, "filetype", "markdown")
      
      -- Make it read-only after setting content
      vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
    end,
  })
end

return M
