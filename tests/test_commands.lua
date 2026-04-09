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

run_test("cmd_xcp.numeric_selects_target", function()
   build_test_targets()
   mock.reset()

   cmd_xcp(nil, nil, {[1] = "2"})

   local target = State.get_target()
   assert_not_nil(target, "target selected by index")
   assert_equal("a mutated goat", target.mob, "second target selected")
end)

run_test("cmd_xcp.not_on_cp", function()
   -- Not on CP — should show error
   CP._on_cp = false
   State._activity = "none"
   mock.reset()

   cmd_xcp(nil, nil, {[1] = "1"})

   assert_nil(State.get_target(), "no target when not on CP")
end)

run_test("cmd_xcp.index_out_of_bounds", function()
   build_test_targets()
   mock.reset()

   cmd_xcp(nil, nil, {[1] = "99"})

   assert_nil(State.get_target(), "no target for out-of-bounds index")
end)

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

run_test("cmd_go.empty_list", function()
   Nav._goto_list = {}
   mock.reset()

   cmd_go(nil, nil, {[1] = "1"})

   -- Should not crash, no navigation
   assert_nil(mock.calls["Execute"], "no Execute for empty goto list")
end)

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

run_test("cmd_nx.at_end_of_list", function()
   Nav._goto_list = {11111, 22222}
   Nav._goto_index = 2
   State._room = {rmid = 22222, arid = "test", name = "Room 2", exits = {}, maze = false}
   mock.reset()

   cmd_nx(nil, nil, {})

   -- At end of list — should not advance further
   assert_nil(mock.calls["Execute"], "no navigation at end of list")
end)

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

run_test("cmd_xrt.navigates_to_area", function()
   mock.reset()

   cmd_xrt(nil, nil, {[1] = "diatz"})

   local found = false
   for _, call in ipairs(mock.calls["Execute"] or {}) do
      if call[1] == "mapper goto 1254" then found = true end
   end
   assert_true(found, "xrt navigates to diatz start room")
end)

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

run_test("cmd_xrt.no_arg_error", function()
   mock.reset()

   cmd_xrt(nil, nil, {[1] = ""})

   -- Should not navigate, show error
   assert_nil(mock.calls["Execute"], "no navigation with empty xrt arg")
end)

run_test("cmd_xrt.unknown_area", function()
   mock.reset()

   cmd_xrt(nil, nil, {[1] = "zzzznonexistent"})

   assert_nil(mock.calls["Execute"], "no navigation for unknown area")
end)

------------------------------------------------------------------------
-- xset kw: keyword override for current target
------------------------------------------------------------------------

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

run_test("cmd_kk.no_target_error", function()
   State._target = nil
   mock.reset()

   cmd_kk(nil, nil, {})

   assert_nil(mock.calls["SendNoEcho"], "no command sent without target")
end)

------------------------------------------------------------------------
-- cmd_xset: config settings
------------------------------------------------------------------------

run_test("cmd_xset.set_config_value", function()
   Config._settings = {}
   Config.load()
   mock.reset()

   cmd_xset(nil, nil, {[1] = "debug_mode on"})

   assert_equal("on", Config.get("debug_mode"), "debug_mode set to on")
end)

run_test("cmd_xset.invalid_key_error", function()
   mock.reset()

   cmd_xset(nil, nil, {[1] = "nonexistent_key value"})

   -- Should not crash, config unchanged
   assert_nil(Config._settings["nonexistent_key"], "invalid key not stored")
end)

------------------------------------------------------------------------
-- CP.do_info / CP.do_check direct tests
------------------------------------------------------------------------

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
   -- Should enable trigger group
   local enabled = false
   for _, call in ipairs(mock.calls["EnableTriggerGroup"] or {}) do
      if call[1] == "grp_cp_info" and call[2] == true then enabled = true end
   end
   assert_true(enabled, "grp_cp_info enabled")
end)

run_test("CP.do_check.cooldown_guard", function()
   CP._last_check_time = os.clock()  -- just called
   mock.reset()

   CP.do_check()

   -- Should be blocked by cooldown
   assert_nil(mock.calls["SendNoEcho"], "blocked by cooldown")
end)

run_test("CP.do_check.sends_when_ready", function()
   CP._last_check_time = os.clock() - 2.0  -- 2 seconds ago, past cooldown
   mock.reset()

   CP.do_check()

   local sent = false
   for _, call in ipairs(mock.calls["SendNoEcho"] or {}) do
      if call[1] == "cp check" then sent = true end
   end
   assert_true(sent, "cp check sent when cooldown expired")
end)
