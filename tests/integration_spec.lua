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
