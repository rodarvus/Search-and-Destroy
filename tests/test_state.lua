------------------------------------------------------------------------
-- test_state.lua - Tests for the State module
------------------------------------------------------------------------

if not CONST then
   local load_plugin = require("load_plugin")
   load_plugin()
end

function setUp()
   mock.reset()
   -- Reset State to initial values
   State._room = {rmid = -1, arid = "", name = "", exits = {}, maze = false}
   State._prev_room = {rmid = -2, arid = ""}
   State._target = nil
   State._activity = "none"
   State._char_state = "0"
   State._noexp = false
   State._level = 0
   State._tier = 0
   State._tnl = 0
   State._dirty = false
end

run_test("State.initial", function()
   assert_equal(-1, State._room.rmid, "initial room rmid is -1")
   assert_equal("", State._room.arid, "initial room arid is empty")
   assert_equal("none", State.get_activity(), "initial activity is none")
   assert_nil(State.get_target(), "initial target is nil")
   assert_equal(0, State._level, "initial level is 0")
end)

run_test("State.update_room", function()
   State.update_room({
      num = 12345,
      zone = "diatz",
      name = "The Three Pillars",
      exits = {n = 12346, s = 12344},
      details = "",
   })
   local room = State.get_room()
   assert_equal(12345, room.rmid, "room id updated")
   assert_equal("diatz", room.arid, "room area updated")
   assert_equal("The Three Pillars", room.name, "room name updated")
   assert_false(room.maze, "non-maze room")
end)

run_test("State.update_room_maze", function()
   State.update_room({
      num = 99999,
      zone = "partroxis",
      name = "A Maze",
      exits = {},
      details = "maze",
   })
   local room = State.get_room()
   assert_true(room.maze, "maze room detected")
end)

run_test("State.update_room_prev", function()
   State.update_room({num = 11111, zone = "aylor", name = "Aylor", exits = {}})
   State.update_room({num = 22222, zone = "diatz", name = "Diatz", exits = {}})
   assert_equal(22222, State._room.rmid, "current room updated")
   assert_equal(11111, State._prev_room.rmid, "previous room saved")
end)

run_test("State.update_room_nil_fields", function()
   State.update_room({})
   local room = State.get_room()
   assert_equal(-1, room.rmid, "nil num defaults to -1")
   assert_equal("", room.arid, "nil zone defaults to empty")
   assert_equal("", room.name, "nil name defaults to empty")
end)

run_test("State.update_char", function()
   State.update_char({
      state = "3",
      level = "150",
      tnl = "2500",
   })
   assert_equal("3", State._char_state, "char state updated")
   assert_equal(150, State._level, "level updated")
   assert_equal(2500, State._tnl, "tnl updated")
end)

run_test("State.update_char_nil", function()
   State._char_state = "3"
   State.update_char(nil)
   assert_equal("3", State._char_state, "char state unchanged after nil update")
end)

run_test("State.set_activity", function()
   State.set_activity("cp")
   assert_equal("cp", State.get_activity(), "activity changed to cp")
   assert_true(State._dirty, "dirty flag set")
   local found = false
   for _, call in ipairs(mock.calls["BroadcastPlugin"] or {}) do
      if call[1] == CONST.BCAST_ACTIVITY and call[2] == "cp" then
         found = true
      end
   end
   assert_true(found, "BCAST_ACTIVITY sent with 'cp'")
end)

run_test("State.set_activity_same", function()
   State._activity = "cp"
   State.set_activity("cp")
   assert_false(State._dirty, "dirty not set for same activity")
   assert_nil(mock.calls["BroadcastPlugin"], "no broadcast for same activity")
end)

run_test("State.set_target", function()
   local target = {keyword = "vand", name = "a vandal", area = "diatz", index = 1}
   State.set_target(target)
   assert_equal(target, State.get_target(), "target set")
   assert_true(State._dirty, "dirty flag set")
   local found_changed = false
   for _, call in ipairs(mock.calls["BroadcastPlugin"] or {}) do
      if call[1] == CONST.BCAST_TARGET_CHANGED then
         found_changed = true
      end
   end
   assert_true(found_changed, "BCAST_TARGET_CHANGED sent")
end)

run_test("State.clear_target", function()
   State._target = {keyword = "test"}
   State.clear_target()
   assert_nil(State.get_target(), "target cleared")
   local found_cleared = false
   for _, call in ipairs(mock.calls["BroadcastPlugin"] or {}) do
      if call[1] == CONST.BCAST_TARGET_CLEARED then
         found_cleared = true
      end
   end
   assert_true(found_cleared, "BCAST_TARGET_CLEARED sent")
end)

run_test("State.broadcast_full", function()
   State._room = {rmid = 100, arid = "test", name = "Test Room", exits = {}, maze = false}
   State._activity = "gq"
   State._level = 75
   State._noexp = true
   State._target = {keyword = "mob", name = "a mob", area = "test"}
   State.broadcast_full()
   local found_full = false
   local full_data = nil
   for _, call in ipairs(mock.calls["BroadcastPlugin"] or {}) do
      if call[1] == CONST.BCAST_FULL_STATE then
         found_full = true
         full_data = call[2]
      end
   end
   assert_true(found_full, "BCAST_FULL_STATE sent")
   assert_not_nil(full_data, "full state data not nil")
   assert_true(#full_data > 10, "full state data has content")
end)

run_test("State.activity_transitions", function()
   State.set_activity("cp")
   assert_equal("cp", State.get_activity(), "transition to cp")
   State.set_activity("gq")
   assert_equal("gq", State.get_activity(), "transition to gq")
   State.set_activity("none")
   assert_equal("none", State.get_activity(), "transition to none")
   local bcast_count = 0
   for _, call in ipairs(mock.calls["BroadcastPlugin"] or {}) do
      if call[1] == CONST.BCAST_ACTIVITY then
         bcast_count = bcast_count + 1
      end
   end
   assert_equal(3, bcast_count, "3 activity broadcasts sent")
end)
