local config = require("simple-calendar.config")

local FileUtils = {}

local function generate_daily_path(timestamp)
    local path = os.date(config.daily_path_pattern, timestamp)
    if config.use_lowercase_paths then
        ---@diagnostic disable-next-line: param-type-mismatch
        path = path:lower()
    end
    return path
end

local function generate_weekly_path(anchor_timestamp)
    local path = os.date(config.weekly_path_pattern, anchor_timestamp)
    if config.use_lowercase_paths then
        path = path:lower()
    end
    return path
end

function FileUtils.get_day_status(date_table)
    if #config.daily_path_pattern == 0 then
        return "normal"
    end

    local timestamp = os.time(date_table)
    local path = generate_daily_path(timestamp)

    if vim.fn.filereadable(path) == 0 then
        return "missing"
    end

    if config.highlight_unfinished_tasks then
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
    end

    return "exists"
end

function FileUtils.convert_pattern_to_regex(pattern)
    -- Build regex pattern by replacing strftime patterns
    local regex_parts = {}
    local current_pos = 1
    local group_count = 0
    local year_index = 0
    local iso_year_index = 0
    local month_index = 0
    local day_index = 0
    local weekday_index = 0
    local week_index = 0

    local function prepare_literal_text(text)
        if config.use_lowercase_paths then
            text = text:lower()
        end
        return (text:gsub("([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1"))
    end

    -- Find all strftime patterns in the pattern
    for match_start, match_type, match_end in pattern:gmatch("()(%%[YmdBbAaGgV])()") do
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
        elseif match_type == "%G" then
            -- ISO week-year (companion to %V)
            table.insert(regex_parts, "(%d%d%d%d)")
            iso_year_index = group_count
        elseif match_type == "%g" then
            -- 2-digit ISO week-year
            table.insert(regex_parts, "(%d%d)")
            iso_year_index = group_count
        elseif match_type == "%V" then
            -- ISO week number (Monday-first, 01..53)
            table.insert(regex_parts, "(%d%d)")
            week_index = group_count
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
        regex = table.concat(regex_parts) .. "$",
        year_index = year_index,
        iso_year_index = iso_year_index,
        month_index = month_index,
        day_index = day_index,
        weekday_index = weekday_index,
        week_index = week_index,
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

    local calendar_core = require("simple-calendar.calendar_core")

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

-- Open an existing file, or prompt to create (including parents) when missing.
function FileUtils.open_or_create(path)
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

function FileUtils.handle_date_selection(selected_day, now)
    local date_table = { year = now.year, month = now.month, day = selected_day }
    local timestamp = os.time(date_table)
    local path = generate_daily_path(timestamp)
    FileUtils.open_or_create(path)
end

-- Extract the week anchor (its Monday) from the current buffer's filename.
-- Returns the anchor date table on success, or nil plus a reason on failure:
--   "no_buffer"    - current buffer has no filename
--   "pattern"      - weekly_path_pattern cannot resolve a week at all (no
--                    ISO week pair %V+%G/%g and no year/month/day tokens),
--                    so no filename could ever resolve
--   "no_match"     - the filename does not match weekly_path_pattern
--   "invalid_week" - the filename matched, but the week is invalid (e.g.
--                    week 53 in a 52-week year)
function FileUtils.extract_week_from_filename()
    local current_file = vim.api.nvim_buf_get_name(0)
    if current_file == "" then
        return nil, "no_buffer"
    end

    local full_path = vim.fn.fnamemodify(current_file, ":p")
    local pattern_info = FileUtils.convert_pattern_to_regex(config.weekly_path_pattern)

    local calendar_core = require("simple-calendar.calendar_core")

    -- The pattern can only resolve a week if it either carries an ISO week
    -- pair (%V + %G/%g) or a full date (year + month + day tokens). %V forces
    -- the ISO branch, so %V without %G/%g is unresolvable even when date
    -- tokens are present: using %Y (calendar year) with %V is ambiguous across
    -- the new-year boundary (e.g. a week in early January belongs to the
    -- previous ISO year).
    local can_resolve
    if pattern_info.week_index > 0 then
        can_resolve = pattern_info.iso_year_index > 0
    else
        can_resolve = pattern_info.year_index > 0 and pattern_info.month_index > 0 and pattern_info.day_index > 0
    end
    if not can_resolve then
        return nil, "pattern"
    end

    local captures = { full_path:match(pattern_info.regex) }
    if #captures == 0 then
        return nil, "no_match"
    end

    -- %V + %G/%g -> ISO week + week-year.
    if pattern_info.week_index > 0 then
        local raw = captures[pattern_info.iso_year_index]
        local iso_year = tonumber(raw)
        -- %g is 2-digit; expand using the nearest century
        if #raw == 2 then
            iso_year = calendar_core.expand_two_digit_year(iso_year)
        end

        local anchor = calendar_core.iso_week_to_anchor(iso_year, tonumber(captures[pattern_info.week_index]))
        if not anchor then
            return nil, "invalid_week"
        end
        return anchor
    end

    -- Otherwise the week must be anchored by its Monday's date tokens. All
    -- three are present (guaranteed by the can_resolve check above).
    local year = captures[pattern_info.year_index]
    local month = captures[pattern_info.month_index]
    local day = captures[pattern_info.day_index]

    if month and not tonumber(month) then
        month = calendar_core.month_name_to_number(month)
    end

    local anchor = {
        year = tonumber(year),
        month = tonumber(month),
        day = tonumber(day),
    }
    -- Normalize to the Monday of that week.
    return calendar_core.get_week_anchor(anchor)
end

function FileUtils.get_week_status(anchor_date)
    if #config.weekly_path_pattern == 0 then
        return "normal"
    end

    local timestamp = os.time(anchor_date)
    local path = generate_weekly_path(timestamp)

    if vim.fn.filereadable(path) == 0 then
        return "missing"
    end

    return "exists"
end

function FileUtils.handle_week_selection(anchor_date)
    local timestamp = os.time(anchor_date)
    local path = generate_weekly_path(timestamp)
    FileUtils.open_or_create(path)
end

return FileUtils
