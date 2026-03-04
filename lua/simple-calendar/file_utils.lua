local config = require("simple-calendar.config")
local calendar_core = require("simple-calendar.calendar_core")

local FileUtils = {}

local function generate_daily_path(timestamp)
    local path = os.date(config.daily_path_pattern, timestamp)
    if config.use_lowercase_daily_path then
        ---@diagnostic disable-next-line: param-type-mismatch
        path = path:lower()
    end
    return path
end

function FileUtils.get_day_status(date_table)
    if #config.daily_path_pattern == 0 or not config.highlight_unfinished_tasks then
        return "normal"
    end

    local timestamp = os.time(date_table)
    local path = generate_daily_path(timestamp)

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
            for _, marker in ipairs(config.completed_task_markers) do
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
    local weekday_index = 0

    local function prepare_literal_text(text)
        if config.use_lowercase_daily_path then
            text = text:lower()
        end
        return (text:gsub("([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1"))
    end

    -- Find all strftime patterns in the pattern
    for match_start, match_type, match_end in pattern:gmatch("()(%%[YmdBbAa])()") do
        match_start = tonumber(match_start)
        match_end = tonumber(match_end)

        -- Add text before the match
        if match_start > current_pos then
            local text_before = pattern:sub(current_pos, match_start - 1)
            table.insert(regex_parts, prepare_literal_text(text_before))
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
        elseif match_type == "%b" then
            table.insert(regex_parts, "(%a+)")
            -- %b is month abbreviation, track as month_index
            month_index = group_count
        elseif match_type == "%a" or match_type == "%A" then
            table.insert(regex_parts, "(%a+)")
            -- %a and %A are weekday abbreviations/names
            weekday_index = group_count
        end

        if match_end then
            current_pos = match_end
        end
    end

    -- Add remaining text after last match
    if current_pos <= #pattern then
        local text_after = pattern:sub(current_pos)
        table.insert(regex_parts, prepare_literal_text(text_after))
    end

    return {
        regex = table.concat(regex_parts),
        year_index = year_index,
        month_index = month_index,
        day_index = day_index,
        weekday_index = weekday_index,
    }
end

function FileUtils.extract_date_from_filename()
    local current_file = vim.api.nvim_buf_get_name(0)
    if current_file == "" then
        return nil
    end

    -- Convert pattern to regex and get capture group indices
    local full_path = vim.fn.fnamemodify(current_file, ":p")
    local pattern_info = FileUtils.convert_pattern_to_regex(config.daily_path_pattern)
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

    if month and not tonumber(month) then
        month = calendar_core.month_name_to_number(month)
    end

    if year and month and day then
        -- Validate weekday if present in pattern
        if pattern_info.weekday_index > 0 then
            local weekday_str = captures[pattern_info.weekday_index]
            local weekday_num = calendar_core.weekday_name_to_number(weekday_str)
            if not weekday_num then
                return nil
            end

            -- Compute weekday from extracted date
            local date_table = { year = tonumber(year), month = tonumber(month), day = tonumber(day) }
            local timestamp = os.time(date_table)
            local extracted_weekday_num = os.date("*t", timestamp).wday

            if weekday_num ~= extracted_weekday_num then
                return nil
            end
        end

        return {
            year = tonumber(year),
            month = tonumber(month),
            day = tonumber(day),
        }
    end
end

function FileUtils.handle_date_selection(selected_day, now)
    local date_table = { year = now.year, month = now.month, day = selected_day }
    local timestamp = os.time(date_table)
    local path = generate_daily_path(timestamp)

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

return FileUtils
