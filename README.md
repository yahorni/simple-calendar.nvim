# simple-calendar.nvim

A simple calendar plugin for Neovim.

![Simple calendar](assets/simple-calendar.png)

## Features

- Navigation using h/j/k/l keys
- Month switching using p/n keys
- Date selection that opens files based on configurable pattern
- Automatically opens on current file date when filename matches pattern

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{ "yahorni/simple-calendar.nvim" }
```

## Usage

Open the calendar:

```lua
:lua require('simple-calendar').show_calendar()
```

When opened, the calendar will automatically show the date from the current filename if it matches the `daily_path_pattern` (e.g., `2024-10-15.md`). Otherwise, it shows the current date.

Or create a keymap:

```lua
vim.keymap.set('n', '<leader>c', require("simple-calendar").show_calendar, { desc = "Open [C]alendar" })
```

## Keybindings

When the calendar is open:

- `h` - Move left to previous day
- `j` - Move down to next week
- `k` - Move up to previous week
- `l` - Move right to next day
- `p` - Switch to previous month
- `n` - Switch to next month
- `<CR>` - Select current date and open corresponding file
- `q` - Close calendar window

## Configuration

No configuration required. Optional setup:

```lua
require("simple-calendar").setup({
    -- Path pattern to daily notes
    daily_path_pattern = vim.fn.expand("~") .. "/journal/%Y-%m-%d.md",
    -- Highlight days whose daily note contains unfinished tasks
    highlight_unfinished_tasks = true,
    -- Completed task markers (default: {"x", "-"})
    completed_task_markers = {"x", "-"},
})
```

### Path Pattern Support

The `daily_path_pattern` supports directory structures with date components:

- **Simple pattern**: `%Y-%m-%d.md` → `2024-10-15.md`
- **Complex patterns**:
  - `%Y-%m %B/%Y-%m-%d.md` → `2024-10 October/2024-10-15.md`
  - `notes/%Y/%m-%B/%Y-%m-%d.md` → `notes/2024/10-October/2024-10-15.md`

Supported strftime tokens:
- `%Y` - 4-digit year (e.g., 2024)
- `%m` - 2-digit month (e.g., 10)
- `%d` - 2-digit day (e.g., 15)
- `%B` - Full month name (e.g., October)

When `highlight_unfinished_tasks` is enabled:
- Days with unfinished markdown tasks (like `- [ ]`, `* [ ]`, `+ [ ]`) are highlighted with `Todo` highlight group
- Days where the file doesn't exist are highlighted with `Comment` highlight group
- Days with only completed tasks (configurable markers, default: `- [x]`, `- [-]`) highlighted as usual
- Supports `-`, `*`, `+` markdown list markers

Use `completed_task_markers` to customize which bracket contents mark a task as completed.
Markers must be single characters (e.g., `"x"`, `"-"`, `"✓"`, `"✅"`). Matching is exact - spaces in brackets are not trimmed.

## Testing

Run the tests:

```bash
nvim --headless -u tests/runner.lua
```

## License

GNU Affero General Public License v3.0
