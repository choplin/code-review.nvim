local M = {}

local config = require("code-review.config")
local state = require("code-review.state")
local comment = require("code-review.comment")
local ui = require("code-review.ui")
local formatter = require("code-review.formatter")
local utils = require("code-review.utils")

--- Setup function to initialize the plugin
---@param opts table? User configuration
function M.setup(opts)
  config.setup(opts or {})

  -- Create commands
  vim.api.nvim_create_user_command("CodeReviewClear", function()
    M.clear()
  end, { desc = "Clear all review comments" })

  vim.api.nvim_create_user_command("CodeReviewComment", function(args)
    local context_lines = tonumber(args.args)
    M.add_comment(context_lines)
  end, {
    desc = "Add a comment at current location",
    nargs = "?",
  })

  vim.api.nvim_create_user_command("CodeReviewPreview", function()
    M.preview()
  end, { desc = "Preview the code review" })

  vim.api.nvim_create_user_command("CodeReviewSave", function(args)
    M.save(args.args ~= "" and args.args or nil)
  end, {
    desc = "Save review to file",
    nargs = "?",
    complete = "file",
  })

  vim.api.nvim_create_user_command("CodeReviewCopy", function()
    M.copy()
  end, { desc = "Copy review to clipboard" })

  vim.api.nvim_create_user_command("CodeReviewShowComment", function()
    M.show_comment_at_cursor()
  end, { desc = "Show comment at cursor position" })

  vim.api.nvim_create_user_command("CodeReviewList", function()
    M.list_comments()
  end, { desc = "List all comments" })

  vim.api.nvim_create_user_command("CodeReviewDeleteComment", function()
    M.delete_comment_at_cursor()
  end, { desc = "Delete comment at cursor position" })

  -- Setup keymaps if enabled
  local keymaps = config.get("keymaps")
  if keymaps then
    for action, mapping in pairs(keymaps) do
      if mapping then
        local key, mode
        -- Support both old format (string) and new format (table)
        if type(mapping) == "string" then
          key = mapping
          mode = action == "add_comment" and { "n", "v" } or "n"
        elseif type(mapping) == "table" and mapping.key then
          key = mapping.key
          mode = mapping.mode or (action == "add_comment" and { "n", "v" } or "n")
        end

        if key then
          local desc = {
            clear = "Clear review comments",
            add_comment = "Add review comment",
            preview = "Preview review",
            save = "Save review to file",
            copy = "Copy review to clipboard",
            show_comment = "Show comment at cursor",
            list_comments = "List all comments",
            delete_comment = "Delete comment at cursor",
          }

          local func = {
            clear = M.clear,
            add_comment = function()
              M.add_comment(vim.v.count > 0 and vim.v.count or nil)
            end,
            preview = M.preview,
            save = M.save,
            copy = M.copy,
            show_comment = M.show_comment_at_cursor,
            list_comments = M.list_comments,
            delete_comment = M.delete_comment_at_cursor,
          }

          if func[action] then
            vim.keymap.set(mode, key, func[action], { desc = desc[action] })
          end
        end
      end
    end
  end

  -- Setup autocmd to show indicators when entering a buffer
  vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost" }, {
    group = vim.api.nvim_create_augroup("CodeReviewIndicators", { clear = true }),
    callback = function()
      -- Update indicators for current buffer
      require("code-review.comment").update_indicators()
    end,
    desc = "Update code review indicators",
  })
end

--- Clear all comments
function M.clear()
  state.clear()
end

--- Add a comment at the current location
---@param context_lines number? Number of lines before/after to include
function M.add_comment(context_lines)
  state.ensure_active()
  comment.add(context_lines)
end

--- Show preview of the review
function M.preview()
  state.ensure_active()
  local comments = state.get_comments()
  if #comments == 0 then
    vim.notify("No comments to preview", vim.log.levels.WARN)
    return
  end

  -- Determine preview format
  local preview_format = config.get("ui.preview.format")
  local format
  if preview_format == "auto" then
    format = config.get("output.format")
  else
    format = preview_format
  end

  local content = formatter.format(comments, format)
  ui.show_preview(content, format)
end

--- Save review to file
---@param path string? File path to save to
function M.save(path)
  state.ensure_active()
  local comments = state.get_comments()
  if #comments == 0 then
    vim.notify("No comments to save", vim.log.levels.WARN)
    return
  end

  local format = config.get("output.format")
  local review_utils = require("code-review.utils")

  -- Generate default path if not provided
  if not path then
    local save_dir = config.get("output.save_dir") or vim.fn.getcwd()
    local filename = review_utils.generate_filename(format)
    local default_path = vim.fn.fnamemodify(save_dir .. "/" .. filename, ":p")

    -- Use vim.ui.input to get the save path
    vim.ui.input({
      prompt = "Save to: ",
      default = default_path,
      completion = "file",
    }, function(input)
      if input and input ~= "" then
        local content = formatter.format(comments, format)
        formatter.save_to_file(content, input, format)
      end
    end)
  else
    -- If path is provided, save directly
    local content = formatter.format(comments, format)
    formatter.save_to_file(content, path, format)
  end
end

--- Copy review to clipboard
function M.copy()
  state.ensure_active()
  local comments = state.get_comments()
  if #comments == 0 then
    vim.notify("No comments to copy", vim.log.levels.WARN)
    return
  end

  local format = config.get("output.format")
  local content = formatter.format(comments, format)
  vim.fn.setreg("+", content)
  vim.notify("Code reviews copied to clipboard")
end

--- Show comment at cursor position
function M.show_comment_at_cursor()
  state.ensure_active()
  local comments = state.get_comments()
  if #comments == 0 then
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local file = utils.normalize_path(vim.api.nvim_buf_get_name(bufnr))
  local row = vim.api.nvim_win_get_cursor(0)[1]

  -- Find comments for current line
  local line_comments = {}
  for _, comment_data in ipairs(comments) do
    if comment_data.file == file and row >= comment_data.line_start and row <= comment_data.line_end then
      table.insert(line_comments, comment_data)
    end
  end

  if #line_comments == 0 then
    return
  end

  -- Show comments in floating window
  ui.show_comment_list(line_comments)
end

--- List all comments
function M.list_comments()
  require("code-review.list").list_comments()
end

--- Delete comment at cursor position
function M.delete_comment_at_cursor()
  state.ensure_active()
  local comments = state.get_comments()
  if #comments == 0 then
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local file = utils.normalize_path(vim.api.nvim_buf_get_name(bufnr))
  local row = vim.api.nvim_win_get_cursor(0)[1]

  -- Find comments for current line
  local line_comments = {}
  for _, comment_data in ipairs(comments) do
    if comment_data.file == file and row >= comment_data.line_start and row <= comment_data.line_end then
      table.insert(line_comments, comment_data)
    end
  end

  if #line_comments == 0 then
    vim.notify("No comment at cursor position", vim.log.levels.WARN)
    return
  end

  -- If multiple comments, let user choose
  if #line_comments > 1 then
    vim.ui.select(line_comments, {
      prompt = "Select comment to delete:",
      format_item = function(item)
        local first_line = item.comment:match("^[^\n]*") or item.comment
        if #first_line > 50 then
          first_line = first_line:sub(1, 47) .. "..."
        end
        return string.format("Line %d-%d: %s", item.line_start, item.line_end, first_line)
      end,
    }, function(choice)
      if choice then
        state.delete_comment(choice.id)
        require("code-review.comment").update_indicators()
        vim.notify("Comment deleted")
      end
    end)
  else
    -- Single comment, confirm deletion
    local comment_data = line_comments[1]
    local first_line = comment_data.comment:match("^[^\n]*") or comment_data.comment
    if #first_line > 50 then
      first_line = first_line:sub(1, 47) .. "..."
    end

    vim.ui.select({ "Yes", "No" }, {
      prompt = string.format("Delete comment: %s?", first_line),
    }, function(choice)
      if choice == "Yes" then
        state.delete_comment(comment_data.id)
        require("code-review.comment").update_indicators()
        vim.notify("Comment deleted")
      end
    end)
  end
end

--- Get input buffer functions for keymapping
---@param bufnr number Buffer number
---@return table Functions for the buffer
function M.get_input_buffer_functions(bufnr)
  -- We need to store the callback function somewhere accessible
  -- This will be set by the UI module
  return {
    submit = function()
      -- Trigger submit action for this buffer
      if vim.b[bufnr]._code_review_submit then
        vim.b[bufnr]._code_review_submit()
      end
    end,
    cancel = function()
      -- Trigger cancel action for this buffer
      if vim.b[bufnr]._code_review_cancel then
        vim.b[bufnr]._code_review_cancel()
      end
    end,
  }
end

return M
