local config = require("simple-calendar.config")
local calendar_core = require("simple-calendar.calendar_core")
local file_utils = require("simple-calendar.file_utils")
local ui_navigation = require("simple-calendar.ui_navigation")

local M = {}

-- Global state (shared with UI module)
local _current_win = nil
local _programmatic_cursor_move_count = 0

-- Share state with UI module
ui_navigation.set_shared_state({
    _current_win = _current_win,
    _programmatic_cursor_move_count = _programmatic_cursor_move_count,
})

function M.setup(user_config)
    if user_config == nil then
        return
    end

    local warn_level = vim.log.levels and vim.log.levels.WARN or 2
    local function log_warn(message)
        vim.notify("simple-calendar: " .. message, warn_level)
    end

    for k, v in pairs(user_config) do
        if k == "completed_task_markers" and type(v) == "table" then
            -- Validate that all markers are single characters (space not allowed)
            local valid_markers = {}
            for _, marker in ipairs(v) do
                if type(marker) ~= "string" then
                    log_warn("Invalid completed_task_marker given - must be 'string'")
                elseif vim.fn.strchars(marker) ~= 1 then
                    log_warn("Invalid completed_task_marker '" .. marker .. "' - must be a single character")
                elseif marker == " " then
                    log_warn("Invalid completed_task_marker ' ' - space is not allowed as a marker")
                else
                    table.insert(valid_markers, marker)
                end
            end
            config._config[k] = valid_markers
        else
            config._config[k] = v
        end
    end
end

-- Persistent autocmd group for cleanup
local _au_group = vim.api.nvim_create_augroup("SimpleCalendarGlobal", {})

-- Set up autocmd to clean up when calendar window closes
vim.api.nvim_create_autocmd("WinClosed", {
    group = _au_group,
    callback = function(event)
        if _current_win == event.win then
            _current_win = nil
            ui_navigation.set_shared_state({ _current_win = nil })
        end
    end,
})

local function with_programmatic_move(fn)
    _programmatic_cursor_move_count = _programmatic_cursor_move_count + 1
    ui_navigation.set_shared_state({ _programmatic_cursor_move_count = _programmatic_cursor_move_count })
    local ok, err = pcall(fn)
    _programmatic_cursor_move_count = _programmatic_cursor_move_count - 1
    ui_navigation.set_shared_state({ _programmatic_cursor_move_count = _programmatic_cursor_move_count })
    if not ok then error(err) end
end

-- Make with_programmatic_move accessible to UI module
ui_navigation.set_shared_state({ with_programmatic_move = with_programmatic_move })

function M.show_calendar(date)
    -- Clean up any invalid window reference
    if _current_win and not vim.api.nvim_win_is_valid(_current_win) then
        _current_win = nil
        ui_navigation.set_shared_state({ _current_win = nil })
    end

    -- Close any existing calendar window before creating a new one
    ui_navigation.UI.close_calendar_window(_current_win)

    local state = {}

    if date then
        state.now = date
        state.selected_day = date.day
    else
        local extracted_date = file_utils.extract_date_from_filename()
        if extracted_date then
            state.now = extracted_date
            state.selected_day = extracted_date.day
        else
            state.now = os.date("*t")
            state.selected_day = state.now.day
        end
    end

    state.grid, state.calendar_lines = calendar_core.refresh_calendar(state.now)

    local max_width = 0
    for _, line in ipairs(state.calendar_lines) do
        max_width = math.max(max_width, #line)
    end

    local width = max_width
    local height = #state.calendar_lines

    -- Calculate window position (centered)
    local col, row = ui_navigation.UI.calculate_window_position(width, height)
    if not col then
        -- Warning already shown by calculate_window_position
        return
    end

    state.buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, state.calendar_lines)
    vim.api.nvim_buf_set_option(state.buf, "filetype", "calendar")
    vim.api.nvim_buf_set_option(state.buf, "buftype", "nofile")
    vim.api.nvim_buf_set_option(state.buf, "modifiable", false)
    vim.api.nvim_buf_set_option(state.buf, "readonly", true)

    state.win = vim.api.nvim_open_win(state.buf, true, {
        relative = "editor",
        width = width,
        height = height,
        col = col,
        row = row,
        style = "minimal",
        border = "rounded",
    })
    vim.api.nvim_win_set_option(state.win, "cursorline", false)
    vim.api.nvim_win_set_option(state.win, "cursorcolumn", false)

    _current_win = state.win
    ui_navigation.set_shared_state({ _current_win = state.win })

    local au_group = vim.api.nvim_create_augroup("SimpleCalendarCursor", { clear = true })
    vim.api.nvim_create_autocmd("CursorMoved", {
        group = au_group,
        buffer = state.buf,
        callback = function()
            if _programmatic_cursor_move_count > 0 then
                return
            end

            local cursor = vim.api.nvim_win_get_cursor(state.win)
            local buffer_line = cursor[1] - 1
            local grid_line = buffer_line - 2
            local cursor_col = cursor[2]

            if grid_line >= 0 and grid_line < #state.grid then
                local current_day = ui_navigation.UI.day_from_position(state.grid, grid_line, cursor_col)
                if current_day and current_day ~= state.selected_day then
                    state.selected_day = current_day
                    ui_navigation.UI.update_highlight(state)
                else
                    ui_navigation.UI.ensure_cursor_position(state)
                end
            else
                ui_navigation.UI.ensure_cursor_position(state)
            end
        end,
    })

    vim.api.nvim_create_autocmd("VimResized", {
        group = au_group,
        callback = function()
            if state.win and vim.api.nvim_win_is_valid(state.win) then
                ui_navigation.UI.reposition_window(state.win)
            end
        end,
    })

    ui_navigation.UI.update_highlight(state)

    ui_navigation.Navigation.setup_keybindings(state)
end

-- Export internal modules for testing when in test mode
if vim.g and vim.g.SIMPLE_CALENDAR_TEST then
    M._test = {
        CalendarCore = calendar_core,
        FileUtils = file_utils,
        UI = ui_navigation.UI,
        Navigation = ui_navigation.Navigation,
        _config = config._config,
        MONTH_NAMES = config.MONTH_NAMES,
    }
end

return M
