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

--- Test: Config._defaults contains expected default values for all settings
-- Input: none (reads Config._defaults table directly)
-- Expected: quick_kill_command="k", noexp_auto="on", debug_mode="off", etc.
-- Covers: Config._defaults
run_test("Config.defaults", function()
   assert_equal("k", Config._defaults.quick_kill_command, "quick_kill_command default is k")
   assert_equal("on", Config._defaults.noexp_auto, "noexp_auto default is on")
   assert_equal("0", Config._defaults.noexp_tnl_cutoff, "noexp_tnl_cutoff default is 0")
   assert_equal("off", Config._defaults.debug_mode, "debug_mode default is off")
end)

--- Test: Config.load uses defaults when no stored variables exist
-- Setup: mock.variables empty
-- Expected: Config.get returns defaults for all keys
-- Covers: Config.load(), Config.get()
run_test("Config.load", function()
   Config.load()
   assert_equal("k", Config.get("quick_kill_command"), "load uses default for missing variable")
   assert_equal("off", Config.get("debug_mode"), "load uses default for debug_mode")
end)

--- Test: Config.load reads stored MUSHclient variables over defaults
-- Setup: mock.variables has snd_quick_kill_command="kill", snd_debug_mode="on"
-- Expected: Config.get returns stored values, not defaults
-- Covers: Config.load(), Config.get()
run_test("Config.load_with_stored", function()
   mock.variables["snd_quick_kill_command"] = "kill"
   mock.variables["snd_debug_mode"] = "on"
   Config.load()
   assert_equal("kill", Config.get("quick_kill_command"), "load uses stored quick_kill_command")
   assert_equal("on", Config.get("debug_mode"), "load uses stored debug_mode")
end)

--- Test: Config.set updates value and marks dirty for valid keys
-- Setup: Config loaded with defaults
-- Input: Config.set("debug_mode", "on")
-- Expected: returns true, value updated, dirty flag set
-- Covers: Config.set()
run_test("Config.set", function()
   Config.load()
   local ok = Config.set("debug_mode", "on")
   assert_true(ok, "set returns true for valid key")
   assert_equal("on", Config.get("debug_mode"), "set updates value")
   assert_true(Config._dirty, "set marks config as dirty")
end)

--- Test: Config.set rejects unknown keys without modifying state
-- Setup: Config loaded with defaults
-- Input: Config.set("nonexistent_key", "value")
-- Expected: returns false, dirty flag NOT set
-- Covers: Config.set() validation
run_test("Config.set_invalid", function()
   Config.load()
   local ok = Config.set("nonexistent_key", "value")
   assert_false(ok, "set returns false for unknown key")
   assert_false(Config._dirty, "set doesn't dirty on invalid key")
end)

--- Test: Config.get falls back to _defaults when key not in _settings
-- Setup: _settings is empty (no load called)
-- Expected: returns default value for known key
-- Covers: Config.get() fallback logic
run_test("Config.get_default_fallback", function()
   assert_equal("k", Config.get("quick_kill_command"), "get falls back to default")
end)

--- Test: Config.save writes settings to MUSHclient variables and clears dirty
-- Setup: _settings populated, _dirty=true
-- Expected: mock.variables has snd_ prefixed values, dirty cleared
-- Covers: Config.save()
run_test("Config.save", function()
   Config._settings = {xcp_action_mode = "ht", debug_mode = "on"}
   Config._dirty = true
   Config.save()
   assert_equal("ht", mock.variables["snd_xcp_action_mode"], "save stores to variable")
   assert_equal("on", mock.variables["snd_debug_mode"], "save stores debug_mode")
   assert_false(Config._dirty, "save clears dirty flag")
end)

--- Test: Config.save is a no-op when not dirty
-- Setup: _dirty=false
-- Expected: SetVariable never called
-- Covers: Config.save() dirty guard
run_test("Config.save_not_dirty", function()
   Config._dirty = false
   Config.save()
   assert_nil(mock.calls["SetVariable"], "save doesn't call SetVariable when not dirty")
end)

--- Test: Config set → save → reload preserves values
-- Setup: load defaults, set two values, save, clear settings, reload
-- Expected: reloaded values match what was set
-- Covers: Config.set(), Config.save(), Config.load() roundtrip
run_test("Config.roundtrip", function()
   Config.load()
   Config.set("quick_kill_command", "kill")
   Config.set("noexp_tnl_cutoff", "500")
   Config.save()
   Config._settings = {}
   Config.load()
   assert_equal("kill", Config.get("quick_kill_command"), "roundtrip preserves quick_kill_command")
   assert_equal("500", Config.get("noexp_tnl_cutoff"), "roundtrip preserves noexp_tnl_cutoff")
end)
