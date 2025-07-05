-- vim: ft=lua tw=80

-- Rerun tests only if their modification time changed.
cache = true

std = luajit
codes = true

self = false

-- Glorious list of warnings: https://luacheck.readthedocs.io/en/stable/warnings.html
ignore = {
  "212", -- Unused argument, In the case of callback function, _arg_name is easier to understand than _, so this option is set to off.
  "631", -- max_line_length, vscode pkg URL is too long
}

-- Exclude dependency directories
exclude_files = {
  "deps/",
}

-- Global objects defined by the C code
read_globals = {
  "vim",
}

globals = {
  "vim.g",
  "vim.b",
  "vim.w",
  "vim.o",
  "vim.bo",
  "vim.wo",
  "vim.go",
  "vim.env",
}

-- Unused variables that are intentional
files = {
  ["lua/code-review/formatter.lua"] = {
    ignore = {
      "i", -- loop counter in parse_markdown
    },
  },
  ["tests/"] = {
    read_globals = {
      "MiniTest",
    },
  },
  ["tests/minimal_init.lua"] = {
    ignore = {
      "122", -- Setting read-only field MiniTest.expect.match (intentional extension)
    },
  },
  ["tests/test_formatter.lua"] = {
    ignore = {
      "122", -- Setting read-only field vim.notify (intentional mocking)
    },
  },
}