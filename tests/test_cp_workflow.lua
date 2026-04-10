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
   -- Reset hunting modules
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

--- Test: xcp 1 selects first target, resolves area key, navigates, sets arrival callback
-- Expected: target set with mob/area_key/keyword, mapper goto called, Nav._on_arrive set
-- Covers: cmd_xcp() → State.set_target() + Nav.goto_area() + _on_arrive callback
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

   -- Arrival callback should be set for post-navigation action
   assert_not_nil(Nav._on_arrive, "arrival callback set for area target")
   assert_equal("function", type(Nav._on_arrive), "arrival callback is a function")
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

--- Test: xcp picks up existing campaign when plugin loaded mid-CP
-- Setup: CP._on_cp = false, no targets (plugin just loaded)
-- Input: cmd_xcp("") triggers pickup, then simulate full info→check pipeline
-- Expected: CP detected, targets built, CP._on_cp = true
-- Covers: cmd_xcp() pickup path → CP.do_info() → on_cp_info_end() → CP.do_check() → on_cp_check_end()
run_test("workflow.xcp_picks_up_existing_cp", function()
   -- Plugin loaded mid-campaign: CP state is clean
   CP._on_cp = false
   CP._info_list = {}
   CP._check_list = {}
   CP._level = 0
   CP._type = "area"
   CP._last_check_time = 0
   State._activity = "none"
   TargetList.clear()
   State.clear_target()
   mock.reset()
   mock.reset_db()
   DB.init()

   -- User types "xcp" — should trigger pickup attempt
   cmd_xcp(nil, nil, {[1] = ""})

   -- Verify CP.do_info() was called
   local send_calls = mock.calls["SendNoEcho"]
   assert_not_nil(send_calls, "SendNoEcho called")
   assert_equal("cp info", send_calls[1][1], "sends cp info")

   -- Simulate server responding with cp info output
   on_cp_info_level(nil, nil, {[1] = "10"})
   on_cp_info_start(nil, nil, {})
   on_cp_info_line(nil, nil, {[1] = "an old woman", [2] = "Dortmund"})
   on_cp_info_line(nil, nil, {[1] = "hatred", [2] = "Fantasy Fields"})
   on_cp_info_end(nil, nil, {})

   -- After info end: CP should be active
   assert_true(CP._on_cp, "CP active after info end")
   assert_equal("cp", State.get_activity(), "activity is cp")
   assert_equal(10, CP._level, "level captured")

   -- Simulate cp check response (chained by DoAfterSpecial)
   CP._last_check_time = 0  -- reset cooldown for test
   CP._check_list = {}
   on_cp_check_line(nil, nil, {[1] = "an old woman", [2] = "Dortmund", [3] = false})
   on_cp_check_line(nil, nil, {[1] = "hatred", [2] = "Fantasy Fields", [3] = false})
   on_cp_check_end(nil, nil, {})

   -- Target list should be built
   assert_equal(2, TargetList.count(), "target list built with 2 targets")
   assert_equal(2, #TargetList.get_alive(), "both targets alive")
end)

------------------------------------------------------------------------
-- Phase 3: Hunting tool integration workflows
------------------------------------------------------------------------

--- Helper: set up a CP with targets and create mapper DB fixture
local mapper_db_path = "/tmp/test_data/Aardwolf.db"

local function setup_cp_with_mapper()
   -- Create mapper DB fixture
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
      INSERT INTO rooms VALUES ('1260', 'A Narrow Passage', 'diatz');
   ]])
   db:close()

   -- Simulate CP with targets
   CP._on_cp = true
   CP._type = "area"
   CP._level = 45
   State._activity = "cp"
   local check_list = {
      {mob = "a sinister vandal", location = "The Three Pillars of Diatz", dead = false},
      {mob = "a mutated goat", location = "The Killing Fields", dead = false},
   }
   TargetList.build(check_list, "area", 45)
end

--- Test: Full flow: xcp → arrive → HT cycles → unable → QW exact → match → goto_list
-- Simulates the complete HT→QW chain from selecting a target
-- Covers: cmd_xcp → HuntTrick.start → on_ht_direction → on_ht_unable → QuickWhere.start_exact → on_qw_match
run_test("workflow.xcp_ht_to_qw_chain", function()
   setup_cp_with_mapper()
   mock.variables["snd_xcp_action_mode"] = "ht"
   Config.load()

   -- Select target 1
   cmd_xcp(nil, nil, {[1] = "1"})
   local target = State.get_target()
   assert_true(target ~= nil, "target selected")

   -- Simulate area arrival
   assert_true(Nav._on_arrive ~= nil, "on_arrive set")
   Nav._on_arrive()
   assert_true(HuntTrick._active, "HT started on arrival")
   assert_equal(1, HuntTrick._index, "HT at index 1")

   -- Simulate HT direction found (mob is north)
   on_ht_direction("trg_ht_direction", "You are certain that a sinister vandal is north from here.",
      {"north", false, false, false, false})
   assert_equal(2, HuntTrick._index, "HT advanced to index 2")

   -- Simulate HT direction again
   on_ht_direction("trg_ht_direction", "You are certain that a sinister vandal is east from here.",
      {"east", false, false, false, false})
   assert_equal(3, HuntTrick._index, "HT advanced to index 3")

   -- Simulate HT unable (all instances exhausted)
   State._room = {rmid = 1254, arid = "diatz", name = "A Room", exits = {}, maze = false}
   on_ht_unable("trg_ht_unable", "You seem unable to hunt that target for some reason.", {})
   assert_false(HuntTrick._active, "HT reset after unable")
   assert_true(QuickWhere._active, "QW started after HT unable")
   assert_true(QuickWhere._exact, "QW in exact mode")
   assert_equal(3, QuickWhere._index, "QW at HT's last index")
   assert_true(QuickWhere._auto_go, "QW has auto_go from HT")

   -- Simulate QW match
   on_qw_match("trg_qw_match", "a sinister vandal              A Dusty Room",
      {"a sinister vandal             ", "A Dusty Room"})
   assert_false(QuickWhere._active, "QW reset after match")
   assert_true(#Nav._goto_list > 0, "goto_list populated from mapper DB")

   os.remove(mapper_db_path)
end)

--- Test: Full flow: xcp → arrive → QW → match → goto_list built with auto_go
-- Covers: cmd_xcp → QuickWhere.start_exact → on_qw_match → Nav.build_goto_list
run_test("workflow.xcp_qw_direct", function()
   setup_cp_with_mapper()
   mock.variables["snd_xcp_action_mode"] = "qw"
   Config.load()

   -- Select target 1
   cmd_xcp(nil, nil, {[1] = "1"})
   local target = State.get_target()
   assert_true(target ~= nil, "target selected")

   -- Simulate area arrival
   Nav._on_arrive()
   assert_true(QuickWhere._active, "QW started on arrival")
   assert_true(QuickWhere._exact, "QW in exact mode")
   assert_true(QuickWhere._auto_go, "QW with auto_go")

   -- Simulate QW match
   State._room = {rmid = 1254, arid = "diatz", name = "A Room", exits = {}, maze = false}
   on_qw_match("trg_qw_match", "a sinister vandal              A Dusty Room",
      {"a sinister vandal             ", "A Dusty Room"})
   assert_false(QuickWhere._active, "QW reset after match")
   assert_true(#Nav._goto_list > 0, "goto_list populated")
   assert_true(Nav._goto_index > 0, "auto_go advanced goto_index")

   os.remove(mapper_db_path)
end)

--- Test: HT "here" chains to QW exact to identify room
-- Covers: on_ht_here → QuickWhere.start_exact
run_test("workflow.ht_here_chains_qw", function()
   setup_cp_with_mapper()

   -- Start HT directly
   State._target = TargetList.get(1)
   HuntTrick._auto_go = true
   HuntTrick.start(1, State._target.keyword)

   -- Simulate "here" after some cycling
   HuntTrick._index = 5
   State._room = {rmid = 1254, arid = "diatz", name = "A Room", exits = {}, maze = false}
   on_ht_here("trg_ht_here", "A sinister vandal is here!", {})
   assert_false(HuntTrick._active, "HT reset")
   assert_true(QuickWhere._active, "QW started from 'here'")
   assert_true(QuickWhere._exact, "QW in exact mode")
   assert_equal(5, QuickWhere._index, "QW at HT's index")

   os.remove(mapper_db_path)
end)

--- Test: HT not_found on first target falls back to QW
-- Covers: on_ht_not_found first_target → QuickWhere.start_exact
run_test("workflow.ht_not_found_fallback_qw", function()
   setup_cp_with_mapper()

   State._target = TargetList.get(1)
   HuntTrick._auto_go = true
   HuntTrick.start(1, State._target.keyword)
   assert_true(HuntTrick._first_target, "first_target is true")

   on_ht_not_found("trg_ht_not_found", "No one in this area by the name 'sinister'.", {})
   assert_false(HuntTrick._active, "HT reset")
   assert_true(QuickWhere._active, "QW started as fallback")
   assert_true(QuickWhere._exact, "QW in exact mode")

   os.remove(mapper_db_path)
end)
