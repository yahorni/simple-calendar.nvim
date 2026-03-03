local config = require("simple-calendar.config")
local calendar_core = require("simple-calendar.calendar_core")

local FileUtils = {}

function FileUtils.get_day_status(date_table)
    if #config._config.daily_path_pattern == 0 or not config._config.highlight_unfinished_tasks then
        return "normal"
    end

    local timestamp = os.time(date_table)
    local path = os.date(config._config.daily_path_pattern, timestamp)

    if vim.fn.filereadable(path) == 0 then
        return "missing"
    end

    local lines = vim.fn.readfile(path)
    for _, line in ipairs(lines) do
        -- Match markdown task list items that are not completed
        -- Supports -, *, + bullets, single character inside brackets, excludes markdown links
        local content, pos = line:match("^%s*[-+*] %[(.)%]()")
        if content and (pos > #line or line:sub(pos, pos) ~= "(") then
            -- Check if content matches any completed task marker
            local is_completed = false
            for _, marker in ipairs(config._config.completed_task_markers) do
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
    local pattern = config._config.daily_path_pattern

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
        month = calendar_core.month_name_to_number(month)
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
        local path = os.date(config._config.daily_path_pattern, timestamp)

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

return FileUtils
