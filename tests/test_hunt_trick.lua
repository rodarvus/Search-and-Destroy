------------------------------------------------------------------------
-- test_hunt_trick.lua - Tests for HuntTrick module
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
   State._room = {rmid = 1254, arid = "diatz", name = "A Room", exits = {n = 1255}, maze = false}
end

function tearDown()
   mock.reset_db()
end

------------------------------------------------------------------------
-- HuntTrick.start
------------------------------------------------------------------------

--- Test: start enables grp_hunt_trick and sends hunt command
-- Input: index=1, keyword="citizen"
-- Expected: grp_hunt_trick enabled, Send("hunt citizen"), _active=true
-- Covers: HuntTrick.start()
run_test("HuntTrick.start_basic", function()
   HuntTrick.start(1, "citizen")
   assert_true(HuntTrick._active, "active after start")
   assert_equal("citizen", HuntTrick._keyword, "keyword stored")
   assert_equal(1, HuntTrick._index, "index stored")
   -- Check trigger group enabled
   local grp_enabled = false
   for _, call in ipairs(mock.calls["EnableTriggerGroup"] or {}) do
      if call[1] == "grp_hunt_trick" and call[2] == true then grp_enabled = true end
   end
   assert_true(grp_enabled, "grp_hunt_trick enabled")
   -- Check Send call
   local found = false
   for _, call in ipairs(mock.calls["Send"] or {}) do
      if call[1] == "hunt citizen" then found = true end
   end
   assert_true(found, "sent 'hunt citizen'")
end)

--- Test: start with index > 1 sends "hunt N.keyword"
-- Input: index=3, keyword="citizen"
-- Expected: Send("hunt 3.citizen")
-- Covers: HuntTrick.start() indexed hunt
run_test("HuntTrick.start_with_index", function()
   HuntTrick.start(3, "citizen")
   local found = false
   for _, call in ipairs(mock.calls["Send"] or {}) do
      if call[1] == "hunt 3.citizen" then found = true end
   end
   assert_true(found, "sent 'hunt 3.citizen'")
end)

--- Test: start with index=1 does NOT send "1.keyword"
-- Input: index=1, keyword="citizen"
-- Expected: Send("hunt citizen") NOT "hunt 1.citizen"
-- Covers: HuntTrick.start() no "1." prefix
run_test("HuntTrick.start_no_1_prefix", function()
   HuntTrick.start(1, "citizen")
   for _, call in ipairs(mock.calls["Send"] or {}) do
      assert_true(call[1] ~= "hunt 1.citizen", "must NOT send 'hunt 1.citizen'")
   end
end)

--- Test: start resets other tools (re-entrant safety)
-- Setup: QuickWhere and AutoHunt are active
-- Expected: both reset after HuntTrick.start
-- Covers: HuntTrick.start() re-entrant safety
run_test("HuntTrick.start_resets_others", function()
   QuickWhere._active = true
   AutoHunt._active = true
   HuntTrick.start(1, "citizen")
   assert_false(QuickWhere._active, "QW reset")
   assert_false(AutoHunt._active, "AH reset")
end)

--- Test: start with no_hunt override shows error and does not send
-- Setup: mob_override with no_hunt=1
-- Input: mob "special boss" in area "diatz"
-- Expected: no Send, _active=false
-- Covers: HuntTrick.start() no_hunt check
run_test("HuntTrick.start_no_hunt_blocked", function()
   DB.execute("INSERT INTO mob_overrides (mob_name, area_id, no_hunt) VALUES ('special boss', 'diatz', 1)")
   State._room = {rmid = 1254, arid = "diatz", name = "A Room", exits = {}, maze = false}
   HuntTrick.start(1, "speci", "special boss", "diatz")
   assert_false(HuntTrick._active, "not active when no_hunt")
   assert_nil(mock.calls["Send"], "no Send when no_hunt")
end)

------------------------------------------------------------------------
-- HuntTrick.reset
------------------------------------------------------------------------

--- Test: reset clears all state and disables trigger group
-- Setup: active hunt trick
-- Expected: all fields reset, grp_hunt_trick disabled
-- Covers: HuntTrick.reset()
run_test("HuntTrick.reset_clears_state", function()
   HuntTrick._index = 5
   HuntTrick._keyword = "citizen"
   HuntTrick._active = true
   HuntTrick._first_target = false
   HuntTrick.reset()
   assert_equal(1, HuntTrick._index, "index reset to 1")
   assert_equal("", HuntTrick._keyword, "keyword cleared")
   assert_false(HuntTrick._active, "not active")
   assert_true(HuntTrick._first_target, "first_target reset to true")
   -- Check trigger group disabled
   local found = false
   for _, call in ipairs(mock.calls["EnableTriggerGroup"] or {}) do
      if call[1] == "grp_hunt_trick" and call[2] == false then found = true end
   end
   assert_true(found, "grp_hunt_trick disabled")
end)

------------------------------------------------------------------------
-- HuntTrick.is_active
------------------------------------------------------------------------

--- Test: is_active returns current state
-- Covers: HuntTrick.is_active()
run_test("HuntTrick.is_active", function()
   assert_false(HuntTrick.is_active(), "not active initially")
   HuntTrick._active = true
   assert_true(HuntTrick.is_active(), "active when set")
end)

------------------------------------------------------------------------
-- on_ht_direction callback
------------------------------------------------------------------------

--- Test: direction trigger ignored when inactive
-- Setup: HuntTrick._active = false
-- Expected: no state change, no Send
-- Covers: on_ht_direction() inactive guard
run_test("on_ht_direction.inactive_ignored", function()
   HuntTrick._active = false
   on_ht_direction("trg_ht_direction", "You are certain that a citizen is north from here.", {"north"})
   assert_false(HuntTrick._active, "still inactive")
   assert_nil(mock.calls["Send"], "no Send when inactive")
end)

--- Test: direction trigger increments index and hunts again
-- Setup: active HT at index 2 with keyword "citizen"
-- Expected: index becomes 3, sends "hunt 3.citizen"
-- Covers: on_ht_direction()
run_test("on_ht_direction.increments_and_hunts", function()
   HuntTrick._active = true
   HuntTrick._index = 2
   HuntTrick._keyword = "citizen"
   mock.reset()  -- clear prior calls
   on_ht_direction("trg_ht_direction", "You are certain that a citizen is north from here.", {"north"})
   assert_equal(3, HuntTrick._index, "index incremented to 3")
   local found = false
   for _, call in ipairs(mock.calls["Send"] or {}) do
      if call[1] == "hunt 3.citizen" then found = true end
   end
   assert_true(found, "sent 'hunt 3.citizen'")
   assert_false(HuntTrick._first_target, "first_target set to false")
end)

------------------------------------------------------------------------
-- on_ht_here callback
------------------------------------------------------------------------

--- Test: "here" resets HT and chains to QW exact
-- Setup: active HT at index 4 with keyword "citizen"
-- Expected: HT reset, QW started in exact mode
-- Covers: on_ht_here()
run_test("on_ht_here.chains_to_qw_exact", function()
   HuntTrick._active = true
   HuntTrick._index = 4
   HuntTrick._keyword = "citizen"
   State._target = {mob = "a citizen", keyword = "citizen", area_key = "diatz"}
   on_ht_here("trg_ht_here", "A citizen is here!", {})
   assert_false(HuntTrick._active, "HT reset")
   assert_true(QuickWhere._active, "QW started")
   assert_true(QuickWhere._exact, "QW in exact mode")
   assert_equal(4, QuickWhere._index, "QW at HT's index")
end)

------------------------------------------------------------------------
-- on_ht_unable callback
------------------------------------------------------------------------

--- Test: "unable" resets HT and chains to QW exact
-- Setup: active HT at index 7 with keyword "citizen"
-- Expected: HT reset, QW started in exact mode at index 7
-- Covers: on_ht_unable()
run_test("on_ht_unable.chains_to_qw_exact", function()
   HuntTrick._active = true
   HuntTrick._index = 7
   HuntTrick._keyword = "citizen"
   State._target = {mob = "a citizen", keyword = "citizen", area_key = "diatz"}
   on_ht_unable("trg_ht_unable", "You seem unable to hunt that target for some reason.", {})
   assert_false(HuntTrick._active, "HT reset")
   assert_true(QuickWhere._active, "QW started")
   assert_true(QuickWhere._exact, "QW in exact mode")
   assert_equal(7, QuickWhere._index, "QW at HT's index")
end)

--- Test: "here" with no target notifies instead of crashing
-- Setup: HT active but no State target set
-- Expected: HT reset, QW NOT started, notification shown
-- Covers: on_ht_here() no-target guard
run_test("on_ht_here.no_target_notifies", function()
   HuntTrick._active = true
   HuntTrick._index = 2
   HuntTrick._keyword = "citizen"
   State._target = nil
   on_ht_here("trg_ht_here", "A citizen is here!", {})
   assert_false(HuntTrick._active, "HT reset")
   assert_false(QuickWhere._active, "QW NOT started")
end)

--- Test: "unable" with no target notifies instead of crashing
-- Setup: HT active but no State target set
-- Expected: HT reset, QW NOT started
-- Covers: on_ht_unable() no-target guard
run_test("on_ht_unable.no_target_notifies", function()
   HuntTrick._active = true
   HuntTrick._index = 5
   HuntTrick._keyword = "citizen"
   State._target = nil
   on_ht_unable("trg_ht_unable", "You seem unable to hunt that target for some reason.", {})
   assert_false(HuntTrick._active, "HT reset")
   assert_false(QuickWhere._active, "QW NOT started")
end)

------------------------------------------------------------------------
-- on_ht_not_found callback
------------------------------------------------------------------------

--- Test: "not found" on first target falls back to QW
-- Setup: first_target = true
-- Expected: HT reset, QW started
-- Covers: on_ht_not_found() first target fallback
run_test("on_ht_not_found.first_target_fallback", function()
   HuntTrick._active = true
   HuntTrick._index = 1
   HuntTrick._keyword = "citizen"
   HuntTrick._first_target = true
   State._target = {mob = "a citizen", keyword = "citizen", area_key = "diatz"}
   on_ht_not_found("trg_ht_not_found", "No one in this area by the name 'citizen'.", {})
   assert_false(HuntTrick._active, "HT reset")
   assert_true(QuickWhere._active, "QW started as fallback")
end)

--- Test: "not found" after first target just notifies, no QW
-- Setup: first_target = false
-- Expected: HT reset, QW NOT started
-- Covers: on_ht_not_found() non-first
run_test("on_ht_not_found.not_first_no_qw", function()
   HuntTrick._active = true
   HuntTrick._index = 3
   HuntTrick._keyword = "citizen"
   HuntTrick._first_target = false
   on_ht_not_found("trg_ht_not_found", "No one in this area by the name 'citizen'.", {})
   assert_false(HuntTrick._active, "HT reset")
   assert_false(QuickWhere._active, "QW NOT started")
end)

------------------------------------------------------------------------
-- on_ht_abort callback
------------------------------------------------------------------------

--- Test: abort resets HT and notifies
-- Setup: active HT
-- Expected: HT reset
-- Covers: on_ht_abort()
run_test("on_ht_abort.resets", function()
   HuntTrick._active = true
   HuntTrick._keyword = "citizen"
   on_ht_abort("trg_ht_fighting", "Not while you are fighting!", {})
   assert_false(HuntTrick._active, "HT reset after abort")
end)

------------------------------------------------------------------------
-- cmd_ht
------------------------------------------------------------------------

--- Test: cmd_ht with no target shows error
-- Setup: no target set
-- Expected: error message, no Send
-- Covers: cmd_ht() no target
run_test("cmd_ht.no_target_error", function()
   State._target = nil
   cmd_ht("als_ht", "ht", {""})
   assert_nil(mock.calls["Send"], "no Send when no target")
   assert_false(HuntTrick._active, "not active")
end)

--- Test: cmd_ht with no args uses current target
-- Setup: target with keyword "citizen"
-- Expected: starts HT with keyword "citizen"
-- Covers: cmd_ht() default target
run_test("cmd_ht.uses_current_target", function()
   State._target = {mob = "a citizen", keyword = "citizen", area_key = "diatz"}
   cmd_ht("als_ht", "ht", {""})
   assert_true(HuntTrick._active, "HT started")
   assert_equal("citizen", HuntTrick._keyword, "uses target keyword")
end)

--- Test: cmd_ht with mob argument
-- Input: "guard"
-- Expected: starts HT with keyword "guard"
-- Covers: cmd_ht() with argument
run_test("cmd_ht.with_mob_arg", function()
   cmd_ht("als_ht", "ht guard", {"guard"})
   assert_true(HuntTrick._active, "HT started with arg")
   assert_equal("guard", HuntTrick._keyword, "uses provided keyword")
end)

--- Test: cmd_ht with indexed mob argument "3.guard"
-- Input: "3.guard"
-- Expected: starts HT at index 3 with keyword "guard"
-- Covers: cmd_ht() indexed argument
run_test("cmd_ht.with_indexed_arg", function()
   cmd_ht("als_ht", "ht 3.guard", {"3.guard"})
   assert_true(HuntTrick._active, "HT started")
   assert_equal(3, HuntTrick._index, "index parsed from arg")
   assert_equal("guard", HuntTrick._keyword, "keyword parsed from arg")
end)

--- Test: cmd_ht abort stops hunt trick
-- Input: "abort"
-- Expected: HT reset
-- Covers: cmd_ht() abort
run_test("cmd_ht.abort", function()
   HuntTrick._active = true
   HuntTrick._keyword = "citizen"
   cmd_ht("als_ht", "ht abort", {"abort"})
   assert_false(HuntTrick._active, "HT reset on abort")
end)

--- Test: cmd_ht "0" stops hunt trick
-- Input: "0"
-- Expected: HT reset
-- Covers: cmd_ht() numeric abort
run_test("cmd_ht.zero_abort", function()
   HuntTrick._active = true
   HuntTrick._keyword = "citizen"
   cmd_ht("als_ht", "ht 0", {"0"})
   assert_false(HuntTrick._active, "HT reset on 0")
end)
