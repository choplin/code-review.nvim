.PHONY: all format lint check clean

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