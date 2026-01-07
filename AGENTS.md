# AGENTS.md

## Build/Lint/Test Commands
- **Build**: No build system (Neovim plugin)
- **Test**: `nvim --headless -u tests/runner.lua` (runs all unit tests)
- **Lint**: No linting tools configured
- **Validation**: Manual testing via `:lua require('simple-calendar').show_calendar()`

## Test Structure
- **Location**: `tests/` directory
- **Runner**: `tests/runner.lua` - runs all test suites with color output
- **Helpers**: `tests/helpers.lua` - assertion utilities and mock functions
- **Test Suites** (43 total tests):
  - `calendar_core_spec.lua` - CalendarCore module (date calculations, formatting, month switching)
  - `file_utils_spec.lua` - FileUtils module (pattern parsing, file status, date extraction)
  - `navigation_spec.lua` - Navigation module (state management, keybindings, month transitions)
  - `config_spec.lua` - Configuration validation and merging behavior
  - `integration_spec.lua` - Basic plugin workflow smoke tests
- **Execution**: All tests run in headless Neovim with `vim.g.SIMPLE_CALENDAR_TEST = true` flag
- **Assertions**: Custom assertion library with `assert.assert_equal`, `assert.assert_nil`, etc.
- **Mock Compatibility**: All mock functions use proper Neovim API signatures to prevent `lua_ls` warnings

## Code Style Guidelines
- **Language**: Lua (Neovim plugin)
- **Indentation**: 4 spaces (no tabs) - per .editorconfig
- **Line length**: Max 120 characters
- **Quotes**: Double quotes for strings
- **Naming**:
  - Constants: UPPER_SNAKE_CASE (e.g., `MONTH_NAMES`)
  - Functions: snake_case (e.g., `handle_date_selection`)
  - Variables: snake_case (e.g., `calendar_lines`)
  - Module: `M` for main module table
- **Imports**: Use local variables for modules
- **Error handling**: Explicit nil checks and early returns
- **Formatting**:
  - Trailing table separators: smart
  - Table formatting: vertical alignment for arrays
  - Function spacing: consistent line breaks
- **Neovim API**: Use `vim.api.nvim_*` functions for buffer/window operations
- **Keymaps**: Use `vim.api.nvim_buf_set_keymap` with `noremap=true`

## Project Structure
- Main module: `lua/simple-calendar/init.lua`
- Documentation: `doc/simple-calendar.txt`
- No external dependencies
- Pure Lua implementation for Neovim

## Module Overview
- **Entry point**: `M.show_calendar()` - opens calendar window
- **Configuration**: `_config` table with `path_pattern` and `highlight_unfinished_tasks` options
- **Date handling**: Uses Lua `os.date`/`os.time` for calendar calculations
- **Pattern matching**: Supports strftime patterns (`%Y`, `%m`, `%d`, `%B`) via `convert_pattern_to_regex()`
- **Navigation**: Month switching preserves weekday when moving vertically (k/j keys)
- **Keybindings**: Mapped via `vim.api.nvim_buf_set_keymap` with callbacks
