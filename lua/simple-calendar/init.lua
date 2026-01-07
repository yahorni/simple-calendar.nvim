local M = {}

local MONTH_NAMES = { "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December" }
local WEEKDAYS_HEADER = "Mo Tu We Th Fr Sa Su"

-- Global state
local _config = {
    daily_path_pattern = "%Y-%m-%d.md",
    highlight_unfinished_tasks = false,
    completed_task_markers = { "x", "-" },
}

local _current_win = nil
local _programmatic_cursor_move_count = 0

function M.setup(config)
    if config then
        for k, v in pairs(config) do
            _config[k] = v
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
        end
    end,
})

local function with_programmatic_move(fn)
    _programmatic_cursor_move_count = _programmatic_cursor_move_count + 1
    local ok, err = pcall(fn)
    _programmatic_cursor_move_count = _programmatic_cursor_move_count - 1
    if not ok then error(err) end
end

-- ============================================================================
-- CalendarCore Module
-- ============================================================================

local CalendarCore = {}

function CalendarCore.get_calendar_grid(now)
    local first_day = os.time({ year = now.year, month = now.month, day = 1 })
    local first_weekday = ((tonumber(os.date("%w", first_day)) or 0) - 1) % 7
    local days_in_month = tonumber(os.date("%d", os.time({ year = now.year, month = now.month + 1, day = 0 }))) or 31

    local grid = {}
    local day_count = 1

    for week = 1, 6 do
        local week_days = {}
        for weekday = 1, 7 do
            local day_num = 0
            local text = "  "

            local position = (week - 1) * 7 + weekday
            if position > first_weekday and day_count <= days_in_month then
                day_num = day_count
                text = string.format("%2d", day_count)
                day_count = day_count + 1
            end

            table.insert(week_days, { text = text, day = day_num })
        end

        if week > 1 or day_count > 1 then
            table.insert(grid, week_days)
        end
    end

    return grid
end

function CalendarCore.format_header(month_name, year, width)
    local text = month_name .. " " .. tostring(year)
    local total_padding = width - 2 - #text
    if total_padding < 0 then total_padding = 0 end
    local left_padding = math.floor(total_padding / 2)
    local right_padding = total_padding - left_padding
    return "<" .. string.rep(" ", left_padding) .. text .. string.rep(" ", right_padding) .. ">"
end

function CalendarCore.refresh_calendar(now)
    local grid = CalendarCore.get_calendar_grid(now)

    local header = CalendarCore.format_header(MONTH_NAMES[now.month], now.year, #WEEKDAYS_HEADER)
    local calendar_lines = { header, WEEKDAYS_HEADER }

    for _, week in ipairs(grid) do
        local week_line = {}
        for _, day in ipairs(week) do
            table.insert(week_line, day.text)
        end
        table.insert(calendar_lines, table.concat(week_line, " "))
    end

    return grid, calendar_lines
end

function CalendarCore.switch_month(now, selected_day, direction, mode)
    local new_month = now.month
    local new_year = now.year

    if direction == "previous" then
        new_month = new_month - 1
        if new_month < 1 then
            new_month = 12
            new_year = new_year - 1
        end
    elseif direction == "next" then
        new_month = new_month + 1
        if new_month > 12 then
            new_month = 1
            new_year = new_year + 1
        end
    end

    -- Calculate days in new month
    local next_month_time = os.time({ year = new_year, month = new_month + 1, day = 0 })
    local days_in_new_month = tonumber(os.date("%d", next_month_time)) or 31

    local new_day

    if mode == "sequence" then
        -- Continue day sequence (31 -> 1, 1 -> last day of previous month)
        if direction == "next" then
            new_day = 1
        else
            new_day = days_in_new_month
        end
    elseif mode == "up" then
        -- For up navigation: preserve weekday in last week of previous month
        local current_date = os.time({ year = now.year, month = now.month, day = selected_day })
        local current_weekday = tonumber(os.date("%w", current_date)) or 0

        -- Find the same weekday in the last week of the new month
        local last_day_of_month = os.time({ year = new_year, month = new_month, day = days_in_new_month })
        local last_weekday = tonumber(os.date("%w", last_day_of_month)) or 0

        -- Calculate how many days back from the last day to get the same weekday
        local weekday_offset = (last_weekday - current_weekday) % 7
        new_day = days_in_new_month - weekday_offset

        -- Ensure the day is valid
        new_day = math.max(1, math.min(days_in_new_month, new_day))
    elseif mode == "down" then
        -- For down navigation: preserve weekday in first week of next month
        local current_date = os.time({ year = now.year, month = now.month, day = selected_day })
        local current_weekday = tonumber(os.date("%w", current_date)) or 0

        -- Find the same weekday in the first week of the new month
        local first_day_of_month = os.time({ year = new_year, month = new_month, day = 1 })
        local first_weekday = tonumber(os.date("%w", first_day_of_month)) or 0

        -- Calculate how many days forward from the first day to get the same weekday
        local weekday_offset = (current_weekday - first_weekday) % 7
        new_day = 1 + weekday_offset

        -- Ensure the day is valid
        new_day = math.max(1, math.min(days_in_new_month, new_day))
    else
        -- Default: preserve month day if possible
        new_day = math.min(selected_day, days_in_new_month)
    end

    return { year = new_year, month = new_month, day = new_day }
end

function CalendarCore.month_name_to_number(month_name)
    if type(month_name) ~= "string" then
        return nil
    end
    for i, name in ipairs(MONTH_NAMES) do
        if name:lower() == month_name:lower() then
            return i
        end
    end
    return nil
end

-- ============================================================================
-- FileUtils Module
-- ============================================================================

local FileUtils = {}

function FileUtils.get_day_status(date_table)
    if #_config.daily_path_pattern == 0 or not _config.highlight_unfinished_tasks then
        return "normal"
    end

    local timestamp = os.time(date_table)
    local path = os.date(_config.daily_path_pattern, timestamp)

    if vim.fn.filereadable(path) == 0 then
        return "missing"
    end

    local lines = vim.fn.readfile(path)
    for _, line in ipairs(lines) do
        -- Match markdown task list items that are not completed
        -- Extract content inside brackets (including whitespace)
        local content = line:match("^%s*%- %[(.-)%]")
        if content then
            -- Check if content matches any completed task marker
            local is_completed = false
            for _, marker in ipairs(_config.completed_task_markers) do
                if content == marker then
                    is_completed = true
                    break
                end
            end
            if not is_completed then
                return "unfinished"
            end
        end
    end

    return "normal"
end

function FileUtils.convert_pattern_to_regex(pattern)
    -- Build regex pattern by replacing strftime patterns
    local regex_parts = {}
    local current_pos = 1
    local group_count = 0
    local year_index = 0
    local month_index = 0
    local day_index = 0

    -- Find all strftime patterns in the pattern
    for match_start, match_type, match_end in pattern:gmatch("()(%%[YmdB])()") do
        match_start = tonumber(match_start)
        match_end = tonumber(match_end)

        -- Add text before the match
        if match_start > current_pos then
            local text_before = pattern:sub(current_pos, match_start - 1)
            -- Escape regex special characters
            text_before = text_before:gsub("([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")
            table.insert(regex_parts, text_before)
        end

        -- Add the capture group for the strftime pattern
        group_count = group_count + 1
        if match_type == "%Y" then
            table.insert(regex_parts, "(%d%d%d%d)")
            year_index = group_count
        elseif match_type == "%m" then
            table.insert(regex_parts, "(%d%d)")
            month_index = group_count
        elseif match_type == "%d" then
            table.insert(regex_parts, "(%d%d)")
            day_index = group_count
        elseif match_type == "%B" then
            table.insert(regex_parts, "(%a+)")
            -- %B is treated as month, so track it as month_index
            month_index = group_count
        end

        if match_end then
            current_pos = match_end
        end
    end

    -- Add remaining text after last match
    if current_pos <= #pattern then
        local text_after = pattern:sub(current_pos)
        -- Escape regex special characters
        text_after = text_after:gsub("([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")
        table.insert(regex_parts, text_after)
    end

    local regex_pattern = table.concat(regex_parts)

    return {
        regex = regex_pattern,
        year_index = year_index,
        month_index = month_index,
        day_index = day_index,
    }
end

function FileUtils.extract_date_from_filename()
    local current_file = vim.api.nvim_buf_get_name(0)
    if current_file == "" then
        return nil
    end

    local full_path = vim.fn.fnamemodify(current_file, ":p")
    local pattern = _config.daily_path_pattern

    -- Convert pattern to regex and get capture group indices
    local pattern_info = FileUtils.convert_pattern_to_regex(pattern)

    -- Try to match the pattern against the full path
    local captures = { full_path:match(pattern_info.regex) }

    if #captures == 0 then
        return nil
    end

    -- Extract values using the tracked indices
    local year, month, day
    if pattern_info.year_index > 0 then
        year = captures[pattern_info.year_index]
    end
    if pattern_info.month_index > 0 then
        month = captures[pattern_info.month_index]
    end
    if pattern_info.day_index > 0 then
        day = captures[pattern_info.day_index]
    end

    -- Handle month names if present
    if month and not tonumber(month) then
        month = CalendarCore.month_name_to_number(month)
    end

    if year and month and day then
        return {
            year = tonumber(year),
            month = tonumber(month),
            day = tonumber(day),
        }
    end
end

function FileUtils.handle_date_selection(selected_day, now)
    if selected_day then
        local date_table = { year = now.year, month = now.month, day = selected_day }
        local timestamp = os.time(date_table)
        local path = os.date(_config.daily_path_pattern, timestamp)

        if vim.fn.filereadable(path) == 0 then
            local choice = vim.fn.confirm(
                "File " .. path .. " doesn't exist. Create it?",
                "&Yes\n&No",
                1
            )

            if choice == 1 then
                local dir = vim.fn.fnamemodify(path, ":h")
                if vim.fn.isdirectory(dir) == 0 then
                    vim.fn.mkdir(dir, "p")
                end

                vim.fn.writefile({}, path)
                vim.cmd("edit " .. path)
            end
        else
            vim.cmd("edit " .. path)
        end
    end
end

-- ============================================================================
-- UI Module
-- ============================================================================

local UI = {}

function UI.day_from_position(grid, line, col_pos)
    if line < 0 or line >= #grid then
        return nil
    end
    local week = grid[line + 1]
    local day_idx = math.floor(col_pos / 3) + 1
    if day_idx < 1 or day_idx > #week then
        return nil
    end
    local day = week[day_idx].day
    return day > 0 and day or nil
end

function UI.position_from_day(grid, day)
    for week_idx, week in ipairs(grid) do
        for day_idx, cell in ipairs(week) do
            if cell.day == day then
                local line = week_idx - 1
                local col_val = (day_idx - 1) * 3 + 1
                return { line = line, col = col_val }
            end
        end
    end
    return nil
end

function UI.ensure_cursor_position(state)
    local pos = UI.position_from_day(state.grid, state.selected_day)
    if not pos then return end
    local cur = vim.api.nvim_win_get_cursor(state.win)
    if cur[1] ~= pos.line + 3 or cur[2] ~= pos.col then
        with_programmatic_move(function()
            vim.api.nvim_win_set_cursor(state.win, { pos.line + 3, pos.col })
        end)
    end
end

function UI.update_highlight(state)
    -- Clear existing highlights
    vim.api.nvim_buf_clear_namespace(state.buf, -1, 0, -1)

    -- Highlight days with unfinished tasks
    for week_idx, week in ipairs(state.grid) do
        for day_idx, day in ipairs(week) do
            if day.day > 0 then
                local line_num = week_idx + 2 -- +2 for header and weekday lines
                local col_start = (day_idx - 1) * 3

                -- Check day status and apply appropriate highlights
                local date_table = { year = state.now.year, month = state.now.month, day = day.day }
                local status = FileUtils.get_day_status(date_table)

                if status == "unfinished" then
                    vim.api.nvim_buf_add_highlight(state.buf, -1, "Todo", line_num - 1, col_start, col_start + 2)
                elseif status == "missing" then
                    vim.api.nvim_buf_add_highlight(state.buf, -1, "Comment", line_num - 1, col_start, col_start + 2)
                end

                -- Highlight selected day (overrides task highlight)
                if day.day == state.selected_day then
                    vim.api.nvim_buf_add_highlight(state.buf, -1, "Visual", line_num - 1, col_start, col_start + 2)
                end
            end
        end
    end

    if state.win and state.selected_day then
        UI.ensure_cursor_position(state)
    end
end

function UI.close_calendar_window(win_to_close)
    if win_to_close and vim.api.nvim_win_is_valid(win_to_close) then
        vim.api.nvim_win_close(win_to_close, true)
    end
    if _current_win == win_to_close then
        _current_win = nil
    end
end

function UI.calculate_window_position(width, height)
    local ui = vim.api.nvim_list_uis()[1]
    if not ui then return nil, nil end

    -- Account for border (rounded border adds 2 columns and 2 rows)
    local total_width = width + 2
    local total_height = height + 2

    -- Minimum terminal size (22x10) or total window dimensions, whichever is larger
    local min_width = math.max(22, total_width)
    local min_height = math.max(10, total_height)

    if ui.width < min_width or ui.height < min_height then
        if vim.notify then
            local warn_level = vim.log.levels and vim.log.levels.WARN or 2
            vim.notify("Terminal too small for calendar (needs " .. min_width .. "x" .. min_height .. ")", warn_level)
        end
        return nil, nil
    end

    -- Calculate centered position for total window (including border)
    local total_col = math.floor((ui.width - total_width) / 2)
    local total_row = math.floor((ui.height - total_height) / 2)

    -- Content position is offset by border (1 cell each side)
    local col = total_col + 1
    local row = total_row + 1

    -- Keep window within UI bounds (ensure border doesn't go off screen)
    col = math.max(1, math.min(col, ui.width - width - 1))
    row = math.max(1, math.min(row, ui.height - height - 1))

    return col, row
end

function UI.reposition_window(win)
    if not win or not vim.api.nvim_win_is_valid(win) then return end

    local config = vim.api.nvim_win_get_config(win)
    if not config or not config.width or not config.height then return end

    local col, row = UI.calculate_window_position(config.width, config.height)
    if not col then
        -- Window no longer fits, close it
        UI.close_calendar_window(win)
        return
    end

    config.col = col
    config.row = row
    vim.api.nvim_win_set_config(win, config)
end

-- ============================================================================
-- Navigation Module
-- ============================================================================

local Navigation = {}

local function navigate_date(state, direction)
    local days_in_month = tonumber(os.date("%d", os.time({ year = state.now.year, month = state.now.month + 1, day = 0 }))) or
        31
    local new_day = state.selected_day
    local hit_boundary = false

    if direction == "left" then
        new_day = state.selected_day - 1
        if new_day < 1 then
            hit_boundary = true
            new_day = state.selected_day
        end
    elseif direction == "right" then
        new_day = state.selected_day + 1
        if new_day > days_in_month then
            hit_boundary = true
            new_day = state.selected_day
        end
    elseif direction == "up" then
        new_day = state.selected_day - 7
        if new_day < 1 then
            hit_boundary = true
            new_day = state.selected_day
        end
    elseif direction == "down" then
        new_day = state.selected_day + 7
        if new_day > days_in_month then
            hit_boundary = true
            new_day = state.selected_day
        end
    end

    if new_day <= days_in_month and new_day >= 1 then
        state.selected_day = new_day
        UI.update_highlight(state)
        return new_day, hit_boundary
    end

    return state.selected_day, hit_boundary
end

function Navigation.new_state(buf, win, grid, calendar_lines, selected_day, now)
    return {
        buf = buf,
        win = win,
        grid = grid,
        calendar_lines = calendar_lines,
        selected_day = selected_day,
        now = now,
    }
end

function Navigation.update_display(state, new_now, new_selected_day)
    state.now = new_now
    state.selected_day = new_selected_day
    state.grid, state.calendar_lines = CalendarCore.refresh_calendar(state.now)

    vim.api.nvim_buf_set_option(state.buf, "modifiable", true)
    vim.api.nvim_buf_set_option(state.buf, "readonly", false)
    vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, state.calendar_lines)
    vim.api.nvim_buf_set_option(state.buf, "modifiable", false)
    vim.api.nvim_buf_set_option(state.buf, "readonly", true)

    UI.update_highlight(state)
end

function Navigation.handle(state, direction)
    local month_direction = "next"
    if direction == "left" or direction == "up" then
        month_direction = "previous"
    end

    local mode
    if direction == "left" or direction == "right" then
        mode = "sequence" -- continue day sequence
    elseif direction == "up" then
        mode = "up"       -- preserve weekday in last week of previous month
    else
        mode = "down"     -- preserve weekday in first week of next month
    end

    local _, hit_boundary = navigate_date(state, direction)
    if hit_boundary then
        local new_now = CalendarCore.switch_month(state.now, state.selected_day, month_direction, mode)
        Navigation.update_display(state, new_now, new_now.day)
    end
end

function Navigation.switch_month(state, direction)
    local new_now = CalendarCore.switch_month(state.now, state.selected_day, direction, nil)
    Navigation.update_display(state, new_now, new_now.day)
end

function Navigation.setup_keybindings(state)
    local buf = state.buf
    local win = state.win

    -- Helper function to create keymaps
    local function map(key, callback, command)
        vim.api.nvim_buf_set_keymap(buf, "n", key, command or "", { noremap = true, silent = true, callback = callback })
    end

    -- Navigation keybindings
    map("h", function() Navigation.handle(state, "left") end)
    map("l", function() Navigation.handle(state, "right") end)
    map("k", function() Navigation.handle(state, "up") end)
    map("j", function() Navigation.handle(state, "down") end)

    -- Arrow keys
    map("<Left>", function() Navigation.handle(state, "left") end)
    map("<Right>", function() Navigation.handle(state, "right") end)
    map("<Up>", function() Navigation.handle(state, "up") end)
    map("<Down>", function() Navigation.handle(state, "down") end)

    -- Vim-style navigation keys
    map("b", function() Navigation.handle(state, "left") end)
    map("B", function() Navigation.handle(state, "left") end)
    map("w", function() Navigation.handle(state, "right") end)
    map("W", function() Navigation.handle(state, "right") end)
    map("ge", function() Navigation.handle(state, "left") end)
    map("gE", function() Navigation.handle(state, "left") end)
    map("e", function() Navigation.handle(state, "right") end)
    map("E", function() Navigation.handle(state, "right") end)

    -- Month switching
    map("p", function() Navigation.switch_month(state, "previous") end)
    map("n", function() Navigation.switch_month(state, "next") end)
    map("<C-d>", function() Navigation.switch_month(state, "previous") end)
    map("<C-u>", function() Navigation.switch_month(state, "next") end)

    -- Select day
    map("<CR>", function()
        UI.close_calendar_window(win)
        FileUtils.handle_date_selection(state.selected_day, state.now)
    end)
    map("o", function()
        UI.close_calendar_window(win)
        FileUtils.handle_date_selection(state.selected_day, state.now)
    end)

    -- Close calendar
    map("q", function() UI.close_calendar_window(win) end)
end

-- ============================================================================

function M.show_calendar(date)
    -- Clean up any invalid window reference
    if _current_win and not vim.api.nvim_win_is_valid(_current_win) then
        _current_win = nil
    end

    -- Close any existing calendar window before creating a new one
    UI.close_calendar_window(_current_win)

    local state = {}

    if date then
        state.now = date
        state.selected_day = date.day
    else
        local extracted_date = FileUtils.extract_date_from_filename()
        if extracted_date then
            state.now = extracted_date
            state.selected_day = extracted_date.day
        else
            state.now = os.date("*t")
            state.selected_day = state.now.day
        end
    end

    state.grid, state.calendar_lines = CalendarCore.refresh_calendar(state.now)

    local max_width = 0
    for _, line in ipairs(state.calendar_lines) do
        max_width = math.max(max_width, #line)
    end

    local width = max_width
    local height = #state.calendar_lines

    -- Calculate window position (centered)
    local col, row = UI.calculate_window_position(width, height)
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
                local current_day = UI.day_from_position(state.grid, grid_line, cursor_col)
                if current_day and current_day ~= state.selected_day then
                    state.selected_day = current_day
                    UI.update_highlight(state)
                else
                    UI.ensure_cursor_position(state)
                end
            else
                UI.ensure_cursor_position(state)
            end
        end,
    })

    vim.api.nvim_create_autocmd("VimResized", {
        group = au_group,
        callback = function()
            if state.win and vim.api.nvim_win_is_valid(state.win) then
                UI.reposition_window(state.win)
            end
        end,
    })

    UI.update_highlight(state)

    Navigation.setup_keybindings(state)
end

-- Export internal modules for testing when in test mode
if vim.g and vim.g.SIMPLE_CALENDAR_TEST then
    M._test = {
        CalendarCore = CalendarCore,
        FileUtils = FileUtils,
        UI = UI,
        Navigation = Navigation,
        _config = _config,
        MONTH_NAMES = MONTH_NAMES,
        WEEKDAYS_HEADER = WEEKDAYS_HEADER,
    }
end

return M
