------------------------------------------------------------------------
-- test_cp_workflow.lua - Integration test: full CP workflow end-to-end
-- Simulates: request CP → cp info → cp check → target list → xcp →
--            navigate → kill → refresh → complete
------------------------------------------------------------------------

if not CONST then
   local load_plugin = require("load_plugin")
   load_plugin()
end

local TestData = require("test_data")

function setUp()
   mock.reset()
   mock.reset_db()
   DB.init()
   -- Reset all module state
   CP._on_cp = false
   CP._level = 0
   CP._type = "area"
   CP._info_list = {}
   CP._check_list = {}
   CP._can_get_new = false
   CP._last_check_time = 0
   CP._last_target = nil
   TargetList._main_list = {}
   TargetList._type = "none"
   Nav._goto_list = {}
   Nav._goto_index = 0
   Nav._dest_area = nil
   Nav._dest_room = nil
   Nav._on_arrive = nil
   Nav._vidblain_dest = nil
   State._room = {rmid = 32418, arid = "aylor", name = "Aylor", exits = {}, maze = false}
   State._prev_room = {rmid = -2, arid = ""}
   State._target = nil
   State._activity = "none"
   State._char_state = "3"
   State._noexp = false
   State._level = 45
   State._tnl = 1000
   State._dirty = false
   Noexp._auto_enabled = true
   Noexp._noexp_on = false
   Noexp._tnl_cutoff = 500
end

function tearDown()
   mock.reset_db()
end

------------------------------------------------------------------------
-- Full CP workflow: area-based campaign
------------------------------------------------------------------------

--- Test: "Good luck!" trigger starts CP flow (state + cp info sent)
-- Covers: on_cp_request() → CP.start() → CP.do_info()
run_test("workflow.cp_request_starts_flow", function()
   -- Step 1: NPC says "Good luck!" → CP.start() fires
   on_cp_request(nil, nil, {})

   assert_true(CP._on_cp, "CP active after request")
   assert_equal("cp", State.get_activity(), "activity is cp")
   -- Should have sent "cp info"
   local sent = false
   for _, call in ipairs(mock.calls["SendNoEcho"] or {}) do
      if call[1] == "cp info" then sent = true end
   end
   assert_true(sent, "cp info sent after request")
end)

--- Test: CP request turns noexp off (player needs XP for fighting)
-- Covers: CP.start() → Noexp.set(false)
run_test("workflow.cp_request_turns_noexp_off", function()
   -- Noexp is on (player was protecting from leveling)
   Noexp._noexp_on = true
   State._noexp = true

   on_cp_request(nil, nil, {})

   assert_false(Noexp._noexp_on, "noexp turned off on CP start")
end)

--- Test: CP info parsing → type detection → chains to cp check via DoAfterSpecial
-- Input: full cp info output from TestData (5 targets)
-- Covers: on_cp_info_level/start/line/end(), detect_type, DoAfterSpecial chain
run_test("workflow.cp_info_to_check_chain", function()
   -- Step 2: Simulate cp info output
   on_cp_request(nil, nil, {})
   mock.reset()

   -- cp info arrives
   on_cp_info_level(nil, nil, {[1] = "45"})
   on_cp_info_start(nil, nil, {})

   for _, target in ipairs(TestData.cp_info_area_parsed.targets) do
      on_cp_info_line(nil, nil, {[1] = target.mob, [2] = target.location})
   end

   assert_equal(45, CP._level, "level captured")
   assert_equal(5, #CP._info_list, "5 targets from cp info")

   -- cp info end → detect type, schedule cp check
   on_cp_info_end(nil, nil, {})

   assert_equal("area", CP._type, "area type detected")
   -- cp check should be scheduled via DoAfterSpecial
   assert_not_nil(mock.calls["DoAfterSpecial"], "cp check scheduled")
end)

--- Test: CP check parsing builds target list with alive-first sorting
-- Input: 4 check lines (3 alive, 1 dead)
-- Expected: 4 targets, 3 alive first, dead last
-- Covers: on_cp_check_line/end() → TargetList.build()
run_test("workflow.cp_check_builds_target_list", function()
   -- Set up CP state as if cp info already completed
   CP._on_cp = true
   CP._type = "area"
   CP._level = 45
   State._activity = "cp"
   CP._last_check_time = 0

   -- Step 3: Simulate cp check output
   on_cp_check_line(nil, nil, {[1] = "a sinister vandal", [2] = "The Three Pillars of Diatz", [3] = false})
   on_cp_check_line(nil, nil, {[1] = "a mutated goat", [2] = "The Killing Fields", [3] = false})
   on_cp_check_line(nil, nil, {[1] = "a dancing female patron", [2] = "Wayward Alehouse", [3] = false})
   on_cp_check_line(nil, nil, {[1] = "a dangerous scorpion", [2] = "Desert Doom", [3] = "Dead"})

   assert_equal(4, #CP._check_list, "4 check lines parsed")

   on_cp_check_end(nil, nil, {})

   -- Target list should be built
   assert_equal(4, TargetList.count(), "4 targets in list")
   -- Alive targets should be first (3 alive, 1 dead)
   local alive = TargetList.get_alive()
   assert_equal(3, #alive, "3 alive targets")
   -- Dead target should be last
   local last = TargetList.get(4)
   assert_true(last.dead, "dead target is last")
   assert_equal("a dangerous scorpion", last.mob, "dead target is scorpion")
end)

--- Test: xcp 1 selects first target, resolves area key, navigates
-- Expected: target set with mob/area_key/keyword, mapper goto called
-- Covers: cmd_xcp() → State.set_target() + Nav.goto_area()
run_test("workflow.xcp_selects_and_navigates", function()
   -- Set up: CP active with targets
   CP._on_cp = true
   CP._type = "area"
   CP._level = 45
   State._activity = "cp"
   local check_list = {
      {mob = "a sinister vandal", location = "The Three Pillars of Diatz", dead = false},
      {mob = "a mutated goat", location = "The Killing Fields", dead = false},
   }
   TargetList.build(check_list, "area", 45)
   mock.reset()

   -- Step 4: User types "xcp 1" → select first target + navigate
   cmd_xcp(nil, nil, {[1] = "1"})

   -- Target should be set
   local target = State.get_target()
   assert_not_nil(target, "target selected")
   assert_equal("a sinister vandal", target.mob, "first alive target")
   assert_equal("diatz", target.area_key, "area key resolved")
   assert_not_nil(target.keyword, "keyword generated")

   -- Navigation should have been initiated
   local navigated = false
   for _, call in ipairs(mock.calls["Execute"] or {}) do
      if type(call[1]) == "string" and call[1]:match("^mapper goto") then
         navigated = true
      end
   end
   assert_true(navigated, "navigation initiated to target area")
end)

--- Test: xcp 2 selects second target specifically
-- Covers: cmd_xcp() numeric index selection
run_test("workflow.xcp_numeric_selects_specific", function()
   CP._on_cp = true
   CP._type = "area"
   State._activity = "cp"
   local check_list = {
      {mob = "a sinister vandal", location = "The Three Pillars of Diatz", dead = false},
      {mob = "a mutated goat", location = "The Killing Fields", dead = false},
   }
   TargetList.build(check_list, "area", 45)
   mock.reset()

   -- Step 4b: User types "xcp 2" → select second target
   cmd_xcp(nil, nil, {[1] = "2"})

   local target = State.get_target()
   assert_equal("a mutated goat", target.mob, "second target selected")
end)

--- Test: GMCP room.info arrival in target area fires on_arrive callback
-- Covers: Nav.on_room_change() area arrival detection
run_test("workflow.arrival_in_area", function()
   -- Set up: navigating to diatz
   Nav._dest_area = "diatz"
   local arrived_callback_fired = false
   Nav._on_arrive = function() arrived_callback_fired = true end

   -- Step 5: GMCP room.info says we arrived in diatz
   Nav.on_room_change({num = 1254, zone = "diatz", name = "The Three Pillars"})

   assert_true(arrived_callback_fired, "arrival callback fired")
   assert_nil(Nav._dest_area, "dest_area cleared")
end)

--- Test: Mob kill saves target for re-match and schedules cp check refresh
-- Covers: on_cp_mob_killed() → CP._last_target + DoAfterSpecial
run_test("workflow.mob_killed_refreshes_list", function()
   -- Set up: CP active, target selected, 2 alive targets
   CP._on_cp = true
   CP._type = "area"
   CP._level = 45
   State._activity = "cp"
   local check_list = {
      {mob = "a sinister vandal", location = "The Three Pillars of Diatz", dead = false},
      {mob = "a mutated goat", location = "The Killing Fields", dead = false},
   }
   TargetList.build(check_list, "area", 45)
   State.set_target(TargetList.get(1))
   mock.reset()

   -- Step 6: "Congratulations!" → mob killed
   on_cp_mob_killed(nil, nil, {})

   -- Should have saved target and scheduled cp check
   assert_not_nil(CP._last_target, "target saved for re-match")
   assert_not_nil(mock.calls["DoAfterSpecial"], "cp check scheduled")
end)

--- Test: After kill, cp check refresh auto-advances to next alive target
-- Setup: vandal selected → kill → refresh shows vandal dead
-- Expected: auto-selects goat (next alive)
-- Covers: on_cp_check_end() re-matching with dead detection + auto-advance
run_test("workflow.refresh_after_kill_auto_advances", function()
   -- Set up: CP active, target was vandal (now dead after kill)
   CP._on_cp = true
   CP._type = "area"
   CP._level = 45
   State._activity = "cp"

   -- First build: both alive
   local check_list = {
      {mob = "a sinister vandal", location = "The Three Pillars of Diatz", dead = false},
      {mob = "a mutated goat", location = "The Killing Fields", dead = false},
   }
   TargetList.build(check_list, "area", 45)
   State.set_target(TargetList.get(1))

   -- Simulate kill: save target, then rebuild with vandal dead
   CP._last_target = State.get_target()
   CP._last_check_time = 0
   CP._check_list = {
      {mob = "a sinister vandal", location = "The Three Pillars of Diatz", dead = true},
      {mob = "a mutated goat", location = "The Killing Fields", dead = false},
   }
   on_cp_check_end(nil, nil, {})

   -- Should auto-advance to goat (first alive after vandal died)
   local target = State.get_target()
   assert_not_nil(target, "target auto-advanced")
   assert_equal("a mutated goat", target.mob, "auto-advanced to goat")
end)

--- Test: CP complete resets all state (CP, target, target list, activity)
-- Covers: on_cp_complete() → CP.clear()
run_test("workflow.cp_complete_clears_everything", function()
   -- Set up: CP active
   CP._on_cp = true
   State._activity = "cp"
   State._target = {keyword = "test", mob = "test mob", area_key = "test"}
   TargetList._main_list = {{mob = "test"}}
   mock.reset()

   -- Step 7: "CONGRATULATIONS!" → CP complete
   on_cp_complete(nil, nil, {})

   assert_false(CP._on_cp, "CP cleared")
   assert_equal("none", State.get_activity(), "activity none")
   assert_nil(State.get_target(), "target cleared")
   assert_equal(0, TargetList.count(), "target list cleared")
end)

--- Test: "You may take another campaign" sets can_get_new flag
-- Covers: on_cp_new_available()
run_test("workflow.new_cp_available_after_complete", function()
   CP._can_get_new = false

   on_cp_new_available(nil, nil, {})

   assert_true(CP._can_get_new, "can get new CP")
end)

--- Test: After CP complete, noexp activates when TNL < cutoff and not on CP
-- Covers: Noexp.check_tnl() post-CP normal activation
run_test("workflow.noexp_activates_when_not_on_cp", function()
   -- After CP complete, TNL < cutoff, not on CP → noexp should activate
   CP._on_cp = false
   Noexp._auto_enabled = true
   Noexp._noexp_on = false
   Noexp._tnl_cutoff = 500
   State._tnl = 200
   State._level = 45
   mock.reset()

   Noexp.check_tnl()

   assert_true(Noexp._noexp_on, "noexp on when TNL < cutoff and not on CP")
end)

--- Test: During active CP, noexp stays off even when TNL < cutoff
-- Covers: Noexp.check_tnl() CP._on_cp guard
run_test("workflow.noexp_stays_off_during_cp", function()
   -- During CP, TNL < cutoff → noexp should NOT activate
   CP._on_cp = true
   Noexp._auto_enabled = true
   Noexp._noexp_on = false
   Noexp._tnl_cutoff = 500
   State._tnl = 200
   State._level = 45
   mock.reset()

   Noexp.check_tnl()

   assert_false(Noexp._noexp_on, "noexp stays off during CP")
end)

--- Test: FULL CYCLE — request → info → check → select → kill → refresh → kill → complete
-- Simulates entire CP lifecycle: 2 targets, kill both, complete.
-- Verifies state at each step: activity, target list, auto-advance, cleanup.
-- Covers: CP.start, on_cp_info_*, on_cp_check_*, cmd_xcp, on_cp_mob_killed, on_cp_complete
run_test("workflow.full_cycle_request_to_complete", function()
   -- Complete cycle: request → info → check → select → kill → check → complete

   -- 1. Request CP
   on_cp_request(nil, nil, {})
   assert_true(CP._on_cp, "1: CP active")

   -- 2. CP info arrives
   on_cp_info_level(nil, nil, {[1] = "45"})
   on_cp_info_start(nil, nil, {})
   on_cp_info_line(nil, nil, {[1] = "a sinister vandal", [2] = "The Three Pillars of Diatz"})
   on_cp_info_line(nil, nil, {[1] = "a mutated goat", [2] = "The Killing Fields"})
   on_cp_info_end(nil, nil, {})
   assert_equal("area", CP._type, "2: type detected")

   -- 3. CP check arrives (simulate — normally chained via DoAfterSpecial)
   CP._last_check_time = 0
   on_cp_check_line(nil, nil, {[1] = "a sinister vandal", [2] = "The Three Pillars of Diatz", [3] = false})
   on_cp_check_line(nil, nil, {[1] = "a mutated goat", [2] = "The Killing Fields", [3] = false})
   on_cp_check_end(nil, nil, {})
   assert_equal(2, TargetList.count(), "3: 2 targets")

   -- 4. Select target
   mock.reset()
   cmd_xcp(nil, nil, {[1] = "1"})
   assert_not_nil(State.get_target(), "4: target selected")

   -- 5. Kill mob → refresh
   on_cp_mob_killed(nil, nil, {})
   CP._last_check_time = 0
   CP._check_list = {}
   on_cp_check_line(nil, nil, {[1] = "a sinister vandal", [2] = "The Three Pillars of Diatz", [3] = "Dead"})
   on_cp_check_line(nil, nil, {[1] = "a mutated goat", [2] = "The Killing Fields", [3] = false})
   on_cp_check_end(nil, nil, {})
   -- Should auto-advance to goat
   assert_equal("a mutated goat", State.get_target().mob, "5: auto-advanced to goat")

   -- 6. Kill second mob → all done
   on_cp_mob_killed(nil, nil, {})
   CP._last_check_time = 0
   CP._check_list = {}
   on_cp_check_line(nil, nil, {[1] = "a sinister vandal", [2] = "The Three Pillars of Diatz", [3] = "Dead"})
   on_cp_check_line(nil, nil, {[1] = "a mutated goat", [2] = "The Killing Fields", [3] = "Dead"})
   on_cp_check_end(nil, nil, {})
   -- All dead, no target
   assert_nil(State.get_target(), "6: no target when all dead")

   -- 7. CP complete
   on_cp_complete(nil, nil, {})
   assert_false(CP._on_cp, "7: CP cleared")
   assert_equal("none", State.get_activity(), "7: activity none")
   assert_equal(0, TargetList.count(), "7: list cleared")
end)

--- Test: xset kw override persists through cp check refresh via DB
-- Setup: override keyword, simulate cp check refresh
-- Expected: keyword survives rebuild (DB mob_overrides → MobKeyword.guess stage 1)
-- Covers: cmd_xset "kw", DB.mob_overrides → MobKeyword.guess integration
run_test("workflow.xset_kw_persists_across_refresh", function()
   -- Override keyword, then verify it persists after cp check refresh
   CP._on_cp = true
   CP._type = "area"
   CP._level = 45
   State._activity = "cp"
   local check_list = {
      {mob = "a sinister vandal", location = "The Three Pillars of Diatz", dead = false},
   }
   TargetList.build(check_list, "area", 45)
   State.set_target(TargetList.get(1))

   -- Override keyword
   cmd_xset(nil, nil, {[1] = "kw customkw"})
   assert_equal("customkw", State.get_target().keyword, "keyword overridden")

   -- Refresh list (simulating cp check after kill)
   CP._last_target = State.get_target()
   CP._last_check_time = 0
   CP._check_list = {
      {mob = "a sinister vandal", location = "The Three Pillars of Diatz", dead = false},
   }
   on_cp_check_end(nil, nil, {})

   -- Keyword should persist via DB mob_overrides → MobKeyword.guess Stage 1
   local target = State.get_target()
   assert_not_nil(target, "target re-matched after refresh")
   assert_equal("customkw", target.keyword, "keyword persisted via DB override")
end)
