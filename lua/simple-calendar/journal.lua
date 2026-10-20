local Journal = {}

-- DST-aware
local function shift_days(base_time, offset_days)
    local t = os.date("*t", base_time)
    return os.time({
        year = t.year,
        month = t.month,
        day = t.day + offset_days,
        hour = t.hour,
        min = t.min,
        sec = t.sec,
    })
end

local WDAY = {
    SUNDAY = 1,
    MONDAY = 2,
    FRIDAY = 6,
    SATURDAY = 7,
}

function Journal.get_date_with_weekend_skip(base_time, offset_days, skip_weekends)
    local days_diff = offset_days

    if skip_weekends and offset_days ~= 0 then
        local today = os.date("*t", base_time)

        if offset_days == 1 then
            if today.wday == WDAY.FRIDAY then
                days_diff = 3
            elseif today.wday == WDAY.SATURDAY then
                days_diff = 2
            end
        elseif offset_days == -1 then
            if today.wday == WDAY.MONDAY then
                days_diff = -3
            elseif today.wday == WDAY.SUNDAY then
                days_diff = -2
            end
        end
    end

    return shift_days(base_time, days_diff)
end

function Journal.open_day(string_or_date)
    local config = require("simple-calendar.config")
    if #config.daily_path_pattern == 0 then
        vim.notify("simple-calendar: daily_path_pattern is not set", vim.log.levels.ERROR)
        return
    end

    local date_table
    if string_or_date == nil then
        string_or_date = "today"
    end

    if type(string_or_date) == "string" then
        if string_or_date == "next" or string_or_date == "previous" then
            local file_utils = require("simple-calendar.file_utils")
            local current = file_utils.extract_date_from_filename()
            if not current then
                vim.notify("simple-calendar: Current file does not match daily_path_pattern", vim.log.levels.ERROR)
                return
            end
            local target_time = Journal.get_date_with_weekend_skip(os.time(current),
                string_or_date == "next" and 1 or -1, config.skip_weekends)
            date_table = os.date("*t", target_time)
        else
            local offset
            if string_or_date == "today" or #string_or_date == 0 then
                offset = 0
            elseif string_or_date == "yesterday" then
                offset = -1
            elseif string_or_date == "tomorrow" then
                offset = 1
            else
                vim.notify("simple-calendar: Invalid day. Use 'yesterday', 'today', 'tomorrow', 'next', 'previous' or leave empty",
                    vim.log.levels.ERROR)
                return
            end

            local target_time = Journal.get_date_with_weekend_skip(os.time(), offset, config.skip_weekends)
            if not target_time then
                return
            end

            date_table = os.date("*t", target_time)
        end
    elseif type(string_or_date) == "table" then
        local calendar_core = require("simple-calendar.calendar_core")
        date_table = calendar_core.validate_date(string_or_date)
        if not date_table then
            vim.notify("simple-calendar: Invalid date table", vim.log.levels.ERROR)
            return
        end
    else
        vim.notify("simple-calendar: Invalid day. Use 'yesterday', 'today', 'tomorrow', 'next', 'previous', a date table or leave empty",
            vim.log.levels.ERROR)
        return
    end

    local file_utils = require("simple-calendar.file_utils")
    file_utils.handle_date_selection(date_table.day, date_table)
end

function Journal.open_week(string_or_date)
    local config = require("simple-calendar.config")
    if #config.weekly_path_pattern == 0 then
        vim.notify("simple-calendar: weekly_path_pattern is not set", vim.log.levels.ERROR)
        return
    end

    local calendar_core = require("simple-calendar.calendar_core")
    local file_utils = require("simple-calendar.file_utils")

    local anchor

    if string_or_date == nil then
        string_or_date = "today"
    end

    -- Check the type before looking at the value: a date table has no array
    -- part, so `#string_or_date` would be 0 for it (and `#` on a number
    -- errors) — both would wrongly fall into the "today" branch below.
    if type(string_or_date) == "string" then
        if string_or_date == "today" or #string_or_date == 0 then
            anchor = calendar_core.get_week_anchor(os.date("*t"))
        elseif string_or_date == "previous" or string_or_date == "next" then
            local current, reason = file_utils.extract_week_from_filename()
            if not current then
                if reason == "pattern" then
                    vim.notify("simple-calendar: weekly_path_pattern cannot resolve a week "
                        .. "(pair %V with %G/%g, or use %Y/%m/%d tokens)", vim.log.levels.ERROR)
                elseif reason == "invalid_week" then
                    vim.notify("simple-calendar: Filename matches weekly_path_pattern but contains an invalid ISO week",
                        vim.log.levels.ERROR)
                else
                    vim.notify("simple-calendar: Current file does not match weekly_path_pattern", vim.log.levels.ERROR)
                end
                return
            end
            anchor = calendar_core.switch_week(current, string_or_date)
        elseif string_or_date == "from_daily" then
            local current = file_utils.extract_date_from_filename()
            if not current then
                vim.notify("simple-calendar: Current file does not match daily_path_pattern", vim.log.levels.ERROR)
                return
            end
            anchor = calendar_core.get_week_anchor(current)
        else
            vim.notify("simple-calendar: Invalid week. Use 'today', 'previous', 'next', 'from_daily', a date table or leave empty",
                vim.log.levels.ERROR)
            return
        end
    elseif type(string_or_date) == "table" then
        local valid_date = calendar_core.validate_date(string_or_date)
        if not valid_date then
            vim.notify("simple-calendar: Invalid date table", vim.log.levels.ERROR)
            return
        end
        anchor = calendar_core.get_week_anchor(valid_date)
    else
        vim.notify("simple-calendar: Invalid week. Use 'today', 'previous', 'next', 'from_daily', a date table or leave empty",
            vim.log.levels.ERROR)
        return
    end

    file_utils.handle_week_selection(anchor)
end

return Journal
