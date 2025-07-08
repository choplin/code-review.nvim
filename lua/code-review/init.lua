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
  state.init()

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

  vim.api.nvim_create_user_command("CodeReviewReply", function()
    M.reply_to_comment_at_cursor()
  end, { desc = "Reply to comment at cursor position" })

  vim.api.nvim_create_user_command("CodeReviewResolve", function()
    M.resolve_thread_at_cursor()
  end, { desc = "Resolve thread at cursor position" })

  vim.api.nvim_create_user_command("CodeReviewSetStatus", function(args)
    if args.args == "" then
      vim.notify("Usage: :CodeReviewSetStatus <draft|open|resolved|closed>", vim.log.levels.ERROR)
      return
    end
    M.set_review_status(args.args)
  end, {
    desc = "Set review status",
    nargs = 1,
    complete = function()
      return { "draft", "open", "resolved", "closed" }
    end,
  })

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
            reply_comment = "Reply to comment at cursor",
            resolve_thread = "Resolve thread at cursor",
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
            reply_comment = M.reply_to_comment_at_cursor,
            resolve_thread = M.resolve_thread_at_cursor,
          }

          if func[action] then
            vim.keymap.set(mode, key, func[action], { desc = desc[action] })
          end
        end
      end
    end
  end

  -- Setup autocmd to sync state and update UI (only for file backend)
  if config.get("comment.storage.backend") == "file" then
    vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "CursorHold" }, {
      group = vim.api.nvim_create_augroup("CodeReviewSync", { clear = true }),
      callback = function()
        -- Sync from storage and update UI
        require("code-review.state").sync_from_storage()
      end,
      desc = "Sync code review state and update UI",
    })
  end
end

--- Clear all comments
function M.clear()
  state.clear()
end

--- Add a comment at the current location
---@param context_lines number? Number of lines before/after to include
function M.add_comment(context_lines)
  comment.add(context_lines)
end

--- Show preview of the review
function M.preview()
  local comments = state.get_comments()
  if #comments == 0 then
    vim.notify("No comments to preview", vim.log.levels.WARN)
    return
  end

  local content = formatter.format(comments)
  ui.show_preview(content, "markdown")
end

--- Save review to file
---@param path string? File path to save to
function M.save(path)
  local comments = state.get_comments()
  if #comments == 0 then
    vim.notify("No comments to save", vim.log.levels.WARN)
    return
  end

  local review_utils = require("code-review.utils")

  -- Generate default path if not provided
  if not path then
    local save_dir = config.get("output.save_dir") or vim.fn.getcwd()
    local filename = review_utils.generate_filename("markdown")
    local default_path = vim.fn.fnamemodify(save_dir .. "/" .. filename, ":p")

    -- Use vim.ui.input to get the save path
    vim.ui.input({
      prompt = "Save to: ",
      default = default_path,
      completion = "file",
    }, function(input)
      if input and input ~= "" then
        local content = formatter.format(comments)
        formatter.save_to_file(content, input)
      end
    end)
  else
    -- If path is provided, save directly
    local content = formatter.format(comments)
    formatter.save_to_file(content, path)
  end
end

--- Copy review to clipboard
function M.copy()
  local comments = state.get_comments()
  if #comments == 0 then
    vim.notify("No comments to copy", vim.log.levels.WARN)
    return
  end

  local content = formatter.format(comments)
  vim.fn.setreg("+", content)
  vim.notify("Code reviews copied to clipboard")
end

--- Show comment at cursor position
function M.show_comment_at_cursor()
  local bufnr = vim.api.nvim_get_current_buf()
  local file = utils.normalize_path(vim.api.nvim_buf_get_name(bufnr))
  local row = vim.api.nvim_win_get_cursor(0)[1]

  -- Find comments for current line
  local line_comments = state.get_comments_at_location(file, row)

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

--- Reply to comment at cursor position
function M.reply_to_comment_at_cursor()
  local bufnr = vim.api.nvim_get_current_buf()
  local file = utils.normalize_path(vim.api.nvim_buf_get_name(bufnr))
  local row = vim.api.nvim_win_get_cursor(0)[1]

  -- Find comments for current line
  local line_comments = state.get_comments_at_location(file, row)

  if #line_comments == 0 then
    vim.notify("No comment at cursor position", vim.log.levels.WARN)
    return
  end

  -- Group comments by thread
  local threads = {}
  for _, comment in ipairs(line_comments) do
    local thread_id = comment.thread_id or comment.id
    if not threads[thread_id] then
      threads[thread_id] = {
        id = thread_id,
        root_comment = nil,
        comments = {}
      }
    end
    table.insert(threads[thread_id].comments, comment)
    -- Track root comment
    if not comment.parent_id then
      threads[thread_id].root_comment = comment
    end
  end

  -- Select thread if multiple threads exist
  local thread_count = vim.tbl_count(threads)
  
  if thread_count == 1 then
    -- Single thread case
    local selected_thread = threads[next(threads)]
    local comment_to_reply = selected_thread.root_comment or selected_thread.comments[1]

    -- Show input UI for reply with the same context as the original comment
    ui.show_comment_input(function(reply_text)
      if reply_text and reply_text ~= "" then
        state.add_reply(comment_to_reply.id, reply_text)
        vim.notify("Reply added", vim.log.levels.INFO)
      end
    end, {
      file = comment_to_reply.file,
      line_start = comment_to_reply.line_start,
      line_end = comment_to_reply.line_end,
      lines = comment_to_reply.context_lines or {},
    }, " Reply to Comment (C-CR to submit) ")
  else
    -- Create thread selection items
    local thread_items = {}
    for _, thread in pairs(threads) do
      -- Always use the first comment (oldest) for preview
      local first_comment = thread.comments[1]
      local preview = first_comment.comment:sub(1, 50)
      if #first_comment.comment > 50 then
        preview = preview .. "..."
      end
      local item = {
        display = string.format("%d. %s (%d comments)", #thread_items + 1, preview, #thread.comments),
        thread = thread
      }
      table.insert(thread_items, item)
    end

    -- Show thread selection
    vim.ui.select(thread_items, {
      prompt = "Select thread to reply to:",
      format_item = function(item)
        return item.display
      end,
    }, function(choice)
      if not choice then
        return
      end
      
      selected_thread = choice.thread
      
      -- Continue with reply process inside callback
      local comment_to_reply = selected_thread.root_comment or selected_thread.comments[1]

      -- Show input UI for reply with the same context as the original comment
      ui.show_comment_input(function(reply_text)
        if reply_text and reply_text ~= "" then
          state.add_reply(comment_to_reply.id, reply_text)
          vim.notify("Reply added", vim.log.levels.INFO)
        end
      end, {
        file = comment_to_reply.file,
        line_start = comment_to_reply.line_start,
        line_end = comment_to_reply.line_end,
        lines = comment_to_reply.context_lines or {},
      }, " Reply to Comment (C-CR to submit) ")
    end)
  end
end

--- Resolve thread at cursor position
function M.resolve_thread_at_cursor()
  local bufnr = vim.api.nvim_get_current_buf()
  local file = utils.normalize_path(vim.api.nvim_buf_get_name(bufnr))
  local row = vim.api.nvim_win_get_cursor(0)[1]

  -- Find comments for current line
  local line_comments = state.get_comments_at_location(file, row)

  if #line_comments == 0 then
    vim.notify("No comment at cursor position", vim.log.levels.WARN)
    return
  end

  -- Get unique threads
  local threads = {}
  for _, c in ipairs(line_comments) do
    if c.thread_id then
      threads[c.thread_id] = true
    end
  end

  local thread_count = vim.tbl_count(threads)
  if thread_count == 0 then
    vim.notify("No thread found", vim.log.levels.WARN)
    return
  elseif thread_count == 1 then
    local thread_id = next(threads)
    state.resolve_thread(thread_id)
  else
    -- Multiple threads, let user choose
    vim.notify("Multiple threads at this location", vim.log.levels.WARN)
  end
end

--- Set review status
---@param status string New status
function M.set_review_status(status)
  local review = require("code-review.review")
  review.update_status(status)
end

--- Delete comment at cursor position
function M.delete_comment_at_cursor()
  local bufnr = vim.api.nvim_get_current_buf()
  local file = utils.normalize_path(vim.api.nvim_buf_get_name(bufnr))
  local row = vim.api.nvim_win_get_cursor(0)[1]

  -- Find comments for current line
  local line_comments = state.get_comments_at_location(file, row)

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
