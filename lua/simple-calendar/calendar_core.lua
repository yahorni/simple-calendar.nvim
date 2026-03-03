local config = require("simple-calendar.config")

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

    local header = CalendarCore.format_header(config.MONTH_NAMES[now.month], now.year, #config.WEEKDAYS_HEADER)
    local calendar_lines = { header, config.WEEKDAYS_HEADER }

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
    for i, name in ipairs(config.MONTH_NAMES) do
        if name:lower() == month_name:lower() then
            return i
        end
    end
    return nil
end

return CalendarCore
