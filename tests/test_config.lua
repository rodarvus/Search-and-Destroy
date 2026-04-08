------------------------------------------------------------------------
-- test_config.lua - Tests for the Config module
------------------------------------------------------------------------

if not CONST then
   local load_plugin = require("load_plugin")
   load_plugin()
end

function setUp()
   mock.reset()
   Config._settings = {}
   Config._dirty = false
end

run_test("Config.defaults", function()
   assert_not_nil(Config._defaults.xcp_action_mode, "xcp_action_mode has default")
   assert_equal("qw", Config._defaults.xcp_action_mode, "xcp_action_mode default is qw")
   assert_equal("k", Config._defaults.quick_kill_command, "quick_kill_command default is k")
   assert_equal("on", Config._defaults.noexp_auto, "noexp_auto default is on")
   assert_equal("0", Config._defaults.noexp_tnl_cutoff, "noexp_tnl_cutoff default is 0")
   assert_equal("off", Config._defaults.debug_mode, "debug_mode default is off")
end)

run_test("Config.load", function()
   Config.load()
   assert_equal("qw", Config.get("xcp_action_mode"), "load uses default for missing variable")
   assert_equal("off", Config.get("debug_mode"), "load uses default for debug_mode")
end)

run_test("Config.load_with_stored", function()
   mock.variables["snd_xcp_action_mode"] = "ht"
   mock.variables["snd_debug_mode"] = "on"
   Config.load()
   assert_equal("ht", Config.get("xcp_action_mode"), "load uses stored xcp_action_mode")
   assert_equal("on", Config.get("debug_mode"), "load uses stored debug_mode")
end)

run_test("Config.set", function()
   Config.load()
   local ok = Config.set("debug_mode", "on")
   assert_true(ok, "set returns true for valid key")
   assert_equal("on", Config.get("debug_mode"), "set updates value")
   assert_true(Config._dirty, "set marks config as dirty")
end)

run_test("Config.set_invalid", function()
   Config.load()
   local ok = Config.set("nonexistent_key", "value")
   assert_false(ok, "set returns false for unknown key")
   assert_false(Config._dirty, "set doesn't dirty on invalid key")
end)

run_test("Config.get_default_fallback", function()
   -- _settings empty, get should fall back to default
   assert_equal("qw", Config.get("xcp_action_mode"), "get falls back to default")
end)

run_test("Config.save", function()
   Config._settings = {xcp_action_mode = "ht", debug_mode = "on"}
   Config._dirty = true
   Config.save()
   assert_equal("ht", mock.variables["snd_xcp_action_mode"], "save stores to variable")
   assert_equal("on", mock.variables["snd_debug_mode"], "save stores debug_mode")
   assert_false(Config._dirty, "save clears dirty flag")
end)

run_test("Config.save_not_dirty", function()
   Config._dirty = false
   Config.save()
   assert_nil(mock.calls["SetVariable"], "save doesn't call SetVariable when not dirty")
end)

run_test("Config.roundtrip", function()
   Config.load()
   Config.set("quick_kill_command", "kill")
   Config.set("noexp_tnl_cutoff", "500")
   Config.save()
   -- Simulate reload
   Config._settings = {}
   Config.load()
   assert_equal("kill", Config.get("quick_kill_command"), "roundtrip preserves quick_kill_command")
   assert_equal("500", Config.get("noexp_tnl_cutoff"), "roundtrip preserves noexp_tnl_cutoff")
end)
