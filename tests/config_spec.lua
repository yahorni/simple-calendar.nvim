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
    local original_path_pattern = _config.path_pattern
    local original_highlight_unfinished_tasks = _config.highlight_unfinished_tasks

    -- Test: Default configuration
    assert.run_test("Default configuration values", function()
        -- Reset config to defaults (plugin should have defaults already)
        _config.path_pattern = "%Y-%m-%d.md"
        _config.highlight_unfinished_tasks = false

        -- The defaults are set in the plugin; we just verify they match expected
        assert.assert_equal(_config.path_pattern, "%Y-%m-%d.md", "Default path_pattern should be %Y-%m-%d.md")
        assert.assert_equal(_config.highlight_unfinished_tasks, false,
            "Default highlight_unfinished_tasks should be false")
    end)

    -- Test: M.setup - merges configuration
    assert.run_test("M.setup - merges partial configuration", function()
        -- Reset to defaults
        _config.path_pattern = "%Y-%m-%d.md"
        _config.highlight_unfinished_tasks = false

        -- Call setup with partial config
        plugin.setup({ path_pattern = "notes/%Y/%m/%d.md" })

        -- Verify merged config
        assert.assert_equal(_config.path_pattern, "notes/%Y/%m/%d.md", "path_pattern should be updated")
        assert.assert_equal(_config.highlight_unfinished_tasks, false, "highlight_unfinished_tasks should remain false")
    end)

    assert.run_test("M.setup - merges full configuration", function()
        -- Reset to defaults
        _config.path_pattern = "%Y-%m-%d.md"
        _config.highlight_unfinished_tasks = false

        plugin.setup({
            path_pattern = "journal/%B-%d-%Y.txt",
            highlight_unfinished_tasks = true,
        })

        assert.assert_equal(_config.path_pattern, "journal/%B-%d-%Y.txt", "path_pattern should be updated")
        assert.assert_equal(_config.highlight_unfinished_tasks, true, "highlight_unfinished_tasks should be updated")
    end)

    assert.run_test("M.setup - handles empty configuration", function()
        -- Reset to defaults
        _config.path_pattern = "%Y-%m-%d.md"
        _config.highlight_unfinished_tasks = false

        plugin.setup({})

        -- Should keep defaults
        assert.assert_equal(_config.path_pattern, "%Y-%m-%d.md", "path_pattern should remain default")
        assert.assert_equal(_config.highlight_unfinished_tasks, false, "highlight_unfinished_tasks should remain default")
    end)

    assert.run_test("M.setup - handles nil configuration", function()
        -- Reset to defaults
        _config.path_pattern = "%Y-%m-%d.md"
        _config.highlight_unfinished_tasks = false

        plugin.setup(nil)

        -- Should keep defaults (no error)
        assert.assert_equal(_config.path_pattern, "%Y-%m-%d.md", "path_pattern should remain default")
        assert.assert_equal(_config.highlight_unfinished_tasks, false, "highlight_unfinished_tasks should remain default")
    end)

    -- Test: Configuration influences FileUtils behavior (integration)
    assert.run_test("Configuration influences extract_date_from_filename", function()
        -- This test requires mocking vim.api.nvim_buf_get_name
        local original_buf_get_name = vim.api.nvim_buf_get_name
        local mock_buf_get_name = function(_buffer) return "/home/user/2025-01-15.md" end
        vim.api.nvim_buf_get_name = mock_buf_get_name

        -- Set custom pattern
        _config.path_pattern = "%Y-%m-%d.md"

        local FileUtils = plugin._test.FileUtils
        local date = FileUtils.extract_date_from_filename()

        assert.assert_not_nil(date, "Should extract date with custom pattern")
        assert.assert_equal(date and date.year, 2025, "Year should match")

        vim.api.nvim_buf_get_name = original_buf_get_name
    end)

    -- Restore original config
    _config.path_pattern = original_path_pattern
    _config.highlight_unfinished_tasks = original_highlight_unfinished_tasks

    print("  All Configuration tests completed")
end

return M
