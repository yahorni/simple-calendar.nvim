-- Simple assertion utilities for unit testing
local M = {}

function M.assert_equal(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s",
            message or "Assertion failed", tostring(expected), tostring(actual)))
    end
end

function M.assert_not_equal(actual, expected, message)
    if actual == expected then
        error(string.format("%s: values should not be equal", message or "Assertion failed"))
    end
end

function M.assert_nil(value, message)
    if value ~= nil then
        error(string.format("%s: expected nil, got %s", message or "Assertion failed", tostring(value)))
    end
end

function M.assert_not_nil(value, message)
    if value == nil then
        error(string.format("%s: expected non-nil value", message or "Assertion failed"))
    end
end

function M.assert_table_equal(actual, expected, message)
    if type(actual) ~= "table" or type(expected) ~= "table" then
        error(string.format("%s: both arguments must be tables", message or "Assertion failed"))
    end

    for key, expected_value in pairs(expected) do
        if actual[key] ~= expected_value then
            error(string.format("%s: key '%s' mismatch: expected %s, got %s",
                message or "Assertion failed", tostring(key),
                tostring(expected_value), tostring(actual[key])))
        end
    end

    for key, actual_value in pairs(actual) do
        if expected[key] == nil then
            error(string.format("%s: unexpected key '%s' with value %s",
                message or "Assertion failed", tostring(key), tostring(actual_value)))
        end
    end
end

function M.assert_contains(array, value, message)
    for _, v in ipairs(array) do
        if v == value then
            return
        end
    end
    error(string.format("%s: array does not contain %s", message or "Assertion failed", tostring(value)))
end

function M.assert_not_contains(array, value, message)
    for _, v in ipairs(array) do
        if v == value then
            error(string.format("%s: array should not contain %s", message or "Assertion failed", tostring(value)))
        end
    end
end

function M.assert_type(value, expected_type, message)
    local actual_type = type(value)
    if actual_type ~= expected_type then
        error(string.format("%s: expected type %s, got %s",
            message or "Assertion failed", expected_type, actual_type))
    end
end

function M.assert_approx_equal(actual, expected, epsilon, message)
    epsilon = epsilon or 0.0001
    if math.abs(actual - expected) > epsilon then
        error(string.format("%s: expected %s ± %s, got %s",
            message or "Assertion failed", tostring(expected),
            tostring(epsilon), tostring(actual)))
    end
end

-- Helper to create a mock function that records calls and returns configurable value
function M.create_mock_fn(return_value)
    local calls = {}
    local mock_fn = {}
    local mt = {
        __call = function(_, ...)
            table.insert(calls, { ... })
            return return_value
        end,
    }
    setmetatable(mock_fn, mt)
    mock_fn.get_calls = function() return calls end
    mock_fn.was_called = function() return #calls > 0 end
    mock_fn.get_call_count = function() return #calls end
    mock_fn.get_last_call = function() return calls[#calls] end
    mock_fn.set_return_value = function(value) return_value = value end
    return mock_fn
end

-- Helper to run a test block and catch errors
function M.run_test(name, test_fn)
    local ok, err = pcall(test_fn)
    if ok then
        print(string.format("  ✓ %s", name))
        return true
    else
        print(string.format("  ✗ %s: %s", name, err))
        error(err, 0)
    end
end

return M
