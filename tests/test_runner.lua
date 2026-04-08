------------------------------------------------------------------------
-- test_runner.lua - Standalone test runner for Search & Destroy v2
-- Run with: lua tests/test_runner.lua
------------------------------------------------------------------------

-- Track test results (global so test files can access it)
_tests = {
   total = 0,
   passed = 0,
   failed = 0,
   errors = {},
   current_file = "",
   current_test = "",
}

------------------------------------------------------------------------
-- Assertion functions
------------------------------------------------------------------------

function assert_equal(expected, actual, msg)
   _tests.total = _tests.total + 1
   if expected == actual then
      _tests.passed = _tests.passed + 1
      return true
   else
      _tests.failed = _tests.failed + 1
      local err = string.format(
         "[FAIL] %s:%s - %s\n       expected: %s\n       actual:   %s",
         _tests.current_file, _tests.current_test,
         msg or "assert_equal",
         tostring(expected), tostring(actual)
      )
      _tests.errors[#_tests.errors + 1] = err
      return false
   end
end

function assert_true(value, msg)
   _tests.total = _tests.total + 1
   if value then
      _tests.passed = _tests.passed + 1
      return true
   else
      _tests.failed = _tests.failed + 1
      local err = string.format(
         "[FAIL] %s:%s - %s\n       expected: true\n       actual:   %s",
         _tests.current_file, _tests.current_test,
         msg or "assert_true",
         tostring(value)
      )
      _tests.errors[#_tests.errors + 1] = err
      return false
   end
end

function assert_false(value, msg)
   _tests.total = _tests.total + 1
   if not value then
      _tests.passed = _tests.passed + 1
      return true
   else
      _tests.failed = _tests.failed + 1
      local err = string.format(
         "[FAIL] %s:%s - %s\n       expected: false\n       actual:   %s",
         _tests.current_file, _tests.current_test,
         msg or "assert_false",
         tostring(value)
      )
      _tests.errors[#_tests.errors + 1] = err
      return false
   end
end

function assert_nil(value, msg)
   _tests.total = _tests.total + 1
   if value == nil then
      _tests.passed = _tests.passed + 1
      return true
   else
      _tests.failed = _tests.failed + 1
      local err = string.format(
         "[FAIL] %s:%s - %s\n       expected: nil\n       actual:   %s",
         _tests.current_file, _tests.current_test,
         msg or "assert_nil",
         tostring(value)
      )
      _tests.errors[#_tests.errors + 1] = err
      return false
   end
end

function assert_not_nil(value, msg)
   _tests.total = _tests.total + 1
   if value ~= nil then
      _tests.passed = _tests.passed + 1
      return true
   else
      _tests.failed = _tests.failed + 1
      local err = string.format(
         "[FAIL] %s:%s - %s\n       expected: not nil\n       actual:   nil",
         _tests.current_file, _tests.current_test,
         msg or "assert_not_nil"
      )
      _tests.errors[#_tests.errors + 1] = err
      return false
   end
end

function assert_match(pattern, str, msg)
   _tests.total = _tests.total + 1
   if type(str) == "string" and str:match(pattern) then
      _tests.passed = _tests.passed + 1
      return true
   else
      _tests.failed = _tests.failed + 1
      local err = string.format(
         "[FAIL] %s:%s - %s\n       pattern:  %s\n       string:   %s",
         _tests.current_file, _tests.current_test,
         msg or "assert_match",
         tostring(pattern), tostring(str)
      )
      _tests.errors[#_tests.errors + 1] = err
      return false
   end
end

function assert_no_match(pattern, str, msg)
   _tests.total = _tests.total + 1
   if type(str) ~= "string" or not str:match(pattern) then
      _tests.passed = _tests.passed + 1
      return true
   else
      _tests.failed = _tests.failed + 1
      local err = string.format(
         "[FAIL] %s:%s - %s\n       pattern should NOT match: %s\n       string:   %s",
         _tests.current_file, _tests.current_test,
         msg or "assert_no_match",
         tostring(pattern), tostring(str)
      )
      _tests.errors[#_tests.errors + 1] = err
      return false
   end
end

function assert_table_equal(expected, actual, msg)
   _tests.total = _tests.total + 1
   local function tables_equal(t1, t2)
      if type(t1) ~= "table" or type(t2) ~= "table" then return t1 == t2 end
      for k, v in pairs(t1) do
         if not tables_equal(v, t2[k]) then return false end
      end
      for k, v in pairs(t2) do
         if t1[k] == nil then return false end
      end
      return true
   end
   if tables_equal(expected, actual) then
      _tests.passed = _tests.passed + 1
      return true
   else
      _tests.failed = _tests.failed + 1
      local err = string.format(
         "[FAIL] %s:%s - %s\n       tables not equal",
         _tests.current_file, _tests.current_test,
         msg or "assert_table_equal"
      )
      _tests.errors[#_tests.errors + 1] = err
      return false
   end
end

function assert_error(fn, msg)
   _tests.total = _tests.total + 1
   local ok, err = pcall(fn)
   if not ok then
      _tests.passed = _tests.passed + 1
      return true
   else
      _tests.failed = _tests.failed + 1
      local errmsg = string.format(
         "[FAIL] %s:%s - %s\n       expected error but function succeeded",
         _tests.current_file, _tests.current_test,
         msg or "assert_error"
      )
      _tests.errors[#_tests.errors + 1] = errmsg
      return false
   end
end

------------------------------------------------------------------------
-- Per-test setUp/tearDown support
------------------------------------------------------------------------

--- Run a single named test with setUp/tearDown support.
--- Test files should call this for each test instead of setting
--- _tests.current_test and running assertions inline.
---
--- Usage in test files:
---   function setUp()    mock.reset() end
---   function tearDown() DB.close()   end
---   run_test("MyModule.some_case", function()
---      assert_equal(1, 1, "basic check")
---   end)
function run_test(name, fn)
   _tests.current_test = name
   -- Call file-level setUp if defined
   if type(setUp) == "function" then
      local ok, err = pcall(setUp)
      if not ok then
         _tests.failed = _tests.failed + 1
         _tests.total = _tests.total + 1
         _tests.errors[#_tests.errors + 1] = string.format(
            "[ERROR] %s:%s - setUp failed: %s",
            _tests.current_file, name, tostring(err)
         )
         return
      end
   end
   -- Run the test
   local ok, err = pcall(fn)
   if not ok then
      _tests.failed = _tests.failed + 1
      _tests.total = _tests.total + 1
      _tests.errors[#_tests.errors + 1] = string.format(
         "[ERROR] %s:%s - %s",
         _tests.current_file, name, tostring(err)
      )
   end
   -- Call file-level tearDown if defined
   if type(tearDown) == "function" then
      local td_ok, td_err = pcall(tearDown)
      if not td_ok then
         _tests.errors[#_tests.errors + 1] = string.format(
            "[WARN] %s:%s - tearDown failed: %s",
            _tests.current_file, name, tostring(td_err)
         )
      end
   end
end

------------------------------------------------------------------------
-- Test discovery and execution
------------------------------------------------------------------------

--- Run a single test file
local function run_test_file(filepath)
   _tests.current_file = filepath
   -- Clear any setUp/tearDown from previous test file
   setUp = nil
   tearDown = nil
   print(string.format("  Running %s...", filepath))

   local ok, err = pcall(dofile, filepath)
   if not ok then
      _tests.failed = _tests.failed + 1
      _tests.total = _tests.total + 1
      _tests.errors[#_tests.errors + 1] = string.format(
         "[ERROR] %s - File error: %s", filepath, tostring(err)
      )
   end
   -- Clean up setUp/tearDown after file completes
   setUp = nil
   tearDown = nil
end

--- Discover test files in the tests/ directory
local function discover_tests(dir)
   local files = {}
   -- Use ls to find test files (cross-platform fallback)
   local handle = io.popen('ls "' .. dir .. '"/test_*.lua 2>/dev/null || dir /b "' .. dir .. '"\\test_*.lua 2>nul')
   if handle then
      for line in handle:lines() do
         -- Normalize path
         local filename = line:match("([^/\\]+)$") or line
         if filename:match("^test_") and filename:match("%.lua$")
            and filename ~= "test_runner.lua"    -- don't run ourselves
            and filename ~= "test_data.lua"      -- data file, not tests
         then
            files[#files + 1] = dir .. "/" .. filename
         end
      end
      handle:close()
   end
   table.sort(files)
   return files
end

------------------------------------------------------------------------
-- Main
------------------------------------------------------------------------

local function main()
   -- Determine script directory
   local script_path = arg and arg[0] or "tests/test_runner.lua"
   local test_dir = script_path:match("(.+)/[^/]+$") or script_path:match("(.+)\\[^\\]+$") or "tests"

   -- Set up package path to find our modules
   local plugin_dir = test_dir:match("(.+)/tests$") or test_dir:match("(.+)\\tests$") or "."
   package.path = test_dir .. "/?.lua;" .. plugin_dir .. "/?.lua;" .. package.path

   -- Load mock MUSHclient environment
   require("mock_mushclient")

   -- Pre-load the plugin code so all tests share it
   local load_plugin = require("load_plugin")
   local plugin_ok, plugin_err = pcall(load_plugin)
   if not plugin_ok then
      print("ERROR: Failed to load plugin: " .. tostring(plugin_err))
      return 1
   end

   print("\n=== Search & Destroy v2 - Test Suite ===\n")

   -- Discover and run test files
   local test_files = discover_tests(test_dir)

   if #test_files == 0 then
      print("  No test files found in " .. test_dir)
      print("  Looking for test_*.lua files...")
      return 1
   end

   for _, filepath in ipairs(test_files) do
      run_test_file(filepath)
   end

   -- Report results
   print(string.format("\n=== Results: %d/%d passed, %d failed ===",
      _tests.passed, _tests.total, _tests.failed))

   if #_tests.errors > 0 then
      print("\nFailures:")
      for _, err in ipairs(_tests.errors) do
         print("  " .. err)
      end
   end

   print("")
   return _tests.failed > 0 and 1 or 0
end

local exit_code = main()
os.exit(exit_code)
