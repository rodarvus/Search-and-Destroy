------------------------------------------------------------------------
-- test_smart_scan.lua - Tests for SmartScan parsing (Phase 4 / Item A2)
-- Covers parse_flags, is_player, reset, and the on_scan_* / on_roomchars_*
-- callbacks. Render pipeline is tested separately once A5 lands.
------------------------------------------------------------------------

if not CONST then
   local load_plugin = require("load_plugin")
   load_plugin()
end

function setUp()
   mock.reset()
   SmartScan._scan_full_display = {}
   SmartScan._scanned_mobs = {}
   SmartScan._considered_mobs = {}
   SmartScan._running_smart_scan = false
   SmartScan._con_after_scan = false
   SmartScan._scanning_current_room = false
   SmartScan._mob_count_here = 0
   SmartScan._target_found_here = false
   SmartScan._target_found_nearby = false
end

------------------------------------------------------------------------
-- SmartScan.parse_flags
------------------------------------------------------------------------

run_test("SmartScan.parse_flags_empty", function()
   assert_equal(0, #SmartScan.parse_flags(""), "empty string -> empty list")
   assert_equal(0, #SmartScan.parse_flags(nil), "nil -> empty list")
end)

run_test("SmartScan.parse_flags_single_paren", function()
   local flags = SmartScan.parse_flags(" (Old)")
   assert_equal(1, #flags, "one flag")
   assert_equal("Old", flags[1], "flag content without parens")
end)

run_test("SmartScan.parse_flags_multiple", function()
   local flags = SmartScan.parse_flags(" (Old) (Hidden) (Invis)")
   assert_equal(3, #flags, "three flags")
   assert_equal("Old", flags[1])
   assert_equal("Hidden", flags[2])
   assert_equal("Invis", flags[3])
end)

run_test("SmartScan.parse_flags_afk_bracket", function()
   local flags = SmartScan.parse_flags(" [AFK] (P)")
   assert_equal(2, #flags, "AFK bracket + paren")
   -- order: brackets first, then parens (impl detail; test both present)
   local has_afk, has_p = false, false
   for _, f in ipairs(flags) do
      if f == "AFK" then has_afk = true end
      if f == "P" then has_p = true end
   end
   assert_true(has_afk, "AFK extracted")
   assert_true(has_p, "P extracted")
end)

------------------------------------------------------------------------
-- SmartScan.is_player
------------------------------------------------------------------------

run_test("SmartScan.is_player_short_P", function()
   assert_true(SmartScan.is_player(" (P)"), "(P) is player")
end)

run_test("SmartScan.is_player_long_word", function()
   assert_true(SmartScan.is_player(" (Player)"), "(Player) is player")
end)

run_test("SmartScan.is_player_OPK", function()
   assert_true(SmartScan.is_player(" (OPK) (Linkdead)"), "OPK is player")
end)

run_test("SmartScan.is_player_mob_flags_not_player", function()
   assert_false(SmartScan.is_player(" (Old)"), "Old is not player")
   assert_false(SmartScan.is_player(" (Hidden) (Invis)"), "mob flags only")
end)

run_test("SmartScan.is_player_empty", function()
   assert_false(SmartScan.is_player(""), "no flags = not player")
   assert_false(SmartScan.is_player(nil), "nil = not player")
end)

------------------------------------------------------------------------
-- on_scan_start / on_scan_end markers
------------------------------------------------------------------------

run_test("on_scan_start.clears_and_enables", function()
   -- Pre-state: stale data from prior scan
   SmartScan._scan_full_display = {{header = "stale", mobs = {}, doors = {}}}
   SmartScan._scanned_mobs = {"stale_mob"}
   SmartScan._scanning_current_room = true
   mock.reset()

   on_scan_start("trg_scan_start", "{scan}", {})

   assert_equal(0, #SmartScan._scan_full_display, "accumulator cleared")
   assert_equal(0, #SmartScan._scanned_mobs, "scanned_mobs cleared")
   assert_false(SmartScan._scanning_current_room, "scanning flag reset")
   -- grp_scan enabled
   local enabled = false
   for _, call in ipairs(mock.calls["EnableTriggerGroup"] or {}) do
      if call[1] == "grp_scan" and call[2] == true then enabled = true end
   end
   assert_true(enabled, "grp_scan enabled by on_scan_start")
end)

run_test("on_scan_end.disables_group", function()
   mock.reset()
   on_scan_end("trg_scan_end", "{/scan}", {})
   local disabled = false
   for _, call in ipairs(mock.calls["EnableTriggerGroup"] or {}) do
      if call[1] == "grp_scan" and call[2] == false then disabled = true end
   end
   assert_true(disabled, "grp_scan disabled by on_scan_end")
end)

------------------------------------------------------------------------
-- on_roomchars_*
------------------------------------------------------------------------

run_test("on_roomchars_start.resets_and_enables", function()
   SmartScan._mob_count_here = 7
   mock.reset()
   on_roomchars_start("trg_roomchars_start", "{roomchars}", {})
   assert_equal(0, SmartScan._mob_count_here, "count reset to 0")
   local enabled = false
   for _, call in ipairs(mock.calls["EnableTriggerGroup"] or {}) do
      if call[1] == "grp_roomchars" and call[2] == true then enabled = true end
   end
   assert_true(enabled, "grp_roomchars enabled")
end)

run_test("on_roomchars_end.disables_group", function()
   mock.reset()
   on_roomchars_end("trg_roomchars_end", "{/roomchars}", {})
   local disabled = false
   for _, call in ipairs(mock.calls["EnableTriggerGroup"] or {}) do
      if call[1] == "grp_roomchars" and call[2] == false then disabled = true end
   end
   assert_true(disabled, "grp_roomchars disabled")
end)

run_test("on_roomchars_line.increments", function()
   SmartScan._mob_count_here = 0
   on_roomchars_line(nil, "any line", {})
   on_roomchars_line(nil, "another", {})
   on_roomchars_line(nil, "third", {})
   assert_equal(3, SmartScan._mob_count_here, "count = 3 after three lines")
end)

------------------------------------------------------------------------
-- on_scan_room_current / nearby
------------------------------------------------------------------------

run_test("on_scan_room_current.starts_block", function()
   on_scan_room_current(nil, "Right here you see:", {})
   assert_equal(1, #SmartScan._scan_full_display, "one block created")
   assert_true(SmartScan._scanning_current_room, "scanning_current_room set")
   assert_equal(0, SmartScan._scan_full_display[1].distance, "distance 0 for current")
   assert_equal("here", SmartScan._scan_full_display[1].direction, "direction here")
end)

run_test("on_scan_room_nearby.starts_block_no_distance", function()
   on_scan_room_nearby(nil, "North from here you see:", {[1] = false, [2] = "North"})
   assert_equal(1, #SmartScan._scan_full_display, "one block")
   assert_false(SmartScan._scanning_current_room, "scanning_current_room cleared")
   assert_equal(1, SmartScan._scan_full_display[1].distance, "default distance 1")
   assert_equal("north", SmartScan._scan_full_display[1].direction, "direction lowered")
end)

run_test("on_scan_room_nearby.captures_distance", function()
   on_scan_room_nearby(nil, "3 East from here you see:", {[1] = "3 ", [2] = "East"})
   assert_equal(3, SmartScan._scan_full_display[1].distance, "distance 3 captured")
   assert_equal("east", SmartScan._scan_full_display[1].direction, "direction east")
end)

------------------------------------------------------------------------
-- on_scan_mob
------------------------------------------------------------------------

run_test("on_scan_mob.appends_to_current_block", function()
   on_scan_room_current(nil, "Right here you see:", {})
   on_scan_mob(nil, "     - an old woman", {[1] = "", [2] = "an old woman"})
   on_scan_mob(nil, "     - the storm demon", {[1] = "", [2] = "the storm demon"})

   local block = SmartScan._scan_full_display[1]
   assert_equal(2, #block.mobs, "two mobs accumulated")
   assert_equal("an old woman", block.mobs[1].mob, "first mob name")
   assert_equal("the storm demon", block.mobs[2].mob, "second mob name")
   -- Currently scanning current room → scanned_mobs populated (lowercase)
   assert_equal(2, #SmartScan._scanned_mobs, "scanned_mobs has 2 entries")
   assert_equal("an old woman", SmartScan._scanned_mobs[1], "lowercase tracked")
end)

run_test("on_scan_mob.skips_player_P", function()
   on_scan_room_current(nil, "Right here you see:", {})
   on_scan_mob(nil, "     - (P) bob", {[1] = " (P)", [2] = "bob"})
   assert_equal(0, #SmartScan._scan_full_display[1].mobs, "player skipped")
   assert_equal(0, #SmartScan._scanned_mobs, "player not tracked in scanned_mobs")
end)

run_test("on_scan_mob.skips_player_word", function()
   on_scan_room_current(nil, "Right here you see:", {})
   on_scan_mob(nil, "     - (Player) alice", {[1] = " (Player)", [2] = "alice"})
   assert_equal(0, #SmartScan._scan_full_display[1].mobs, "Player word skipped")
end)

run_test("on_scan_mob.nearby_room_does_not_track_in_scanned_mobs", function()
   -- scanned_mobs is the list of mobs in the CURRENT room (used by smart-scan
   -- to decide if we need to auto-`con` for hidden mobs). Nearby-room mobs go
   -- into the display block but not the local-mob count.
   on_scan_room_nearby(nil, "1 North from here you see:", {[1] = "1 ", [2] = "North"})
   on_scan_mob(nil, "     - a guard", {[1] = "", [2] = "a guard"})
   assert_equal(1, #SmartScan._scan_full_display[1].mobs, "mob in nearby block")
   assert_equal(0, #SmartScan._scanned_mobs, "nearby mob not in scanned_mobs")
end)

run_test("on_scan_mob.no_room_block_safe", function()
   -- Defensive: mob line before any room header (shouldn't happen in real output)
   on_scan_mob(nil, "     - orphan", {[1] = "", [2] = "orphan"})
   assert_equal(0, #SmartScan._scan_full_display, "no crash, no spurious block")
end)

------------------------------------------------------------------------
-- on_scan_door / on_scan_empty
------------------------------------------------------------------------

run_test("on_scan_door.appends", function()
   on_scan_room_current(nil, "Right here you see:", {})
   on_scan_door(nil, "You see a door north.", {})
   assert_equal(1, #SmartScan._scan_full_display[1].doors, "door appended")
end)

run_test("on_scan_empty.notes_unless_smart", function()
   SmartScan._running_smart_scan = false
   mock.reset()
   on_scan_empty(nil, "Nothing to see around here, might as well move on.", {})
   assert_not_nil(mock.calls["Note"], "Note printed when not smart-scan")

   SmartScan._running_smart_scan = true
   mock.reset()
   on_scan_empty(nil, "Nothing to see around here, might as well move on.", {})
   assert_nil(mock.calls["Note"], "Note suppressed during smart-scan")
end)

------------------------------------------------------------------------
-- on_consider_mob (Item A3) — re-render with [CP] tag + difficulty colour
------------------------------------------------------------------------

--- Helper: install CP target + ensure display_overwrite=on
local function setup_consider_test()
   Config.load()
   Config._settings = {}  -- defaults
   State._activity = "cp"
   State._room = {rmid = 1254, arid = "diatz", name = "x", exits = {}, maze = false}
   TargetList._main_list = {{
      mob = "an old woman", area_key = "diatz", link_type = "area",
      keyword = "old", dead = false, index = 1, _input_order = 1, rooms = {},
   }}
end

run_test("on_consider_mob.renders_with_tag_when_target_match", function()
   setup_consider_test()
   mock.reset()
   on_consider_mob("trg_con_5", "an old woman should be a fair fight!", {[1] = "an old woman"})

   -- Tag emitted via ColourTell ("[", "CP", "] "), then mob silver, then level lime
   local tells = mock.calls["ColourTell"] or {}
   assert_true(#tells >= 4, "ColourTell called for tag segments + mob")
   -- Level range note (lime for con_5) emitted via ColourNote
   local notes = mock.calls["ColourNote"] or {}
   local found_level = false
   for _, c in ipairs(notes) do
      if c[3] and string.find(c[3], "%-1 to %+1") then found_level = true end
   end
   assert_true(found_level, "level range '-1 to +1' rendered")
end)

run_test("on_consider_mob.renders_no_tag_when_not_target", function()
   setup_consider_test()
   -- Mob NOT on target list
   mock.reset()
   on_consider_mob("trg_con_5", "a random goat should be a fair fight!", {[1] = "a random goat"})

   local tells = mock.calls["ColourTell"] or {}
   -- Without tag: just 1 mob ColourTell (silver), no bracket/CP/bracket
   assert_equal(1, #tells, "only mob name ColourTell, no tag segments")
   assert_equal("a random goat", tells[1][3], "mob name printed")
end)

run_test("on_consider_mob.overwrite_off_passthrough", function()
   setup_consider_test()
   Config._settings.display_overwrite = "off"
   mock.reset()
   on_consider_mob("trg_con_5", "an old woman should be a fair fight!", {[1] = "an old woman"})

   -- With overwrite off, just Note the original line
   local notes = mock.calls["Note"] or {}
   assert_equal(1, #notes, "Note called once with original line")
   assert_equal("an old woman should be a fair fight!", notes[1][1], "original line passed through")
   assert_nil(mock.calls["ColourTell"], "no re-render when overwrite off")
end)

run_test("on_consider_mob.tracks_in_considered_mobs", function()
   setup_consider_test()
   SmartScan._considered_mobs = {}
   on_consider_mob("trg_con_5", "an old woman should be a fair fight!", {[1] = "an old woman"})
   on_consider_mob("trg_con_3", "No Problem! the goblin is weak compared to you.", {[1] = "the goblin"})

   assert_equal(2, #SmartScan._considered_mobs, "two mobs tracked")
   assert_equal("an old woman", SmartScan._considered_mobs[1], "lowercase tracking")
   assert_equal("the goblin", SmartScan._considered_mobs[2])
end)

run_test("on_consider_mob.unknown_trigger_safe", function()
   setup_consider_test()
   mock.reset()
   -- Defensive: shouldn't crash on unknown trigger name
   on_consider_mob("trg_unknown", "garbage line", {[1] = "ghost"})
   assert_nil(mock.calls["ColourTell"], "no render for unknown trigger")
   assert_nil(mock.calls["ColourNote"], "no note for unknown trigger")
end)

run_test("on_consider_mob.con_after_scan_skips_non_target", function()
   setup_consider_test()
   SmartScan._con_after_scan = true
   mock.reset()
   -- Non-target mob during con_after_scan → skipped (no spam)
   on_consider_mob("trg_con_5", "a random goat should be a fair fight!", {[1] = "a random goat"})
   assert_nil(mock.calls["ColourTell"], "non-target skipped during con_after_scan")
   assert_nil(mock.calls["ColourNote"], "no level note for skipped mob")
end)

run_test("on_consider_mob.con_after_scan_renders_target", function()
   setup_consider_test()
   SmartScan._con_after_scan = true
   mock.reset()
   -- Target mob still rendered during con_after_scan
   on_consider_mob("trg_con_5", "an old woman should be a fair fight!", {[1] = "an old woman"})
   assert_not_nil(mock.calls["ColourTell"], "target rendered during con_after_scan")
end)

------------------------------------------------------------------------
-- Display.render_scan (Item A5)
------------------------------------------------------------------------

run_test("Display.render_scan_with_tags", function()
   Config._settings = {}  -- defaults: display_overwrite="on"
   State._activity = "cp"
   State._room = {rmid = 1254, arid = "diatz", name = "x", exits = {}, maze = false}
   TargetList._main_list = {{
      mob = "an old woman", area_key = "diatz", link_type = "area",
      keyword = "old", dead = false, index = 1, _input_order = 1, rooms = {},
   }}
   local blocks = {{
      header = "Right here you see:",
      mobs = {{flags = "", mob = "an old woman", line = "     - an old woman"}},
      doors = {},
   }}
   mock.reset()
   Display.render_scan(blocks)
   -- Header noted
   local notes = mock.calls["Note"] or {}
   local found_header = false
   for _, n in ipairs(notes) do if n[1] == "Right here you see:" then found_header = true end end
   assert_true(found_header, "header noted")
   -- Tag emitted (3 ColourTell calls for [, CP, ])
   assert_not_nil(mock.calls["ColourTell"], "tag ColourTell emitted")
   -- Stripped line noted (leading 5 spaces removed in front of dash)
   local found_stripped = false
   for _, n in ipairs(notes) do
      if n[1] == "- an old woman" then found_stripped = true end
   end
   assert_true(found_stripped, "mob line stripped of leading indent")
end)

run_test("Display.render_scan_without_tags", function()
   Config._settings = {}
   State._activity = "cp"
   State._room = {rmid = 1254, arid = "diatz", name = "x", exits = {}, maze = false}
   TargetList._main_list = {}  -- no targets, so no tags
   local blocks = {{
      header = "Right here you see:",
      mobs = {{flags = "", mob = "a goat", line = "     - a goat"}},
      doors = {},
   }}
   mock.reset()
   Display.render_scan(blocks)
   assert_nil(mock.calls["ColourTell"], "no tag for non-target mob")
   -- Original line passed through (with leading indent intact)
   local notes = mock.calls["Note"] or {}
   local found_orig = false
   for _, n in ipairs(notes) do
      if n[1] == "     - a goat" then found_orig = true end
   end
   assert_true(found_orig, "original line emitted as-is when no tag")
end)

run_test("Display.render_scan_empty_blocks_skipped", function()
   Config._settings = {}
   local blocks = {
      {header = "Right here you see:", mobs = {}, doors = {}},  -- empty: skip header too
      {header = "1 North from here you see:", mobs = {{flags = "", mob = "a guard", line = "     - a guard"}}, doors = {}},
   }
   mock.reset()
   Display.render_scan(blocks)
   local notes = mock.calls["Note"] or {}
   local found_empty_header = false
   for _, n in ipairs(notes) do
      if n[1] == "Right here you see:" then found_empty_header = true end
   end
   assert_false(found_empty_header, "empty room header suppressed")
end)

run_test("Display.render_scan_overwrite_off_passthrough", function()
   Config._settings = {display_overwrite = "off"}
   State._activity = "cp"
   State._room = {rmid = 1254, arid = "diatz", name = "x", exits = {}, maze = false}
   TargetList._main_list = {{
      mob = "an old woman", area_key = "diatz", link_type = "area",
      keyword = "old", dead = false, index = 1, _input_order = 1, rooms = {},
   }}
   local blocks = {{
      header = "Right here you see:",
      mobs = {{flags = "", mob = "an old woman", line = "     - an old woman"}},
      doors = {},
   }}
   mock.reset()
   Display.render_scan(blocks)
   assert_nil(mock.calls["ColourTell"], "no tag rendering when overwrite off")
   -- Plain Note for both header and mob line
   local notes = mock.calls["Note"] or {}
   assert_true(#notes >= 2, "header + mob line both noted")
end)

run_test("Display.render_scan_doors_rendered", function()
   Config._settings = {}
   local blocks = {{
      header = "Right here you see:",
      mobs = {{flags = "", mob = "a goat", line = "     - a goat"}},
      doors = {{line = "You see a closed door north."}},
   }}
   mock.reset()
   Display.render_scan(blocks)
   local notes = mock.calls["Note"] or {}
   local found_door = false
   for _, n in ipairs(notes) do
      if n[1] == "You see a closed door north." then found_door = true end
   end
   assert_true(found_door, "door line rendered after mobs")
end)

------------------------------------------------------------------------
-- on_scan_end render + auto-con fallback
------------------------------------------------------------------------

run_test("on_scan_end.renders_blocks", function()
   Config._settings = {}
   State._activity = "cp"
   State._room = {rmid = 1254, arid = "diatz", name = "x", exits = {}, maze = false}
   TargetList._main_list = {}
   SmartScan._scan_full_display = {{
      header = "Right here you see:",
      mobs = {{flags = "", mob = "a goat", line = "     - a goat"}},
      doors = {},
   }}
   SmartScan._running_smart_scan = false
   SmartScan._mob_count_here = 0
   mock.reset()
   on_scan_end(nil, "{/scan}", {})
   local notes = mock.calls["Note"] or {}
   assert_true(#notes >= 2, "header + mob noted")
end)

run_test("on_scan_end.smart_fallback_to_con", function()
   SmartScan._scan_full_display = {}
   SmartScan._running_smart_scan = true
   SmartScan._mob_count_here = 3   -- room has 3 mobs
   SmartScan._scanned_mobs = {"visible_mob"}  -- but only 1 in scan output
   mock.reset()
   on_scan_end(nil, "{/scan}", {})
   -- Auto-con fired
   local sends = mock.calls["SendNoEcho"] or {}
   local found_con = false
   for _, s in ipairs(sends) do if s[1] == "con" then found_con = true end end
   assert_true(found_con, "auto-con fired when scanned < roomchars during smart-scan")
   assert_true(SmartScan._con_after_scan, "_con_after_scan flag set")
   assert_false(SmartScan._running_smart_scan, "_running_smart_scan reset after handling")
end)

run_test("on_scan_end.no_fallback_when_not_smart", function()
   SmartScan._scan_full_display = {}
   SmartScan._running_smart_scan = false
   SmartScan._mob_count_here = 3
   SmartScan._scanned_mobs = {"visible_mob"}
   mock.reset()
   on_scan_end(nil, "{/scan}", {})
   local sends = mock.calls["SendNoEcho"] or {}
   for _, s in ipairs(sends) do
      assert_false(s[1] == "con", "no auto-con fired during plain scan")
   end
end)

run_test("on_scan_end.no_fallback_when_all_seen", function()
   SmartScan._scan_full_display = {}
   SmartScan._running_smart_scan = true
   SmartScan._mob_count_here = 2
   SmartScan._scanned_mobs = {"a", "b"}  -- equal
   mock.reset()
   on_scan_end(nil, "{/scan}", {})
   local sends = mock.calls["SendNoEcho"] or {}
   for _, s in ipairs(sends) do
      assert_false(s[1] == "con", "no auto-con when scanned == roomchars")
   end
end)

--- Test: scan_end persists current-room scanned mobs to S&D mobs DB
-- Why: Phase 3's DB-first xcp flow needs growing mob history. Without this write,
--   scanning never feeds the DB and xcp degrades to discovery-only over time.
-- Covers: on_scan_end() DB persistence — Crowley's write_mob_list_to_db
run_test("on_scan_end.persists_scanned_mobs_to_db", function()
   mock.reset_db()
   DB.init()
   State._room = {rmid = 786, arid = "dortmund", name = "A dirt road", exits = {}, maze = false}
   SmartScan._scan_full_display = {}
   SmartScan._scanned_mobs = {"an old woman", "a townswoman"}
   SmartScan._running_smart_scan = false
   SmartScan._mob_count_here = 2

   on_scan_end(nil, "{/scan}", {})

   local rows = DB.find_mob("an old woman", "dortmund")
   assert_true(#rows >= 1, "scanned mob persisted to DB")
   assert_equal(786, rows[1].roomid, "correct roomid stored")
   assert_equal("dortmund", rows[1].zone, "correct zone stored")

   local rows2 = DB.find_mob("a townswoman", "dortmund")
   assert_true(#rows2 >= 1, "second scanned mob persisted")
end)

--- Test: scan_end skips DB write when room data is missing
-- Setup: rmid invalid (-1) — plugin not yet got room.info
-- Covers: on_scan_end() defensive guard
run_test("on_scan_end.skips_db_write_no_room", function()
   mock.reset_db()
   DB.init()
   State._room = {rmid = -1, arid = "", name = "", exits = {}, maze = false}
   SmartScan._scan_full_display = {}
   SmartScan._scanned_mobs = {"some mob"}
   SmartScan._running_smart_scan = false
   SmartScan._mob_count_here = 1

   on_scan_end(nil, "{/scan}", {})

   local rows = DB.find_mob("some mob", "")
   assert_equal(0, #rows, "no DB write when room is invalid")
end)

------------------------------------------------------------------------
-- cmd_qs (Phase 4 / Item A5)
------------------------------------------------------------------------

run_test("cmd_qs.smart_scan_when_on_activity", function()
   State._activity = "cp"
   State._target = {mob = "an old woman", keyword = "old"}
   mock.reset()
   cmd_qs(nil, nil, {[1] = ""})
   assert_true(SmartScan._running_smart_scan, "smart-scan flag set")
   local sends = mock.calls["SendNoEcho"] or {}
   assert_equal("scan", sends[1] and sends[1][1], "raw scan sent silently")
end)

run_test("cmd_qs.filtered_when_target_no_activity", function()
   State._activity = "none"
   State._target = {mob = "an old woman", keyword = "old"}
   SmartScan._running_smart_scan = false
   mock.reset()
   cmd_qs(nil, nil, {[1] = ""})
   assert_false(SmartScan._running_smart_scan, "smart-scan flag NOT set without activity")
   local sends = mock.calls["Send"] or {}
   assert_equal("scan old", sends[1] and sends[1][1], "filtered scan with target keyword")
end)

run_test("cmd_qs.plain_when_no_target", function()
   State._activity = "none"
   State._target = nil
   SmartScan._running_smart_scan = false
   mock.reset()
   cmd_qs(nil, nil, {[1] = ""})
   local sends = mock.calls["Send"] or {}
   assert_equal("scan", sends[1] and sends[1][1], "plain scan sent")
end)
