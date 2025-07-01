local M = {}

-- Default configuration
local defaults = {
  -- UI settings
  ui = {
    -- Floating window settings for comment input
    input_window = {
      width = 60,
      height = 1,
      max_height = 20, -- Maximum height when content requires scrolling
      border = "rounded",
      title = " Add Comment (C-CR to submit) ",
      title_pos = "center",
    },
    -- Preview window settings
    preview = {
      format = "markdown", -- 'markdown' or 'json' or 'auto' (auto = same as output.format)
      split = "vertical", -- 'vertical' or 'horizontal' or 'float'
      vertical_width = 80,
      horizontal_height = 20,
      float = {
        width = 0.8,
        height = 0.8,
        border = "rounded",
        title = " Review Preview ",
        title_pos = "center",
      },
    },
  },
  -- Output settings
  output = {
    format = "markdown", -- 'markdown' or 'json'
    date_format = "%Y-%m-%d %H:%M:%S",
    -- Default save directory (nil means current directory)
    save_dir = nil,
  },
  -- Keymaps (set to false to disable all keymaps)
  keymaps = {
    -- Clear all comments
    clear = {
      mode = "n",
      key = "<leader>rx",
    },
    -- Add comment at cursor/selection
    add_comment = {
      mode = { "n", "v" },
      key = "<leader>rc",
    },
    -- Preview review
    preview = {
      mode = "n",
      key = "<leader>rp",
    },
    -- Save review to file
    save = {
      mode = "n",
      key = "<leader>rw",
    },
    -- Copy review to clipboard
    copy = {
      mode = "n",
      key = "<leader>ry",
    },
    -- Show comment at cursor
    show_comment = {
      mode = "n",
      key = "<leader>rs",
    },
    -- List all comments
    list_comments = {
      mode = "n",
      key = "<leader>rl",
    },
  },
  -- Integration settings
  integrations = {
    -- Automatically detect and use available pickers
    picker = "auto", -- 'auto', 'telescope', 'fzf-lua', 'snacks', false
  },
}

local config = {}

--- Merge user config with defaults
---@param opts table User configuration
---@return table
local function merge_config(opts)
  return vim.tbl_deep_extend("force", defaults, opts)
end

--- Setup configuration
---@param opts table User configuration
function M.setup(opts)
  config = merge_config(opts)

  -- Create highlight groups
  vim.api.nvim_set_hl(0, "CodeReviewSign", { link = "Comment", default = true })
  vim.api.nvim_set_hl(0, "CodeReviewVirtualText", { link = "Comment", default = true })
end

--- Get configuration value
---@param path string Dot-separated path to config value
---@return any
function M.get(path)
  local value = config
  for key in path:gmatch("[^.]+") do
    if type(value) ~= "table" then
      return nil
    end
    value = value[key]
  end
  return value
end

--- Get entire configuration
---@return table
function M.get_all()
  return config
end

return M
