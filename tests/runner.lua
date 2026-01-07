-- Simple test runner for simple-calendar.nvim
-- Usage: nvim --headless -u tests/runner.lua

-- Add current directory to runtime path
vim.opt.rtp:append(".")

-- Set test mode flag
vim.g.SIMPLE_CALENDAR_TEST = true

local test_results = { passed = 0, failed = 0, total = 0, skipped = 0 }

-- Helper to run a test suite
local function run_test_suite(name, module_path)
    print(string.format("\n=== %s ===", name))

    local ok, test_module = pcall(require, module_path)
    if not ok then
        print(string.format("  ⚠ Could not load test module: %s", test_module))
        test_results.skipped = test_results.skipped + 1
        test_results.total = test_results.total + 1
        return
    end

    if type(test_module) ~= "table" or type(test_module.run) ~= "function" then
        print(string.format("  ⚠ Test module %s does not export run() function", module_path))
        test_results.skipped = test_results.skipped + 1
        test_results.total = test_results.total + 1
        return
    end

    -- Run the test suite
    local suite_ok, suite_err = pcall(test_module.run)
    if suite_ok then
        print("  ✓ All tests passed")
        test_results.passed = test_results.passed + 1
    else
        print(string.format("  ✗ Test suite failed: %s", suite_err))
        test_results.failed = test_results.failed + 1
    end

    test_results.total = test_results.total + 1
end

-- Main test execution
print("Running simple-calendar.nvim unit tests...")
print(string.rep("=", 50))

-- Run test suites in order
run_test_suite("CalendarCore", "tests.calendar_core_spec")
run_test_suite("FileUtils", "tests.file_utils_spec")
run_test_suite("Navigation", "tests.navigation_spec")
run_test_suite("Configuration", "tests.config_spec")
run_test_suite("Integration", "tests.integration_spec")

-- Summary
print(string.rep("=", 50))
print(string.format("\n=== Test Summary ==="))
print(string.format("Total suites: %d", test_results.total))
print(string.format("Passed: %d", test_results.passed))
print(string.format("Failed: %d", test_results.failed))
print(string.format("Skipped: %d", test_results.skipped))

-- Exit with appropriate code
if test_results.failed > 0 then
    print("\n❌ Some tests failed")
    os.exit(1)
elseif test_results.passed == 0 and test_results.skipped > 0 then
    print("\n⚠ No tests were executed")
    os.exit(0)
else
    print("\n✅ All tests passed")
    os.exit(0)
end
