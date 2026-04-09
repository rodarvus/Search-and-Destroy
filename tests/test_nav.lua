------------------------------------------------------------------------
-- test_nav.lua - Tests for Nav module
-- TDD: Tests define expected behavior. Implementation follows.
------------------------------------------------------------------------

if not CONST then
   local load_plugin = require("load_plugin")
   load_plugin()
end

function setUp()
   mock.reset()
   mock.reset_db()
   DB.init()
   -- Reset Nav state
   Nav._goto_list = {}
   Nav._goto_index = 0
   Nav._dest_area = nil
   Nav._dest_room = nil
   Nav._on_arrive = nil
   Nav._vidblain_dest = nil
   -- Reset State room
   State._room = {rmid = -1, arid = "", name = "", exits = {}, maze = false}
end

function tearDown()
   mock.reset_db()
end

------------------------------------------------------------------------
-- Nav.goto_area: navigate to area start room
------------------------------------------------------------------------

run_test("Nav.goto_area_basic", function()
   -- Navigate to a known area — should look up start room and send mapper goto
   Nav.goto_area("diatz")

   -- Should have sent mapper goto with diatz start room (1254)
   local found_goto = false
   for _, call in ipairs(mock.calls["Execute"] or {}) do
      if call[1] == "mapper goto 1254" then found_goto = true end
   end
   assert_true(found_goto, "sent mapper goto to diatz start room 1254")
end)

run_test("Nav.goto_area_sets_dest", function()
   Nav.goto_area("diatz")
   assert_equal("diatz", Nav._dest_area, "dest_area set to diatz")
end)

run_test("Nav.goto_area_unknown", function()
   -- Unknown area — should show error, not crash
   mock.reset()
   Nav.goto_area("totally_nonexistent_area_xyz")

   -- Should NOT have sent any mapper goto
   assert_nil(mock.calls["Execute"], "no Execute for unknown area")
end)

run_test("Nav.goto_area_ft2_hack", function()
   -- ft2 should be translated to ftii
   Nav.goto_area("ft2")

   -- Should have looked up ftii's start room (26673)
   local found = false
   for _, call in ipairs(mock.calls["Execute"] or {}) do
      if call[1] == "mapper goto 26673" then found = true end
   end
   assert_true(found, "ft2 translated to ftii, sent mapper goto 26673")
end)

run_test("Nav.goto_area_vidblain", function()
   -- Vidblain area when NOT in vidblain — should go to portal first
   State._room = {rmid = 32418, arid = "aylor", name = "Aylor", exits = {}, maze = false}
   Nav.goto_area("asherodan")

   -- Should have sent mapper goto to portal room 11910 and "enter hole"
   local found_portal = false
   local found_enter = false
   for _, call in ipairs(mock.calls["Execute"] or {}) do
      if call[1] == "mapper goto 11910" then found_portal = true end
      if call[1] == "enter hole" then found_enter = true end
   end
   assert_true(found_portal, "sent mapper goto to Vidblain portal 11910")
   assert_true(found_enter, "sent enter hole command")
end)

run_test("Nav.goto_area_vidblain_already_in", function()
   -- Already in vidblain area — direct navigation, no portal
   State._room = {rmid = 33570, arid = "vidblain", name = "Vidblain", exits = {}, maze = false}
   Nav.goto_area("asherodan")

   -- Should have sent direct mapper goto to asherodan start room (37400)
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
-- Nav.goto_room: navigate to specific room
------------------------------------------------------------------------

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

run_test("Nav.on_room_change_area_arrival", function()
   -- Set up: navigating to diatz area
   Nav._dest_area = "diatz"
   local arrived = false
   Nav._on_arrive = function() arrived = true end

   -- Simulate room change to diatz
   Nav.on_room_change({num = 1254, zone = "diatz", name = "A Room"})

   assert_true(arrived, "on_arrive callback fired on area arrival")
   assert_nil(Nav._dest_area, "dest_area cleared after arrival")
end)

run_test("Nav.on_room_change_area_not_arrived", function()
   -- Set up: navigating to diatz, but arrive in different area
   Nav._dest_area = "diatz"
   local arrived = false
   Nav._on_arrive = function() arrived = true end

   Nav.on_room_change({num = 32418, zone = "aylor", name = "Aylor"})

   assert_false(arrived, "on_arrive NOT fired when in wrong area")
   assert_equal("diatz", Nav._dest_area, "dest_area still set")
end)

run_test("Nav.on_room_change_room_arrival", function()
   -- Set up: navigating to specific room
   Nav._dest_room = 12345
   local arrived = false
   Nav._on_arrive = function() arrived = true end

   Nav.on_room_change({num = 12345, zone = "diatz", name = "The Room"})

   assert_true(arrived, "on_arrive callback fired on room arrival")
   assert_nil(Nav._dest_room, "dest_room cleared after arrival")
end)

run_test("Nav.on_room_change_no_dest", function()
   -- No destination set — should not crash
   Nav._dest_area = nil
   Nav._dest_room = nil
   Nav._on_arrive = nil

   Nav.on_room_change({num = 1234, zone = "diatz", name = "A Room"})
   -- Should not crash, no assertions needed beyond no-error
   assert_true(true, "no crash with no destination")
end)

------------------------------------------------------------------------
-- Nav.fuzzy_match_area: fuzzy area key matching for xrt
------------------------------------------------------------------------

run_test("Nav.fuzzy_match_area_exact", function()
   local key = Nav.fuzzy_match_area("diatz")
   assert_equal("diatz", key, "exact match on area key")
end)

run_test("Nav.fuzzy_match_area_partial", function()
   local key = Nav.fuzzy_match_area("dia")
   assert_equal("diatz", key, "partial match on area key")
end)

run_test("Nav.fuzzy_match_area_ft2_hack", function()
   local key = Nav.fuzzy_match_area("ft2")
   assert_equal("ftii", key, "ft2 translated to ftii")
end)

run_test("Nav.fuzzy_match_area_no_match", function()
   local key = Nav.fuzzy_match_area("zzzznonexistent")
   assert_nil(key, "nil for no match")
end)

------------------------------------------------------------------------
-- Nav.goto_next: advance through room list
------------------------------------------------------------------------

run_test("Nav.goto_next_basic", function()
   Nav._goto_list = {11111, 22222, 33333}
   Nav._goto_index = 1

   Nav.goto_next()

   assert_equal(2, Nav._goto_index, "index advanced to 2")
   assert_equal(22222, Nav._dest_room, "dest_room set to second room")
end)

run_test("Nav.goto_next_at_end", function()
   Nav._goto_list = {11111, 22222}
   Nav._goto_index = 2

   Nav.goto_next()

   -- At end of list — should not advance
   assert_equal(2, Nav._goto_index, "index stays at end")
end)

run_test("Nav.goto_next_empty_list", function()
   Nav._goto_list = {}
   Nav._goto_index = 0

   Nav.goto_next()

   -- Should not crash
   assert_equal(0, Nav._goto_index, "index stays at 0 for empty list")
end)
