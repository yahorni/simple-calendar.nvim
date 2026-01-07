-- Unit tests for FileUtils module
local assert = require("tests.helpers")

-- Load the plugin module
local plugin = require("simple-calendar")

-- Get test exports
local FileUtils = plugin._test.FileUtils

local _config = plugin._test._config

local M = {}

function M.run()
    print("Running FileUtils tests...")

    -- Backup original vim functions and config
    local original_filereadable = vim.fn.filereadable
    local original_readfile = vim.fn.readfile
    local original_buf_get_name = vim.api.nvim_buf_get_name
    local original_config_pattern = _config.path_pattern
    local original_config_highlight = _config.highlight_unfinished_tasks

    -- Mock functions with configurable return values
    local mock_filereadable_return = 0
    local mock_filereadable = function(_path) return mock_filereadable_return end
    vim.fn.filereadable = mock_filereadable

    local mock_readfile_calls = 0
    local mock_readfile_return = {}
    local mock_readfile = function(_path)
        mock_readfile_calls = mock_readfile_calls + 1
        return mock_readfile_return
    end
    vim.fn.readfile = mock_readfile

    -- Mock buffer name function with configurable return value
    local mock_buf_get_name_return = ""
    local mock_buf_get_name = function(_buffer) return mock_buf_get_name_return end
    vim.api.nvim_buf_get_name = mock_buf_get_name

    -- Helper to restore original state
    local function restore_state()
        vim.fn.filereadable = original_filereadable
        vim.fn.readfile = original_readfile
        vim.api.nvim_buf_get_name = original_buf_get_name
        _config.path_pattern = original_config_pattern
        _config.highlight_unfinished_tasks = original_config_highlight
    end

    -- Test: convert_pattern_to_regex - basic patterns
    assert.run_test("convert_pattern_to_regex - default pattern", function()
        local pattern = "%Y-%m-%d.md"
        local result = FileUtils.convert_pattern_to_regex(pattern)

        assert.assert_equal(result.year_index, 1, "Year should be capture group 1")
        assert.assert_equal(result.month_index, 2, "Month should be capture group 2")
        assert.assert_equal(result.day_index, 3, "Day should be capture group 3")
        assert.assert_equal(result.regex, "(%d%d%d%d)%-(%d%d)%-(%d%d)%.md", "Regex should match YYYY-MM-DD.md")
    end)

    assert.run_test("convert_pattern_to_regex - month name pattern", function()
        local pattern = "notes/%B-%d-%Y.txt"
        local result = FileUtils.convert_pattern_to_regex(pattern)

        assert.assert_equal(result.year_index, 3, "Year should be capture group 3")
        assert.assert_equal(result.month_index, 1, "Month should be capture group 1 (month name)")
        assert.assert_equal(result.day_index, 2, "Day should be capture group 2")
        -- Month name capture group should be (%a+)
        assert.assert_type(result.regex, "string", "Regex should be string")
        -- Check that pattern contains notes/ and .txt
        assert.assert_not_nil(string.find(result.regex, "notes/"), "Regex should contain 'notes/' prefix")
        assert.assert_not_nil(string.find(result.regex, "%.txt"), "Regex should contain '.txt' suffix")
    end)

    assert.run_test("convert_pattern_to_regex - mixed patterns", function()
        local pattern = "journal/%Y/%m/%d.md"
        local result = FileUtils.convert_pattern_to_regex(pattern)

        assert.assert_equal(result.year_index, 1, "Year should be capture group 1")
        assert.assert_equal(result.month_index, 2, "Month should be capture group 2")
        assert.assert_equal(result.day_index, 3, "Day should be capture group 3")
        -- Should escape slashes
        assert.assert_not_nil(string.find(result.regex, "journal/"), "Regex should contain 'journal/'")
    end)

    assert.run_test("convert_pattern_to_regex - no date patterns", function()
        local pattern = "daily-notes.txt"
        local result = FileUtils.convert_pattern_to_regex(pattern)

        assert.assert_equal(result.year_index, 0, "Year index should be 0")
        assert.assert_equal(result.month_index, 0, "Month index should be 0")
        assert.assert_equal(result.day_index, 0, "Day index should be 0")
        assert.assert_equal(result.regex, "daily%-notes%.txt", "Regex should escape hyphens and dot")
    end)

    -- Test: extract_date_from_filename - with mock buffer
    assert.run_test("extract_date_from_filename - valid date in filename", function()
        -- Set mock return value
        mock_buf_get_name_return = "/home/user/2025-01-15.md"
        -- Set config pattern to default
        _config.path_pattern = "%Y-%m-%d.md"

        local date = FileUtils.extract_date_from_filename()

        assert.assert_not_nil(date, "Should extract date from filename")
        assert.assert_equal(date and date.year, 2025, "Year should be 2025")
        assert.assert_equal(date and date.month, 1, "Month should be 1")
        assert.assert_equal(date and date.day, 15, "Day should be 15")
    end)

    assert.run_test("extract_date_from_filename - month name pattern", function()
        mock_buf_get_name_return = "/home/user/notes/January-15-2025.txt"
        _config.path_pattern = "notes/%B-%d-%Y.txt"

        local date = FileUtils.extract_date_from_filename()

        assert.assert_not_nil(date, "Should extract date from month name pattern")
        assert.assert_equal(date and date.year, 2025, "Year should be 2025")
        assert.assert_equal(date and date.month, 1, "January should be month 1")
        assert.assert_equal(date and date.day, 15, "Day should be 15")
    end)

    assert.run_test("extract_date_from_filename - no match", function()
        mock_buf_get_name_return = "/home/user/random-file.txt"
        _config.path_pattern = "%Y-%m-%d.md"

        local date = FileUtils.extract_date_from_filename()

        assert.assert_nil(date, "Should return nil when pattern doesn't match")
    end)

    assert.run_test("extract_date_from_filename - empty buffer name", function()
        mock_buf_get_name_return = ""

        local date = FileUtils.extract_date_from_filename()

        assert.assert_nil(date, "Should return nil for empty buffer name")
    end)

    -- Test: get_day_status - requires mocking filereadable and readfile
    assert.run_test("get_day_status - missing file", function()
        mock_filereadable_return = 0
        mock_readfile_calls = 0 -- reset counter
        _config.path_pattern = "%Y-%m-%d.md"
        _config.highlight_unfinished_tasks = true

        local date = { year = 2025, month = 1, day = 15 }
        local status = FileUtils.get_day_status(date)

        assert.assert_equal(status, "missing", "Missing file should return 'missing'")
        assert.assert_equal(mock_readfile_calls, 0, "readfile should not be called when file doesn't exist")
    end)

    assert.run_test("get_day_status - file with no unfinished tasks", function()
        mock_filereadable_return = 1
        mock_readfile_calls = 0 -- reset counter
        mock_readfile_return = { "# Daily log", "- [x] Task done", "- [-] Another done" }
        _config.path_pattern = "%Y-%m-%d.md"
        _config.highlight_unfinished_tasks = true

        local date = { year = 2025, month = 1, day = 15 }
        local status = FileUtils.get_day_status(date)

        assert.assert_equal(status, "normal", "File with no unfinished tasks should return 'normal'")
        assert.assert_equal(mock_readfile_calls, 1, "readfile should be called once")
    end)

    assert.run_test("get_day_status - file with unfinished tasks", function()
        mock_filereadable_return = 1
        mock_readfile_calls = 0 -- reset counter
        mock_readfile_return = { "# Daily log", "- [ ] Unfinished task", "- [x] Done task" }
        _config.path_pattern = "%Y-%m-%d.md"
        _config.highlight_unfinished_tasks = true

        local date = { year = 2025, month = 1, day = 15 }
        local status = FileUtils.get_day_status(date)

        assert.assert_equal(status, "unfinished", "File with unfinished tasks should return 'unfinished'")
        assert.assert_equal(mock_readfile_calls, 1, "readfile should be called once")
    end)

    assert.run_test("get_day_status - highlight_unfinished_tasks disabled", function()
        _config.highlight_unfinished_tasks = false

        local date = { year = 2025, month = 1, day = 15 }
        local status = FileUtils.get_day_status(date)

        assert.assert_equal(status, "normal", "When highlight_unfinished_tasks is false, always return 'normal'")
    end)

    assert.run_test("get_day_status - empty path pattern", function()
        _config.path_pattern = ""
        _config.highlight_unfinished_tasks = true

        local date = { year = 2025, month = 1, day = 15 }
        local status = FileUtils.get_day_status(date)

        assert.assert_equal(status, "normal", "Empty path pattern should return 'normal'")
    end)

    -- Restore original state
    restore_state()

    print("  All FileUtils tests completed")
end

return M
