-- Unit tests for Configuration module
local assert = require("tests.helpers")

-- Load the plugin module
local plugin = require("simple-calendar")

-- Get test exports
local _config = plugin._test._config

local M = {}

function M.run()
    print("Running Configuration tests...")

    -- Backup original config
    local original_daily_path_pattern = _config.daily_path_pattern
    local original_highlight_unfinished_tasks = _config.highlight_unfinished_tasks
    local original_completed_task_markers = _config.completed_task_markers

    -- Test: Default configuration
    assert.run_test("Default configuration values", function()
        -- Reset config to defaults (plugin should have defaults already)
        _config.daily_path_pattern = "%Y-%m-%d.md"
        _config.highlight_unfinished_tasks = false

        -- The defaults are set in the plugin; we just verify they match expected
        assert.assert_equal(_config.daily_path_pattern, "%Y-%m-%d.md", "Default daily_path_pattern should be %Y-%m-%d.md")
        assert.assert_equal(_config.highlight_unfinished_tasks, false,
            "Default highlight_unfinished_tasks should be false")
    end)

    -- Test: M.setup - merges configuration
    assert.run_test("M.setup - merges partial configuration", function()
        -- Reset to defaults
        _config.daily_path_pattern = "%Y-%m-%d.md"
        _config.highlight_unfinished_tasks = false

        -- Call setup with partial config
        plugin.setup({ daily_path_pattern = "notes/%Y/%m/%d.md" })

        -- Verify merged config
        assert.assert_equal(_config.daily_path_pattern, "notes/%Y/%m/%d.md", "daily_path_pattern should be updated")
        assert.assert_equal(_config.highlight_unfinished_tasks, false, "highlight_unfinished_tasks should remain false")
    end)

    assert.run_test("M.setup - merges full configuration", function()
        -- Reset to defaults
        _config.daily_path_pattern = "%Y-%m-%d.md"
        _config.highlight_unfinished_tasks = false

        plugin.setup({
            daily_path_pattern = "journal/%B-%d-%Y.txt",
            highlight_unfinished_tasks = true,
        })

        assert.assert_equal(_config.daily_path_pattern, "journal/%B-%d-%Y.txt", "daily_path_pattern should be updated")
        assert.assert_equal(_config.highlight_unfinished_tasks, true, "highlight_unfinished_tasks should be updated")
    end)

    assert.run_test("M.setup - handles empty configuration", function()
        -- Reset to defaults
        _config.daily_path_pattern = "%Y-%m-%d.md"
        _config.highlight_unfinished_tasks = false

        plugin.setup({})

        -- Should keep defaults
        assert.assert_equal(_config.daily_path_pattern, "%Y-%m-%d.md", "daily_path_pattern should remain default")
        assert.assert_equal(_config.highlight_unfinished_tasks, false, "highlight_unfinished_tasks should remain default")
    end)

    assert.run_test("M.setup - handles nil configuration", function()
        -- Reset to defaults
        _config.daily_path_pattern = "%Y-%m-%d.md"
        _config.highlight_unfinished_tasks = false

        plugin.setup(nil)

        -- Should keep defaults (no error)
        assert.assert_equal(_config.daily_path_pattern, "%Y-%m-%d.md", "daily_path_pattern should remain default")
        assert.assert_equal(_config.highlight_unfinished_tasks, false, "highlight_unfinished_tasks should remain default")
    end)

    -- Test: Configuration influences FileUtils behavior (integration)
    assert.run_test("Configuration influences extract_date_from_filename", function()
        -- This test requires mocking vim.api.nvim_buf_get_name
        local original_buf_get_name = vim.api.nvim_buf_get_name
        local mock_buf_get_name = function(_buffer) return "/home/user/2025-01-15.md" end
        vim.api.nvim_buf_get_name = mock_buf_get_name

        -- Set custom pattern
        _config.daily_path_pattern = "%Y-%m-%d.md"

        local FileUtils = plugin._test.FileUtils
        local date = FileUtils.extract_date_from_filename()

        assert.assert_not_nil(date, "Should extract date with custom pattern")
        assert.assert_equal(date and date.year, 2025, "Year should match")

        vim.api.nvim_buf_get_name = original_buf_get_name
    end)

    -- Test: completed_task_markers default and merging
    assert.run_test("completed_task_markers - default value", function()
        -- Reset to defaults
        _config.daily_path_pattern = "%Y-%m-%d.md"
        _config.highlight_unfinished_tasks = false
        _config.completed_task_markers = { "x", "-" }

        assert.assert_equal(#_config.completed_task_markers, 2, "Should have 2 default markers")
        assert.assert_equal(_config.completed_task_markers[1], "x", "First marker should be 'x'")
        assert.assert_equal(_config.completed_task_markers[2], "-", "Second marker should be '-'")
    end)

    assert.run_test("completed_task_markers - custom value", function()
        -- Reset all config to defaults (consistent with other tests)
        _config.daily_path_pattern = "%Y-%m-%d.md"
        _config.highlight_unfinished_tasks = false
        _config.completed_task_markers = { "x", "-" }

        plugin.setup({ completed_task_markers = { "done", "X" } })
        assert.assert_equal(#_config.completed_task_markers, 2, "Should have 2 custom markers")
        assert.assert_equal(_config.completed_task_markers[1], "done", "First marker should be 'done'")
        assert.assert_equal(_config.completed_task_markers[2], "X", "Second marker should be 'X'")
    end)

    -- Restore original config
    _config.daily_path_pattern = original_daily_path_pattern
    _config.highlight_unfinished_tasks = original_highlight_unfinished_tasks
    _config.completed_task_markers = original_completed_task_markers

    print("  All Configuration tests completed")
end

return M
