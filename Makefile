.PHONY: all format lint check clean test test-all

all: format lint

format:
	@echo "Formatting with stylua..."
	@stylua . || echo "stylua not installed, run: cargo install stylua"

lint:
	@echo "Linting with luacheck..."
	@luacheck . || echo "luacheck not installed, run: luarocks install luacheck"

check: format lint

clean:
	@echo "Cleaning up..."
	@find . -name "*.swp" -delete
	@find . -name "*.swo" -delete
	@find . -name "*~" -delete

test: test-all

test-all:
	@echo "Running all tests..."
	@nvim --headless --noplugin -u tests/minimal_init.lua \
		-c "lua MiniTest.run({ collect = { find_files = function() return vim.fn.glob('tests/test_*.lua', false, true) end }, execute = { reporter = MiniTest.gen_reporter.stdout({ quit_on_finish = true }) } })" 2>&1

test-%:
	@echo "Running test: $*..."
	@nvim --headless --noplugin -u tests/minimal_init.lua \
		-c "lua MiniTest.run_file('tests/test_$*.lua', { execute = { reporter = MiniTest.gen_reporter.stdout({ quit_on_finish = true }) } })" 2>&1
