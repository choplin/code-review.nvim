-- Add project root to 'runtimepath' to be able to use 'lua' files
vim.cmd([[let &rtp.=','.getcwd()]])

-- Set up 'mini.test' only when calling headless Neovim (like with `make test`)
if #vim.api.nvim_list_uis() == 0 then
  -- Add 'mini.nvim' to 'runtimepath' to be able to use 'mini.test'
  -- Assumes that 'mini.nvim' is stored as 'deps/mini.nvim'
  vim.cmd("set rtp+=deps/mini.nvim")

  -- Set up 'mini.test'
  require("mini.test").setup()

  -- Make MiniTest globally available like in mini.nvim tests
  _G.MiniTest = require("mini.test")

  -- Add custom expectations
  MiniTest.expect.match = MiniTest.new_expectation("string matching", function(str, pattern)
    return str:find(pattern) ~= nil
  end, function(str, pattern)
    return string.format("Pattern: %s\nObserved string: %s", vim.inspect(pattern), str)
  end)
end
