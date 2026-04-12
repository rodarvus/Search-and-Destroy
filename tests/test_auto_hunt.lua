------------------------------------------------------------------------
-- test_auto_hunt.lua - Tests for AutoHunt module
------------------------------------------------------------------------

if not CONST then
   local load_plugin = require("load_plugin")
   load_plugin()
end

function setUp()
   mock.reset()
   mock.reset_db()
   DB.init()
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
   State._target = nil
   State._activity = "none"
   State._room = {rmid = 1254, arid = "diatz", name = "A Room", exits = {n = 1255, s = 1253}, maze = false}
end

function tearDown()
   mock.reset_db()
end

------------------------------------------------------------------------
-- AutoHunt.start
------------------------------------------------------------------------

--- Test: start enables grp_auto_hunt and sends hunt command
-- Input: keyword="citizen"
-- Expected: grp_auto_hunt enabled, Send("hunt citizen"), _active=true
-- Covers: AutoHunt.start()
run_test("AutoHunt.start_basic", function()
   AutoHunt.start("citizen")
   assert_true(AutoHunt._active, "active after start")
   assert_equal("citizen", AutoHunt._keyword, "keyword stored")
   -- Check trigger group enabled
   local grp_enabled = false
   for _, call in ipairs(mock.calls["EnableTriggerGroup"] or {}) do
      if call[1] == "grp_auto_hunt" and call[2] == true then grp_enabled = true end
   end
   assert_true(grp_enabled, "grp_auto_hunt enabled")
   local found = false
   for _, call in ipairs(mock.calls["Send"] or {}) do
      if call[1] == "hunt citizen" then found = true end
   end
   assert_true(found, "sent 'hunt citizen'")
end)

--- Test: AH.start does NOT reset other tools (parallel mode allowed)
-- Covers: AutoHunt.start() — exclusivity moved to cmd_ah
run_test("AutoHunt.start_does_not_reset_others", function()
   HuntTrick._active = true
   QuickWhere._active = true
   AutoHunt.start("citizen")
   assert_true(HuntTrick._active, "HT NOT reset by AH.start (parallel-safe)")
   assert_true(QuickWhere._active, "QW NOT reset by AH.start (parallel-safe)")
end)

--- Test: cmd_ah (manual command) DOES reset other hunting tools
-- Covers: cmd_ah() exclusivity
run_test("cmd_ah.resets_others", function()
   State._target = {keyword = "wolf", mob = "a wolf", area_key = "diatz"}
   HuntTrick._active = true
   QuickWhere._active = true
   cmd_ah(nil, nil, {[1] = ""})
   assert_false(HuntTrick._active, "HT reset by cmd_ah")
   assert_false(QuickWhere._active, "QW reset by cmd_ah")
end)

------------------------------------------------------------------------
-- AutoHunt.reset
------------------------------------------------------------------------

--- Test: reset clears all state and disables trigger group
-- Covers: AutoHunt.reset()
run_test("AutoHunt.reset_clears_state", function()
   AutoHunt._keyword = "citizen"
   AutoHunt._direction = "n"
   AutoHunt._active = true
   AutoHunt.reset()
   assert_equal("", AutoHunt._keyword, "keyword cleared")
   assert_equal("", AutoHunt._direction, "direction cleared")
   assert_false(AutoHunt._active, "not active")
end)

------------------------------------------------------------------------
-- on_ah_direction callback
------------------------------------------------------------------------

--- Test: direction trigger moves in direction and hunts again
-- Setup: active AH, GMCP shows north exit
-- Input: direction="north" (wildcards[1]="north")
-- Expected: Send("n"), Send("hunt citizen")
-- Covers: on_ah_direction() normal exit
run_test("on_ah_direction.moves_and_hunts", function()
   AutoHunt._active = true
   AutoHunt._keyword = "citizen"
   State._room = {rmid = 1254, arid = "diatz", name = "A Room",
      exits = {n = 1255, s = 1253}, maze = false}
   mock.reset()  -- clear prior calls
   -- wildcards: direction captured in first group
   on_ah_direction("trg_ah_direction",
      "You are certain that a citizen is north from here.",
      {"north", false, false, false, false})
   -- Check we moved north and hunted again
   local found_move = false
   local found_hunt = false
   for _, call in ipairs(mock.calls["Send"] or {}) do
      if call[1] == "n" then found_move = true end
      if call[1] == "hunt citizen" then found_hunt = true end
   end
   assert_true(found_move, "moved north")
   assert_true(found_hunt, "hunted again after move")
   assert_equal("n", AutoHunt._direction, "direction saved")
end)

--- Test: direction trigger opens door when exit not in GMCP
-- Setup: GMCP has no west exit
-- Input: direction="west"
-- Expected: Send("open w"), Send("w"), Send("hunt citizen")
-- Covers: on_ah_direction() door opening
run_test("on_ah_direction.opens_door", function()
   AutoHunt._active = true
   AutoHunt._keyword = "citizen"
   State._room = {rmid = 1254, arid = "diatz", name = "A Room",
      exits = {n = 1255}, maze = false}
   mock.reset()
   on_ah_direction("trg_ah_direction",
      "You are certain that a citizen is west from here.",
      {false, false, false, false, "west"})  -- 5th group captures
   local found_open = false
   local found_move = false
   local found_hunt = false
   for _, call in ipairs(mock.calls["Send"] or {}) do
      if call[1] == "open w" then found_open = true end
      if call[1] == "w" then found_move = true end
      if call[1] == "hunt citizen" then found_hunt = true end
   end
   assert_true(found_open, "sent 'open w' for hidden exit")
   assert_true(found_move, "moved west")
   assert_true(found_hunt, "hunted again")
end)

--- Test: direction from 2nd capture group (portal heading)
-- Input: wildcards with direction in group 2
-- Expected: moves in that direction
-- Covers: on_ah_direction() alternate capture group
run_test("on_ah_direction.second_capture_group", function()
   AutoHunt._active = true
   AutoHunt._keyword = "citizen"
   State._room = {rmid = 1254, arid = "diatz", name = "A Room",
      exits = {s = 1253}, maze = false}
   mock.reset()
   on_ah_direction("trg_ah_direction",
      "You are confident that a citizen passed through here, heading south.",
      {false, "south", false, false, false})
   local found_move = false
   for _, call in ipairs(mock.calls["Send"] or {}) do
      if call[1] == "s" then found_move = true end
   end
   assert_true(found_move, "moved south from 2nd capture group")
end)

--- Test: inactive AH ignores direction
-- Covers: on_ah_direction() guard
run_test("on_ah_direction.inactive_ignored", function()
   AutoHunt._active = false
   on_ah_direction("trg_ah_direction", "You are certain...", {"north", false, false, false, false})
   assert_nil(mock.calls["Send"], "no Send when inactive")
end)

------------------------------------------------------------------------
-- on_ah_here callback
------------------------------------------------------------------------

--- Test: "here" resets AH and notifies
-- Covers: on_ah_here()
run_test("on_ah_here.completes", function()
   AutoHunt._active = true
   AutoHunt._keyword = "citizen"
   on_ah_here("trg_ah_here", "A citizen is here!", {})
   assert_false(AutoHunt._active, "AH reset")
end)

------------------------------------------------------------------------
-- on_ah_not_found callback
------------------------------------------------------------------------

--- Test: not found resets AH and notifies
-- Covers: on_ah_not_found()
run_test("on_ah_not_found.aborts", function()
   AutoHunt._active = true
   AutoHunt._keyword = "citizen"
   on_ah_not_found("trg_ah_not_found", "No one in this area by the name 'citizen'.", {})
   assert_false(AutoHunt._active, "AH reset")
end)

------------------------------------------------------------------------
-- cmd_ah
------------------------------------------------------------------------

--- Test: cmd_ah cancel resets
-- Covers: cmd_ah() cancel
run_test("cmd_ah.cancel_resets", function()
   AutoHunt._active = true
   cmd_ah("als_ah", "ah cancel", {"cancel"})
   assert_false(AutoHunt._active, "AH reset on cancel")
end)

--- Test: cmd_ah abort resets
-- Covers: cmd_ah() abort
run_test("cmd_ah.abort_resets", function()
   AutoHunt._active = true
   cmd_ah("als_ah", "ah abort", {"abort"})
   assert_false(AutoHunt._active, "AH reset on abort")
end)

--- Test: cmd_ah "0" resets
-- Covers: cmd_ah() numeric abort
run_test("cmd_ah.zero_resets", function()
   AutoHunt._active = true
   cmd_ah("als_ah", "ah 0", {"0"})
   assert_false(AutoHunt._active, "AH reset on 0")
end)

--- Test: cmd_ah no target shows error
-- Covers: cmd_ah() no target
run_test("cmd_ah.no_target_error", function()
   State._target = nil
   cmd_ah("als_ah", "ah", {""})
   assert_false(AutoHunt._active, "not active")
   assert_nil(mock.calls["Send"], "no Send")
end)

--- Test: cmd_ah with no args uses current target
-- Covers: cmd_ah() default target
run_test("cmd_ah.uses_current_target", function()
   State._target = {mob = "a citizen", keyword = "citizen", area_key = "diatz"}
   cmd_ah("als_ah", "ah", {""})
   assert_true(AutoHunt._active, "AH started")
   assert_equal("citizen", AutoHunt._keyword, "uses target keyword")
end)

--- Test: cmd_ah with keyword argument
-- Covers: cmd_ah() with argument
run_test("cmd_ah.with_keyword_arg", function()
   cmd_ah("als_ah", "ah guard", {"guard"})
   assert_true(AutoHunt._active, "AH started")
   assert_equal("guard", AutoHunt._keyword, "uses provided keyword")
end)
