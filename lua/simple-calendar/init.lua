local M = {}

local MONTH_NAMES = { "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December" }
local WEEKDAYS_HEADER = "Mo Tu We Th Fr Sa Su"

local _config = { path_pattern = "%Y-%m-%d.md", highlight_unfinished_tasks = false }

function M.setup(config)
    _config = config
end

local function get_day_status(date_table)
    if not _config.highlight_unfinished_tasks then
        return "normal"
    end

    local timestamp = os.time(date_table)
    local path = os.date(_config.path_pattern, timestamp)

    if vim.fn.filereadable(path) == 0 then
        return "missing"
    end

    local lines = vim.fn.readfile(path)
    for _, line in ipairs(lines) do
        -- Match markdown task list items that are not completed (- [x] or - [-])
        -- This matches: - [ ], - [/], - [?], etc. but not - [x] or - [-]
        if line:match("^%s*%- %[%s*[^x%-]%]%s*") then
            return "unfinished"
        end
    end

    return "normal"
end

local function get_calendar_grid(now)
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

local function update_highlight(buf, grid, selected_day, now)
    -- Clear existing highlights
    vim.api.nvim_buf_clear_namespace(buf, -1, 0, -1)

    -- Highlight days with unfinished tasks
    for week_idx, week in ipairs(grid) do
        for day_idx, day in ipairs(week) do
            if day.day > 0 then
                local line_num = week_idx + 2 -- +2 for header and weekday lines
                local col_start = (day_idx - 1) * 3

                -- Check day status and apply appropriate highlights
                local date_table = { year = now.year, month = now.month, day = day.day }
                local status = get_day_status(date_table)

                if status == "unfinished" then
                    vim.api.nvim_buf_add_highlight(buf, -1, "Todo", line_num - 1, col_start, col_start + 2)
                elseif status == "missing" then
                    vim.api.nvim_buf_add_highlight(buf, -1, "Comment", line_num - 1, col_start, col_start + 2)
                end

                -- Highlight selected day (overrides task highlight)
                if day.day == selected_day then
                    vim.api.nvim_buf_add_highlight(buf, -1, "Visual", line_num - 1, col_start, col_start + 2)
                end
            end
        end
    end
end

local function navigate_date(buf, grid, selected_day, direction, now)
    local days_in_month = tonumber(os.date("%d", os.time({ year = now.year, month = now.month + 1, day = 0 }))) or 31
    local new_day = selected_day
    local hit_boundary = false

    if direction == "left" then
        new_day = selected_day - 1
        if new_day < 1 then
            hit_boundary = true
            new_day = selected_day
        end
    elseif direction == "right" then
        new_day = selected_day + 1
        if new_day > days_in_month then
            hit_boundary = true
            new_day = selected_day
        end
    elseif direction == "up" then
        new_day = selected_day - 7
        if new_day < 1 then
            hit_boundary = true
            new_day = selected_day
        end
    elseif direction == "down" then
        new_day = selected_day + 7
        if new_day > days_in_month then
            hit_boundary = true
            new_day = selected_day
        end
    end

    if new_day <= days_in_month and new_day >= 1 then
        update_highlight(buf, grid, new_day, now)
        return new_day, hit_boundary
    end

    return selected_day, hit_boundary
end

local function handle_date_selection(selected_day, now)
    if selected_day then
        local date_table = { year = now.year, month = now.month, day = selected_day }
        local timestamp = os.time(date_table)
        local path = os.date(_config.path_pattern, timestamp)

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

local function switch_month(now, selected_day, direction, mode)
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

local function format_header(month_name, year, width)
    local text = month_name .. " " .. tostring(year)
    local total_padding = width - 2 - #text
    if total_padding < 0 then total_padding = 0 end
    local left_padding = math.floor(total_padding / 2)
    local right_padding = total_padding - left_padding
    return "<" .. string.rep(" ", left_padding) .. text .. string.rep(" ", right_padding) .. ">"
end

local function refresh_calendar(now)
    local grid = get_calendar_grid(now)

    local header = format_header(MONTH_NAMES[now.month], now.year, #WEEKDAYS_HEADER)
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

local function month_name_to_number(month_name)
    for i, name in ipairs(MONTH_NAMES) do
        if name:lower() == month_name:lower() then
            return i
        end
    end
    return nil
end

local function convert_pattern_to_regex(pattern)
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

local function extract_date_from_filename()
    local current_file = vim.api.nvim_buf_get_name(0)
    if current_file == "" then
        return nil
    end

    local full_path = vim.fn.fnamemodify(current_file, ":p")
    local pattern = _config.path_pattern

    -- Convert pattern to regex and get capture group indices
    local pattern_info = convert_pattern_to_regex(pattern)

    -- Try to match the pattern against the full path
    local captures = { full_path:match(pattern_info.regex) }

    if #captures > 0 then
        local year, month, day

        -- Extract values using the tracked indices
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
            month = month_name_to_number(month)
        end

        if year and month and day then
            return {
                year = tonumber(year),
                month = tonumber(month),
                day = tonumber(day),
            }
        end
    end

    -- Fallback: try to extract date from filename only
    local filename = vim.fn.fnamemodify(current_file, ":t")
    local year, month, day = filename:match("^(%d%d%d%d)-(%d%d)-(%d%d)%.md$")
    if year and month and day then
        return {
            year = tonumber(year),
            month = tonumber(month),
            day = tonumber(day),
        }
    end

    return nil
end

function M.show_calendar(date)
    local now
    local selected_day

    if date then
        now = date
        selected_day = date.day
    else
        local extracted_date = extract_date_from_filename()
        if extracted_date then
            now = extracted_date
            selected_day = extracted_date.day
        else
            now = os.date("*t")
            selected_day = now.day
        end
    end

    local grid, calendar_lines = refresh_calendar(now)

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

    update_highlight(buf, grid, selected_day, now)

    local function update_calendar_display(new_now, new_selected_day)
        now = new_now
        selected_day = new_selected_day
        grid, calendar_lines = refresh_calendar(now)
        vim.api.nvim_buf_set_option(buf, "modifiable", true)
        vim.api.nvim_buf_set_option(buf, "readonly", false)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, calendar_lines)
        vim.api.nvim_buf_set_option(buf, "modifiable", false)
        vim.api.nvim_buf_set_option(buf, "readonly", true)
        update_highlight(buf, grid, selected_day, now)
    end

    local function handle_navigation(direction)
        local month_direction = "next"
        if direction == "left" or direction == "up" then
            month_direction = "previous"
        end

        local mode
        if direction == "left" or direction == "right" then
            mode = "sequence" -- h/l: continue day sequence
        elseif direction == "up" then
            mode = "up"       -- k: preserve weekday in last week of previous month
        else
            mode = "down"     -- j: preserve weekday in first week of next month
        end

        local new_day, hit_boundary = navigate_date(buf, grid, selected_day, direction, now)
        if hit_boundary then
            local new_now = switch_month(now, selected_day, month_direction, mode)
            update_calendar_display(new_now, new_now.day)
        else
            selected_day = new_day
        end
    end

    local function handle_month_switch(direction)
        local new_now = switch_month(now, selected_day, direction, nil)
        update_calendar_display(new_now, new_now.day)
    end

    local function navigate_left()
        handle_navigation("left")
    end

    local function navigate_right()
        handle_navigation("right")
    end

    local function navigate_up()
        handle_navigation("up")
    end

    local function navigate_down()
        handle_navigation("down")
    end

    local function select_date()
        vim.api.nvim_win_close(win, true)
        handle_date_selection(selected_day, now)
    end

    local function switch_month_previous()
        handle_month_switch("previous")
    end

    local function switch_month_next()
        handle_month_switch("next")
    end

    vim.api.nvim_buf_set_keymap(buf, "n", "q", "<cmd>close<cr>", { noremap = true, silent = true })
    vim.api.nvim_buf_set_keymap(buf, "n", "<CR>", "", { noremap = true, silent = true, callback = select_date })
    vim.api.nvim_buf_set_keymap(buf, "n", "h", "", { noremap = true, silent = true, callback = navigate_left })
    vim.api.nvim_buf_set_keymap(buf, "n", "l", "", { noremap = true, silent = true, callback = navigate_right })
    vim.api.nvim_buf_set_keymap(buf, "n", "k", "", { noremap = true, silent = true, callback = navigate_up })
    vim.api.nvim_buf_set_keymap(buf, "n", "j", "", { noremap = true, silent = true, callback = navigate_down })
    vim.api.nvim_buf_set_keymap(buf, "n", "p", "", { noremap = true, silent = true, callback = switch_month_previous })
    vim.api.nvim_buf_set_keymap(buf, "n", "n", "", { noremap = true, silent = true, callback = switch_month_next })
end

return M
