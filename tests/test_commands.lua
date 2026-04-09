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
