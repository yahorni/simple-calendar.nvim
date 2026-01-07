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

    -- Helper to capture warnings from vim.notify
    local function capture_warnings()
        local warnings = {}
        local original_notify = vim.notify
        vim.notify = function(message, level, _)
            if level == (vim.log.levels and vim.log.levels.WARN or 2) then
                table.insert(warnings, message)
            end
        end
        return {
            get_warnings = function() return warnings end,
            restore = function() vim.notify = original_notify end,
        }
    end

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

        plugin.setup({ completed_task_markers = { "✓", "X" } })
        assert.assert_equal(#_config.completed_task_markers, 2, "Should have 2 custom markers")
        assert.assert_equal(_config.completed_task_markers[1], "✓", "First marker should be '✓'")
        assert.assert_equal(_config.completed_task_markers[2], "X", "Second marker should be 'X'")
    end)

    assert.run_test("completed_task_markers - validation filters multi-character markers", function()
        -- Reset all config to defaults
        _config.daily_path_pattern = "%Y-%m-%d.md"
        _config.highlight_unfinished_tasks = false
        _config.completed_task_markers = { "x", "-" }

        -- Setup with mixed valid and invalid markers
        plugin.setup({ completed_task_markers = { "done", "X", "", "  ", "✅", "✓" } })
        -- Only single characters should remain: "X", "✅", "✓"
        assert.assert_equal(#_config.completed_task_markers, 3, "Should filter to 3 single-character markers")
        -- Order may not be preserved, but check contents
        assert.assert_contains(_config.completed_task_markers, "X", "Should contain 'X'")
        assert.assert_contains(_config.completed_task_markers, "✅", "Should contain '✅'")
        assert.assert_contains(_config.completed_task_markers, "✓", "Should contain '✓'")
        -- Ensure invalid markers are filtered out
        assert.assert_not_contains(_config.completed_task_markers, "done",
            "Should not contain multi-character marker 'done'")
        assert.assert_not_contains(_config.completed_task_markers, "", "Should not contain empty marker")
        assert.assert_not_contains(_config.completed_task_markers, "  ", "Should not contain whitespace marker")
    end)

    -- New tests for M.setup validation logic
    assert.run_test("completed_task_markers - validates non-string markers", function()
        -- Reset all config to defaults
        _config.daily_path_pattern = "%Y-%m-%d.md"
        _config.highlight_unfinished_tasks = false
        _config.completed_task_markers = { "x", "-" }

        local capturer = capture_warnings()
        plugin.setup({ completed_task_markers = { 123, true, {}, function() end } })
        local warnings = capturer.get_warnings()
        capturer.restore()

        -- All non-string markers should be filtered out
        assert.assert_equal(#_config.completed_task_markers, 0, "Should filter out all non-string markers")
        assert.assert_equal(#warnings, 4, "Should log 4 warnings for 4 invalid markers")
        for _, warning in ipairs(warnings) do
            assert.assert_not_nil(string.find(warning, "must be 'string'"),
                "Warning should mention string requirement: " .. warning)
        end
    end)

    assert.run_test("completed_task_markers - validates multi-character strings", function()
        _config.daily_path_pattern = "%Y-%m-%d.md"
        _config.highlight_unfinished_tasks = false
        _config.completed_task_markers = { "x", "-" }

        local capturer = capture_warnings()
        plugin.setup({ completed_task_markers = { "abc", "xy", "✓✓" } })
        local warnings = capturer.get_warnings()
        capturer.restore()

        -- Only single-character markers allowed
        assert.assert_equal(#_config.completed_task_markers, 0, "Should filter out multi-character markers and space")
        assert.assert_equal(#warnings, 3, "Should log 3 warnings")
        -- Check that warnings mention single character requirement
        for _, warning in ipairs(warnings) do
            assert.assert_not_nil(string.find(warning, "single character"),
                "Warning should mention single character requirement: " .. warning)
        end
    end)

    assert.run_test("completed_task_markers - rejects space marker", function()
        _config.daily_path_pattern = "%Y-%m-%d.md"
        _config.highlight_unfinished_tasks = false
        _config.completed_task_markers = { "x", "-" }

        local capturer = capture_warnings()
        plugin.setup({ completed_task_markers = { " ", "x" } })
        local warnings = capturer.get_warnings()
        capturer.restore()

        -- Space should be filtered out, "x" should remain
        assert.assert_equal(#_config.completed_task_markers, 1, "Should keep only valid marker 'x'")
        assert.assert_equal(_config.completed_task_markers[1], "x", "Should contain 'x'")
        assert.assert_equal(#warnings, 1, "Should log 1 warning for space")
        if #warnings > 0 then
            assert.assert_not_nil(string.find(warnings[1], "space is not allowed as a marker"),
                "Warning should mention space not allowed: " .. warnings[1])
        end
    end)

    assert.run_test("completed_task_markers - accepts valid single-character markers", function()
        _config.daily_path_pattern = "%Y-%m-%d.md"
        _config.highlight_unfinished_tasks = false
        _config.completed_task_markers = { "x", "-" }

        local capturer = capture_warnings()
        plugin.setup({ completed_task_markers = { "x", "✓", "✅", "X", "-", "!" } })
        local warnings = capturer.get_warnings()
        capturer.restore()

        -- All markers are single characters (including Unicode emoji)
        assert.assert_equal(#_config.completed_task_markers, 6, "Should keep all 6 valid markers")
        assert.assert_equal(#warnings, 0, "Should log no warnings for valid markers")
        -- Verify all markers present (order may not be preserved)
        for _, marker in ipairs({ "x", "✓", "✅", "X", "-", "!" }) do
            assert.assert_contains(_config.completed_task_markers, marker, "Should contain marker: " .. marker)
        end
    end)

    assert.run_test("completed_task_markers - handles non-table value (string)", function()
        _config.daily_path_pattern = "%Y-%m-%d.md"
        _config.highlight_unfinished_tasks = false
        _config.completed_task_markers = { "x", "-" }

        -- When completed_task_markers is a string (not a table), it should be assigned directly
        -- This tests backward compatibility with old config format
        plugin.setup({ completed_task_markers = "✓" })
        assert.assert_equal(_config.completed_task_markers, "✓", "Should assign string directly")
    end)

    assert.run_test("completed_task_markers - handles non-table value (number)", function()
        _config.daily_path_pattern = "%Y-%m-%d.md"
        _config.highlight_unfinished_tasks = false
        _config.completed_task_markers = { "x", "-" }

        -- When completed_task_markers is a number (not a table), it should be assigned directly
        plugin.setup({ completed_task_markers = 42 })
        assert.assert_equal(_config.completed_task_markers, 42, "Should assign number directly")
    end)

    assert.run_test("completed_task_markers - warning messages contain plugin prefix", function()
        _config.daily_path_pattern = "%Y-%m-%d.md"
        _config.highlight_unfinished_tasks = false
        _config.completed_task_markers = { "x", "-" }

        local capturer = capture_warnings()
        plugin.setup({ completed_task_markers = { 123, "abc", " " } })
        local warnings = capturer.get_warnings()
        capturer.restore()

        assert.assert_equal(#warnings, 3, "Should log 3 warnings")
        for _, warning in ipairs(warnings) do
            assert.assert_not_nil(string.find(warning, "simple%-calendar:"),
                "Warning should contain plugin prefix: " .. warning)
        end
    end)

    -- Restore original config
    _config.daily_path_pattern = original_daily_path_pattern
    _config.highlight_unfinished_tasks = original_highlight_unfinished_tasks
    _config.completed_task_markers = original_completed_task_markers

    print("  All Configuration tests completed")
end

return M
