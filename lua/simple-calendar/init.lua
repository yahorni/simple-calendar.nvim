local M = {}

local MONTH_NAMES = { "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December" }
local WEEKDAYS_HEADER = "Mo Tu We Th Fr Sa Su"

local _config = { path_pattern = "%Y-%m-%d.md" }

function M.setup(config)
    _config = config
end

local function get_calendar_grid(now)
    local first_day = os.time({ year = now.year, month = now.month, day = 1 })
    local first_weekday = (tonumber(os.date("%w", first_day)) - 1) % 7
    local days_in_month = tonumber(os.date("%d", os.time({ year = now.year, month = now.month + 1, day = 0 })))

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

local function update_highlight(buf, grid, selected_day)
    -- Clear existing highlights
    vim.api.nvim_buf_clear_namespace(buf, -1, 0, -1)

    -- Find and highlight selected day
    for week_idx, week in ipairs(grid) do
        for day_idx, day in ipairs(week) do
            if day.day == selected_day and day.day > 0 then
                local line_num = week_idx + 2 -- +2 for header and weekday lines
                local col_start = (day_idx - 1) * 3
                vim.api.nvim_buf_add_highlight(buf, -1, "Visual", line_num - 1, col_start, col_start + 2)
                return
            end
        end
    end
end

local function navigate_date(buf, grid, selected_day, direction, now)
    local days_in_month = tonumber(os.date("%d", os.time({ year = now.year, month = now.month + 1, day = 0 }))) or 31
    local new_day = selected_day

    if direction == "left" then
        new_day = math.max(1, selected_day - 1)
    elseif direction == "right" then
        new_day = math.min(days_in_month, selected_day + 1)
    elseif direction == "up" then
        new_day = math.max(1, selected_day - 7)
    elseif direction == "down" then
        new_day = math.min(days_in_month, selected_day + 7)
    end

    if new_day <= days_in_month and new_day >= 1 then
        update_highlight(buf, grid, new_day)
        return new_day
    end

    return selected_day
end

local function handle_date_selection(selected_day, now)
    if selected_day then
        local date_table = { year = now.year, month = now.month, day = selected_day }
        local timestamp = os.time(date_table)
        local path = os.date(_config.path_pattern, timestamp)
        vim.cmd("edit " .. path)
    end
end

function M.show_calendar()
    local now = os.date("*t")
    local selected_day = now.day

    local grid = get_calendar_grid(now)

    local header = string.format("< %s %d >", MONTH_NAMES[now.month], now.year)
    local calendar_lines = { header, WEEKDAYS_HEADER }

    for _, week in ipairs(grid) do
        local week_line = {}
        for _, day in ipairs(week) do
            table.insert(week_line, day.text)
        end
        table.insert(calendar_lines, table.concat(week_line, " "))
    end

    local max_width = 0
    for _, line in ipairs(calendar_lines) do
        max_width = math.max(max_width, #line)
    end

    local width = max_width
    local height = #calendar_lines

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, calendar_lines)
    vim.api.nvim_buf_set_option(buf, "filetype", "calendar")
    vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
    vim.api.nvim_buf_set_option(buf, "modifiable", false)
    vim.api.nvim_buf_set_option(buf, "readonly", true)

    -- Calculate window position (centered)
    local ui = vim.api.nvim_list_uis()[1]
    local col = ui and math.floor((ui.width - width) / 2) or 0
    local row = ui and math.floor((ui.height - height) / 2) or 0

    local win = vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        width = width,
        height = height,
        col = col,
        row = row,
        style = "minimal",
        border = "rounded",
    })
    vim.api.nvim_win_set_option(win, "cursorline", false)
    vim.api.nvim_win_set_option(win, "cursorcolumn", false)

    update_highlight(buf, grid, selected_day)

    local function navigate_left()
        selected_day = navigate_date(buf, grid, selected_day, "left", now)
    end

    local function navigate_right()
        selected_day = navigate_date(buf, grid, selected_day, "right", now)
    end

    local function navigate_up()
        selected_day = navigate_date(buf, grid, selected_day, "up", now)
    end

    local function navigate_down()
        selected_day = navigate_date(buf, grid, selected_day, "down", now)
    end

    local function select_date()
        vim.api.nvim_win_close(win, true)
        handle_date_selection(selected_day, now)
    end

    vim.api.nvim_buf_set_keymap(buf, "n", "q", "<cmd>close<cr>", { noremap = true, silent = true })
    vim.api.nvim_buf_set_keymap(buf, "n", "<CR>", "", { noremap = true, silent = true, callback = select_date })
    vim.api.nvim_buf_set_keymap(buf, "n", "h", "", { noremap = true, silent = true, callback = navigate_left })
    vim.api.nvim_buf_set_keymap(buf, "n", "l", "", { noremap = true, silent = true, callback = navigate_right })
    vim.api.nvim_buf_set_keymap(buf, "n", "k", "", { noremap = true, silent = true, callback = navigate_up })
    vim.api.nvim_buf_set_keymap(buf, "n", "j", "", { noremap = true, silent = true, callback = navigate_down })
end

return M
