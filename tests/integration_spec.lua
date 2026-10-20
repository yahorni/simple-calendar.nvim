-- Integration tests for simple-calendar.nvim
local assert = require("tests.helpers")

-- Load the plugin module
local plugin = require("simple-calendar")

local M = {}

function M.run()
    print("Running Integration tests...")

    -- Backup original vim.api functions
    local original_api = {}
    local api_calls = {}

    -- Helper to mock any vim.api function
    local function mock_api(name, impl)
        original_api[name] = vim.api[name]
        vim.api[name] = function(...)
            api_calls[name] = api_calls[name] or {}
            table.insert(api_calls[name], { ... })
            if impl then
                return impl(...)
            end
            -- Default returns
            if name == "nvim_create_buf" then return 1 end
            if name == "nvim_open_win" then return 2 end
            if name == "nvim_list_uis" then return { { width = 80, height = 24 } } end
            if name == "nvim_win_is_valid" then return true end
            if name == "nvim_win_get_cursor" then return { 3, 1 } end
            if name == "nvim_buf_get_name" then return "" end
            if name == "nvim_buf_set_option" then return nil end
            if name == "nvim_buf_set_lines" then return nil end
            if name == "nvim_buf_clear_namespace" then return nil end
            if name == "nvim_buf_add_highlight" then return nil end
            if name == "nvim_win_set_option" then return nil end
            if name == "nvim_win_set_cursor" then return nil end
            if name == "nvim_create_augroup" then return 3 end
            if name == "nvim_create_autocmd" then return nil end
            if name == "nvim_win_close" then return nil end
            return nil
        end
    end

    -- Mock all used vim.api functions
    mock_api("nvim_create_buf")
    mock_api("nvim_open_win")
    mock_api("nvim_list_uis")
    mock_api("nvim_win_is_valid")
    mock_api("nvim_win_get_cursor")
    mock_api("nvim_buf_get_name")
    mock_api("nvim_buf_set_option")
    mock_api("nvim_buf_set_lines")
    mock_api("nvim_buf_clear_namespace")
    mock_api("nvim_buf_add_highlight")
    mock_api("nvim_win_set_option")
    mock_api("nvim_win_set_cursor")
    mock_api("nvim_create_augroup")
    mock_api("nvim_create_autocmd")
    mock_api("nvim_win_close")

    -- Mock vim.fn functions
    local original_filereadable = vim.fn.filereadable
    local original_fnamemodify = vim.fn.fnamemodify
    local original_isdirectory = vim.fn.isdirectory
    local original_mkdir = vim.fn.mkdir
    local original_writefile = vim.fn.writefile
    local original_readfile = vim.fn.readfile
    local original_confirm = vim.fn.confirm

    vim.fn.filereadable = function(_path) return 0 end
    vim.fn.fnamemodify = function(_path, _mod) return _path end
    vim.fn.isdirectory = function(_path) return 0 end
    vim.fn.mkdir = function(_path, _mode) end
    vim.fn.writefile = function(_list, _path) end
    vim.fn.readfile = function(_path) return {} end
    vim.fn.confirm = function(_msg, _choices, _default) return 1 end

    -- Test: M.open - basic invocation
    assert.run_test("M.open - can be called without errors", function()
        local ok, err = pcall(function() plugin.open() end)
        assert.assert_equal(ok, true, "calendar.open should not error: " .. tostring(err))

        -- Verify some API calls were made
        assert.assert_not_nil(api_calls["nvim_create_buf"], "should create buffer")
        assert.assert_not_nil(api_calls["nvim_open_win"], "should open window")
    end)

    assert.run_test("M.open - with date parameter", function()
        local date = { year = 2025, month = 1, day = 15 }
        local ok, err = pcall(function() plugin.open(date) end)
        assert.assert_equal(ok, true, "calendar.open with date should not error: " .. tostring(err))
    end)

    assert.run_test("M.open - invalid date table does not crash", function()
        local invalid = {
            { year = 2025, month = 13, day = 1 },
            { year = 2025, month = 0, day = 1 },
            { year = 2025, month = "1", day = 1 },
            { year = 2025 },
            "2025-01-01",
        }
        for _, date in ipairs(invalid) do
            local ok, err = pcall(plugin.open, date)
            assert.assert_equal(ok, true, "open() should not crash on invalid date: " .. tostring(err))
        end
    end)

    -- Test: M.open - focuses on the open weekly note's week
    assert.run_test("M.open - focuses on the open weekly note's week", function()
        local config = plugin._test._config
        local original_weekly = config.weekly_path_pattern
        local original_daily = config.daily_path_pattern
        local original_show = config.show_week_number
        config.weekly_path_pattern = "%G-W%V.md"
        config.daily_path_pattern = "%Y-%m-%d.md"
        config.show_week_number = false

        local original_buf_get_name = vim.api.nvim_buf_get_name
        vim.api.nvim_buf_get_name = function() return "/home/user/notes/2025-W03.md" end

        api_calls["nvim_buf_set_lines"] = {}
        api_calls["nvim_win_set_cursor"] = {}

        local ok, err = pcall(function() plugin.open() end)
        assert.assert_equal(ok, true, "open() with weekly filename should not error: " .. tostring(err))

        -- Header should show the week's month
        local set_lines_calls = api_calls["nvim_buf_set_lines"]
        local lines = set_lines_calls[#set_lines_calls][5]
        assert.assert_not_nil(string.find(lines[1], "January 2025"), "Header should show January 2025")

        -- Selection should land on the week's Thursday (Jan 16 2025): grid
        -- row 3, fourth column => buffer line 5, col 10.
        local set_cursor_calls = api_calls["nvim_win_set_cursor"]
        local pos = set_cursor_calls[#set_cursor_calls][2]
        assert.assert_equal(pos[1], 5, "Cursor line should be the Thursday's row")
        assert.assert_equal(pos[2], 10, "Cursor col should be the Thursday's column")

        -- Restore
        config.weekly_path_pattern = original_weekly
        config.daily_path_pattern = original_daily
        config.show_week_number = original_show
        vim.api.nvim_buf_get_name = original_buf_get_name
    end)

    -- Test: M.open - current weekly note focuses today instead of Monday
    assert.run_test("M.open - current weekly note focuses today", function()
        local config = plugin._test._config
        local original_weekly = config.weekly_path_pattern
        local original_daily = config.daily_path_pattern
        local original_show = config.show_week_number
        config.weekly_path_pattern = "%G-W%V.md"
        config.daily_path_pattern = "%Y-%m-%d.md"
        config.show_week_number = false

        -- Build the filename for the actual current ISO week (no hardcoded dates).
        local CalendarCore = plugin._test.CalendarCore
        local today = CalendarCore.validate_date(os.date("*t"))
        local iso = CalendarCore.iso_week_of_anchor(CalendarCore.get_week_anchor(today))
        local filename = string.format("/home/user/notes/%d-W%02d.md", iso.iso_year, iso.week)

        local original_buf_get_name = vim.api.nvim_buf_get_name
        vim.api.nvim_buf_get_name = function() return filename end

        -- Force a cursor position that never matches, so the final
        -- nvim_win_set_cursor call is always the one we assert on.
        local original_win_get_cursor = vim.api.nvim_win_get_cursor
        vim.api.nvim_win_get_cursor = function() return { 0, 0 } end

        api_calls["nvim_buf_set_lines"] = {}
        api_calls["nvim_win_set_cursor"] = {}

        local ok, err = pcall(function() plugin.open() end)
        assert.assert_equal(ok, true, "open() with current weekly filename should not error: " .. tostring(err))

        -- Header should show today's month
        local set_lines_calls = api_calls["nvim_buf_set_lines"]
        local lines = set_lines_calls[#set_lines_calls][5]
        local expected_header = CalendarCore.MONTH_NAMES[today.month] .. " " .. tostring(today.year)
        assert.assert_not_nil(string.find(lines[1], expected_header),
            "Header should show today's month (" .. expected_header .. ")")

        -- Selection should land on today, not on the week's Monday
        local UI = plugin._test.UI
        local grid = CalendarCore.get_calendar_grid(today)
        local expected = UI.position_from_day(grid, today.day)
        local set_cursor_calls = api_calls["nvim_win_set_cursor"]
        local pos = set_cursor_calls[#set_cursor_calls][2]
        assert.assert_equal(pos[1], expected.line + 3, "Cursor line should be today's row")
        assert.assert_equal(pos[2], expected.col, "Cursor col should be today's column")

        -- Restore
        config.weekly_path_pattern = original_weekly
        config.daily_path_pattern = original_daily
        config.show_week_number = original_show
        vim.api.nvim_buf_get_name = original_buf_get_name
        vim.api.nvim_win_get_cursor = original_win_get_cursor
    end)

    -- Control: a daily-pattern filename still focuses that day (daily wins)
    assert.run_test("M.open - daily filename still focuses the day", function()
        local config = plugin._test._config
        local original_weekly = config.weekly_path_pattern
        local original_daily = config.daily_path_pattern
        local original_show = config.show_week_number
        config.weekly_path_pattern = "%G-W%V.md"
        config.daily_path_pattern = "%Y-%m-%d.md"
        config.show_week_number = false

        local original_buf_get_name = vim.api.nvim_buf_get_name
        vim.api.nvim_buf_get_name = function() return "/home/user/notes/2025-01-15.md" end

        api_calls["nvim_win_set_cursor"] = {}

        local ok, err = pcall(function() plugin.open() end)
        assert.assert_equal(ok, true, "open() with daily filename should not error: " .. tostring(err))

        -- Jan 15 2025 is Wednesday: grid row 3, third column => line 5, col 7.
        local set_cursor_calls = api_calls["nvim_win_set_cursor"]
        local pos = set_cursor_calls[#set_cursor_calls][2]
        assert.assert_equal(pos[1], 5, "Cursor line should be Jan 15's row")
        assert.assert_equal(pos[2], 7, "Cursor col should be Jan 15's column")

        -- Restore
        config.weekly_path_pattern = original_weekly
        config.daily_path_pattern = original_daily
        config.show_week_number = original_show
        vim.api.nvim_buf_get_name = original_buf_get_name
    end)

    -- Test: M.open - today's cell gets the CalendarToday underline
    assert.run_test("M.open - today's cell is underlined", function()
        local config = plugin._test._config
        local original_weekly = config.weekly_path_pattern
        local original_daily = config.daily_path_pattern
        local original_show = config.show_week_number
        config.weekly_path_pattern = ""
        config.daily_path_pattern = ""
        config.show_week_number = false

        api_calls["nvim_buf_add_highlight"] = {}

        local ok, err = pcall(function() plugin.open() end)
        assert.assert_equal(ok, true, "open() should not error: " .. tostring(err))

        -- Expected cell: today's position in the current month's grid.
        local CalendarCore = plugin._test.CalendarCore
        local UI = plugin._test.UI
        local today = CalendarCore.validate_date(os.date("*t"))
        local grid = CalendarCore.get_calendar_grid(today)
        local pos = UI.position_from_day(grid, today.day)
        local expected_line = pos.line + 2 -- 0-based buffer line
        local expected_col_start = pos.col - 1

        local found = false
        for _, call in ipairs(api_calls["nvim_buf_add_highlight"]) do
            if call[3] == "CalendarToday" and call[4] == expected_line and call[5] == expected_col_start then
                found = true
                break
            end
        end
        assert.assert_equal(found, true, "today's cell should be highlighted with CalendarToday")

        -- Restore
        config.weekly_path_pattern = original_weekly
        config.daily_path_pattern = original_daily
        config.show_week_number = original_show
    end)

    -- Test: M.journal - basic invocation
    assert.run_test("M.journal - can be called without errors", function()
        -- Set a pattern to avoid empty pattern error
        local config = plugin._test._config
        local original_pattern = config.daily_path_pattern
        config.daily_path_pattern = "%Y-%m-%d.md"

        -- Mock vim.notify to suppress output during test
        local original_notify = vim.notify
        vim.notify = function(_msg, _level, _) end

        -- Mock vim.cmd to avoid swap file errors
        local original_cmd = vim.cmd
        vim.cmd = function(_) end

        -- Call journal with different offsets (should not crash)
        local ok, err = pcall(function() plugin.journal() end)
        assert.assert_equal(ok, true, "journal() should not error: " .. tostring(err))

        ok, err = pcall(function() plugin.journal("today") end)
        assert.assert_equal(ok, true, "journal(0) should not error: " .. tostring(err))

        ok, err = pcall(function() plugin.journal("tomorrow") end)
        assert.assert_equal(ok, true, "journal(1) should not error: " .. tostring(err))

        ok, err = pcall(function() plugin.journal("yesterday") end)
        assert.assert_equal(ok, true, "journal(-1) should not error: " .. tostring(err))

        -- Invalid offset should also not crash (vim.notify used, no error)
        ok, err = pcall(function() plugin.journal("hello") end)
        assert.assert_equal(ok, true, "journal('hello') should not error: " .. tostring(err))

        ok, err = pcall(function() plugin.journal(0) end)
        assert.assert_equal(ok, true, "journal(0) should not error: " .. tostring(err))

        ok, err = pcall(function() plugin.journal(1) end)
        assert.assert_equal(ok, true, "journal(1) should not error: " .. tostring(err))


        -- Restore
        config.daily_path_pattern = original_pattern
        vim.notify = original_notify
        vim.cmd = original_cmd
    end)

    -- Test: M.journal - table arguments
    assert.run_test("M.journal - table arguments", function()
        local config = plugin._test._config
        local original_pattern = config.daily_path_pattern
        config.daily_path_pattern = "%Y-%m-%d.md"

        local original_notify = vim.notify
        vim.notify = function(_msg, _level, _) end

        local original_cmd = vim.cmd
        vim.cmd = function(_) end

        -- Valid date table
        local ok, err = pcall(function() plugin.journal({ year = 2025, month = 1, day = 15 }) end)
        assert.assert_equal(ok, true, "journal with valid date table should not error: " .. tostring(err))

        -- Invalid date tables
        ok, err = pcall(function() plugin.journal({ year = 2025, month = 13, day = 1 }) end)
        assert.assert_equal(ok, true, "journal with invalid month should not error: " .. tostring(err))

        ok, err = pcall(function() plugin.journal({ year = 2025, month = 2, day = 30 }) end)
        assert.assert_equal(ok, true, "journal with invalid day should not error: " .. tostring(err))

        ok, err = pcall(function() plugin.journal({ year = "2025", month = 1, day = 1 }) end)
        assert.assert_equal(ok, true, "journal with non-numeric year should not error: " .. tostring(err))

        ok, err = pcall(function() plugin.journal({ month = 1, day = 1 }) end)
        assert.assert_equal(ok, true, "journal missing year should not error: " .. tostring(err))

        ok, err = pcall(function() plugin.journal({}) end)
        assert.assert_equal(ok, true, "journal empty table should not error: " .. tostring(err))

        -- Restore
        config.daily_path_pattern = original_pattern
        vim.notify = original_notify
        vim.cmd = original_cmd
    end)

    -- Test: M.journal - next/previous day relative to current note
    assert.run_test("M.journal - next/previous day relative to current note", function()
        local config = plugin._test._config
        local original_pattern = config.daily_path_pattern
        local original_skip_weekends = config.skip_weekends
        config.daily_path_pattern = "%Y-%m-%d.md"
        config.skip_weekends = false

        local original_notify = vim.notify
        vim.notify = function(_msg, _level, _) end

        local original_cmd = vim.cmd
        local last_cmd
        vim.cmd = function(cmd) last_cmd = cmd end

        local original_buf_get_name = vim.api.nvim_buf_get_name
        vim.api.nvim_buf_get_name = function() return "/home/user/notes/2025-06-13.md" end

        local ok, err = pcall(function() plugin.journal("next") end)
        assert.assert_equal(ok, true, "journal('next') should not error: " .. tostring(err))
        assert.assert_equal(last_cmd, "edit 2025-06-14.md", "next from Friday should open Saturday")

        ok, err = pcall(function() plugin.journal("previous") end)
        assert.assert_equal(ok, true, "journal('previous') should not error: " .. tostring(err))
        assert.assert_equal(last_cmd, "edit 2025-06-12.md", "previous from Friday should open Thursday")

        config.skip_weekends = true
        ok, err = pcall(function() plugin.journal("next") end)
        assert.assert_equal(ok, true, "journal('next') with skip_weekends should not error: " .. tostring(err))
        assert.assert_equal(last_cmd, "edit 2025-06-16.md", "next from Friday should skip to Monday")

        last_cmd = nil
        vim.api.nvim_buf_get_name = function() return "/home/user/random.txt" end
        ok, err = pcall(function() plugin.journal("next") end)
        assert.assert_equal(ok, true, "journal('next') from non-note file should not error: " .. tostring(err))
        assert.assert_equal(last_cmd, nil, "no edit should be attempted without a current note")

        -- Restore
        config.daily_path_pattern = original_pattern
        config.skip_weekends = original_skip_weekends
        vim.notify = original_notify
        vim.cmd = original_cmd
        vim.api.nvim_buf_get_name = original_buf_get_name
    end)

    -- Restore original functions
    for name, fn in pairs(original_api) do
        vim.api[name] = fn
    end

    vim.fn.filereadable = original_filereadable
    vim.fn.fnamemodify = original_fnamemodify
    vim.fn.isdirectory = original_isdirectory
    vim.fn.mkdir = original_mkdir
    vim.fn.writefile = original_writefile
    vim.fn.readfile = original_readfile
    vim.fn.confirm = original_confirm

    print("  All Integration tests completed")
end

return M
