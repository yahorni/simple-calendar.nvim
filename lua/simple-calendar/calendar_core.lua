local CalendarCore = {}

local WEEKDAYS_HEADER = "Mo Tu We Th Fr Sa Su"
local WEEKDAY_NAMES = {
    "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday",
}
local WEEKDAY_ABBR = {
    "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat",
}
local MONTH_ABBR = {
    "Jan", "Feb", "Mar", "Apr", "May", "Jun",
    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
}
local MONTH_NAMES = {
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December",
}

CalendarCore.WEEKDAY_NAMES = WEEKDAY_NAMES
CalendarCore.WEEKDAY_ABBR = WEEKDAY_ABBR
CalendarCore.MONTH_NAMES = MONTH_NAMES
CalendarCore.MONTH_ABBR = MONTH_ABBR

function CalendarCore.get_calendar_grid(now)
    local first_day = os.time({ year = now.year, month = now.month, day = 1 })
    local first_weekday = ((tonumber(os.date("%w", first_day)) or 0) - 1) % 7
    local days_in_month = tonumber(os.date("%d", os.time({ year = now.year, month = now.month + 1, day = 0 }))) or 31

    local grid = {}
    local day_count = 1

    -- Always render a fixed 6-week grid. The trailing week(s) are left blank on
    -- purpose to keep the calendar window the same height for every month
    for week = 1, 6 do
        local week_days = {}
        local first_real_day = nil
        for weekday = 1, 7 do
            local day_num = 0
            local text = "  "

            local position = (week - 1) * 7 + weekday
            if position > first_weekday and day_count <= days_in_month then
                day_num = day_count
                text = string.format("%2d", day_count)
                if not first_real_day then
                    first_real_day = day_count
                end
                day_count = day_count + 1
            end

            table.insert(week_days, { text = text, day = day_num })
        end

        -- Attach the Monday anchor for this row's week so the UI can render
        -- a gutter column without recomputing it. Only set when the row has a
        -- real day (rows can be entirely blank).
        if first_real_day then
            week_days.week_anchor = CalendarCore.get_week_anchor({
                year = now.year, month = now.month, day = first_real_day,
            })
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

-- Week-number gutter width: right-aligned 2-digit number + `|` separator, no
-- trailing space (the day grid's own leading space provides separation). Pure
-- ASCII, so byte width equals display-cell width for the buffer column APIs.
function CalendarCore.gutter_width()
    return 3
end

function CalendarCore.gutter_header()
    return " W|"
end

function CalendarCore.refresh_calendar(now)
    local grid = CalendarCore.get_calendar_grid(now)

    local config = require("simple-calendar.config")
    local show_gutter = config.show_week_number

    -- Content width: gutter + weekday grid.
    local full_width = #WEEKDAYS_HEADER
    if show_gutter then
        full_width = full_width + CalendarCore.gutter_width()
    end

    local header = CalendarCore.format_header(MONTH_NAMES[now.month], now.year, full_width)
    local weekday_header = WEEKDAYS_HEADER
    if show_gutter then
        weekday_header = CalendarCore.gutter_header() .. WEEKDAYS_HEADER
    end

    local calendar_lines = { header, weekday_header }

    for _, week in ipairs(grid) do
        local week_line = {}
        local has_day = false
        for _, day in ipairs(week) do
            table.insert(week_line, day.text)
            if day.day > 0 then
                has_day = true
            end
        end
        -- Trim trailing empty day cells (the month's last row often ends
        -- before Sunday, leaving an empty trailing column).
        local line_text = table.concat(week_line, " ")
        if has_day then
            line_text = line_text:gsub("%s+$", "")
        end
        -- Keep fully-blank weeks as an empty line: the fixed 6-week grid means
        -- the trailing week exists to keep the window height constant for
        -- months that span 6 weeks.
        if not has_day then
            line_text = ""
        end

        if show_gutter then
            if week.week_anchor then
                local week_num = CalendarCore.iso_week_of_anchor(week.week_anchor).week
                line_text = string.format("%2d|", week_num) .. line_text
            else
                -- Blank week: no number, no separator.
                line_text = string.rep(" ", CalendarCore.gutter_width()) .. line_text
            end
        end
        table.insert(calendar_lines, line_text)
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

    local lower_name = month_name:lower()
    for i, name in ipairs(MONTH_NAMES) do
        if name:lower() == lower_name then
            return i
        end
    end
    for i, abbr in ipairs(MONTH_ABBR) do
        if abbr:lower() == lower_name then
            return i
        end
    end
    return nil
end

function CalendarCore.weekday_name_to_number(weekday_name)
    if type(weekday_name) ~= "string" then
        return nil
    end

    local lower_name = weekday_name:lower()
    for i, name in ipairs(WEEKDAY_NAMES) do
        if name:lower() == lower_name then
            return i
        end
    end
    for i, abbr in ipairs(WEEKDAY_ABBR) do
        if abbr:lower() == lower_name then
            return i
        end
    end
    return nil
end

-- Expand a 2-digit year to 4 digits. Uses 50/50 pivot:
-- 00..49 -> 20xx, 50..99 -> 19xx.
function CalendarCore.expand_two_digit_year(year)
    if not year then
        return nil
    end
    if year < 50 then
        return 2000 + year
    end
    return 1900 + year
end

-- Return the Monday (anchor) of the week containing `date_table`. Monday-first.
function CalendarCore.get_week_anchor(date_table)
    local timestamp = os.time(date_table)
    local t = os.date("*t", timestamp)
    -- os.date wday: Sunday=1 .. Saturday=7. Convert to Monday-first offset
    -- (Monday=0 .. Sunday=6).
    local offset = (t.wday + 5) % 7
    local shifted = os.time({
        year = t.year,
        month = t.month,
        day = t.day - offset,
    })
    return os.date("*t", shifted)
end

-- Shift a date table by N calendar days (DST-safe); returns a date table.
function CalendarCore.shift_days(date_table, days)
    return os.date("*t", os.time({
        year = date_table.year,
        month = date_table.month,
        day = date_table.day + days,
    }))
end

-- Shift a week anchor forward or backward by one week (DST-safe).
function CalendarCore.switch_week(anchor_date, direction)
    return CalendarCore.shift_days(anchor_date, (direction == "next") and 7 or -7)
end

-- Compute the ISO week-year and ISO week number for a Monday anchor date.
-- Returns { iso_year = Y, week = W }. The anchor is the Monday of the week,
-- which belongs unambiguously to a single ISO year + week.
function CalendarCore.iso_week_of_anchor(anchor_date)
    -- Thursday of the ISO week is unambiguous: January 4 is always in week 01,
    -- and the ISO week-year is the calendar year of that Thursday.
    local t = {}
    for k, v in pairs(anchor_date) do t[k] = v end
    t.day = t.day + 3 -- Monday -> Thursday of the same week
    local thursday = os.date("*t", os.time(t))

    -- ISO week number: weeks numbered by the Thursday's day-of-year.
    local week = math.floor((thursday.yday - 1) / 7) + 1

    return { iso_year = thursday.year, week = week }
end

-- Convert an ISO year + ISO week number to the Monday anchor date of that week.
function CalendarCore.iso_week_to_anchor(iso_year, week)
    if not iso_year or not week then
        return nil
    end
    iso_year = tonumber(iso_year)
    week = tonumber(week)
    if not iso_year or not week or week < 1 or week > 53 then
        return nil
    end

    -- January 4 of the ISO year is always in week 01.
    local jan4 = os.time({ year = iso_year, month = 1, day = 4 })
    local jan4_t = os.date("*t", jan4)
    local offset = (jan4_t.wday + 5) % 7 -- days since Monday
    local week1_monday = os.time({
        year = iso_year,
        month = 1,
        day = 4 - offset,
    })

    -- Add weeks via calendar-day arithmetic (re-read as a date table, then
    -- offset the day field), not `+ N * 86400`, to stay DST-safe (see shift_days
    -- in journal.lua).
    local monday = os.date("*t", week1_monday)
    local anchor_time = os.time({
        year = monday.year,
        month = monday.month,
        day = monday.day + (week - 1) * 7,
    })
    local anchor = os.date("*t", anchor_time)

    -- Only some ISO years have 53 weeks (e.g. 2020 does, 2025 does not). For a
    -- 52-week year, week 53 would land on the Monday that is actually week 01
    -- of the following ISO year; reject it rather than resolving to the wrong
    -- week (which would also make next/previous skip a week).
    if week == 53 and CalendarCore.iso_week_of_anchor(anchor).week ~= 53 then
        return nil
    end

    return anchor
end

function CalendarCore.validate_date(date_table)
    if type(date_table) ~= "table" then
        return nil
    end

    local year = date_table.year
    local month = date_table.month
    local day = date_table.day

    if type(year) ~= "number" or type(month) ~= "number" or type(day) ~= "number"
        or month < 1 or month > 12 then
        return nil
    end

    local days_in_month = tonumber(os.date("%d", os.time({ year = year, month = month + 1, day = 0 })))
    if day < 1 or day > days_in_month then
        return nil
    end

    return { year = year, month = month, day = day }
end

return CalendarCore
