------------------------------------------------------------------------
-- test_nav.lua - Tests for Nav module
------------------------------------------------------------------------

if not CONST then
   local load_plugin = require("load_plugin")
   load_plugin()
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
end

function tearDown()
   mock.reset_db()
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
