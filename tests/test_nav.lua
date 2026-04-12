------------------------------------------------------------------------
-- test_nav.lua - Tests for Nav module
------------------------------------------------------------------------

if not CONST then
   local load_plugin = require("load_plugin")
   load_plugin()
end

--- Create a test fixture mapper DB with known rooms
local mapper_db_path = "/tmp/test_data/Aardwolf.db"

local function create_mapper_fixture()
   os.execute("mkdir -p /tmp/test_data")
   -- Remove old fixture
   os.remove(mapper_db_path)
   local db = require("lsqlite3").open(mapper_db_path)
   db:exec([[
      CREATE TABLE IF NOT EXISTS rooms (
         uid TEXT NOT NULL PRIMARY KEY,
         name TEXT,
         area TEXT
      );
      INSERT INTO rooms VALUES ('1254', 'A Dusty Room', 'diatz');
      INSERT INTO rooms VALUES ('1255', 'A Dark Corridor', 'diatz');
      INSERT INTO rooms VALUES ('1260', 'A Dusty Room', 'diatz');
      INSERT INTO rooms VALUES ('5000', 'The Town Square', 'aylor');
      INSERT INTO rooms VALUES ('5001', 'A Dusty Room', 'aylor');
   ]])
   db:close()
end

function setUp()
   mock.reset()
   mock.reset_db()
   DB.init()
   Nav._goto_list = {}
   Nav._goto_index = 0
   Nav._dest_area = nil
   Nav._dest_room = nil
   Nav._on_arrive = nil
   Nav._vidblain_dest = nil
   State._room = {rmid = -1, arid = "", name = "", exits = {}, maze = false}
   create_mapper_fixture()
end

function tearDown()
   mock.reset_db()
   os.remove(mapper_db_path)
end

------------------------------------------------------------------------
-- Nav.goto_area
------------------------------------------------------------------------

--- Test: goto_area sends mapper goto to area's start room
-- Input: "diatz" (start room 1254 in CONST)
-- Expected: Execute("mapper goto 1254") called
-- Covers: Nav.goto_area(), Nav.mapper_goto(), DB.get_start_room()
run_test("Nav.goto_area_basic", function()
   Nav.goto_area("diatz")
   local found_goto = false
   for _, call in ipairs(mock.calls["Execute"] or {}) do
      if call[1] == "mapper goto 1254" then found_goto = true end
   end
   assert_true(found_goto, "sent mapper goto to diatz start room 1254")
end)

--- Test: goto_area sets _dest_area for arrival detection
-- Input: "diatz"
-- Expected: Nav._dest_area = "diatz"
-- Covers: Nav.goto_area() state management
run_test("Nav.goto_area_sets_dest", function()
   Nav.goto_area("diatz")
   assert_equal("diatz", Nav._dest_area, "dest_area set to diatz")
end)

--- Test: goto_area for unknown area shows error, no navigation
-- Input: nonexistent area key
-- Expected: no Execute call
-- Covers: Nav.goto_area() error path
run_test("Nav.goto_area_unknown", function()
   mock.reset()
   Nav.goto_area("totally_nonexistent_area_xyz")
   assert_nil(mock.calls["Execute"], "no Execute for unknown area")
end)

--- Test: goto_area translates ft2 → ftii (Faerie Tales II hack)
-- Input: "ft2"
-- Expected: Execute("mapper goto 26673") (ftii's start room)
-- Covers: Nav.goto_area() ft2→ftii translation
run_test("Nav.goto_area_ft2_hack", function()
   Nav.goto_area("ft2")
   local found = false
   for _, call in ipairs(mock.calls["Execute"] or {}) do
      if call[1] == "mapper goto 26673" then found = true end
   end
   assert_true(found, "ft2 translated to ftii, sent mapper goto 26673")
end)

--- Test: goto_area for Vidblain area (not in Vidblain) goes via portal
-- Setup: player in aylor (non-Vidblain)
-- Input: "asherodan" (Vidblain area)
-- Expected: mapper goto 11910 (portal) + "enter hole", deferred destination
-- Covers: Nav.goto_area() Vidblain portal handling
run_test("Nav.goto_area_vidblain", function()
   State._room = {rmid = 32418, arid = "aylor", name = "Aylor", exits = {}, maze = false}
   Nav.goto_area("asherodan")
   local found_portal = false
   local found_enter = false
   for _, call in ipairs(mock.calls["Execute"] or {}) do
      if call[1] == "mapper goto 11910" then found_portal = true end
      if call[1] == "enter hole" then found_enter = true end
   end
   assert_true(found_portal, "sent mapper goto to Vidblain portal 11910")
   assert_true(found_enter, "sent enter hole command")
end)

--- Test: goto_area for Vidblain area when already in Vidblain goes direct
-- Setup: player in vidblain continent
-- Input: "asherodan" (Vidblain area)
-- Expected: direct mapper goto 37400 (asherodan start), no portal
-- Covers: Nav.goto_area() Vidblain already-in path
run_test("Nav.goto_area_vidblain_already_in", function()
   State._room = {rmid = 33570, arid = "vidblain", name = "Vidblain", exits = {}, maze = false}
   Nav.goto_area("asherodan")
   local found_direct = false
   local found_portal = false
   for _, call in ipairs(mock.calls["Execute"] or {}) do
      if call[1] == "mapper goto 37400" then found_direct = true end
      if call[1] == "mapper goto 11910" then found_portal = true end
   end
   assert_true(found_direct, "sent direct mapper goto to asherodan 37400")
   assert_false(found_portal, "did NOT go to portal when already in vidblain")
end)

------------------------------------------------------------------------
-- Nav.goto_room
------------------------------------------------------------------------

--- Test: goto_room sends mapper goto to specific room ID
-- Input: roomid 12345
-- Expected: Execute("mapper goto 12345"), _dest_room set
-- Covers: Nav.goto_room()
run_test("Nav.goto_room_basic", function()
   Nav.goto_room(12345)
   local found = false
   for _, call in ipairs(mock.calls["Execute"] or {}) do
      if call[1] == "mapper goto 12345" then found = true end
   end
   assert_true(found, "sent mapper goto to specific room")
   assert_equal(12345, Nav._dest_room, "dest_room set")
end)

------------------------------------------------------------------------
-- Nav.on_room_change: arrival detection
------------------------------------------------------------------------

--- Test: Area arrival fires callback and clears dest_area
-- Setup: dest_area="diatz", on_arrive callback set
-- Input: room.info with zone="diatz"
-- Expected: callback fires, dest_area cleared
-- Covers: Nav.on_room_change() area arrival path
run_test("Nav.on_room_change_area_arrival", function()
   Nav._dest_area = "diatz"
   local arrived = false
   Nav._on_arrive = function() arrived = true end
   Nav.on_room_change({num = 1254, zone = "diatz", name = "A Room"})
   assert_true(arrived, "on_arrive callback fired on area arrival")
   assert_nil(Nav._dest_area, "dest_area cleared after arrival")
end)

--- Test: Wrong area does NOT fire arrival callback
-- Setup: dest_area="diatz", arrive in aylor
-- Expected: callback NOT fired, dest_area still set
-- Covers: Nav.on_room_change() area non-match
run_test("Nav.on_room_change_area_not_arrived", function()
   Nav._dest_area = "diatz"
   local arrived = false
   Nav._on_arrive = function() arrived = true end
   Nav.on_room_change({num = 32418, zone = "aylor", name = "Aylor"})
   assert_false(arrived, "on_arrive NOT fired when in wrong area")
   assert_equal("diatz", Nav._dest_area, "dest_area still set")
end)

--- Test: Room arrival fires callback and clears dest_room
-- Setup: dest_room=12345, on_arrive callback set
-- Input: room.info with num=12345
-- Expected: callback fires, dest_room cleared
-- Covers: Nav.on_room_change() room arrival path
run_test("Nav.on_room_change_room_arrival", function()
   Nav._dest_room = 12345
   local arrived = false
   Nav._on_arrive = function() arrived = true end
   Nav.on_room_change({num = 12345, zone = "diatz", name = "The Room"})
   assert_true(arrived, "on_arrive callback fired on room arrival")
   assert_nil(Nav._dest_room, "dest_room cleared after arrival")
end)

--- Test: No destination set — on_room_change is a no-op
-- Setup: all dest fields nil
-- Expected: no crash
-- Covers: Nav.on_room_change() nil guard
run_test("Nav.on_room_change_no_dest", function()
   Nav._dest_area = nil
   Nav._dest_room = nil
   Nav._on_arrive = nil
   Nav.on_room_change({num = 1234, zone = "diatz", name = "A Room"})
   assert_true(true, "no crash with no destination")
end)

------------------------------------------------------------------------
-- Nav.fuzzy_match_area
------------------------------------------------------------------------

--- Test: Exact area key match
-- Input: "diatz"
-- Expected: "diatz"
-- Covers: Nav.fuzzy_match_area() exact path
run_test("Nav.fuzzy_match_area_exact", function()
   local key = Nav.fuzzy_match_area("diatz")
   assert_equal("diatz", key, "exact match on area key")
end)

--- Test: Partial prefix match (dia → diatz)
-- Input: "dia"
-- Expected: "diatz" (prefix match)
-- Covers: Nav.fuzzy_match_area() prefix match
run_test("Nav.fuzzy_match_area_partial", function()
   local key = Nav.fuzzy_match_area("dia")
   assert_equal("diatz", key, "partial match on area key")
end)

--- Test: ft2 → ftii translation in fuzzy match
-- Input: "ft2"
-- Expected: "ftii"
-- Covers: Nav.fuzzy_match_area() ft2 hack
run_test("Nav.fuzzy_match_area_ft2_hack", function()
   local key = Nav.fuzzy_match_area("ft2")
   assert_equal("ftii", key, "ft2 translated to ftii")
end)

--- Test: No match returns nil
-- Input: nonexistent area prefix
-- Expected: nil
-- Covers: Nav.fuzzy_match_area() miss
run_test("Nav.fuzzy_match_area_no_match", function()
   local key = Nav.fuzzy_match_area("zzzznonexistent")
   assert_nil(key, "nil for no match")
end)

------------------------------------------------------------------------
-- Nav.goto_next
------------------------------------------------------------------------

--- Test: goto_next advances index and navigates to next room
-- Setup: 3-room list, index at 1
-- Expected: index becomes 2, mapper goto to room 22222
-- Covers: Nav.goto_next()
run_test("Nav.goto_next_basic", function()
   Nav._goto_list = {11111, 22222, 33333}
   Nav._goto_index = 1
   Nav.goto_next()
   assert_equal(2, Nav._goto_index, "index advanced to 2")
   assert_equal(22222, Nav._dest_room, "dest_room set to second room")
end)

--- Test: goto_next at end of list does not advance
-- Setup: 2-room list, index at 2 (last)
-- Expected: index stays at 2
-- Covers: Nav.goto_next() boundary
run_test("Nav.goto_next_at_end", function()
   Nav._goto_list = {11111, 22222}
   Nav._goto_index = 2
   Nav.goto_next()
   assert_equal(2, Nav._goto_index, "index stays at end")
end)

--- Test: goto_next with empty list is a no-op
-- Setup: empty goto_list
-- Expected: no crash, index stays at 0
-- Covers: Nav.goto_next() empty guard
run_test("Nav.goto_next_empty_list", function()
   Nav._goto_list = {}
   Nav._goto_index = 0
   Nav.goto_next()
   assert_equal(0, Nav._goto_index, "index stays at 0 for empty list")
end)

------------------------------------------------------------------------
-- Nav.mapper_db_path
------------------------------------------------------------------------

--- Test: mapper_db_path returns expected path
-- Expected: GetInfo(66) .. "Aardwolf.db" = "/tmp/test_data/Aardwolf.db"
-- Covers: Nav.mapper_db_path()
run_test("Nav.mapper_db_path", function()
   local path = Nav.mapper_db_path()
   assert_equal("/tmp/test_data/Aardwolf.db", path, "mapper DB path from GetInfo(66)")
end)

------------------------------------------------------------------------
-- Nav.search_rooms
------------------------------------------------------------------------

--- Test: search_rooms finds rooms matching name and area, ordered by uid ascending
-- Setup: mapper fixture has 2 rooms named "A Dusty Room" in diatz (uids 1254, 1260)
-- Input: room_name="A Dusty Room", area_key="diatz"
-- Expected: returns 2 results with uid 1254 first, 1260 second (deterministic order)
-- Why: undefined SQL order made `nx` non-deterministic across calls
-- Covers: Nav.search_rooms() basic match + ORDER BY uid
run_test("Nav.search_rooms_found", function()
   local results = Nav.search_rooms("A Dusty Room", "diatz")
   assert_equal(2, #results, "found 2 rooms")
   -- uids stored as strings from sqlite TEXT column; sort numerically
   assert_equal("1254", results[1].uid, "first result has lowest uid")
   assert_equal("1260", results[2].uid, "second result has higher uid")
end)

--- Test: search_rooms returns empty for nonexistent room name
-- Input: room_name="Nonexistent Chamber", area_key="diatz"
-- Expected: empty table
-- Covers: Nav.search_rooms() no match
run_test("Nav.search_rooms_no_match", function()
   local results = Nav.search_rooms("Nonexistent Chamber", "diatz")
   assert_equal(0, #results, "no results for nonexistent room")
end)

--- Test: search_rooms returns empty when room exists in different area
-- Setup: "A Dusty Room" exists in diatz and aylor but not "wooble"
-- Input: room_name="A Dusty Room", area_key="wooble"
-- Expected: empty table
-- Covers: Nav.search_rooms() area filtering
run_test("Nav.search_rooms_wrong_area", function()
   local results = Nav.search_rooms("A Dusty Room", "wooble")
   assert_equal(0, #results, "no results for wrong area")
end)

--- Test: search_rooms result structure has uid and name
-- Input: room_name="The Town Square", area_key="aylor"
-- Expected: 1 result with uid="5000", name="The Town Square"
-- Covers: Nav.search_rooms() result fields
run_test("Nav.search_rooms_result_fields", function()
   local results = Nav.search_rooms("The Town Square", "aylor")
   assert_equal(1, #results, "found 1 room")
   assert_equal("5000", results[1].uid, "uid is string from DB")
   assert_equal("The Town Square", results[1].name, "name preserved")
end)

--- Test: search_rooms handles nil/empty args gracefully
-- Input: nil room_name
-- Expected: empty table, no crash
-- Covers: Nav.search_rooms() nil guard
run_test("Nav.search_rooms_nil_args", function()
   local results = Nav.search_rooms(nil, "diatz")
   assert_equal(0, #results, "empty for nil room_name")
end)

--- Test: search_rooms handles missing mapper DB gracefully
-- Setup: remove mapper DB file
-- Input: valid room_name and area_key
-- Expected: empty table, no crash
-- Covers: Nav.search_rooms() DB open failure
run_test("Nav.search_rooms_no_db", function()
   os.remove(mapper_db_path)
   local results = Nav.search_rooms("A Dusty Room", "diatz")
   assert_equal(0, #results, "empty when mapper DB missing")
end)

------------------------------------------------------------------------
-- Nav.build_goto_list
------------------------------------------------------------------------

--- Test: build_goto_list populates goto_list from search results
-- Input: 3 results with uid fields
-- Expected: goto_list = {1254, 1260, 5001}, goto_index = 0
-- Covers: Nav.build_goto_list()
run_test("Nav.build_goto_list_basic", function()
   local results = {
      {uid = "1254", name = "A Dusty Room"},
      {uid = "1260", name = "A Dusty Room"},
      {uid = "5001", name = "A Dusty Room"},
   }
   Nav.build_goto_list(results)
   assert_equal(3, #Nav._goto_list, "3 rooms in list")
   assert_equal(1254, Nav._goto_list[1], "first room uid as number")
   assert_equal(1260, Nav._goto_list[2], "second room uid as number")
   assert_equal(0, Nav._goto_index, "index starts at 0")
end)

--- Test: build_goto_list with empty results clears the list
-- Input: empty results
-- Expected: goto_list = {}, goto_index = 0
-- Covers: Nav.build_goto_list() empty input
run_test("Nav.build_goto_list_empty", function()
   Nav._goto_list = {111, 222}
   Nav._goto_index = 2
   Nav.build_goto_list({})
   assert_equal(0, #Nav._goto_list, "list cleared")
   assert_equal(0, Nav._goto_index, "index reset to 0")
end)

--- Test: build_goto_list skips invalid UIDs (non-numeric)
-- Input: results with one invalid uid
-- Expected: only valid UIDs in list
-- Covers: Nav.build_goto_list() sanitization
run_test("Nav.build_goto_list_skips_invalid", function()
   local results = {
      {uid = "1254", name = "A Room"},
      {uid = "nomap", name = "Unmappable"},
      {uid = "1260", name = "Another Room"},
   }
   Nav.build_goto_list(results)
   assert_equal(2, #Nav._goto_list, "skipped non-numeric uid")
   assert_equal(1254, Nav._goto_list[1], "first valid room")
   assert_equal(1260, Nav._goto_list[2], "second valid room")
end)
