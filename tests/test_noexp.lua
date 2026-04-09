------------------------------------------------------------------------
-- test_noexp.lua - Tests for the Noexp module
------------------------------------------------------------------------

if not CONST then
   local load_plugin = require("load_plugin")
   load_plugin()
end

function setUp()
   mock.reset()
   -- Reset Noexp to known state
   Noexp._auto_enabled = true
   Noexp._noexp_on = false
   Noexp._tnl_cutoff = 0
   -- Reset State fields that Noexp reads/writes
   State._tnl = 0
   State._level = 0
   State._noexp = false
   -- Reset CP state (check_tnl checks CP._on_cp)
   CP._on_cp = false
end

run_test("Noexp.init_defaults", function()
   Config._settings = {}
   Config.load()
   Noexp.init()
   assert_true(Noexp._auto_enabled, "auto enabled by default")
   assert_equal(0, Noexp._tnl_cutoff, "tnl cutoff defaults to 0")
end)

run_test("Noexp.init_custom", function()
   mock.variables["snd_noexp_auto"] = "off"
   mock.variables["snd_noexp_tnl_cutoff"] = "500"
   Config._settings = {}
   Config.load()
   Noexp.init()
   assert_false(Noexp._auto_enabled, "auto disabled when config says off")
   assert_equal(500, Noexp._tnl_cutoff, "tnl cutoff from config")
end)

run_test("Noexp.check_tnl_disabled", function()
   Noexp._auto_enabled = false
   Noexp._noexp_on = false
   State._tnl = 100
   Noexp._tnl_cutoff = 500
   Noexp.check_tnl()
   assert_false(Noexp._noexp_on, "noexp stays off when auto disabled")
   assert_nil(mock.calls["SendNoEcho"], "no command sent when auto disabled")
end)

run_test("Noexp.check_tnl_cutoff_zero", function()
   Noexp._auto_enabled = true
   Noexp._noexp_on = false
   State._tnl = 100
   Noexp._tnl_cutoff = 0
   State._level = 50
   Noexp.check_tnl()
   assert_false(Noexp._noexp_on, "noexp stays off when cutoff is 0")
end)

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

run_test("Noexp.check_tnl_level_200", function()
   Noexp._auto_enabled = true
   Noexp._noexp_on = true
   Noexp._tnl_cutoff = 500
   State._tnl = 100
   State._level = 200
   Noexp.check_tnl()
   assert_false(Noexp._noexp_on, "noexp forced off at level 200")
end)

run_test("Noexp.check_tnl_level_201", function()
   Noexp._auto_enabled = true
   Noexp._noexp_on = true
   Noexp._tnl_cutoff = 500
   State._tnl = 100
   State._level = 201
   Noexp.check_tnl()
   assert_false(Noexp._noexp_on, "noexp forced off at level 201")
end)

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

run_test("Noexp.set_no_change", function()
   Noexp._noexp_on = true
   Noexp.set(true)
   assert_nil(mock.calls["SendNoEcho"], "no command when setting same state")
   assert_nil(mock.calls["BroadcastPlugin"], "no broadcast when setting same state")
end)

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

run_test("Noexp.check_tnl_exact_cutoff_off", function()
   -- When OFF and TNL == cutoff: stays OFF (uses <, not <=)
   Noexp._auto_enabled = true
   Noexp._noexp_on = false
   Noexp._tnl_cutoff = 500
   State._tnl = 500
   State._level = 50
   Noexp.check_tnl()
   assert_false(Noexp._noexp_on, "noexp stays off when TNL exactly equals cutoff")
end)

run_test("Noexp.check_tnl_exact_cutoff_on", function()
   -- When ON and TNL == cutoff: stays ON (gap: neither < nor > fires)
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
