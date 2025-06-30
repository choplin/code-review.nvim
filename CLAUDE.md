# Development Guidelines for code-review.nvim

This document outlines the development rules and conventions for maintaining code-review.nvim.

## Code Quality

### Formatting

- Use **stylua** for consistent code formatting
- Run `make format` before committing
- Configuration is in `.stylua.toml`

### Linting

- Use **luacheck** for static analysis
- Run `make lint` before committing
- Configuration is in `.luacheckrc`
- All warnings must be resolved

### Pre-commit Checklist

```bash
# Run both formatter and linter
make check
```

## Git Conventions

### Commit Messages

Follow [Conventional Commits](https://www.conventionalcommits.org/) specification:

```
<type>(<scope>): <subject>

<body>

<footer>
```

#### Types

- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes (formatting, missing semicolons, etc)
- `refactor`: Code refactoring without changing functionality
- `test`: Adding or modifying tests
- `chore`: Maintenance tasks, dependency updates

#### Examples

```
feat(ui): add floating window position adjustment

fix(comment): resolve undefined variable warnings

docs: update installation instructions

chore: bump stylua version
```

### Scope (optional)

- `ui`: User interface components
- `comment`: Comment functionality
- `formatter`: Output formatting
- `state`: Session state management
- `config`: Configuration handling

## Changelog

Follow [Keep a Changelog](https://keepachangelog.com/) format:

### Categories

- `Added` for new features
- `Changed` for changes in existing functionality
- `Deprecated` for soon-to-be removed features
- `Removed` for now removed features
- `Fixed` for any bug fixes
- `Security` in case of vulnerabilities

### Guidelines

1. Keep an `Unreleased` section at the top
2. Update the changelog with every PR
3. When releasing, move `Unreleased` items to a new version section
4. Include the release date in ISO format (YYYY-MM-DD)

## Release Process

1. Update `CHANGELOG.md`
   - Move items from `Unreleased` to new version section
   - Add release date

2. Commit with conventional commit message
   ```bash
   git commit -m "chore: release v0.2.0"
   ```

3. Create and push tag
   ```bash
   git tag v0.2.0
   git push origin v0.2.0
   ```

4. GitHub Actions will automatically create the release

## Code Style Guidelines

### Lua Conventions

1. Use early returns to reduce nesting
2. Prefer local functions when they're only used within the module
3. Use meaningful variable names (avoid single letters except for loops)
4. Add type annotations for public functions
5. Group related functions together

### Documentation

1. All public functions must have LuaLS annotations
2. Use `---@param`, `---@return` for type information
3. Add descriptive comments for complex logic
4. Update README.md when adding new features

### Error Handling

1. Use `vim.notify` for user-facing messages
2. Validate inputs early
3. Provide helpful error messages
4. Never silently fail

## Testing

While formal tests are not yet implemented, ensure:

1. Manual testing of all code paths
2. Test with both nui.nvim present and absent
3. Test with various Neovim versions (0.10+)
4. Test visual mode and normal mode operations

## Dependencies

1. Keep dependencies minimal
2. Always provide fallbacks when optional dependencies are missing
3. Document why each dependency is needed

## Pull Request Guidelines

1. Create feature branches from `main`
2. Keep PRs focused on a single feature/fix
3. Update documentation as needed
4. Ensure CI passes (formatting and linting)
5. Add changelog entry in `Unreleased` section