------------------------------------------------------------------------
-- test_commands.lua - Tests for command handlers (xcp, go, nx, xrt, xset kw)
-- TDD: Tests define expected behavior. Implementation follows.
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
   -- Reset module state
   CP._on_cp = false
   CP._level = 0
   CP._type = "area"
   CP._info_list = {}
   CP._check_list = {}
   CP._can_get_new = false
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
   State._target = nil
   State._activity = "none"
   State._level = 50
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

--- Helper: build a test target list with known targets
local function build_test_targets()
   CP._on_cp = true
   CP._type = "area"
   CP._level = 45
   State._activity = "cp"
   local check_list = {
      {mob = "a sinister vandal", location = "The Three Pillars of Diatz", dead = false},
      {mob = "a mutated goat", location = "The Killing Fields", dead = false},
      {mob = "a dangerous scorpion", location = "Desert Doom", dead = true},
   }
   TargetList.build(check_list, "area", 45)
end

------------------------------------------------------------------------
-- cmd_xcp: target selection
------------------------------------------------------------------------

--- Test: xcp with no arg displays target list (no auto-navigate)
-- Covers: cmd_xcp() no-arg → TargetList.display()
run_test("cmd_xcp.no_arg_displays_list", function()
   build_test_targets()
   mock.reset()

   cmd_xcp(nil, nil, {[1] = ""})

   -- Should display list (ColourNote calls), NOT auto-navigate
   assert_not_nil(mock.calls["ColourNote"], "ColourNote called for list display")
   -- Should NOT have navigated
   assert_nil(mock.calls["Execute"], "no navigation on xcp with no arg")
   -- Target should NOT have been set
   assert_nil(State.get_target(), "no target set on list display")
end)

--- Test: xcp N selects target by index and navigates
-- Covers: cmd_xcp() numeric path → State.set_target() + Nav.goto_area()
run_test("cmd_xcp.numeric_selects_target", function()
   build_test_targets()
   mock.reset()

   cmd_xcp(nil, nil, {[1] = "2"})

   local target = State.get_target()
   assert_not_nil(target, "target selected by index")
   assert_equal("a mutated goat", target.mob, "second target selected")
end)

--- Test: xcp attempts CP pickup when not on CP
-- Setup: CP._on_cp = false (plugin loaded mid-campaign)
-- Input: cmd_xcp with any argument
-- Expected: CP.do_info() called (sends "cp info", enables level+start triggers), no target set (async)
-- Covers: cmd_xcp() CP pickup path → CP.do_info()
run_test("cmd_xcp.not_on_cp", function()
   -- Not on CP — should attempt pickup via CP.do_info()
   CP._on_cp = false
   State._activity = "none"
   mock.reset()

   cmd_xcp(nil, nil, {[1] = "1"})

   assert_nil(State.get_target(), "no target set (pickup is async)")
   -- Verify CP.do_info() was called: sends "cp info" and enables individual triggers
   local send_calls = mock.calls["SendNoEcho"]
   assert_not_nil(send_calls, "SendNoEcho called for cp info")
   assert_equal("cp info", send_calls[1][1], "sends cp info command")
   local level_enabled = false
   local start_enabled = false
   for _, call in ipairs(mock.calls["EnableTrigger"] or {}) do
      if call[1] == "trg_cp_info_level" and call[2] == true then level_enabled = true end
      if call[1] == "trg_cp_info_start" and call[2] == true then start_enabled = true end
   end
   assert_true(level_enabled, "trg_cp_info_level enabled")
   assert_true(start_enabled, "trg_cp_info_start enabled")
end)

--- Test: xcp with invalid index shows error
-- Covers: cmd_xcp() bounds validation
run_test("cmd_xcp.index_out_of_bounds", function()
   build_test_targets()
   mock.reset()

   cmd_xcp(nil, nil, {[1] = "99"})

   assert_nil(State.get_target(), "no target for out-of-bounds index")
end)

--- Test: Alive target at index 1 when dead sorts after alive
-- Covers: cmd_xcp() + TargetList sort (alive first)
run_test("cmd_xcp.numeric_skips_dead", function()
   -- Selecting a dead target by index should still work (user's choice)
   CP._on_cp = true
   CP._type = "area"
   State._activity = "cp"
   local check_list = {
      {mob = "dead mob", location = "The Three Pillars of Diatz", dead = true},
      {mob = "alive mob", location = "The Killing Fields", dead = false},
   }
   TargetList.build(check_list, "area", 45)
   mock.reset()

   -- Select the alive target (index 1 because alive sorts first)
   cmd_xcp(nil, nil, {[1] = "1"})

   local target = State.get_target()
   assert_not_nil(target, "target selected by index")
   assert_equal("alive mob", target.mob, "alive target at index 1")
end)

--- Test: xcp rejects target with unknown link_type
-- Covers: cmd_xcp() link_type validation
run_test("cmd_xcp.unknown_rejected", function()
   -- Build list where target has unknown link_type
   CP._on_cp = true
   CP._type = "area"
   State._activity = "cp"
   local check_list = {
      {mob = "mystery mob", location = "Totally Unknown Area", dead = false},
   }
   TargetList.build(check_list, "area", 45)
   mock.reset()

   cmd_xcp(nil, nil, {[1] = "1"})

   -- Unknown link_type should be rejected
   assert_nil(State.get_target(), "unknown target rejected")
end)

------------------------------------------------------------------------
-- cmd_go: room navigation
------------------------------------------------------------------------

--- Test: go N navigates to gotoList[N] room
-- Covers: cmd_go() numeric room path
run_test("cmd_go.navigates_to_room", function()
   Nav._goto_list = {11111, 22222, 33333}
   Nav._goto_index = 0
   mock.reset()

   cmd_go(nil, nil, {[1] = "1"})

   -- Should navigate to first room
   local found = false
   for _, call in ipairs(mock.calls["Execute"] or {}) do
      if call[1] == "mapper goto 11111" then found = true end
   end
   assert_true(found, "navigated to room 11111")
end)

--- Test: go with no arg defaults to index 1
-- Covers: cmd_go() default index
run_test("cmd_go.no_arg_defaults_to_first", function()
   Nav._goto_list = {11111, 22222}
   Nav._goto_index = 0
   mock.reset()

   cmd_go(nil, nil, {[1] = ""})

   local found = false
   for _, call in ipairs(mock.calls["Execute"] or {}) do
      if call[1] == "mapper goto 11111" then found = true end
   end
   assert_true(found, "no arg defaults to first room")
end)

--- Test: go with empty goto_list shows error, no navigation
-- Covers: cmd_go() empty list guard
run_test("cmd_go.empty_list", function()
   Nav._goto_list = {}
   mock.reset()

   cmd_go(nil, nil, {[1] = "1"})

   -- Should not crash, no navigation
   assert_nil(mock.calls["Execute"], "no Execute for empty goto list")
end)

--- Test: go with string entry in goto_list triggers area navigation
-- Covers: cmd_go() string (area) vs number (room) dispatch
run_test("cmd_go.area_string_entry", function()
   -- gotoList can contain area names (strings) for area-based navigation
   Nav._goto_list = {"diatz", 22222}
   Nav._goto_index = 0
   mock.reset()

   cmd_go(nil, nil, {[1] = "1"})

   -- String entry should trigger area navigation (mapper goto to start room)
   local found = false
   for _, call in ipairs(mock.calls["Execute"] or {}) do
      if type(call[1]) == "string" and call[1]:match("^mapper goto") then
         found = true
      end
   end
   assert_true(found, "area string entry triggers navigation")
end)

------------------------------------------------------------------------
-- cmd_nx: next room
------------------------------------------------------------------------

--- Test: nx advances index and navigates to next room when at current room
-- Setup: at room 11111 (index 1), list has 3 rooms
-- Expected: index → 2, mapper goto 22222
-- Covers: cmd_nx() advance + navigate
run_test("cmd_nx.advances_room", function()
   Nav._goto_list = {11111, 22222, 33333}
   Nav._goto_index = 1
   -- Simulate: we're at room 11111 (current destination)
   State._room = {rmid = 11111, arid = "test", name = "Room 1", exits = {}, maze = false}
   Nav._dest_room = nil  -- already arrived
   mock.reset()

   cmd_nx(nil, nil, {})

   assert_equal(2, Nav._goto_index, "index advanced to 2")
   local found = false
   for _, call in ipairs(mock.calls["Execute"] or {}) do
      if call[1] == "mapper goto 22222" then found = true end
   end
   assert_true(found, "navigated to next room 22222")
end)

--- Test: nx advances after arrival when GMCP delivered num as string
-- Setup: simulate the actual production path — State.update_room({num="11111",...}) then nx
-- Expected: rmid coerced to number → comparison succeeds → index advances → goto next room
-- Covers: cmd_nx() advance + State.update_room() string-num coercion (regression for "already in that room" bug)
run_test("cmd_nx.advances_after_string_num_arrival", function()
   Nav._goto_list = {11111, 22222, 33333}
   Nav._goto_index = 1
   -- Simulate Aardwolf GMCP delivering num as string (the production case)
   State.update_room({num = "11111", zone = "test", name = "Room 1", exits = {}})
   Nav._dest_room = nil
   mock.reset()

   cmd_nx(nil, nil, {})

   assert_equal(2, Nav._goto_index, "index advanced — comparison handled string num")
   local found = false
   for _, call in ipairs(mock.calls["Execute"] or {}) do
      if call[1] == "mapper goto 22222" then found = true end
   end
   assert_true(found, "navigated to next room 22222")
end)

--- Test: nx at end of list does not advance or navigate
-- Covers: cmd_nx() boundary
run_test("cmd_nx.at_end_of_list", function()
   Nav._goto_list = {11111, 22222}
   Nav._goto_index = 2
   State._room = {rmid = 22222, arid = "test", name = "Room 2", exits = {}, maze = false}
   mock.reset()

   cmd_nx(nil, nil, {})

   -- At end of list — should not advance further
   assert_nil(mock.calls["Execute"], "no navigation at end of list")
end)

--- Test: nx with empty list shows error
-- Covers: cmd_nx() empty guard
run_test("cmd_nx.empty_list", function()
   Nav._goto_list = {}
   Nav._goto_index = 0
   mock.reset()

   cmd_nx(nil, nil, {})

   assert_nil(mock.calls["Execute"], "no navigation with empty list")
end)

--- Test: cmd_go cancels any in-flight HT (user taking manual control)
-- Setup: HT active, goto_list has rooms
-- Expected: HT.reset() called, navigation proceeds
-- Covers: cmd_go() HT cancellation
run_test("cmd_go.cancels_ht", function()
   Nav._goto_list = {11111, 22222}
   Nav._goto_index = 0
   State._room = {rmid = 99999, arid = "test", name = "Elsewhere", exits = {}, maze = false}
   HuntTrick._active = true
   HuntTrick._keyword = "wolf"
   mock.reset()

   cmd_go(nil, nil, {[1] = "1"})

   assert_false(HuntTrick._active, "HT cancelled when user types go")
end)

--- Test: cmd_nx cancels any in-flight HT (user taking manual control)
-- Setup: HT active, at first room of list
-- Expected: HT.reset() called, advance to next room
-- Covers: cmd_nx() HT cancellation
run_test("cmd_nx.cancels_ht", function()
   Nav._goto_list = {11111, 22222}
   Nav._goto_index = 1
   State._room = {rmid = 11111, arid = "test", name = "Room 1", exits = {}, maze = false}
   HuntTrick._active = true
   HuntTrick._keyword = "wolf"
   mock.reset()

   cmd_nx(nil, nil, {})

   assert_false(HuntTrick._active, "HT cancelled when user types nx")
end)

------------------------------------------------------------------------
-- cmd_xrt: area runto
------------------------------------------------------------------------

--- Test: xrt navigates to area start room via fuzzy match
-- Covers: cmd_xrt() → Nav.fuzzy_match_area() + Nav.goto_area()
run_test("cmd_xrt.navigates_to_area", function()
   mock.reset()

   cmd_xrt(nil, nil, {[1] = "diatz"})

   local found = false
   for _, call in ipairs(mock.calls["Execute"] or {}) do
      if call[1] == "mapper goto 1254" then found = true end
   end
   assert_true(found, "xrt navigates to diatz start room")
end)

--- Test: xrt with partial area name fuzzy matches
-- Covers: cmd_xrt() fuzzy matching
run_test("cmd_xrt.fuzzy_match", function()
   mock.reset()

   cmd_xrt(nil, nil, {[1] = "dia"})

   -- Should fuzzy match to diatz
   local found = false
   for _, call in ipairs(mock.calls["Execute"] or {}) do
      if call[1] == "mapper goto 1254" then found = true end
   end
   assert_true(found, "xrt fuzzy matches dia to diatz")
end)

--- Test: xrt with no arg shows error
-- Covers: cmd_xrt() empty arg guard
run_test("cmd_xrt.no_arg_error", function()
   mock.reset()

   cmd_xrt(nil, nil, {[1] = ""})

   -- Should not navigate, show error
   assert_nil(mock.calls["Execute"], "no navigation with empty xrt arg")
end)

--- Test: xrt with unknown area shows error, no navigation
-- Covers: cmd_xrt() unknown area path
run_test("cmd_xrt.unknown_area", function()
   mock.reset()

   cmd_xrt(nil, nil, {[1] = "zzzznonexistent"})

   assert_nil(mock.calls["Execute"], "no navigation for unknown area")
end)

------------------------------------------------------------------------
-- xset kw: keyword override for current target
------------------------------------------------------------------------

--- Test: xset kw <keyword> overrides current target's keyword in target + list
-- Covers: cmd_xset() "kw" path → State target + TargetList update
run_test("xset_kw.overrides_current_target", function()
   build_test_targets()
   -- Select first target
   State.set_target(TargetList.get(1))
   assert_match("sinis", State.get_target().keyword, "default keyword before override")
   mock.reset()

   -- Override keyword via xset
   cmd_xset(nil, nil, {[1] = "kw newkeyword"})

   -- Current target keyword should be updated
   assert_equal("newkeyword", State.get_target().keyword, "keyword overridden on current target")
   -- TargetList entry should also be updated
   assert_equal("newkeyword", TargetList.get(1).keyword, "keyword overridden in target list")
end)

--- Test: xset kw persists keyword to DB mob_overrides
-- Covers: cmd_xset() "kw" → DB.execute INSERT mob_overrides
run_test("xset_kw.saves_to_db", function()
   build_test_targets()
   State.set_target(TargetList.get(1))
   mock.reset()

   cmd_xset(nil, nil, {[1] = "kw testkw"})

   -- Should be saved in mob_overrides DB
   local override = DB.get_mob_override("a sinister vandal", "diatz")
   assert_not_nil(override, "override saved to DB")
   assert_equal("testkw", override.keyword, "keyword saved correctly")
end)

--- Test: xset kw with no target set shows error, no DB write
-- Covers: cmd_xset() "kw" no-target guard
run_test("xset_kw.no_target_error", function()
   -- No target set — should show error
   State._target = nil
   mock.reset()

   cmd_xset(nil, nil, {[1] = "kw something"})

   -- Should not crash, no DB write
   assert_nil(State.get_target(), "still no target")
end)

------------------------------------------------------------------------
-- cmd_kk: quick kill
------------------------------------------------------------------------

--- Test: kk sends quick_kill_command + keyword via SendNoEcho
-- Covers: cmd_kk()
run_test("cmd_kk.sends_kill_command", function()
   State._target = {keyword = "vand", name = "a vandal", area_key = "diatz"}
   Config._settings = {quick_kill_command = "k"}
   mock.reset()

   cmd_kk(nil, nil, {})

   local sent = false
   for _, call in ipairs(mock.calls["SendNoEcho"] or {}) do
      if call[1] == "k vand" then sent = true end
   end
   assert_true(sent, "sent kill command with keyword")
end)

--- Test: kk with no target shows error, no command sent
-- Covers: cmd_kk() no-target guard
run_test("cmd_kk.no_target_error", function()
   State._target = nil
   mock.reset()

   cmd_kk(nil, nil, {})

   assert_nil(mock.calls["SendNoEcho"], "no command sent without target")
end)

------------------------------------------------------------------------
-- cmd_xset: config settings
------------------------------------------------------------------------

--- Test: xset key value changes a config setting
-- Covers: cmd_xset() normal key/value path → Config.set()
run_test("cmd_xset.set_config_value", function()
   Config._settings = {}
   Config.load()
   mock.reset()

   cmd_xset(nil, nil, {[1] = "debug_mode on"})

   assert_equal("on", Config.get("debug_mode"), "debug_mode set to on")
end)

--- Test: xset with invalid key rejects without storing
-- Covers: cmd_xset() → Config.set() returns false for unknown key
run_test("cmd_xset.invalid_key_error", function()
   mock.reset()

   cmd_xset(nil, nil, {[1] = "nonexistent_key value"})

   -- Should not crash, config unchanged
   assert_nil(Config._settings["nonexistent_key"], "invalid key not stored")
end)

------------------------------------------------------------------------
-- CP.do_info / CP.do_check direct tests
------------------------------------------------------------------------

--- Test: CP.do_info clears list, enables level+start triggers only, sends "cp info"
-- Setup: CP._info_list has stale data
-- Expected: list cleared, only trg_cp_info_level + trg_cp_info_start enabled (NOT line/end),
--   "cp info" sent, safety timer enabled
-- Covers: CP.do_info() individual trigger enabling (prevents premature end trigger)
run_test("CP.do_info.enables_triggers_and_sends", function()
   CP._info_list = {{mob = "old"}}
   mock.reset()

   CP.do_info()

   -- Should clear info list
   assert_equal(0, #CP._info_list, "info list cleared")
   -- Should send cp info
   local sent = false
   for _, call in ipairs(mock.calls["SendNoEcho"] or {}) do
      if call[1] == "cp info" then sent = true end
   end
   assert_true(sent, "cp info command sent")
   -- Should enable only level and start triggers (not the whole group)
   local level_enabled = false
   local start_enabled = false
   local line_enabled = false
   local end_enabled = false
   for _, call in ipairs(mock.calls["EnableTrigger"] or {}) do
      if call[1] == "trg_cp_info_level" and call[2] == true then level_enabled = true end
      if call[1] == "trg_cp_info_start" and call[2] == true then start_enabled = true end
      if call[1] == "trg_cp_info_line" and call[2] == true then line_enabled = true end
      if call[1] == "trg_cp_info_end" and call[2] == true then end_enabled = true end
   end
   assert_true(level_enabled, "trg_cp_info_level enabled")
   assert_true(start_enabled, "trg_cp_info_start enabled")
   assert_false(line_enabled, "trg_cp_info_line NOT enabled yet")
   assert_false(end_enabled, "trg_cp_info_end NOT enabled yet")
end)

--- Test: on_cp_info_start enables line+end triggers and clears info list
-- Setup: trg_cp_info_line and trg_cp_info_end not yet enabled
-- Expected: both triggers enabled, info list cleared, start trigger disabled
-- Covers: on_cp_info_start() trigger staging (line+end enabled after "The targets..." line)
run_test("CP.do_info.start_enables_line_and_end", function()
   CP._info_list = {{mob = "stale"}}
   mock.reset()

   on_cp_info_start(nil, nil, {})

   -- Should clear info list
   assert_equal(0, #CP._info_list, "info list cleared by start")
   -- Should enable line+end triggers
   local line_enabled = false
   local end_enabled = false
   local start_disabled = false
   for _, call in ipairs(mock.calls["EnableTrigger"] or {}) do
      if call[1] == "trg_cp_info_line" and call[2] == true then line_enabled = true end
      if call[1] == "trg_cp_info_end" and call[2] == true then end_enabled = true end
      if call[1] == "trg_cp_info_start" and call[2] == false then start_disabled = true end
   end
   assert_true(line_enabled, "trg_cp_info_line enabled by start")
   assert_true(end_enabled, "trg_cp_info_end enabled by start")
   assert_true(start_disabled, "trg_cp_info_start disabled after matching")
end)

--- Test: CP.do_check blocked by 1.0s cooldown
-- Setup: _last_check_time = now (just called)
-- Expected: no SendNoEcho
-- Covers: CP.do_check() cooldown guard
run_test("CP.do_check.cooldown_guard", function()
   CP._last_check_time = os.clock()  -- just called
   mock.reset()

   CP.do_check()

   -- Should be blocked by cooldown
   assert_nil(mock.calls["SendNoEcho"], "blocked by cooldown")
end)

--- Test: CP.do_check sends "cp check", enables only check_line trigger (not end)
-- Setup: _last_check_time 2 seconds ago
-- Expected: sends "cp check", enables trg_cp_check_line only (end enabled by first line match)
-- Covers: CP.do_check() normal send path + individual trigger enabling
run_test("CP.do_check.sends_when_ready", function()
   CP._last_check_time = os.clock() - 2.0  -- 2 seconds ago, past cooldown
   mock.reset()

   CP.do_check()

   local sent = false
   for _, call in ipairs(mock.calls["SendNoEcho"] or {}) do
      if call[1] == "cp check" then sent = true end
   end
   assert_true(sent, "cp check sent when cooldown expired")
   -- Should enable only check_line (not check_end — enabled by first line match)
   local line_enabled = false
   local end_enabled = false
   for _, call in ipairs(mock.calls["EnableTrigger"] or {}) do
      if call[1] == "trg_cp_check_line" and call[2] == true then line_enabled = true end
      if call[1] == "trg_cp_check_end" and call[2] == true then end_enabled = true end
   end
   assert_true(line_enabled, "trg_cp_check_line enabled")
   assert_false(end_enabled, "trg_cp_check_end NOT enabled yet")
end)

------------------------------------------------------------------------
-- cmd_xcp: redesigned flow (DB-first, where-fallback, auto-go-on-1, HT in parallel)
------------------------------------------------------------------------

--- Helper: build a target with explicit S&D mob history (skips DB.find_mob)
local function build_target_with_rooms(mob, area_key, rooms)
   CP._on_cp = true
   CP._type = "area"
   State._activity = "cp"
   TargetList._main_list = {{
      mob = mob, location = area_key, area_key = area_key,
      keyword = mob:gsub("%s", ""):sub(1, 8), dead = false, link_type = "area",
      roomid = nil, room_name = nil,
      rooms = rooms or {}, found_in_area = (rooms and #rooms > 0) or false,
      unlikely = false, likely = false, index = 1, _input_order = 1,
   }}
   TargetList._type = "area"
end

--- Test: xcp uses S&D history when available (no `where` sent)
-- Setup: target has 3 historical rooms in t.rooms
-- Expected: goto_list built from t.rooms, list displayed, no `where` SendNoEcho call
-- Covers: cmd_xcp() Path 2 (DB history)
run_test("cmd_xcp.uses_db_history_when_available", function()
   build_target_with_rooms("an old woman", "dortmund", {
      {roomid = 100, room_name = "A log cabin", freq = 5},
      {roomid = 200, room_name = "A small house", freq = 3},
      {roomid = 300, room_name = "A dirt road", freq = 1},
   })
   State._room = {rmid = 32418, arid = "aylor", name = "Aylor", exits = {}, maze = false}
   mock.reset()

   cmd_xcp(nil, nil, {[1] = "1"})

   assert_equal(3, #Nav._goto_list, "goto_list built from 3 historical rooms")
   assert_equal(100, Nav._goto_list[1], "first room is highest-freq (100)")
   -- No `where` should be sent
   for _, call in ipairs(mock.calls["SendNoEcho"] or {}) do
      assert_false(call[1]:find("where") ~= nil, "no where command sent — using DB history")
   end
   -- List was displayed
   assert_not_nil(mock.calls["ColourNote"], "list displayed via ColourNote")
end)

--- Test: xcp auto-navigates when only 1 room matches
-- Setup: target has 1 historical room
-- Expected: mapper goto fires, _goto_index = 1
-- Covers: cmd_xcp() Path 2 single-room auto-navigate
run_test("cmd_xcp.auto_navigates_single_room", function()
   build_target_with_rooms("an old woman", "dortmund", {
      {roomid = 100, room_name = "A log cabin", freq = 5},
   })
   State._room = {rmid = 32418, arid = "aylor", name = "Aylor", exits = {}, maze = false}
   mock.reset()

   cmd_xcp(nil, nil, {[1] = "1"})

   assert_equal(1, #Nav._goto_list, "single-room goto_list")
   assert_equal(1, Nav._goto_index, "goto_next advanced index")
   local found = false
   for _, call in ipairs(mock.calls["Execute"] or {}) do
      if call[1] == "mapper goto 100" then found = true end
   end
   assert_true(found, "auto-navigated to the single room")
end)

--- Test: xcp shows list and waits when multiple rooms match
-- Setup: target has 3 historical rooms
-- Expected: list displayed, NO mapper goto
-- Covers: cmd_xcp() Path 2 multi-room wait-for-user
run_test("cmd_xcp.shows_list_waits_multiple_rooms", function()
   build_target_with_rooms("an old woman", "dortmund", {
      {roomid = 100, room_name = "A log cabin", freq = 5},
      {roomid = 200, room_name = "A small house", freq = 3},
   })
   State._room = {rmid = 32418, arid = "aylor", name = "Aylor", exits = {}, maze = false}
   mock.reset()

   cmd_xcp(nil, nil, {[1] = "1"})

   assert_equal(2, #Nav._goto_list, "2-room goto_list")
   assert_equal(0, Nav._goto_index, "no auto-navigate — waiting for user")
   local mapper_called = false
   for _, call in ipairs(mock.calls["Execute"] or {}) do
      if call[1]:find("mapper goto") then mapper_called = true end
   end
   assert_false(mapper_called, "no mapper goto — user must pick")
end)

--- Test: xcp with no history but in target area sends `where` directly
-- Setup: target has empty rooms, current room is in target area
-- Expected: QW.start_exact called (sends `where`), no Nav.goto_area
-- Covers: cmd_xcp() Path 3 in-area discovery
run_test("cmd_xcp.no_history_in_area_sends_where_directly", function()
   build_target_with_rooms("an old woman", "dortmund", {})  -- no history
   -- In target area
   State._room = {rmid = 786, arid = "dortmund", name = "A dirt road", exits = {}, maze = false}
   mock.reset()

   cmd_xcp(nil, nil, {[1] = "1"})

   assert_true(QuickWhere._active, "QW activated for discovery")
   assert_true(QuickWhere._exact, "QW in exact mode")
   assert_false(QuickWhere._auto_go, "auto_go=false — handled by goto_list size at on_qw_match time")
   -- No mapper navigation
   for _, call in ipairs(mock.calls["Execute"] or {}) do
      assert_false(call[1]:find("mapper goto") ~= nil, "no mapper goto when already in area")
   end
end)

--- Test: xcp with no history out of area navigates first, then runs `where` on arrival
-- Setup: target has empty rooms, current room is in DIFFERENT area
-- Expected: Nav.goto_area called, _on_arrive set; QW NOT yet active
-- Covers: cmd_xcp() Path 3 navigate-then-discover
run_test("cmd_xcp.no_history_out_of_area_navigates_first", function()
   build_target_with_rooms("an old woman", "dortmund", {})
   State._room = {rmid = 32418, arid = "aylor", name = "Aylor", exits = {}, maze = false}
   mock.reset()

   cmd_xcp(nil, nil, {[1] = "1"})

   assert_not_nil(Nav._on_arrive, "_on_arrive set for deferred where+HT")
   assert_false(QuickWhere._active, "QW not yet active — waits for arrival")
   -- Mapper navigation should have been initiated
   local mapper_called = false
   for _, call in ipairs(mock.calls["Execute"] or {}) do
      if call[1]:find("mapper goto") then mapper_called = true end
   end
   assert_true(mapper_called, "mapper goto fired for area navigation")
end)

--- Test: xcp starts HT in parallel with chain_on_complete=false
-- Setup: target with history rooms (Path 2)
-- Expected: HT active, chain_on_complete = false (so HT won't clobber goto_list via QW chain)
-- Covers: cmd_xcp() HT-in-parallel behavior
run_test("cmd_xcp.starts_ht_in_parallel", function()
   build_target_with_rooms("an old woman", "dortmund", {
      {roomid = 100, room_name = "A log cabin", freq = 5},
      {roomid = 200, room_name = "A small house", freq = 3},
   })
   State._room = {rmid = 32418, arid = "aylor", name = "Aylor", exits = {}, maze = false}
   mock.reset()

   cmd_xcp(nil, nil, {[1] = "1"})

   assert_true(HuntTrick._active, "HT started in parallel")
   assert_false(HuntTrick._chain_on_complete, "HT chain disabled — won't rebuild goto_list")
end)

--- Test: cmd_xcp on reselect cancels prior HT
-- Setup: HT active from earlier xcp
-- Expected: HT.reset() called before new selection
-- Covers: cmd_xcp() reselect cleanup
run_test("cmd_xcp.cancels_ht_on_reselect", function()
   build_target_with_rooms("an old woman", "dortmund", {
      {roomid = 100, room_name = "A log cabin", freq = 5},
   })
   State._room = {rmid = 32418, arid = "aylor", name = "Aylor", exits = {}, maze = false}
   -- Simulate HT already active
   HuntTrick._active = true
   HuntTrick._keyword = "stale"
   mock.reset()

   cmd_xcp(nil, nil, {[1] = "1"})

   -- HT reset and restarted with new keyword
   assert_true(HuntTrick._active, "HT re-started for new target")
   assert_false(HuntTrick._keyword == "stale", "stale keyword cleared")
end)
