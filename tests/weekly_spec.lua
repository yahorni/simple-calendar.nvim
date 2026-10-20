-- Unit tests for weekly notes
local assert = require("tests.helpers")

local plugin = require("simple-calendar")

local CalendarCore = plugin._test.CalendarCore
local FileUtils = plugin._test.FileUtils
local _config = plugin._test._config

local M = {}

function M.run()
    print("Running Weekly notes tests...")

    -- Back up state
    local original_buf_get_name = vim.api.nvim_buf_get_name
    local original_fnamemodify = vim.fn.fnamemodify
    local original_filereadable = vim.fn.filereadable
    local original_notify = vim.notify
    local original_cmd = vim.cmd
    local original_isdirectory = vim.fn.isdirectory
    local original_mkdir = vim.fn.mkdir
    local original_writefile = vim.fn.writefile
    local original_confirm = vim.fn.confirm

    local original_weekly_pattern = _config.weekly_path_pattern
    local original_daily_pattern = _config.daily_path_pattern
    local original_use_lowercase = _config.use_lowercase_paths
    local original_show_week_number = _config.show_week_number

    local mock_buf_get_name_return = ""

    vim.api.nvim_buf_get_name = function(_) return mock_buf_get_name_return end
    vim.fn.fnamemodify = function(path, _) return path end

    local mock_filereadable_return = {}
    vim.fn.filereadable = function(path)
        if type(mock_filereadable_return) == "table" then
            return mock_filereadable_return[path] or 0
        end
        return mock_filereadable_return
    end

    local notifications = {}
    vim.notify = function(msg, level, _)
        notifications[#notifications + 1] = { msg = msg, level = level }
    end

    local last_cmd
    vim.cmd = function(cmd) last_cmd = cmd end
    vim.fn.isdirectory = function(_) return 0 end
    vim.fn.mkdir = function(_, _) end
    vim.fn.writefile = function(_, _) end
    vim.fn.confirm = function(_, _, _) return 1 end

    local function restore_state()
        vim.api.nvim_buf_get_name = original_buf_get_name
        vim.fn.fnamemodify = original_fnamemodify
        vim.fn.filereadable = original_filereadable
        vim.notify = original_notify
        vim.cmd = original_cmd
        vim.fn.isdirectory = original_isdirectory
        vim.fn.mkdir = original_mkdir
        vim.fn.writefile = original_writefile
        vim.fn.confirm = original_confirm
        _config.weekly_path_pattern = original_weekly_pattern
        _config.daily_path_pattern = original_daily_pattern
        _config.use_lowercase_paths = original_use_lowercase
        _config.show_week_number = original_show_week_number
    end

    -- All tests live in run_tests so restore_state always runs, even when a
    -- failing assertion aborts the suite mid-way (assert.run_test re-raises).
    -- Without this, the mocked vim.api/vim.fn functions and config (e.g.
    -- show_week_number) would leak into the suites that run after this one.
    local function run_tests()
        -- CalendarCore: get_week_anchor
        assert.run_test("get_week_anchor - midweek day snaps to Monday", function()
            local anchor = CalendarCore.get_week_anchor({ year = 2025, month = 1, day = 15 }) -- Wednesday
            assert.assert_equal(anchor.year, 2025, "Year should be 2025")
            assert.assert_equal(anchor.month, 1, "Month should be 1")
            assert.assert_equal(anchor.day, 13, "Jan 15 2025 is Wednesday, Monday is Jan 13")
        end)

        assert.run_test("get_week_anchor - Monday is its own anchor", function()
            local anchor = CalendarCore.get_week_anchor({ year = 2025, month = 1, day = 13 })
            assert.assert_equal(anchor.day, 13, "A Monday should anchor to itself")
        end)

        assert.run_test("get_week_anchor - Sunday snaps back to Monday", function()
            local anchor = CalendarCore.get_week_anchor({ year = 2025, month = 1, day = 19 }) -- Sunday
            assert.assert_equal(anchor.day, 13, "Sunday Jan 19 2025 belongs to week Mon Jan 13")
        end)

        -- CalendarCore: switch_week
        assert.run_test("switch_week - next and previous", function()
            local anchor = { year = 2025, month = 1, day = 13 }
            local next_week = CalendarCore.switch_week(anchor, "next")
            assert.assert_equal(next_week.day, 20, "Next week Monday should be Jan 20")
            local prev_week = CalendarCore.switch_week(anchor, "previous")
            assert.assert_equal(prev_week.day, 6, "Previous week Monday should be Jan 6")
        end)

        assert.run_test("switch_week - year rollover", function()
            local anchor = { year = 2024, month = 12, day = 30 }
            local next_week = CalendarCore.switch_week(anchor, "next")
            assert.assert_equal(next_week.year, 2025, "Year should roll to 2025")
            assert.assert_equal(next_week.month, 1, "Month should roll to January")
            assert.assert_equal(next_week.day, 6, "2024-W01's next Monday is Jan 6 2025")
        end)

        assert.run_test("shift_days - calendar-day offset with month rollover", function()
            local d = CalendarCore.shift_days({ year = 2025, month = 1, day = 29 }, 7)
            assert.assert_equal(d.year, 2025, "Year should stay 2025")
            assert.assert_equal(d.month, 2, "Month should roll to February")
            assert.assert_equal(d.day, 5, "Jan 29 + 7 days is Feb 5")
        end)

        -- CalendarCore: iso_week_of_anchor / iso_week_to_anchor
        assert.run_test("iso_week_of_anchor - known ISO weeks", function()
            local w = CalendarCore.iso_week_of_anchor({ year = 2024, month = 12, day = 30 })
            assert.assert_equal(w.iso_year, 2025, "Dec 30 2024 Monday is ISO 2025")
            assert.assert_equal(w.week, 1, "Dec 30 2024 Monday is ISO week 01")

            local w2 = CalendarCore.iso_week_of_anchor({ year = 2020, month = 12, day = 28 }) -- Monday
            assert.assert_equal(w2.week, 53, "Dec 28 2020 Monday is ISO week 53")
        end)

        assert.run_test("iso_week_to_anchor - roundtrip", function()
            local anchor = CalendarCore.iso_week_to_anchor(2025, 1)
            assert.assert_equal(anchor.year, 2024, "2025-W01 starts Mon Dec 30 2024")
            assert.assert_equal(anchor.month, 12, "2025-W01 starts in December")
            assert.assert_equal(anchor.day, 30, "2025-W01 starts Dec 30")

            assert.assert_nil(CalendarCore.iso_week_to_anchor(2025, 54), "Week 54 is invalid")
            assert.assert_nil(CalendarCore.iso_week_to_anchor(2025, 0), "Week 0 is invalid")
        end)

        assert.run_test("iso_week_to_anchor - week 53 only for 53-week years", function()
            -- 2020 has 53 ISO weeks; 2025 has only 52.
            local w53 = CalendarCore.iso_week_to_anchor(2020, 53)
            assert.assert_not_nil(w53, "2020-W53 is a valid ISO week")
            assert.assert_equal(w53.year, 2020, "2020-W53 starts in 2020")
            assert.assert_equal(w53.day, 28, "2020-W53 starts Mon Dec 28")

            assert.assert_nil(CalendarCore.iso_week_to_anchor(2025, 53),
                "2025-W53 is not a valid ISO week (2025 has 52 weeks)")
        end)

        assert.run_test("iso_week_to_anchor - DST-safe week arithmetic", function()
            -- 2025 US DST begins Mar 9 (week 10 -> week 11). Weeks must stay exactly
            -- 7 calendar days apart even across the transition.
            local w10 = CalendarCore.iso_week_to_anchor(2025, 10)
            local w11 = CalendarCore.iso_week_to_anchor(2025, 11)
            assert.assert_equal(w10.day, 3, "2025-W10 Monday is Mar 3")
            assert.assert_equal(w11.day, 10, "2025-W11 Monday is Mar 10")
            -- Both anchors are Mondays and 7 days apart on the calendar (the day
            -- numbers differ by 7 and the month/year are consistent).
            assert.assert_equal(w11.day - w10.day, 7, "Consecutive week Mondays differ by 7 days")
        end)

        -- FileUtils: extract_week_from_filename
        assert.run_test("extract_week_from_filename - %G-W%V pattern", function()
            _config.weekly_path_pattern = "%G-W%V.md"
            mock_buf_get_name_return = "/home/user/notes/2025-W03.md"
            local anchor = FileUtils.extract_week_from_filename()
            assert.assert_not_nil(anchor, "Should extract week anchor")
            assert.assert_equal(anchor.year, 2025, "Year should be 2025")
            assert.assert_equal(anchor.month, 1, "Month should be January")
            assert.assert_equal(anchor.day, 13, "2025-W03 starts Mon Jan 13")
        end)

        assert.run_test("extract_week_from_filename - Monday-anchored date pattern", function()
            _config.weekly_path_pattern = "weekly/%Y-%m-%d.md"
            mock_buf_get_name_return = "/home/user/weekly/2025-01-13.md"
            local anchor = FileUtils.extract_week_from_filename()
            assert.assert_not_nil(anchor, "Should extract week anchor")
            assert.assert_equal(anchor.day, 13, "Monday anchor stays Jan 13")
        end)

        assert.run_test("extract_week_from_filename - no match returns nil with no_match reason", function()
            _config.weekly_path_pattern = "%G-W%V.md"
            mock_buf_get_name_return = "/home/user/random.txt"
            local anchor, reason = FileUtils.extract_week_from_filename()
            assert.assert_nil(anchor, "Non-matching file returns nil")
            assert.assert_equal(reason, "no_match", "Reason should be 'no_match'")
        end)

        assert.run_test("extract_week_from_filename - %V without %G/%g returns nil with pattern reason", function()
            _config.weekly_path_pattern = "%Y-W%V.md"
            mock_buf_get_name_return = "/home/user/notes/2025-W03.md"
            local anchor, reason = FileUtils.extract_week_from_filename()
            assert.assert_nil(anchor, "%V without %G/%g cannot be resolved unambiguously")
            assert.assert_equal(reason, "pattern", "Reason should be 'pattern'")
        end)

        assert.run_test("extract_week_from_filename - pattern without tokens returns nil with pattern reason",
            function()
                _config.weekly_path_pattern = "weekly.md"
                mock_buf_get_name_return = "/home/user/notes/weekly.md"
                local anchor, reason = FileUtils.extract_week_from_filename()
                assert.assert_nil(anchor, "Pattern without week tokens cannot resolve a week")
                assert.assert_equal(reason, "pattern", "Reason should be 'pattern'")
            end)

        assert.run_test("extract_week_from_filename - week 53 in a 52-week year returns nil with invalid_week reason",
            function()
                _config.weekly_path_pattern = "%G-W%V.md"
                mock_buf_get_name_return = "/home/user/notes/2025-W53.md"
                local anchor, reason = FileUtils.extract_week_from_filename()
                assert.assert_nil(anchor, "2025-W53 is not a valid ISO week and must not resolve to a wrong week")
                assert.assert_equal(reason, "invalid_week", "Reason should be 'invalid_week'")
            end)

        -- FileUtils: get_week_status
        assert.run_test("get_week_status - exists and missing", function()
            _config.weekly_path_pattern = "%G-W%V.md"
            mock_filereadable_return = { ["2025-W03.md"] = 1 }
            assert.assert_equal(FileUtils.get_week_status({ year = 2025, month = 1, day = 13 }), "exists",
                "Existing weekly file returns exists")
            assert.assert_equal(FileUtils.get_week_status({ year = 2025, month = 1, day = 20 }), "missing",
                "Missing weekly file returns missing")
        end)

        assert.run_test("get_week_status - empty pattern returns normal", function()
            _config.weekly_path_pattern = ""
            assert.assert_equal(FileUtils.get_week_status({ year = 2025, month = 1, day = 13 }), "normal",
                "Empty pattern returns normal")
        end)

        -- API: M.weekly
        assert.run_test("weekly - empty pattern shows error", function()
            _config.weekly_path_pattern = ""
            notifications = {}
            plugin.weekly()
            assert.assert_equal(#notifications, 1, "Should show one error")
            assert.assert_not_nil(string.find(notifications[1].msg, "weekly_path_pattern"),
                "Error should mention weekly_path_pattern")
        end)

        assert.run_test("weekly - today opens current week", function()
            _config.weekly_path_pattern = "%G-W%V.md"
            notifications = {}
            last_cmd = nil
            plugin.weekly("today")
            assert.assert_not_nil(last_cmd, "Should attempt to edit a file")
        end)

        assert.run_test("weekly - empty string opens current week (user command)", function()
            _config.weekly_path_pattern = "%G-W%V.md"
            notifications = {}
            last_cmd = nil
            plugin.weekly("")
            assert.assert_equal(#notifications, 0, "Empty string should not error")
            assert.assert_not_nil(last_cmd, "Empty string should open this week's file")
        end)

        assert.run_test("weekly - date table opens that date's week", function()
            _config.weekly_path_pattern = "%G-W%V.md"
            mock_filereadable_return = {}
            notifications = {}
            last_cmd = nil
            plugin.weekly({ year = 2025, month = 1, day = 15 })
            -- Jan 15 2025 is Wednesday of 2025-W03
            assert.assert_equal(#notifications, 0, "Date table should not error")
            assert.assert_equal(last_cmd, "edit 2025-W03.md", "Date table should open 2025-W03")
        end)

        assert.run_test("weekly - non-string non-table arg shows error", function()
            _config.weekly_path_pattern = "%G-W%V.md"
            notifications = {}
            plugin.weekly(42)
            assert.assert_equal(#notifications, 1, "Should show one error")
            assert.assert_not_nil(string.find(notifications[1].msg, "Invalid week"),
                "Error should mention the invalid week argument")
        end)

        assert.run_test("weekly - previous/next relative to open file", function()
            _config.weekly_path_pattern = "%G-W%V.md"
            mock_buf_get_name_return = "/home/user/notes/2025-W03.md"
            mock_filereadable_return = {} -- file does not exist, so confirm->create

            last_cmd = nil
            plugin.weekly("next")
            -- 2025-W03 (Jan 13) next week = Jan 20 = 2025-W04
            assert.assert_equal(last_cmd, "edit 2025-W04.md", "next should open 2025-W04")

            last_cmd = nil
            plugin.weekly("previous")
            -- 2025-W03 previous week = Jan 6 = 2025-W02
            assert.assert_equal(last_cmd, "edit 2025-W02.md", "previous should open 2025-W02")
        end)

        assert.run_test("weekly - from_daily opens the week of the open daily note", function()
            _config.weekly_path_pattern = "%G-W%V.md"
            _config.daily_path_pattern = "%Y-%m-%d.md"
            mock_buf_get_name_return = "/home/user/notes/2025-01-13.md"
            mock_filereadable_return = {}

            last_cmd = nil
            plugin.weekly("from_daily")
            -- Jan 13 2025 is Monday of 2025-W03
            assert.assert_equal(last_cmd, "edit 2025-W03.md", "from_daily should open 2025-W03")
        end)

        assert.run_test("weekly - previous with non-matching file shows error", function()
            _config.weekly_path_pattern = "%G-W%V.md"
            mock_buf_get_name_return = "/home/user/random.txt"
            notifications = {}
            plugin.weekly("previous")
            assert.assert_equal(#notifications, 1, "Should show one error")
            assert.assert_not_nil(string.find(notifications[1].msg, "weekly_path_pattern"),
                "Error should mention weekly_path_pattern")
        end)

        assert.run_test("weekly - next with pattern lacking tokens shows specific error", function()
            _config.weekly_path_pattern = "weekly.md"
            mock_buf_get_name_return = "/home/user/notes/weekly.md"
            notifications = {}
            plugin.weekly("next")
            assert.assert_equal(#notifications, 1, "Should show one error")
            assert.assert_not_nil(string.find(notifications[1].msg, "cannot resolve a week", 1, true),
                "Error should report that the pattern cannot resolve a week")
        end)

        assert.run_test("weekly - next with %V without %G shows pattern error, not mismatch", function()
            _config.weekly_path_pattern = "%Y-W%V.md"
            mock_buf_get_name_return = "/home/user/notes/2025-W03.md"
            notifications = {}
            plugin.weekly("next")
            assert.assert_equal(#notifications, 1, "Should show one error")
            assert.assert_not_nil(string.find(notifications[1].msg, "cannot resolve a week", 1, true),
                "Error should report that the pattern cannot resolve a week")
        end)

        assert.run_test("weekly - next with invalid week in filename shows specific error", function()
            _config.weekly_path_pattern = "%G-W%V.md"
            mock_buf_get_name_return = "/home/user/notes/2025-W53.md"
            notifications = {}
            plugin.weekly("next")
            assert.assert_equal(#notifications, 1, "Should show one error")
            assert.assert_not_nil(string.find(notifications[1].msg, "invalid ISO week", 1, true),
                "Error should report the invalid ISO week")
        end)

        assert.run_test("weekly - from_daily with non-matching file shows error", function()
            _config.weekly_path_pattern = "%G-W%V.md"
            _config.daily_path_pattern = "%Y-%m-%d.md"
            mock_buf_get_name_return = "/home/user/random.txt"
            notifications = {}
            plugin.weekly("from_daily")
            assert.assert_equal(#notifications, 1, "Should show one error")
            assert.assert_not_nil(string.find(notifications[1].msg, "daily_path_pattern"),
                "Error should mention daily_path_pattern")
        end)

        assert.run_test("weekly - invalid string shows error", function()
            _config.weekly_path_pattern = "%G-W%V.md"
            notifications = {}
            plugin.weekly("notaword")
            assert.assert_equal(#notifications, 1, "Should show one error")
        end)

        -- Grid gutter anchor
        assert.run_test("get_calendar_grid - rows carry week_anchor", function()
            local grid = CalendarCore.get_calendar_grid({ year = 2025, month = 1, day = 1 })
            assert.assert_not_nil(grid[1].week_anchor, "First row should have a week_anchor")
            assert.assert_equal(grid[1].week_anchor.day, 30, "First row of Jan 2025 anchors to Dec 30 2024")
        end)

        -- Gutter rendering
        assert.run_test("refresh_calendar - gutter label, separator, trailing row", function()
            _config.show_week_number = true
            local grid, lines = CalendarCore.refresh_calendar({ year = 2026, month = 10, day = 1 })

            -- Header spans full width (gutter 3 + weekday grid 20)
            assert.assert_equal(#lines[1], 23, "Header should span full width")

            -- Weekday header has W label and separator
            assert.assert_equal(lines[2]:sub(1, 3), " W|", "Weekday header prefix should be ' W|'")

            -- Week rows have right-aligned number + separator, no trailing space
            assert.assert_equal(lines[3]:sub(1, 3), "40|", "First week row should start with '40|'")
            assert.assert_equal(lines[4]:sub(1, 3), "41|", "Second week row should start with '41|'")

            -- Last week is trimmed of its trailing empty day cell (Oct 2026 ends Sat)
            assert.assert_equal(lines[7], "44|26 27 28 29 30 31", "Last week should be trimmed to its last real day")

            -- The blank trailing week is still present (empty line) for constant height
            assert.assert_equal(#lines, 8, "Six-week grid keeps an empty trailing week")
            assert.assert_equal(lines[8], "   ", "Blank week renders as empty gutter (3 spaces)")
            _config.show_week_number = false
        end)
    end

    local ok, err = pcall(run_tests)
    restore_state()
    if not ok then
        error(err, 0)
    end

    print("  All Weekly notes tests completed")
end

return M
