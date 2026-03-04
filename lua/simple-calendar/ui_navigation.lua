local config = require("simple-calendar.config")
local file_utils = require("simple-calendar.file_utils")
local calendar_core = require("simple-calendar.calendar_core")

local UI = {}
local Navigation = {}

local _programmatic_cursor_move_count = 0

-- UI

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

    local function with_programmatic_move(fn)
        _programmatic_cursor_move_count = _programmatic_cursor_move_count + 1
        local ok, err = pcall(fn)
        _programmatic_cursor_move_count = _programmatic_cursor_move_count - 1
        if not ok then error(err) end
    end

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
                local status = file_utils.get_day_status(date_table)

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
            vim.notify("simple-calendar: Terminal too small (needs " .. min_width .. "x" .. min_height .. ")", warn_level)
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

    local win_config = vim.api.nvim_win_get_config(win)
    if not win_config or not win_config.width or not win_config.height then return end

    local col, row = UI.calculate_window_position(win_config.width, win_config.height)
    if not col then
        -- Window no longer fits, close it
        UI.close_calendar_window(win)
        return
    end

    win_config.col = col
    win_config.row = row
    vim.api.nvim_win_set_config(win, win_config)
end

function UI.configure_events_handling(state)
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
end

-- Navigation

function Navigation.navigate_date(state, direction)
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
    state.grid, state.calendar_lines = calendar_core.refresh_calendar(state.now)

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

    local _, hit_boundary = Navigation.navigate_date(state, direction)
    if hit_boundary then
        local new_now = calendar_core.switch_month(state.now, state.selected_day, month_direction, mode)
        Navigation.update_display(state, new_now, new_now.day)
    end
end

function Navigation.switch_month(state, direction)
    local new_now = calendar_core.switch_month(state.now, state.selected_day, direction, nil)
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
    map("<C-D>", function() Navigation.switch_month(state, "previous") end)
    map("<C-U>", function() Navigation.switch_month(state, "next") end)

    -- Select day
    local function handle_selection()
        if #config.daily_path_pattern ~= 0 then
            UI.close_calendar_window(win)
            file_utils.handle_date_selection(state.selected_day, state.now)
        end
    end
    map("o", handle_selection)
    map("<CR>", handle_selection)

    -- Close calendar
    map("q", function() UI.close_calendar_window(win) end)
    map("<Esc>", function() UI.close_calendar_window(win) end)
end

return { UI = UI, Navigation = Navigation }
