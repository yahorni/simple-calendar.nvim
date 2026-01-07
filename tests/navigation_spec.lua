-- Unit tests for Navigation module
local assert = require("tests.helpers")

-- Load the plugin module
local plugin = require("simple-calendar")

-- Get test exports
local Navigation = plugin._test.Navigation

local M = {}

function M.run()
    print("Running Navigation tests...")

    -- Backup original vim.api functions
    local original_buf_set_option = vim.api.nvim_buf_set_option
    local original_buf_set_lines = vim.api.nvim_buf_set_lines
    local original_buf_add_highlight = vim.api.nvim_buf_add_highlight
    local original_buf_clear_namespace = vim.api.nvim_buf_clear_namespace
    local original_win_get_cursor = vim.api.nvim_win_get_cursor
    local original_win_set_cursor = vim.api.nvim_win_set_cursor

    -- Mock vim.api functions
    local mock_buf_set_option_calls = 0
    vim.api.nvim_buf_set_option = function(_buf, _option, _value)
        mock_buf_set_option_calls = mock_buf_set_option_calls + 1
    end

    local mock_buf_set_lines_calls = 0
    vim.api.nvim_buf_set_lines = function(_buf, _start, _end_idx, _strict, _lines)
        mock_buf_set_lines_calls = mock_buf_set_lines_calls + 1
    end

    vim.api.nvim_buf_add_highlight = function(_buf, _ns_id, _hl_group, _line, _col_start, _col_end) end
    vim.api.nvim_buf_clear_namespace = function(_buf, _ns_id, _line_start, _line_end) end

    local mock_win_get_cursor_calls = 0
    local mock_cursor_pos = { 3, 1 } -- default position
    vim.api.nvim_win_get_cursor = function(_win)
        mock_win_get_cursor_calls = mock_win_get_cursor_calls + 1
        return mock_cursor_pos
    end

    vim.api.nvim_win_set_cursor = function(_win, _pos) end

    -- Helper to create a minimal mock state
    local function create_mock_state()
        return {
            buf = 1,
            win = 2,
            grid = { { text = " 1", day = 1 }, { text = " 2", day = 2 } },
            calendar_lines = { "<   January 2025   >", "Mo Tu We Th Fr Sa Su", " 1  2  3  4  5  6  7" },
            selected_day = 1,
            now = { year = 2025, month = 1, day = 1 },
        }
    end

    -- Test: Navigation.new_state
    assert.run_test("Navigation.new_state - creates state table", function()
        local buf, win, grid, calendar_lines, selected_day, now = 1, 2, {}, {}, 15, { year = 2025, month = 1, day = 15 }
        local state = Navigation.new_state(buf, win, grid, calendar_lines, selected_day, now)

        assert.assert_equal(state.buf, buf, "buf should match")
        assert.assert_equal(state.win, win, "win should match")
        assert.assert_equal(state.grid, grid, "grid should match")
        assert.assert_equal(state.calendar_lines, calendar_lines, "calendar_lines should match")
        assert.assert_equal(state.selected_day, selected_day, "selected_day should match")
        assert.assert_equal(state.now, now, "now should match")
    end)

    -- Test: Navigation.update_display - basic functionality
    assert.run_test("Navigation.update_display - updates state and calls vim.api functions", function()
        local state = create_mock_state()
        local new_now = { year = 2025, month = 2, day = 1 }
        local new_selected_day = 1

        -- Reset call counters
        mock_buf_set_option_calls = 0
        mock_buf_set_lines_calls = 0

        Navigation.update_display(state, new_now, new_selected_day)

        assert.assert_equal(state.now, new_now, "now should be updated")
        assert.assert_equal(state.selected_day, new_selected_day, "selected_day should be updated")
        assert.assert_equal(mock_buf_set_option_calls, 4,
            "should call nvim_buf_set_option four times (modifiable/readonly toggle)")
        assert.assert_equal(mock_buf_set_lines_calls, 1, "should call nvim_buf_set_lines once")
    end)

    -- Test: Navigation.switch_month - month transitions
    assert.run_test("Navigation.switch_month - next month", function()
        local state = create_mock_state()
        local original_now = state.now

        Navigation.switch_month(state, "next")

        -- Verify state was updated (month incremented)
        assert.assert_not_equal(state.now, original_now, "now should change")
        assert.assert_equal(state.now and state.now.month, 2, "month should be February")
        assert.assert_equal(state.now and state.now.year, 2025, "year should stay same")
    end)

    assert.run_test("Navigation.switch_month - previous month", function()
        local state = create_mock_state()
        state.now = { year = 2025, month = 3, day = 15 }
        state.selected_day = 15

        Navigation.switch_month(state, "previous")

        assert.assert_equal(state.now and state.now.month, 2, "month should be February")
        assert.assert_equal(state.now and state.now.year, 2025, "year should stay same")
    end)

    -- Test: Navigation.handle - boundary navigation (hits month switch)
    -- This is complex due to mocking; we'll focus on logic that doesn't hit boundary
    assert.run_test("Navigation.handle - left navigation within month", function()
        local state = create_mock_state()
        state.selected_day = 15

        -- Mock navigate_date to return new day and no boundary hit
        -- We'll need to mock the internal navigate_date function; instead we can test via actual
        -- But we can mock the vim.api functions used by UI.update_highlight
        -- Let's just test that the function doesn't error
        local ok, err = pcall(function() Navigation.handle(state, "left") end)
        assert.assert_equal(ok, true, "Navigation.handle should not error: " .. tostring(err))
    end)

    -- Test: Navigation.setup_keybindings - creates keymaps
    assert.run_test("Navigation.setup_keybindings - sets up keybindings", function()
        local state = create_mock_state()
        local original_buf_set_keymap = vim.api.nvim_buf_set_keymap
        local keymap_calls = 0
        vim.api.nvim_buf_set_keymap = function(buf, mode, _lhs, _rhs, opts)
            keymap_calls = keymap_calls + 1
            assert.assert_equal(buf, state.buf, "keymap should be set on state.buf")
            assert.assert_equal(mode, "n", "keymap mode should be normal")
            assert.assert_equal(opts.noremap, true, "keymap should be noremap")
            assert.assert_equal(opts.silent, true, "keymap should be silent")
        end

        Navigation.setup_keybindings(state)

        -- Should set up multiple keybindings (h, l, k, j, arrows, etc.)
        assert.assert_equal(keymap_calls > 10, true, "should set up many keybindings")

        vim.api.nvim_buf_set_keymap = original_buf_set_keymap
    end)

    -- Restore original functions
    vim.api.nvim_buf_set_option = original_buf_set_option
    vim.api.nvim_buf_set_lines = original_buf_set_lines
    vim.api.nvim_buf_add_highlight = original_buf_add_highlight
    vim.api.nvim_buf_clear_namespace = original_buf_clear_namespace
    vim.api.nvim_win_get_cursor = original_win_get_cursor
    vim.api.nvim_win_set_cursor = original_win_set_cursor

    print("  All Navigation tests completed")
end

return M
