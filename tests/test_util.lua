------------------------------------------------------------------------
-- test_util.lua - Tests for the Util module
------------------------------------------------------------------------

if not CONST then
   local load_plugin = require("load_plugin")
   load_plugin()
end

function setUp()
   mock.reset()
end

run_test("Util.fixsql", function()
   assert_equal("'hello'", Util.fixsql("hello"), "fixsql wraps string in quotes")
   assert_equal("NULL", Util.fixsql(nil), "fixsql returns NULL for nil")
   assert_equal("'it''s'", Util.fixsql("it's"), "fixsql escapes single quotes")
   assert_equal("'don''t stop'", Util.fixsql("don't stop"), "fixsql escapes multiple quotes")
   assert_equal("''", Util.fixsql(""), "fixsql handles empty string")
   assert_equal("'123'", Util.fixsql(123), "fixsql converts number to string")
end)

run_test("Util.trim", function()
   assert_equal("hello", Util.trim("hello"), "trim no-op on clean string")
   assert_equal("hello", Util.trim("  hello  "), "trim removes leading/trailing spaces")
   assert_equal("hello", Util.trim("\thello\t"), "trim removes tabs")
   assert_equal("hello world", Util.trim("  hello world  "), "trim preserves internal spaces")
   assert_equal("", Util.trim(""), "trim handles empty string")
   assert_equal("", Util.trim("   "), "trim handles whitespace-only string")
   assert_equal("", Util.trim(nil), "trim handles nil")
end)

run_test("Util.split", function()
   local parts = Util.split("hello world foo")
   assert_equal(3, #parts, "split by whitespace: count")
   assert_equal("hello", parts[1], "split by whitespace: first")
   assert_equal("world", parts[2], "split by whitespace: second")
   assert_equal("foo", parts[3], "split by whitespace: third")

   parts = Util.split("one,two,three", "[^,]+")
   assert_equal(3, #parts, "split by comma: count")
   assert_equal("one", parts[1], "split by comma: first")
   assert_equal("three", parts[3], "split by comma: third")

   parts = Util.split("")
   assert_equal(0, #parts, "split empty string")

   parts = Util.split("single")
   assert_equal(1, #parts, "split single word")
   assert_equal("single", parts[1], "split single word value")
end)

run_test("Util.strip_colours", function()
   assert_equal("hello", Util.strip_colours("@Whello"), "strip simple color code")
   assert_equal("hello world", Util.strip_colours("@Whello @Gworld"), "strip multiple colors")
   assert_equal("@", Util.strip_colours("@@"), "strip double-@ to single @")
   assert_equal("hello", Util.strip_colours("@x123hello"), "strip xterm color")
   assert_equal("hello", Util.strip_colours("hello"), "strip no colors is no-op")
   assert_equal("", Util.strip_colours(""), "strip empty string")
   assert_equal("", Util.strip_colours(nil), "strip nil")
end)

run_test("Util.ellipsify", function()
   assert_equal("hello", Util.ellipsify("hello", 10), "ellipsify short string unchanged")
   assert_equal("hello", Util.ellipsify("hello", 5), "ellipsify exact length unchanged")
   assert_equal("he...", Util.ellipsify("hello world", 5), "ellipsify truncates with ...")
   assert_equal("hello w...", Util.ellipsify("hello world", 10), "ellipsify at 10 chars")
   assert_equal("", Util.ellipsify("", 10), "ellipsify empty string")
   assert_equal("", Util.ellipsify(nil, 10), "ellipsify nil")
   assert_equal("hello world this is a...", Util.ellipsify("hello world this is a long string", 24), "ellipsify longer string")
end)

run_test("Util.round", function()
   assert_equal(0, Util.round(0), "round 0")
   assert_equal(2, Util.round(1.5), "round 1.5 to even")
   assert_equal(2, Util.round(2.5), "round 2.5 to even")
   assert_equal(4, Util.round(3.5), "round 3.5 to even")
   assert_equal(1, Util.round(0.7), "round 0.7 up")
   assert_equal(0, Util.round(0.3), "round 0.3 down")
end)
