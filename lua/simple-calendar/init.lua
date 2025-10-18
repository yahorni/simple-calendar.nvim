local M = {}

local MONTH_NAMES = { "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December" }
local WEEKDAYS_HEADER = "Mo Tu We Th Fr Sa Su"

local _config = { path_pattern = "%Y-%m-%d.md" }

function M.setup(config)
    _config = config
end

local function handle_date_selection(now, win, calendar_lines)
    local cursor_pos = vim.api.nvim_win_get_cursor(win)
    local line_num = cursor_pos[1]
    local col_num = cursor_pos[2] + 1

    if line_num < 3 then
        vim.api.nvim_win_close(win, true)
        return
    end

    local line = calendar_lines[line_num]

    local prev = line:sub(col_num - 1, col_num - 1)
    local curr = line:sub(col_num, col_num)
    local next = line:sub(col_num + 1, col_num + 1)
    local subs = line:sub(col_num + 2, col_num + 2)

    local day_num = nil
    if tonumber(curr) then
        if tonumber(next) then
            day_num = tonumber(curr .. next)
        elseif tonumber(prev) then
            day_num = tonumber(prev .. curr)
        end
    elseif tonumber(next) and not tonumber(subs) then
        day_num = tonumber(next)
    end

    if day_num then
        local date_table = { year = now.year, month = now.month, day = day_num }
        local timestamp = os.time(date_table)
        local path = os.date(_config.path_pattern, timestamp)

        vim.api.nvim_win_close(win, true)
        vim.cmd("edit " .. path)
    else
        vim.api.nvim_win_close(win, true)
    end
end

function M.show_calendar()
    local now = os.date("*t")

    local header = string.format("< %s %d >", MONTH_NAMES[now.month], now.year)
    local calendar_lines = { header, WEEKDAYS_HEADER }

    local days = {}
    -- Add leading spaces for first week
    local first_day = os.time({ year = now.year, month = now.month, day = 1 })
    local first_weekday = tonumber(os.date("%w", first_day)) - 1
    for _ = 1, first_weekday do
        table.insert(days, "  ")
    end
    -- Add days of month
    local days_in_month = tonumber(os.date("%d", os.time({ year = now.year, month = now.month + 1, day = 0 })))
    for d = 1, days_in_month do
        table.insert(days, string.format("%2d", d))
    end
    -- Group into weeks
    for i = 1, #days, 7 do
        local week_days = {}
        for j = i, math.min(i + 6, #days) do
            table.insert(week_days, days[j])
        end
        table.insert(calendar_lines, table.concat(week_days, " "))
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
    vim.api.nvim_win_set_option(win, "cursorline", true)

    -- Position cursor on current date
    local current_date_pattern = string.format("%2d", now.day)
    for line_num = 2, #calendar_lines do
        local start_pos = calendar_lines[line_num]:find(current_date_pattern, 1, true)
        if start_pos then
            vim.api.nvim_win_set_cursor(win, { line_num, start_pos - 1 })
            break
        end
    end

    -- Set keymaps
    vim.api.nvim_buf_set_keymap(buf, "n", "q", "<cmd>close<cr>", { noremap = true, silent = true })
    vim.api.nvim_buf_set_keymap(buf, "n", "<CR>", "",
        { noremap = true, silent = true, callback = function() handle_date_selection(now, win, calendar_lines) end })
end

return M
