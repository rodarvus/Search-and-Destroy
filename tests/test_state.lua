------------------------------------------------------------------------
-- test_state.lua - Tests for the State module
------------------------------------------------------------------------

if not CONST then
   local load_plugin = require("load_plugin")
   load_plugin()
end

local TestData = require("test_data")

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
   -- Reset CP state
   CP._on_cp = false
   CP._level = 0
   CP._type = "area"
   CP._info_list = {}
   CP._check_list = {}
   CP._can_get_new = false
   CP._last_check_time = 0
   CP._last_target = nil
   -- Reset TargetList
   TargetList._main_list = {}
   TargetList._type = "none"
   -- Reset Noexp
   Noexp._auto_enabled = true
   Noexp._noexp_on = false
   Noexp._tnl_cutoff = 0
end

--- Test: Initial state has safe defaults (-1 room, "none" activity, nil target)
-- Covers: State initialization
run_test("State.initial", function()
   assert_equal(-1, State._room.rmid, "initial room rmid is -1")
   assert_equal("", State._room.arid, "initial room arid is empty")
   assert_equal("none", State.get_activity(), "initial activity is none")
   assert_nil(State.get_target(), "initial target is nil")
   assert_equal(0, State._level, "initial level is 0")
end)

--- Test: update_room populates rmid, arid, name, maze from GMCP room.info
-- Covers: State.update_room()
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

--- Test: "maze" in details field sets maze=true
-- Covers: State.update_room() maze detection
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

--- Test: Previous room saved on each update_room call
-- Covers: State.update_room() _prev_room tracking
run_test("State.update_room_prev", function()
   State.update_room({num = 11111, zone = "aylor", name = "Aylor", exits = {}})
   State.update_room({num = 22222, zone = "diatz", name = "Diatz", exits = {}})
   assert_equal(22222, State._room.rmid, "current room updated")
   assert_equal(11111, State._prev_room.rmid, "previous room saved")
end)

--- Test: Missing GMCP fields default safely (-1 for rmid, "" for strings)
-- Covers: State.update_room() nil field handling
run_test("State.update_room_nil_fields", function()
   State.update_room({})
   local room = State.get_room()
   assert_equal(-1, room.rmid, "nil num defaults to -1")
   assert_equal("", room.arid, "nil zone defaults to empty")
   assert_equal("", room.name, "nil name defaults to empty")
end)

--- Test: GMCP num as string is coerced to number for safe comparisons
-- Setup: Aardwolf GMCP may deliver room.info.num as a string (Crowley defends against this)
-- Input: update_room with num="12345" (string)
-- Expected: rmid stored as number 12345 so downstream comparisons (cmd_nx, on_room_change) work
-- Covers: State.update_room() type coercion — prevents nx "already in that room" bug
run_test("State.update_room_coerces_string_num", function()
   State.update_room({num = "12345", zone = "diatz", name = "Test Room", exits = {}})
   local room = State.get_room()
   assert_equal(12345, room.rmid, "string num coerced to number")
   assert_equal("number", type(room.rmid), "rmid type is number")
end)

--- Test: GMCP num as bogus string defaults to -1 (number)
-- Setup: defensive case if GMCP ever delivers garbage
-- Expected: tonumber fails → fallback to -1 (still number)
-- Covers: State.update_room() coercion fallback
run_test("State.update_room_invalid_num_defaults", function()
   State.update_room({num = "not_a_number", zone = "diatz", name = "X", exits = {}})
   local room = State.get_room()
   assert_equal(-1, room.rmid, "unparseable num defaults to -1")
   assert_equal("number", type(room.rmid), "rmid type is number even on fallback")
end)

--- Test: update_char populates char_state, level, tnl from GMCP char.status
-- Covers: State.update_char()
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

--- Test: nil char status is safe (no crash, state unchanged)
-- Covers: State.update_char() nil guard
run_test("State.update_char_nil", function()
   State._char_state = "3"
   State.update_char(nil)
   assert_equal("3", State._char_state, "char state unchanged after nil update")
end)

--- Test: set_activity changes state, sets dirty, broadcasts BCAST_ACTIVITY
-- Covers: State.set_activity()
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

--- Test: Setting same activity is a no-op (no dirty, no broadcast)
-- Covers: State.set_activity() same-value guard
run_test("State.set_activity_same", function()
   State._activity = "cp"
   State.set_activity("cp")
   assert_false(State._dirty, "dirty not set for same activity")
   assert_nil(mock.calls["BroadcastPlugin"], "no broadcast for same activity")
end)

--- Test: set_target stores target, sets dirty, broadcasts BCAST_TARGET_CHANGED
-- Covers: State.set_target()
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

--- Test: clear_target sets target to nil, broadcasts BCAST_TARGET_CLEARED
-- Covers: State.clear_target() → State.set_target(nil)
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

--- Test: broadcast_full sends BCAST_FULL_STATE with JSON snapshot
-- Covers: State.broadcast_full()
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

--- Test: Activity transitions none→cp→gq→none each broadcast correctly
-- Covers: State.set_activity() sequence, BCAST_ACTIVITY count
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

------------------------------------------------------------------------
-- CP module state transitions
------------------------------------------------------------------------

--- Test: CP.start sets state, turns noexp off, sends "noexp" + "cp info"
-- Setup: noexp on, not on CP
-- Expected: CP._on_cp=true, activity="cp", noexp off, SendNoEcho("noexp") + SendNoEcho("cp info")
-- Covers: CP.start(), Noexp.set()
run_test("CP.start", function()
   -- CP.start() should set state, turn noexp off, and begin cp info parsing
   CP._on_cp = false
   CP._level = 0
   CP._can_get_new = false
   State._activity = "none"
   State._level = 50
   Noexp._noexp_on = true
   Noexp._auto_enabled = true
   Noexp._tnl_cutoff = 500
   State._noexp = true

   CP.start()

   assert_true(CP._on_cp, "CP on after start")
   assert_equal("cp", State.get_activity(), "activity set to cp")
   assert_false(Noexp._noexp_on, "noexp turned off on CP start")
   assert_false(State._noexp, "State._noexp synced off")
   -- Should have sent "noexp" game command to toggle it off
   local sent_noexp = false
   for _, call in ipairs(mock.calls["SendNoEcho"] or {}) do
      if call[1] == "noexp" then sent_noexp = true end
   end
   assert_true(sent_noexp, "noexp game command sent")
   -- Should have sent "cp info" via SendNoEcho
   local sent_cp_info = false
   for _, call in ipairs(mock.calls["SendNoEcho"] or {}) do
      if call[1] == "cp info" then sent_cp_info = true end
   end
   assert_true(sent_cp_info, "sent cp info command")
end)

--- Test: Second CP.start() call is no-op (prevents parallel parsing)
-- Covers: CP.start() double-call guard
run_test("CP.start_double_call_guard", function()
   -- Second call to CP.start() should be no-op
   CP._on_cp = false
   State._activity = "none"
   Noexp._noexp_on = false
   State._noexp = false

   CP.start()
   assert_true(CP._on_cp, "first call activates CP")
   mock.reset()

   -- Second call — should return immediately
   CP.start()
   -- Should NOT have sent another "cp info"
   assert_nil(mock.calls["SendNoEcho"], "second call is no-op")
end)

--- Test: Empty check_list causes early return (parse failure guard)
-- Covers: on_cp_check_end() empty guard
run_test("CP.check_end_empty_list_guard", function()
   -- Empty check list should log error and return without building
   CP._on_cp = true
   CP._type = "area"
   CP._level = 45
   State._activity = "cp"
   CP._check_list = {}  -- empty!
   TargetList.clear()    -- ensure clean slate
   mock.reset_db()
   DB.init()
   mock.reset()

   on_cp_check_end(nil, nil, {})

   -- Should NOT have built target list (early return)
   assert_equal(0, TargetList.count(), "no targets built from empty check list")
end)

--- Test: CP.start doesn't send "noexp" if already off
-- Covers: CP.start() + Noexp.set() guard
run_test("CP.start_noexp_already_off", function()
   -- If noexp is already off, CP.start should not send noexp command
   CP._on_cp = false
   State._activity = "none"
   Noexp._noexp_on = false
   State._noexp = false

   CP.start()

   -- Should not have sent "noexp" game command (only "cp info")
   local sent_noexp = false
   for _, call in ipairs(mock.calls["SendNoEcho"] or {}) do
      if call[1] == "noexp" then sent_noexp = true end
   end
   assert_false(sent_noexp, "no noexp command when already off")
end)

--- Test: CP.clear resets all CP state, clears target list and activity
-- Covers: CP.clear()
run_test("CP.clear", function()
   -- CP.clear() should reset all CP state
   CP._on_cp = true
   CP._level = 50
   CP._info_list = {{mob = "test"}}
   CP._check_list = {{mob = "test"}}
   State._activity = "cp"
   State._target = {keyword = "test", name = "test mob"}
   TargetList._main_list = {{mob = "test"}}

   CP.clear()

   assert_false(CP._on_cp, "CP off after clear")
   assert_equal(0, CP._level, "level reset")
   assert_equal(0, #CP._info_list, "info list cleared")
   assert_equal(0, #CP._check_list, "check list cleared")
   assert_equal("none", State.get_activity(), "activity back to none")
   assert_nil(State.get_target(), "target cleared")
   assert_equal(0, TargetList.count(), "target list cleared")
end)

--- Test: Placeholder for Phase 5 GQ coexistence on CP.clear
-- Covers: CP.clear() TODO Phase 5
run_test("CP.clear_preserves_gq", function()
   -- TODO Phase 5: When GQ coexistence is implemented, CP.clear()
   -- should preserve GQ state if State._activity == "gq".
   -- For now, it clears everything.
   assert_true(true, "placeholder for Phase 5 GQ coexistence test")
end)

--- Test: Kill current target → cp check refresh → auto-advance to next alive
-- Setup: 2 alive targets, select first, simulate kill + refresh with first dead
-- Expected: auto-selects second (alive) target
-- Covers: on_cp_check_end() target re-matching, auto-advance on dead
run_test("CP.check_end_current_target_died", function()
   -- Simulate: target was set, mob killed, cp check shows it dead
   -- Should auto-select next alive target
   CP._on_cp = true
   CP._type = "area"
   CP._level = 45
   State._activity = "cp"
   mock.reset_db()
   DB.init()

   -- First build: two alive targets
   CP._check_list = {
      {mob = "a sinister vandal", location = "The Three Pillars of Diatz", dead = false},
      {mob = "a mutated goat", location = "The Killing Fields", dead = false},
   }
   on_cp_check_end(nil, nil, {})
   -- Select first target
   State.set_target(TargetList.get(1))
   assert_equal("a sinister vandal", State.get_target().mob, "first target selected")

   -- Simulate mob kill: save target, rebuild with first target now dead
   CP._last_target = State.get_target()
   mock.reset()
   CP._check_list = {
      {mob = "a sinister vandal", location = "The Three Pillars of Diatz", dead = true},
      {mob = "a mutated goat", location = "The Killing Fields", dead = false},
   }
   on_cp_check_end(nil, nil, {})

   -- Current target (vandal) is now dead — should auto-select next alive target (goat)
   local target = State.get_target()
   assert_not_nil(target, "target auto-selected after kill")
   assert_equal("a mutated goat", target.mob, "auto-selected next alive target")
end)

--- Test: Different target dies → current target preserved
-- Setup: select goat, vandal dies in refresh
-- Expected: goat still selected
-- Covers: on_cp_check_end() re-matching preserves alive current target
run_test("CP.check_end_different_target_died", function()
   -- Simulate: our target is alive, but a different target died
   -- Should keep current target
   CP._on_cp = true
   CP._type = "area"
   CP._level = 45
   State._activity = "cp"
   mock.reset_db()
   DB.init()

   -- First build: two alive
   CP._check_list = {
      {mob = "a sinister vandal", location = "The Three Pillars of Diatz", dead = false},
      {mob = "a mutated goat", location = "The Killing Fields", dead = false},
   }
   on_cp_check_end(nil, nil, {})
   -- Select second target (goat)
   State.set_target(TargetList.get(2))

   -- Simulate: a kill happened (not ours), vandal died
   CP._last_target = State.get_target()
   mock.reset()
   CP._check_list = {
      {mob = "a sinister vandal", location = "The Three Pillars of Diatz", dead = true},
      {mob = "a mutated goat", location = "The Killing Fields", dead = false},
   }
   on_cp_check_end(nil, nil, {})

   -- Our target (goat) is still alive — should keep it
   local target = State.get_target()
   assert_not_nil(target, "target preserved")
   assert_equal("a mutated goat", target.mob, "kept current alive target")
end)

--- Test: All targets dead after refresh → target cleared
-- Covers: on_cp_check_end() all-dead path
run_test("CP.check_end_all_dead", function()
   -- All targets dead — should clear target
   CP._on_cp = true
   CP._type = "area"
   CP._level = 45
   State._activity = "cp"
   mock.reset_db()
   DB.init()

   CP._last_target = {mob = "a sinister vandal", keyword = "sinis vanda"}
   CP._check_list = {
      {mob = "a sinister vandal", location = "The Three Pillars of Diatz", dead = true},
      {mob = "a mutated goat", location = "The Killing Fields", dead = true},
   }
   on_cp_check_end(nil, nil, {})

   -- No alive targets — should have no target
   assert_nil(State.get_target(), "no target when all dead")
end)

--- Test: check_tnl does NOT turn noexp ON while CP is active
-- Setup: TNL < cutoff, but CP._on_cp = true
-- Expected: noexp stays off
-- Covers: Noexp.check_tnl() CP._on_cp guard
run_test("Noexp.check_tnl_skips_during_cp", function()
   -- check_tnl should NOT turn noexp ON while on a CP
   Noexp._auto_enabled = true
   Noexp._noexp_on = false
   Noexp._tnl_cutoff = 500
   State._tnl = 200  -- below cutoff
   State._level = 50
   CP._on_cp = true  -- on a CP

   Noexp.check_tnl()

   assert_false(Noexp._noexp_on, "noexp stays off during CP even when TNL < cutoff")
   assert_nil(mock.calls["SendNoEcho"], "no noexp command sent during CP")
end)

--- Test: CP info callbacks parse level, accumulate targets from test data
-- Input: on_cp_info_level + on_cp_info_start + 5x on_cp_info_line from TestData
-- Expected: CP._level=45, 5 targets in CP._info_list with correct mob/location
-- Covers: on_cp_info_level(), on_cp_info_start(), on_cp_info_line()
run_test("CP.info_parse_flow", function()
   -- Simulate cp info output by calling trigger callbacks directly
   CP._on_cp = false
   CP._info_list = {}
   CP._level = 0

   on_cp_info_level(nil, nil, {[1] = "45"})
   assert_equal(45, CP._level, "level captured from cp info")

   on_cp_info_start(nil, nil, {})
   assert_equal(0, #CP._info_list, "info list cleared on start")

   -- Feed the cp info lines from test data
   for _, target in ipairs(TestData.cp_info_area_parsed.targets) do
      on_cp_info_line(nil, nil, {[1] = target.mob, [2] = target.location})
   end
   assert_equal(5, #CP._info_list, "5 targets parsed from cp info")
   assert_equal("a sinister vandal", CP._info_list[1].mob, "first mob name correct")
   assert_equal("The Three Pillars of Diatz", CP._info_list[1].location, "first location correct")
end)

--- Test: on_cp_info_end sets CP._on_cp and activity (handles mid-campaign plugin load)
-- Setup: CP._on_cp = false, State._activity = "none", CP._info_list populated
-- Input: on_cp_info_end() callback
-- Expected: CP._on_cp = true, activity = "cp", type detected, cp check scheduled
-- Covers: on_cp_info_end() CP state setting, type detection, DoAfterSpecial chain
run_test("CP.info_end_sets_cp_state", function()
   -- Simulate: plugin loaded mid-campaign, cp info parsed but CP.start() never called
   CP._on_cp = false
   CP._info_list = {
      {mob = "a sinister vandal", location = "The Three Pillars of Diatz"},
      {mob = "a mutated goat", location = "The Killing Fields"},
   }
   State._activity = "none"
   mock.reset()

   on_cp_info_end(nil, nil, {})

   -- Should set CP as active (mid-campaign pickup)
   assert_true(CP._on_cp, "CP._on_cp set to true by info end")
   assert_equal("cp", State.get_activity(), "activity set to cp")

   -- Should detect type from info list
   assert_not_nil(CP._type, "CP type detected")

   -- Should schedule cp check via DoAfterSpecial
   local timer_calls = mock.calls["DoAfterSpecial"]
   assert_not_nil(timer_calls, "DoAfterSpecial called to chain cp check")
end)

--- Test: CP check callbacks parse targets with dead flag, build target list
-- Input: 4 check lines (3 alive, 1 dead), then on_cp_check_end
-- Expected: 4 targets in TargetList, alive first, dead last
-- Covers: on_cp_check_line(), on_cp_check_end(), TargetList.build()
run_test("CP.check_parse_flow", function()
   -- Simulate cp check output
   CP._check_list = {}
   CP._type = "area"
   CP._level = 45
   State._activity = "none"
   mock.reset_db()
   DB.init()

   -- Feed check lines (alive and dead)
   on_cp_check_line(nil, nil, {[1] = "a sinister vandal", [2] = "The Three Pillars of Diatz", [3] = false})
   on_cp_check_line(nil, nil, {[1] = "a mutated goat", [2] = "The Killing Fields", [3] = "Dead"})
   assert_equal(2, #CP._check_list, "2 check lines parsed")
   assert_false(CP._check_list[1].dead, "first target alive")
   assert_true(CP._check_list[2].dead, "second target dead")

   -- Simulate check end — this builds the target list
   on_cp_check_end(nil, nil, {})
   assert_true(CP._on_cp, "CP active after check end")
   assert_equal("cp", State.get_activity(), "activity is cp")
   assert_equal(2, TargetList.count(), "target list built with 2 targets")
end)

--- Test: on_cp_mob_killed saves target and schedules cp check refresh
-- Covers: on_cp_mob_killed(), DoAfterSpecial scheduling
run_test("CP.mob_killed_refreshes", function()
   -- Simulate: CP active, target set, mob killed
   CP._on_cp = true
   State._activity = "cp"
   local target = {mob = "a test mob", keyword = "test", area = "testarea", index = 1}
   State.set_target(target)
   mock.reset()  -- clear call log

   on_cp_mob_killed(nil, nil, {})

   -- Should have saved the target for re-matching
   assert_not_nil(CP._last_target, "last target saved for re-matching")
   assert_equal("a test mob", CP._last_target.mob, "last target mob preserved")

   -- Should have scheduled a cp check via DoAfterSpecial
   assert_not_nil(mock.calls["DoAfterSpecial"], "DoAfterSpecial called")
end)

--- Test: on_cp_complete calls CP.clear() — resets all CP state
-- Covers: on_cp_complete()
run_test("CP.events_complete_clears", function()
   CP._on_cp = true
   State._activity = "cp"
   mock.reset()

   on_cp_complete(nil, nil, {})

   assert_false(CP._on_cp, "CP off after complete")
   assert_equal("none", State.get_activity(), "activity none after complete")
end)

--- Test: on_cp_cleared calls CP.clear()
-- Covers: on_cp_cleared()
run_test("CP.events_cleared", function()
   CP._on_cp = true
   State._activity = "cp"

   on_cp_cleared(nil, nil, {})

   assert_false(CP._on_cp, "CP off after cleared")
end)

--- Test: on_cp_not_on clears CP when CP was active
-- Covers: on_cp_not_on()
run_test("CP.events_not_on", function()
   CP._on_cp = true
   State._activity = "cp"

   on_cp_not_on(nil, nil, {})

   assert_false(CP._on_cp, "CP off after not_on")
end)

--- Test: on_cp_not_on is no-op when not on CP (no broadcast)
-- Covers: on_cp_not_on() guard
run_test("CP.events_not_on_noop", function()
   -- If not on CP, not_on should be a no-op
   CP._on_cp = false
   State._activity = "none"
   mock.reset()

   on_cp_not_on(nil, nil, {})

   -- Should not have broadcast anything
   assert_nil(mock.calls["BroadcastPlugin"], "no broadcast when already not on CP")
end)

--- Test: on_cp_new_available sets can_get_new flag
-- Covers: on_cp_new_available()
run_test("CP.events_new_available", function()
   CP._can_get_new = false

   on_cp_new_available(nil, nil, {})

   assert_true(CP._can_get_new, "can get new after new_available")
end)

--- Test: on_cp_must_level clears can_get_new and turns noexp off
-- Covers: on_cp_must_level(), Noexp.set()
run_test("CP.events_must_level_noexp_off", function()
   CP._can_get_new = true
   Noexp._noexp_on = true
   State._noexp = true
   mock.reset()

   on_cp_must_level(nil, nil, {})

   assert_false(CP._can_get_new, "can't get new after must_level")
   assert_false(Noexp._noexp_on, "noexp off after must_level")
end)

--- Test: check_tnl turns noexp ON when TNL < cutoff and NOT on CP
-- Covers: Noexp.check_tnl() normal activation path
run_test("Noexp.check_tnl_activates_without_cp", function()
   -- check_tnl SHOULD turn noexp ON when not on CP and TNL < cutoff
   Noexp._auto_enabled = true
   Noexp._noexp_on = false
   Noexp._tnl_cutoff = 500
   State._tnl = 200  -- below cutoff
   State._level = 50
   CP._on_cp = false  -- NOT on a CP

   Noexp.check_tnl()

   assert_true(Noexp._noexp_on, "noexp turns on when TNL < cutoff and not on CP")
end)
