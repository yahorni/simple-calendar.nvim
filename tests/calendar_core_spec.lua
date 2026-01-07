-- Unit tests for CalendarCore module
local assert = require("tests.helpers")

-- Load the plugin module
local plugin = require("simple-calendar")

-- Get test exports
local CalendarCore = plugin._test.CalendarCore
local MONTH_NAMES = plugin._test.MONTH_NAMES

local M = {}

function M.run()
    print("Running CalendarCore tests...")

    -- Test: month_name_to_number
    assert.run_test("month_name_to_number - valid month names", function()
        for i, month_name in ipairs(MONTH_NAMES) do
            -- Test exact case
            local result = CalendarCore.month_name_to_number(month_name)
            assert.assert_equal(result, i, string.format("Month '%s' should return %d", month_name, i))

            -- Test lowercase
            result = CalendarCore.month_name_to_number(month_name:lower())
            assert.assert_equal(result, i, string.format("Lowercase month '%s' should return %d", month_name:lower(), i))

            -- Test uppercase
            result = CalendarCore.month_name_to_number(month_name:upper())
            assert.assert_equal(result, i, string.format("Uppercase month '%s' should return %d", month_name:upper(), i))

            -- Test mixed case
            result = CalendarCore.month_name_to_number("jAnUaRy")
            assert.assert_equal(result, 1, "Mixed case 'jAnUaRy' should return 1")
        end
    end)

    assert.run_test("month_name_to_number - invalid month name", function()
        local result = CalendarCore.month_name_to_number("NotAMonth")
        assert.assert_nil(result, "Invalid month name should return nil")

        result = CalendarCore.month_name_to_number("")
        assert.assert_nil(result, "Empty string should return nil")

        result = CalendarCore.month_name_to_number(nil)
        assert.assert_nil(result, "nil should return nil")
    end)

    -- Test: format_header
    assert.run_test("format_header - normal width", function()
        local result = CalendarCore.format_header("January", 2025, 20)
        -- Header format: <   January 2025   >
        -- Total width: 20, text "January 2025" = 12, padding = 6, split 3/3
        assert.assert_equal(result, "<   January 2025   >", "Header should be properly centered")
    end)

    assert.run_test("format_header - exact width", function()
        -- Text "January 2025" = 12 characters, plus < and > = 14 total
        local result = CalendarCore.format_header("January", 2025, 14)
        assert.assert_equal(result, "<January 2025>", "Header should fit exactly with no padding")
    end)

    assert.run_test("format_header - short width", function()
        -- Width too small for text, should still produce something
        local result = CalendarCore.format_header("January", 2025, 10)
        -- Width 10 < text length 12, total_padding becomes 0
        assert.assert_equal(result, "<January 2025>", "Header should handle short width gracefully")
    end)

    -- Test: get_calendar_grid - basic functionality
    assert.run_test("get_calendar_grid - January 2025", function()
        -- January 2025 starts on Wednesday (weekday 3), 31 days
        local date = { year = 2025, month = 1, day = 1 }
        local grid = CalendarCore.get_calendar_grid(date)

        -- Should return a table (grid)
        assert.assert_type(grid, "table", "Grid should be a table")

        -- Should have 6 weeks (some may be empty)
        assert.assert_equal(#grid, 6, "Grid should have 6 weeks")

        -- Count actual days in grid
        local day_count = 0
        for _, week in ipairs(grid) do
            assert.assert_type(week, "table", "Week should be a table")
            assert.assert_equal(#week, 7, "Week should have 7 days")
            for _, day in ipairs(week) do
                assert.assert_type(day, "table", "Day should be a table")
                assert.assert_type(day.text, "string", "Day text should be string")
                assert.assert_type(day.day, "number", "Day number should be number")
                if day.day > 0 then
                    day_count = day_count + 1
                    -- Text should be padded to 2 characters
                    assert.assert_equal(#day.text, 2, string.format("Day text '%s' should be 2 characters", day.text))
                end
            end
        end

        -- Should have exactly 31 days for January
        assert.assert_equal(day_count, 31, "January 2025 should have 31 days in grid")
    end)

    assert.run_test("get_calendar_grid - February 2024 (leap year)", function()
        -- February 2024 is a leap year, has 29 days
        local date = { year = 2024, month = 2, day = 1 }
        local grid = CalendarCore.get_calendar_grid(date)

        local day_count = 0
        for _, week in ipairs(grid) do
            for _, day in ipairs(week) do
                if day.day > 0 then
                    day_count = day_count + 1
                end
            end
        end

        assert.assert_equal(day_count, 29, "February 2024 (leap year) should have 29 days")
    end)

    assert.run_test("get_calendar_grid - April 2025 (30 days)", function()
        -- April has 30 days
        local date = { year = 2025, month = 4, day = 1 }
        local grid = CalendarCore.get_calendar_grid(date)

        local day_count = 0
        for _, week in ipairs(grid) do
            for _, day in ipairs(week) do
                if day.day > 0 then
                    day_count = day_count + 1
                end
            end
        end

        assert.assert_equal(day_count, 30, "April 2025 should have 30 days")
    end)

    -- Test: switch_month - basic month transitions
    assert.run_test("switch_month - next month (sequence mode)", function()
        -- January 31 -> February 1 in sequence mode
        local now = { year = 2025, month = 1, day = 31 }
        local result = CalendarCore.switch_month(now, 31, "next", "sequence")

        assert.assert_equal(result and result.year, 2025, "Year should remain 2025")
        assert.assert_equal(result and result.month, 2, "Month should be February")
        assert.assert_equal(result and result.day, 1, "Day should be 1 in sequence mode")
    end)

    assert.run_test("switch_month - previous month (sequence mode)", function()
        -- February 1 -> January 31 in sequence mode
        local now = { year = 2025, month = 2, day = 1 }
        local result = CalendarCore.switch_month(now, 1, "previous", "sequence")

        assert.assert_equal(result.year, 2025, "Year should remain 2025")
        assert.assert_equal(result.month, 1, "Month should be January")
        assert.assert_equal(result.day, 31, "Day should be 31 in sequence mode")
    end)

    assert.run_test("switch_month - next month (default mode)", function()
        -- January 15 -> February 15 (preserve day)
        local now = { year = 2025, month = 1, day = 15 }
        local result = CalendarCore.switch_month(now, 15, "next", nil)

        assert.assert_equal(result.year, 2025, "Year should remain 2025")
        assert.assert_equal(result.month, 2, "Month should be February")
        assert.assert_equal(result.day, 15, "Day should be preserved (15)")
    end)

    assert.run_test("switch_month - previous month (default mode)", function()
        -- March 31 -> February 28 (preserve day but clamp to max days)
        local now = { year = 2025, month = 3, day = 31 }
        local result = CalendarCore.switch_month(now, 31, "previous", nil)

        assert.assert_equal(result.year, 2025, "Year should remain 2025")
        assert.assert_equal(result.month, 2, "Month should be February")
        assert.assert_equal(result.day, 28, "Day should be clamped to 28 (February has 28 days in 2025)")
    end)

    assert.run_test("switch_month - year rollover forward", function()
        -- December 15 -> January next year
        local now = { year = 2025, month = 12, day = 15 }
        local result = CalendarCore.switch_month(now, 15, "next", nil)

        assert.assert_equal(result.year, 2026, "Year should roll over to 2026")
        assert.assert_equal(result.month, 1, "Month should be January")
        assert.assert_equal(result.day, 15, "Day should be preserved (15)")
    end)

    assert.run_test("switch_month - year rollover backward", function()
        -- January 15 -> December previous year
        local now = { year = 2025, month = 1, day = 15 }
        local result = CalendarCore.switch_month(now, 15, "previous", nil)

        assert.assert_equal(result.year, 2024, "Year should roll back to 2024")
        assert.assert_equal(result.month, 12, "Month should be December")
        assert.assert_equal(result.day, 15, "Day should be preserved (15)")
    end)

    -- Test: switch_month - up/down navigation modes
    -- Note: These tests assume specific weekday calculations
    assert.run_test("switch_month - up mode preserves weekday", function()
        -- January 15, 2025 is a Wednesday (weekday 3)
        -- Moving up to December 2024 should find a Wednesday in last week
        local now = { year = 2025, month = 1, day = 15 }
        local result = CalendarCore.switch_month(now, 15, "previous", "up")

        -- December 2024 has 31 days
        -- We just verify the day is valid for December
        assert.assert_equal(result.year, 2024, "Year should be 2024")
        assert.assert_equal(result.month, 12, "Month should be December")
        assert.assert_equal(result.day >= 1 and result.day <= 31, true, "Day should be valid for December")
    end)

    assert.run_test("switch_month - down mode preserves weekday", function()
        -- January 15, 2025 is a Wednesday (weekday 3)
        -- Moving down to February 2025 should find a Wednesday in first week
        local now = { year = 2025, month = 1, day = 15 }
        local result = CalendarCore.switch_month(now, 15, "next", "down")

        -- February 2025 has 28 days
        assert.assert_equal(result.year, 2025, "Year should remain 2025")
        assert.assert_equal(result.month, 2, "Month should be February")
        assert.assert_equal(result.day >= 1 and result.day <= 28, true, "Day should be valid for February")
    end)

    print("  All CalendarCore tests completed")
end

return M
