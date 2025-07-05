local M = {}

--- Normalize path to the most appropriate relative or absolute form
--- Based on the context.lua implementation
---@param path string Path to normalize
---@return string
function M.normalize_path(path)
  -- Convert to absolute path first
  local absolute_path = vim.fn.fnamemodify(path, ":p")

  -- Try git root
  local search_dir = vim.fn.fnamemodify(absolute_path, ":h")
  local git_file = vim.fn.findfile(".git", search_dir .. ";")
  local git_dir = vim.fn.finddir(".git", search_dir .. ";")
  local git_path = git_file ~= "" and git_file or git_dir

  if git_path ~= "" then
    local git_root = vim.fn.fnamemodify(git_path, ":h")
    if vim.startswith(absolute_path, git_root) then
      local relative = absolute_path:sub(#git_root + 1)
      if relative:sub(1, 1) == "/" then
        relative = relative:sub(2)
      end
      return relative
    end
  end

  -- Try cwd
  local cwd = vim.fn.getcwd()
  if vim.startswith(absolute_path, cwd) then
    return vim.fn.fnamemodify(absolute_path, ":.")
  end

  -- Try home directory
  local home_relative = vim.fn.fnamemodify(absolute_path, ":~")
  if home_relative ~= absolute_path then
    return home_relative
  end

  -- Fallback to absolute path
  return absolute_path
end

--- Get visual selection range
--- Based on the context.lua implementation
---@return number start_line
---@return number start_col
---@return number end_line
---@return number end_col
function M.get_visual_range()
  local start_line, start_col = unpack(vim.fn.getpos("v"), 2, 3)
  local end_line, end_col = unpack(vim.fn.getpos("."), 2, 3)

  -- Ensure start is before end
  if start_line > end_line or (start_line == end_line and start_col > end_col) then
    start_line, end_line = end_line, start_line
    start_col, end_col = end_col, start_col
  end

  -- Handle visual line mode
  if end_col == 2147483647 then
    end_col = vim.fn.col({ end_line, "$" }) - 1
  end

  return start_line, start_col, end_line, end_col
end

--- Get the current selection context
---@param context_lines number? Number of context lines
---@return table
function M.get_selection_context(context_lines)
  context_lines = context_lines or 0
  local mode = vim.fn.mode()
  local bufnr = vim.api.nvim_get_current_buf()
  local file_path = vim.api.nvim_buf_get_name(bufnr)

  local context = {
    file = M.normalize_path(file_path),
    bufnr = bufnr,
  }

  if mode:match("[vV]") then
    -- Visual mode
    local start_line, _, end_line, _ = M.get_visual_range()
    context.line_start = start_line
    context.line_end = end_line
  else
    -- Normal mode
    local row = vim.api.nvim_win_get_cursor(0)[1]
    context.line_start = math.max(1, row - context_lines)
    context.line_end = row + context_lines
  end

  -- Get the actual lines
  local lines = vim.api.nvim_buf_get_lines(bufnr, context.line_start - 1, context.line_end, false)
  context.lines = lines
  context.line_count = #lines

  return context
end

--- Escape special characters for literal matching
---@param str string
---@return string
function M.escape_pattern(str)
  return str:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
end

--- Create a unique file name for saving
---@param format string Deprecated, always uses markdown
---@return string
function M.generate_filename(format)
  local timestamp = os.date("%Y-%m-%d-%H%M%S")
  return string.format("code-review-%s.md", timestamp)
end

--- Copy text to clipboard
---@param text string
---@return boolean success
function M.copy_to_clipboard(text)
  local ok, result = pcall(vim.fn.setreg, "+", text)
  if ok then
    return true
  else
    vim.notify("Failed to copy to clipboard: " .. tostring(result), vim.log.levels.ERROR)
    return false
  end
end

--- Get the storage directory
---@param dir string Directory path from config
---@return string directory path
function M.get_storage_dir(dir)
  -- Expand ~ and environment variables
  local expanded_dir = vim.fn.expand(dir)

  -- Check if it's an absolute path
  if vim.fn.isdirectory(expanded_dir) == 1 or expanded_dir:match("^/") or expanded_dir:match("^~") then
    -- Absolute path, use as-is
    return expanded_dir
  else
    -- Relative path, resolve from project root
    local project_root = M.get_project_root()
    return project_root .. "/" .. dir
  end
end

--- Get project root (git root or cwd)
---@return string
function M.get_project_root()
  -- Try to find git root
  local git_root = vim.fn.finddir(".git", vim.fn.getcwd() .. ";")
  if git_root ~= "" then
    return vim.fn.fnamemodify(git_root, ":h")
  end

  -- Fallback to current directory
  return vim.fn.getcwd()
end

--- Generate a unique filename for auto-save
---@return string filename
function M.generate_auto_save_filename()
  local timestamp = os.date("%Y-%m-%d-%H%M%S")
  local ms = vim.fn.reltimefloat(vim.fn.reltime()) * 1000
  local seq = string.format("%03d", ms % 1000)
  return string.format("%s-%s.md", timestamp, seq)
end

--- Save text to a file
---@param filepath string
---@param content string
---@return boolean success
function M.save_to_file(filepath, content)
  -- Create directory if it doesn't exist
  local dir = vim.fn.fnamemodify(filepath, ":h")
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, "p")
  end

  -- Write content to file
  local file = io.open(filepath, "w")
  if not file then
    vim.notify("Failed to open file: " .. filepath, vim.log.levels.ERROR)
    return false
  end

  file:write(content)
  file:close()
  return true
end

return M
