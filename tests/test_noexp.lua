------------------------------------------------------------------------
-- test_noexp.lua - Tests for the Noexp module
------------------------------------------------------------------------

if not CONST then
   local load_plugin = require("load_plugin")
   load_plugin()
end

function setUp()
   mock.reset()
   Noexp._auto_enabled = true
   Noexp._noexp_on = false
   Noexp._tnl_cutoff = 0
   State._tnl = 0
   State._level = 0
   State._noexp = false
   CP._on_cp = false
end

--- Test: Noexp.init reads default config (auto=on, cutoff=0)
-- Setup: empty config settings
-- Expected: _auto_enabled=true, _tnl_cutoff=0
-- Covers: Noexp.init()
run_test("Noexp.init_defaults", function()
   Config._settings = {}
   Config.load()
   Noexp.init()
   assert_true(Noexp._auto_enabled, "auto enabled by default")
   assert_equal(0, Noexp._tnl_cutoff, "tnl cutoff defaults to 0")
end)

--- Test: Noexp.init reads custom config values
-- Setup: mock variables snd_noexp_auto="off", snd_noexp_tnl_cutoff="500"
-- Expected: _auto_enabled=false, _tnl_cutoff=500
-- Covers: Noexp.init()
run_test("Noexp.init_custom", function()
   mock.variables["snd_noexp_auto"] = "off"
   mock.variables["snd_noexp_tnl_cutoff"] = "500"
   Config._settings = {}
   Config.load()
   Noexp.init()
   assert_false(Noexp._auto_enabled, "auto disabled when config says off")
   assert_equal(500, Noexp._tnl_cutoff, "tnl cutoff from config")
end)

--- Test: check_tnl is a no-op when auto is disabled
-- Setup: auto_enabled=false, TNL below cutoff
-- Expected: noexp stays off, no command sent
-- Covers: Noexp.check_tnl() auto_enabled guard
run_test("Noexp.check_tnl_disabled", function()
   Noexp._auto_enabled = false
   Noexp._noexp_on = false
   State._tnl = 100
   Noexp._tnl_cutoff = 500
   Noexp.check_tnl()
   assert_false(Noexp._noexp_on, "noexp stays off when auto disabled")
   assert_nil(mock.calls["SendNoEcho"], "no command sent when auto disabled")
end)

--- Test: check_tnl is a no-op when cutoff is 0
-- Setup: cutoff=0, TNL=100
-- Expected: noexp stays off (cutoff=0 means feature disabled)
-- Covers: Noexp.check_tnl() cutoff<=0 guard
run_test("Noexp.check_tnl_cutoff_zero", function()
   Noexp._auto_enabled = true
   Noexp._noexp_on = false
   State._tnl = 100
   Noexp._tnl_cutoff = 0
   State._level = 50
   Noexp.check_tnl()
   assert_false(Noexp._noexp_on, "noexp stays off when cutoff is 0")
end)

--- Test: check_tnl turns noexp ON when TNL < cutoff
-- Setup: TNL=200, cutoff=500, noexp off, not on CP
-- Expected: noexp on, State._noexp synced, SendNoEcho("noexp") sent
-- Covers: Noexp.check_tnl() turn-on path, Noexp.set()
run_test("Noexp.check_tnl_turns_on", function()
   Noexp._auto_enabled = true
   Noexp._noexp_on = false
   Noexp._tnl_cutoff = 500
   State._tnl = 200
   State._level = 50
   Noexp.check_tnl()
   assert_true(Noexp._noexp_on, "noexp turned on when TNL < cutoff")
   assert_true(State._noexp, "State._noexp synced")
   assert_not_nil(mock.calls["SendNoEcho"], "SendNoEcho called")
   local sent = false
   for _, call in ipairs(mock.calls["SendNoEcho"] or {}) do
      if call[1] == "noexp" then sent = true end
   end
   assert_true(sent, "sent 'noexp' game command")
end)

--- Test: check_tnl turns noexp OFF when TNL > cutoff
-- Setup: TNL=1000, cutoff=500, noexp on
-- Expected: noexp off, State._noexp synced
-- Covers: Noexp.check_tnl() turn-off path
run_test("Noexp.check_tnl_turns_off", function()
   Noexp._auto_enabled = true
   Noexp._noexp_on = true
   Noexp._tnl_cutoff = 500
   State._tnl = 1000
   State._level = 50
   Noexp.check_tnl()
   assert_false(Noexp._noexp_on, "noexp turned off when TNL > cutoff")
   assert_false(State._noexp, "State._noexp synced off")
end)

--- Test: check_tnl doesn't re-send when already on and TNL still < cutoff
-- Setup: noexp already on, TNL still below cutoff
-- Expected: stays on, no command sent (avoid redundant toggle)
-- Covers: Noexp.check_tnl() no-change path, Noexp.set() guard
run_test("Noexp.check_tnl_no_change_on", function()
   Noexp._auto_enabled = true
   Noexp._noexp_on = true
   Noexp._tnl_cutoff = 500
   State._tnl = 200
   State._level = 50
   Noexp.check_tnl()
   assert_true(Noexp._noexp_on, "noexp stays on")
   assert_nil(mock.calls["SendNoEcho"], "no command sent when already in correct state")
end)

--- Test: check_tnl doesn't re-send when already off and TNL still > cutoff
-- Setup: noexp already off, TNL above cutoff
-- Expected: stays off, no command sent
-- Covers: Noexp.check_tnl() no-change path
run_test("Noexp.check_tnl_no_change_off", function()
   Noexp._auto_enabled = true
   Noexp._noexp_on = false
   Noexp._tnl_cutoff = 500
   State._tnl = 1000
   State._level = 50
   Noexp.check_tnl()
   assert_false(Noexp._noexp_on, "noexp stays off")
   assert_nil(mock.calls["SendNoEcho"], "no command sent when already in correct state")
end)

--- Test: check_tnl forces noexp OFF at level 200 (superhero)
-- Setup: level=200, noexp on, TNL below cutoff
-- Expected: noexp forced off (level 200+ overrides TNL)
-- Covers: Noexp.check_tnl() level>=200 guard
run_test("Noexp.check_tnl_level_200", function()
   Noexp._auto_enabled = true
   Noexp._noexp_on = true
   Noexp._tnl_cutoff = 500
   State._tnl = 100
   State._level = 200
   Noexp.check_tnl()
   assert_false(Noexp._noexp_on, "noexp forced off at level 200")
end)

--- Test: check_tnl forces noexp OFF at level 201+
-- Setup: level=201, noexp on
-- Expected: noexp forced off
-- Covers: Noexp.check_tnl() level>=200 guard
run_test("Noexp.check_tnl_level_201", function()
   Noexp._auto_enabled = true
   Noexp._noexp_on = true
   Noexp._tnl_cutoff = 500
   State._tnl = 100
   State._level = 201
   Noexp.check_tnl()
   assert_false(Noexp._noexp_on, "noexp forced off at level 201")
end)

--- Test: check_tnl no command at level 200 when already off
-- Setup: level=200, noexp already off
-- Expected: stays off, no redundant command
-- Covers: Noexp.check_tnl() level 200 + already-off
run_test("Noexp.check_tnl_level_200_already_off", function()
   Noexp._auto_enabled = true
   Noexp._noexp_on = false
   Noexp._tnl_cutoff = 500
   State._tnl = 100
   State._level = 200
   Noexp.check_tnl()
   assert_false(Noexp._noexp_on, "noexp stays off at level 200")
   assert_nil(mock.calls["SendNoEcho"], "no command when already off at 200")
end)

--- Test: Noexp.set is a no-op when state already matches
-- Setup: noexp already on, set(true)
-- Expected: no command, no broadcast
-- Covers: Noexp.set() same-state guard
run_test("Noexp.set_no_change", function()
   Noexp._noexp_on = true
   Noexp.set(true)
   assert_nil(mock.calls["SendNoEcho"], "no command when setting same state")
   assert_nil(mock.calls["BroadcastPlugin"], "no broadcast when setting same state")
end)

--- Test: Noexp.set broadcasts BCAST_NOEXP on state change
-- Setup: noexp off, set(true)
-- Expected: BCAST_NOEXP broadcast sent
-- Covers: Noexp.set() broadcast
run_test("Noexp.set_broadcasts", function()
   Noexp._noexp_on = false
   Noexp._tnl_cutoff = 500
   Noexp.set(true)
   assert_not_nil(mock.calls["BroadcastPlugin"], "broadcast sent on set")
   local found_noexp_bcast = false
   for _, call in ipairs(mock.calls["BroadcastPlugin"] or {}) do
      if call[1] == CONST.BCAST_NOEXP then
         found_noexp_bcast = true
      end
   end
   assert_true(found_noexp_bcast, "BCAST_NOEXP sent")
end)

--- Test: TNL exactly equals cutoff when OFF → stays OFF (uses <, not <=)
-- Setup: TNL=500, cutoff=500, noexp off
-- Expected: stays off (500 is not < 500)
-- Covers: Noexp.check_tnl() boundary: tnl == cutoff
run_test("Noexp.check_tnl_exact_cutoff_off", function()
   Noexp._auto_enabled = true
   Noexp._noexp_on = false
   Noexp._tnl_cutoff = 500
   State._tnl = 500
   State._level = 50
   Noexp.check_tnl()
   assert_false(Noexp._noexp_on, "noexp stays off when TNL exactly equals cutoff")
end)

--- Test: TNL exactly equals cutoff when ON → stays ON (gap: neither < nor > fires)
-- Setup: TNL=500, cutoff=500, noexp on
-- Expected: stays on, no command (500 is not > 500 either)
-- Covers: Noexp.check_tnl() boundary: tnl == cutoff, hysteresis
run_test("Noexp.check_tnl_exact_cutoff_on", function()
   Noexp._auto_enabled = true
   Noexp._noexp_on = true
   Noexp._tnl_cutoff = 500
   State._tnl = 500
   State._level = 50
   State._noexp = true
   Noexp.check_tnl()
   assert_true(Noexp._noexp_on, "noexp stays on when TNL exactly equals cutoff")
   assert_nil(mock.calls["SendNoEcho"], "no command sent at exact cutoff boundary")
end)
