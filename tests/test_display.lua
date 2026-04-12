------------------------------------------------------------------------
-- test_display.lua - Tests for Display module (Phase 4 / Item A)
-- Display.tag_for_mob — the [CP]/[GQ]/[Q] tag prefix used by re-rendered
-- scan, consider, and live `where` output.
------------------------------------------------------------------------

if not CONST then
   local load_plugin = require("load_plugin")
   load_plugin()
end

function setUp()
   mock.reset()
   TargetList._main_list = {}
   TargetList._type = "none"
   State._activity = "none"
   State._room = {rmid = -1, arid = "", name = "", exits = {}, maze = false}
end

--- Helper: install a single CP target in TargetList for matching tests
local function install_cp_target(mob, area_key)
   State._activity = "cp"
   TargetList._main_list = {{
      mob = mob,
      area_key = area_key,
      link_type = "area",
      keyword = "",
      dead = false,
      index = 1,
      _input_order = 1,
      rooms = {},
   }}
end

--- Test: mob matches CP target in current area → returns gold/magenta [CP] tag
-- Setup: CP active, "an old woman" in dortmund, currently in dortmund
-- Expected: 3-segment style list — "[", "CP", "] "
-- Covers: Display.tag_for_mob() CP match path
run_test("Display.tag_for_mob_cp_match", function()
   install_cp_target("an old woman", "dortmund")
   State._room = {rmid = 786, arid = "dortmund", name = "A dirt road", exits = {}, maze = false}

   local tags = Display.tag_for_mob("an old woman")

   assert_equal(3, #tags, "three style segments")
   assert_equal("[", tags[1].text, "open bracket text")
   assert_equal("gold", tags[1].colour, "open bracket gold")
   assert_equal("CP", tags[2].text, "CP letters")
   assert_equal("magenta", tags[2].colour, "letters magenta")
   assert_equal("] ", tags[3].text, "close bracket + space")
   assert_equal("gold", tags[3].colour, "close bracket gold")
end)

--- Test: mob not on target list → empty result (no tag, no allocation)
-- Covers: Display.tag_for_mob() no-match path
run_test("Display.tag_for_mob_no_match", function()
   install_cp_target("an old woman", "dortmund")
   State._room = {rmid = 786, arid = "dortmund", name = "A dirt road", exits = {}, maze = false}

   local tags = Display.tag_for_mob("a random mob")

   assert_equal(0, #tags, "no tag for non-target mob")
end)

--- Test: mob on CP list but different area → no tag
-- Why: target.area_key is dortmund but we're in aylor — Crowley behavior
-- Covers: Display.tag_for_mob() area-match check
run_test("Display.tag_for_mob_wrong_area", function()
   install_cp_target("an old woman", "dortmund")
   State._room = {rmid = 32418, arid = "aylor", name = "Aylor", exits = {}, maze = false}

   local tags = Display.tag_for_mob("an old woman")

   assert_equal(0, #tags, "no tag when mob's area doesn't match current room")
end)

--- Test: case-insensitive mob name matching
-- Covers: Display.tag_for_mob() lowercase comparison
run_test("Display.tag_for_mob_case_insensitive", function()
   install_cp_target("An Old Woman", "dortmund")
   State._room = {rmid = 786, arid = "dortmund", name = "x", exits = {}, maze = false}

   local tags = Display.tag_for_mob("AN OLD WOMAN")
   assert_equal(3, #tags, "uppercase scan output matches mixed-case target")

   tags = Display.tag_for_mob("an old woman")
   assert_equal(3, #tags, "lowercase scan output matches mixed-case target")
end)

--- Test: no activity (idle) → empty result regardless of TargetList contents
-- Why: stale TargetList shouldn't cause spurious tags after CP cleared
-- Covers: Display.tag_for_mob() activity guard
run_test("Display.tag_for_mob_no_activity", function()
   install_cp_target("an old woman", "dortmund")
   State._activity = "none"  -- stale TargetList; activity reset
   State._room = {rmid = 786, arid = "dortmund", name = "x", exits = {}, maze = false}

   local tags = Display.tag_for_mob("an old woman")

   assert_equal(0, #tags, "no tag when activity is none")
end)

--- Test: empty target list → empty result
-- Covers: Display.tag_for_mob() empty list
run_test("Display.tag_for_mob_empty_target_list", function()
   State._activity = "cp"
   TargetList._main_list = {}
   State._room = {rmid = 786, arid = "dortmund", name = "x", exits = {}, maze = false}

   local tags = Display.tag_for_mob("anyone")

   assert_equal(0, #tags, "no tag when target list empty")
end)

--- Test: empty / nil mob name → empty result (defensive)
-- Covers: Display.tag_for_mob() input guard
run_test("Display.tag_for_mob_empty_input", function()
   install_cp_target("an old woman", "dortmund")
   State._room = {rmid = 786, arid = "dortmund", name = "x", exits = {}, maze = false}

   assert_equal(0, #Display.tag_for_mob(""), "empty string returns empty")
   assert_equal(0, #Display.tag_for_mob(nil), "nil returns empty")
end)

--- Test: target with link_type="unknown" matches regardless of current area
-- Why: Crowley treats unknown-area targets as "could be anywhere" — always tag
-- Covers: Display.tag_for_mob() link_type=="unknown" bypass
run_test("Display.tag_for_mob_unknown_area_target", function()
   State._activity = "cp"
   TargetList._main_list = {{
      mob = "mystery mob",
      area_key = nil,
      link_type = "unknown",
      keyword = "",
      dead = false,
      index = 1,
      _input_order = 1,
      rooms = {},
   }}
   State._room = {rmid = 32418, arid = "aylor", name = "Aylor", exits = {}, maze = false}

   local tags = Display.tag_for_mob("mystery mob")

   assert_equal(3, #tags, "unknown-area target tags regardless of current room")
end)

--- Test: tag uses uppercased activity ("cp" -> "CP", "gq" -> "GQ")
-- Covers: Display.tag_for_mob() activity formatting
run_test("Display.tag_for_mob_gq_activity", function()
   State._activity = "gq"
   TargetList._main_list = {{
      mob = "the dragon",
      area_key = "diatz",
      link_type = "area",
      keyword = "",
      dead = false,
      index = 1,
      _input_order = 1,
      rooms = {},
   }}
   State._room = {rmid = 1254, arid = "diatz", name = "x", exits = {}, maze = false}

   local tags = Display.tag_for_mob("the dragon")

   assert_equal("GQ", tags[2].text, "uppercase activity letters")
end)
