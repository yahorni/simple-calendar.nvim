local config = require("simple-calendar.config")
local file_utils = require("simple-calendar.file_utils")

local Journal = {}

local SECONDS_IN_DAY = 86400
local WDAY = {
    SUNDAY = 1,
    MONDAY = 2,
    FRIDAY = 6,
    SATURDAY = 7,
}

function Journal.get_date_with_weekend_skip(base_time, offset_days, skip_weekends)
    if not skip_weekends or offset_days == 0 then
        return base_time + offset_days * SECONDS_IN_DAY
    end

    local today = os.date("*t", base_time)
    local days_diff = offset_days

    if offset_days == 1 then
        if today.wday == WDAY.FRIDAY then
            days_diff = 3
        elseif today.wday == WDAY.SATURDAY then
            days_diff = 2
        else
            days_diff = 1
        end
    elseif offset_days == -1 then
        if today.wday == WDAY.MONDAY then
            days_diff = -3
        elseif today.wday == WDAY.SUNDAY then
            days_diff = -2
        else
            days_diff = -1
        end
    end

    return base_time + days_diff * SECONDS_IN_DAY
end

function Journal.open_day(string_or_date)
    if #config.daily_path_pattern == 0 then
        vim.notify("simple-calendar: daily_path_pattern is not set", vim.log.levels.ERROR)
        return
    end

    local date_table
    if string_or_date == nil then
        string_or_date = "today"
    end

    if type(string_or_date) == "string" then
        local offset
        if string_or_date == "today" or #string_or_date == 0 then
            offset = 0
        elseif string_or_date == "yesterday" then
            offset = -1
        elseif string_or_date == "tomorrow" then
            offset = 1
        else
            vim.notify("simple-calendar: Invalid day. Use 'yesterday', 'today', 'tomorrow' or leave empty",
                vim.log.levels.ERROR)
            return
        end

        local target_time = Journal.get_date_with_weekend_skip(os.time(), offset, config.skip_weekends)
        if not target_time then
            return
        end

        date_table = os.date("*t", target_time)
    elseif type(string_or_date) == "table" then
        local year = string_or_date.year
        local month = string_or_date.month
        local day = string_or_date.day

        if type(year) ~= "number" or type(month) ~= "number" or type(day) ~= "number"
            or month < 1 or month > 12 then
            vim.notify("simple-calendar: Invalid date table", vim.log.levels.ERROR)
            return
        end

        local days_in_month = tonumber(os.date("%d", os.time({ year = year, month = month + 1, day = 0 })))
        if day < 1 or day > days_in_month then
            vim.notify("simple-calendar: Invalid date table", vim.log.levels.ERROR)
            return
        end

        date_table = { year = year, month = month, day = day }
    else
        vim.notify("simple-calendar: Invalid day. Use 'yesterday', 'today', 'tomorrow', a date table or leave empty",
            vim.log.levels.ERROR)
        return
    end

    file_utils.handle_date_selection(date_table.day, date_table)
end

return Journal
