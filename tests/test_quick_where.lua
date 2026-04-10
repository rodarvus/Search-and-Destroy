------------------------------------------------------------------------
-- test_quick_where.lua - Tests for QuickWhere module
------------------------------------------------------------------------

if not CONST then
   local load_plugin = require("load_plugin")
   load_plugin()
end

--- Create a test fixture mapper DB with known rooms
local mapper_db_path = "/tmp/test_data/Aardwolf.db"

local function create_mapper_fixture()
   os.execute("mkdir -p /tmp/test_data")
   os.remove(mapper_db_path)
   local db = require("lsqlite3").open(mapper_db_path)
   db:exec([[
      CREATE TABLE IF NOT EXISTS rooms (
         uid TEXT NOT NULL PRIMARY KEY,
         name TEXT,
         area TEXT
      );
      INSERT INTO rooms VALUES ('1254', 'A Dusty Room', 'diatz');
      INSERT INTO rooms VALUES ('1260', 'A Dusty Room', 'diatz');
      INSERT INTO rooms VALUES ('5000', 'The Town Square', 'aylor');
   ]])
   db:close()
end

function setUp()
   mock.reset()
   mock.reset_db()
   DB.init()
   HuntTrick._index = 1
   HuntTrick._keyword = ""
   HuntTrick._active = false
   HuntTrick._first_target = true
   HuntTrick._auto_go = false
   QuickWhere._index = 1
   QuickWhere._keyword = ""
   QuickWhere._mob_name = ""
   QuickWhere._exact = false
   QuickWhere._active = false
   QuickWhere._auto_go = false
   AutoHunt._keyword = ""
   AutoHunt._direction = ""
   AutoHunt._active = false
   Nav._goto_list = {}
   Nav._goto_index = 0
   Nav._dest_area = nil
   Nav._dest_room = nil
   Nav._on_arrive = nil
   State._target = nil
   State._activity = "none"
   State._room = {rmid = 1254, arid = "diatz", name = "A Room", exits = {n = 1255}, maze = false}
   create_mapper_fixture()
end

function tearDown()
   mock.reset_db()
   os.remove(mapper_db_path)
end

------------------------------------------------------------------------
-- QuickWhere.start
------------------------------------------------------------------------

--- Test: start enables grp_quick_where and sends where command
-- Input: index=1, keyword="citizen"
-- Expected: grp_quick_where enabled, Send("where citizen"), _active=true
-- Covers: QuickWhere.start()
run_test("QuickWhere.start_basic", function()
   QuickWhere.start(1, "citizen")
   assert_true(QuickWhere._active, "active after start")
   assert_equal("citizen", QuickWhere._keyword, "keyword stored")
   assert_false(QuickWhere._exact, "not exact mode")
   -- Check trigger group enabled
   local grp_enabled = false
   for _, call in ipairs(mock.calls["EnableTriggerGroup"] or {}) do
      if call[1] == "grp_quick_where" and call[2] == true then grp_enabled = true end
   end
   assert_true(grp_enabled, "grp_quick_where enabled")
   local found = false
   for _, call in ipairs(mock.calls["Send"] or {}) do
      if call[1] == "where citizen" then found = true end
   end
   assert_true(found, "sent 'where citizen'")
end)

--- Test: start with index > 1 sends "where N.keyword"
-- Input: index=3, keyword="citizen"
-- Expected: Send("where 3.citizen")
-- Covers: QuickWhere.start() indexed
run_test("QuickWhere.start_with_index", function()
   QuickWhere.start(3, "citizen")
   local found = false
   for _, call in ipairs(mock.calls["Send"] or {}) do
      if call[1] == "where 3.citizen" then found = true end
   end
   assert_true(found, "sent 'where 3.citizen'")
end)

--- Test: start with index=1 does NOT send "1.keyword"
-- Covers: QuickWhere.start() no "1." prefix
run_test("QuickWhere.start_no_1_prefix", function()
   QuickWhere.start(1, "citizen")
   for _, call in ipairs(mock.calls["Send"] or {}) do
      assert_true(call[1] ~= "where 1.citizen", "must NOT send 'where 1.citizen'")
   end
end)

--- Test: start resets other tools (re-entrant safety)
-- Covers: QuickWhere.start() re-entrant safety
run_test("QuickWhere.start_resets_others", function()
   HuntTrick._active = true
   AutoHunt._active = true
   QuickWhere.start(1, "citizen")
   assert_false(HuntTrick._active, "HT reset")
   assert_false(AutoHunt._active, "AH reset")
end)

------------------------------------------------------------------------
-- QuickWhere.start_exact
------------------------------------------------------------------------

--- Test: start_exact sets exact mode with mob name
-- Input: index=4, keyword="citizen", mob_name="a citizen"
-- Expected: _exact=true, _mob_name="a citizen"
-- Covers: QuickWhere.start_exact()
run_test("QuickWhere.start_exact_basic", function()
   QuickWhere.start_exact(4, "citizen", "a citizen")
   assert_true(QuickWhere._active, "active")
   assert_true(QuickWhere._exact, "exact mode")
   assert_equal("a citizen", QuickWhere._mob_name, "mob name stored")
   assert_equal(4, QuickWhere._index, "index stored")
   local found = false
   for _, call in ipairs(mock.calls["Send"] or {}) do
      if call[1] == "where 4.citizen" then found = true end
   end
   assert_true(found, "sent 'where 4.citizen'")
end)

--- Test: start_exact with auto_go flag
-- Covers: QuickWhere.start_exact() auto_go
run_test("QuickWhere.start_exact_auto_go", function()
   QuickWhere.start_exact(1, "citizen", "a citizen", true)
   assert_true(QuickWhere._auto_go, "auto_go set")
end)

------------------------------------------------------------------------
-- QuickWhere.reset
------------------------------------------------------------------------

--- Test: reset clears all state and disables trigger group
-- Covers: QuickWhere.reset()
run_test("QuickWhere.reset_clears_state", function()
   QuickWhere._index = 5
   QuickWhere._keyword = "citizen"
   QuickWhere._exact = true
   QuickWhere._mob_name = "a citizen"
   QuickWhere._active = true
   QuickWhere._auto_go = true
   QuickWhere.reset()
   assert_equal(1, QuickWhere._index, "index reset")
   assert_equal("", QuickWhere._keyword, "keyword cleared")
   assert_false(QuickWhere._exact, "exact cleared")
   assert_equal("", QuickWhere._mob_name, "mob_name cleared")
   assert_false(QuickWhere._active, "not active")
   assert_false(QuickWhere._auto_go, "auto_go cleared")
end)

------------------------------------------------------------------------
-- QuickWhere.check_match
------------------------------------------------------------------------

--- Test: exact mode matches first 30 chars of full mob name
-- Input: mob_field="a citizen                     ", mob_name="a citizen"
-- Expected: true
-- Covers: QuickWhere.check_match() exact positive
run_test("QuickWhere.check_match_exact_positive", function()
   local result = QuickWhere.check_match("a citizen                     ", true, "a citizen", "citizen")
   assert_true(result, "exact match on trimmed field")
end)

--- Test: exact mode rejects different mob
-- Input: mob_field="a guard                       ", mob_name="a citizen"
-- Expected: false
-- Covers: QuickWhere.check_match() exact negative
run_test("QuickWhere.check_match_exact_negative", function()
   local result = QuickWhere.check_match("a guard                       ", true, "a citizen", "citizen")
   assert_false(result, "exact mode rejects different mob")
end)

--- Test: exact mode handles long mob names (truncated to 30 chars)
-- Input: mob_field with 30 chars, mob_name longer than 30 chars
-- Expected: matches on first 30 chars only
-- Covers: QuickWhere.check_match() exact truncation
run_test("QuickWhere.check_match_exact_long_name", function()
   -- 31-char mob name:  "the incredibly ancient dragon!" (31 chars)
   local long_name = "the incredibly ancient dragon!!"
   -- The where output truncates to first 30 chars in the field
   local field_30 = "the incredibly ancient dragon!"  -- 30 chars
   assert_equal(30, #field_30, "field is 30 chars")
   local result = QuickWhere.check_match(field_30, true, long_name, "dragon")
   assert_true(result, "matches on first 30 chars")
end)

--- Test: keyword mode finds keyword in mob field
-- Input: mob_field="a citizen                     ", keyword="citizen"
-- Expected: true
-- Covers: QuickWhere.check_match() keyword positive
run_test("QuickWhere.check_match_keyword_positive", function()
   local result = QuickWhere.check_match("a citizen                     ", false, "", "citizen")
   assert_true(result, "keyword found in field")
end)

--- Test: keyword mode rejects when keyword not in field
-- Input: mob_field="a guard                       ", keyword="citizen"
-- Expected: false
-- Covers: QuickWhere.check_match() keyword negative
run_test("QuickWhere.check_match_keyword_negative", function()
   local result = QuickWhere.check_match("a guard                       ", false, "", "citizen")
   assert_false(result, "keyword not in field")
end)

--- Test: keyword mode with multi-word keyword matches any word
-- Input: mob_field="a dark knight                 ", keyword="dark knigh"
-- Expected: true (matches "dark")
-- Covers: QuickWhere.check_match() keyword multi-word
run_test("QuickWhere.check_match_keyword_multi_word", function()
   local result = QuickWhere.check_match("a dark knight                 ", false, "", "dark knigh")
   assert_true(result, "multi-word keyword partial match")
end)

------------------------------------------------------------------------
-- on_qw_match callback
------------------------------------------------------------------------

--- Test: exact match triggers room search and builds goto list
-- Setup: QW active in exact mode, mob matches, mapper DB has rooms
-- Input: 30-char mob field + room name matching mapper fixture
-- Expected: Nav._goto_list populated
-- Covers: on_qw_match() exact match path
run_test("on_qw_match.exact_match_searches_rooms", function()
   QuickWhere._active = true
   QuickWhere._exact = true
   QuickWhere._keyword = "citizen"
   QuickWhere._mob_name = "a citizen"
   QuickWhere._index = 1
   State._room = {rmid = 1254, arid = "diatz", name = "A Room", exits = {}, maze = false}
   on_qw_match("trg_qw_match", "a citizen                      A Dusty Room",
      {"a citizen                     ", "A Dusty Room"})
   assert_equal(2, #Nav._goto_list, "goto_list has 2 rooms from mapper")
   assert_false(QuickWhere._active, "QW reset after match")
end)

--- Test: keyword match triggers room search
-- Setup: QW active in keyword mode
-- Covers: on_qw_match() keyword match path
run_test("on_qw_match.keyword_match_searches_rooms", function()
   QuickWhere._active = true
   QuickWhere._exact = false
   QuickWhere._keyword = "citizen"
   QuickWhere._mob_name = ""
   QuickWhere._index = 1
   State._room = {rmid = 1254, arid = "diatz", name = "A Room", exits = {}, maze = false}
   on_qw_match("trg_qw_match", "a citizen                      A Dusty Room",
      {"a citizen                     ", "A Dusty Room"})
   assert_true(#Nav._goto_list > 0, "goto_list populated on keyword match")
   assert_false(QuickWhere._active, "QW reset after match")
end)

--- Test: non-matching mob increments index and retries
-- Setup: QW active, mob field doesn't match
-- Expected: index incremented, SendNoEcho with next where command
-- Covers: on_qw_match() no match retry
run_test("on_qw_match.no_match_increments", function()
   QuickWhere._active = true
   QuickWhere._exact = true
   QuickWhere._keyword = "citizen"
   QuickWhere._mob_name = "a citizen"
   QuickWhere._index = 1
   on_qw_match("trg_qw_match", "a guard                        The Barracks",
      {"a guard                       ", "The Barracks"})
   assert_equal(2, QuickWhere._index, "index incremented")
   assert_true(QuickWhere._active, "still active")
   local found = false
   for _, call in ipairs(mock.calls["SendNoEcho"] or {}) do
      if call[1] == "where 2.citizen" then found = true end
   end
   assert_true(found, "sent retry 'where 2.citizen'")
end)

--- Test: max 100 retries then stop
-- Setup: QW at index 100, no match
-- Expected: QW reset, no more retries
-- Covers: on_qw_match() max retry limit
run_test("on_qw_match.max_100_stops", function()
   QuickWhere._active = true
   QuickWhere._exact = true
   QuickWhere._keyword = "citizen"
   QuickWhere._mob_name = "a citizen"
   QuickWhere._index = 100
   on_qw_match("trg_qw_match", "a guard                        The Barracks",
      {"a guard                       ", "The Barracks"})
   assert_false(QuickWhere._active, "QW stopped after max retries")
end)

--- Test: auto_go navigates to first room after match
-- Setup: QW with auto_go=true, match found
-- Expected: Nav.goto_next() called (dest_room set)
-- Covers: on_qw_match() auto_go path
run_test("on_qw_match.auto_go_navigates", function()
   QuickWhere._active = true
   QuickWhere._exact = true
   QuickWhere._keyword = "citizen"
   QuickWhere._mob_name = "a citizen"
   QuickWhere._index = 1
   QuickWhere._auto_go = true
   State._room = {rmid = 1254, arid = "diatz", name = "A Room", exits = {}, maze = false}
   on_qw_match("trg_qw_match", "a citizen                      A Dusty Room",
      {"a citizen                     ", "A Dusty Room"})
   -- goto_next should have advanced index and set dest_room
   assert_true(Nav._goto_index > 0, "goto_index advanced by auto_go")
end)

--- Test: no auto_go just displays results
-- Setup: QW without auto_go
-- Expected: goto_list built but no navigation
-- Covers: on_qw_match() no auto_go
run_test("on_qw_match.no_auto_go_displays", function()
   QuickWhere._active = true
   QuickWhere._exact = true
   QuickWhere._keyword = "citizen"
   QuickWhere._mob_name = "a citizen"
   QuickWhere._index = 1
   QuickWhere._auto_go = false
   State._room = {rmid = 1254, arid = "diatz", name = "A Room", exits = {}, maze = false}
   on_qw_match("trg_qw_match", "a citizen                      A Dusty Room",
      {"a citizen                     ", "A Dusty Room"})
   assert_true(#Nav._goto_list > 0, "goto_list built")
   assert_equal(0, Nav._goto_index, "goto_index stays at 0 without auto_go")
end)

------------------------------------------------------------------------
-- on_qw_no_match callback
------------------------------------------------------------------------

--- Test: no match resets QW and notifies
-- Setup: QW active
-- Expected: QW reset
-- Covers: on_qw_no_match()
run_test("on_qw_no_match.resets", function()
   QuickWhere._active = true
   QuickWhere._keyword = "citizen"
   on_qw_no_match("trg_qw_no_match", "There is no citizen around here.", {})
   assert_false(QuickWhere._active, "QW reset after no match")
end)

------------------------------------------------------------------------
-- cmd_qw
------------------------------------------------------------------------

--- Test: cmd_qw with no target shows error
-- Covers: cmd_qw() no target
run_test("cmd_qw.no_target_error", function()
   State._target = nil
   cmd_qw("als_qw", "qw", {""})
   assert_nil(mock.calls["Send"], "no Send when no target")
   assert_false(QuickWhere._active, "not active")
end)

--- Test: cmd_qw with no args uses current target
-- Covers: cmd_qw() default target
run_test("cmd_qw.uses_current_target", function()
   State._target = {mob = "a citizen", keyword = "citizen", area_key = "diatz"}
   cmd_qw("als_qw", "qw", {""})
   assert_true(QuickWhere._active, "QW started")
   assert_equal("citizen", QuickWhere._keyword, "uses target keyword")
   assert_false(QuickWhere._exact, "keyword mode by default")
end)

--- Test: cmd_qw with mob argument
-- Covers: cmd_qw() with argument
run_test("cmd_qw.with_mob_arg", function()
   cmd_qw("als_qw", "qw guard", {"guard"})
   assert_true(QuickWhere._active, "QW started")
   assert_equal("guard", QuickWhere._keyword, "uses provided keyword")
end)

--- Test: cmd_qw with indexed argument "3.guard"
-- Covers: cmd_qw() indexed argument
run_test("cmd_qw.with_indexed_arg", function()
   cmd_qw("als_qw", "qw 3.guard", {"3.guard"})
   assert_true(QuickWhere._active, "QW started")
   assert_equal(3, QuickWhere._index, "index parsed")
   assert_equal("guard", QuickWhere._keyword, "keyword parsed")
end)

--- Test: cmd_qw abort stops quick where
-- Covers: cmd_qw() abort
run_test("cmd_qw.abort", function()
   QuickWhere._active = true
   cmd_qw("als_qw", "qw abort", {"abort"})
   assert_false(QuickWhere._active, "QW reset")
end)

--- Test: cmd_qw "0" stops quick where
-- Covers: cmd_qw() numeric abort
run_test("cmd_qw.zero_abort", function()
   QuickWhere._active = true
   cmd_qw("als_qw", "qw 0", {"0"})
   assert_false(QuickWhere._active, "QW reset on 0")
end)
