local M = {}
local _current_win = nil
local _global_au_group = nil


function M.setup(user_config)
    if user_config == nil then
        return
    end

    local warn_level = vim.log.levels and vim.log.levels.WARN or 2
    local function log_warn(message)
        vim.notify("simple-calendar: " .. message, warn_level)
    end

    local function validate_completed_task_markers(markers)
        local valid_markers = {}
        for _, marker in ipairs(markers) do
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
        return valid_markers
    end

    local config = require("simple-calendar.config")
    for key, value in pairs(user_config) do
        local default = config[key]
        if default ~= nil then
            if key == "completed_task_markers" then
                if type(value) == "table" then
                    config[key] = validate_completed_task_markers(value)
                else
                    log_warn("completed_task_markers must be a table")
                end
            else
                if type(value) == type(default) then
                    config[key] = value
                else
                    log_warn(key .. " must be " .. type(default))
                end
            end
        end
    end

    -- Warn on weekly_path_pattern values that cannot resolve a week:
    --   - %V without %G/%g: the ISO week-year is missing, so the week is
    --     ambiguous across the new-year boundary.
    --   - no resolvable tokens at all: neither an ISO week pair (%V + %G/%g)
    --     nor a full date (%Y + month + %d), so `weekly("next")` /
    --     `weekly("previous")` can never resolve the current week.
    local pattern = config.weekly_path_pattern
    if type(pattern) == "string" and pattern ~= "" then
        local has_week = pattern:find("%%V") ~= nil
        local has_iso_year = pattern:find("%%G") ~= nil or pattern:find("%%g") ~= nil
        local has_year = pattern:find("%%Y") ~= nil
        local has_month = pattern:find("%%[mBb]") ~= nil
        local has_day = pattern:find("%%d") ~= nil

        if has_week and not has_iso_year then
            log_warn("weekly_path_pattern uses %V without %G/%g; pair %V with %G (or %g) "
                .. "so next/previous can resolve the week")
        elseif not (has_week and has_iso_year) and not (has_year and has_month and has_day) then
            log_warn("weekly_path_pattern has no resolvable week tokens; pair %V with %G/%g, or use %Y/%m/%d")
        end
    end
end

function M.open(date)
    local file_utils = require("simple-calendar.file_utils")
    local ui_navigation = require("simple-calendar.ui_navigation")
    local calendar_core = require("simple-calendar.calendar_core")

    if _current_win and not vim.api.nvim_win_is_valid(_current_win) then
        _current_win = nil
    end

    ui_navigation.UI.close_calendar_window(_current_win)

    local state = {}

    if date then
        local valid_date = calendar_core.validate_date(date)
        if not valid_date then
            vim.notify("simple-calendar: Invalid date table", vim.log.levels.ERROR)
            valid_date = calendar_core.validate_date(os.date("*t")) -- fallback: open today's calendar
        end
        state.now = valid_date
        state.selected_day = valid_date.day
    else
        local extracted_date = file_utils.extract_date_from_filename()
        if extracted_date then
            state.now = extracted_date
            state.selected_day = extracted_date.day
        else
            -- Focus the week of the currently open weekly note.
            local extracted_week = file_utils.extract_week_from_filename()
            if extracted_week then
                -- Current week: focus today instead of the Monday anchor.
                local today = calendar_core.validate_date(os.date("*t"))
                if os.time(calendar_core.get_week_anchor(today)) == os.time(extracted_week) then
                    state.now, state.selected_day = today, today.day
                else
                    -- Other weeks: focus Thursday, the middle of the week.
                    state.now = calendar_core.shift_days(extracted_week, 3)
                    state.selected_day = state.now.day
                end
            else
                state.now = calendar_core.validate_date(os.date("*t"))
                state.selected_day = state.now.day
            end
        end
    end

    state.grid, state.calendar_lines = calendar_core.refresh_calendar(state.now)

    local max_width = 0
    for _, line in ipairs(state.calendar_lines) do
        max_width = math.max(max_width, #line)
    end

    local width = max_width
    local height = #state.calendar_lines

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

    if _global_au_group == nil then
        _global_au_group = vim.api.nvim_create_augroup("SimpleCalendarGlobal", {})
        vim.api.nvim_create_autocmd("WinClosed", {
            group = _global_au_group,
            callback = function(event)
                if _current_win == event.win then
                    _current_win = nil
                end
            end,
        })
    end

    ui_navigation.UI.configure_highlight_group()
    ui_navigation.UI.configure_events_handling(state)
    ui_navigation.UI.update_highlight(state)
    ui_navigation.Navigation.setup_keybindings(state)
end

function M.journal(arg)
    local journal = require("simple-calendar.journal")

    local string_or_date
    if type(arg) == "table" and arg["args"] ~= nil then
        string_or_date = arg.args
    else
        string_or_date = arg
    end
    return journal.open_day(string_or_date)
end

function M.weekly(arg)
    local journal = require("simple-calendar.journal")

    local string_or_date
    if type(arg) == "table" and arg["args"] ~= nil then
        string_or_date = arg.args
    else
        string_or_date = arg
    end
    return journal.open_week(string_or_date)
end

-- Export internal modules for testing when in test mode
if vim.g and vim.g.SIMPLE_CALENDAR_TEST then
    M._test = {
        CalendarCore = require("simple-calendar.calendar_core"),
        FileUtils = require("simple-calendar.file_utils"),
        UI = require("simple-calendar.ui_navigation").UI,
        Navigation = require("simple-calendar.ui_navigation").Navigation,
        _config = require("simple-calendar.config"),
    }
end

return M
