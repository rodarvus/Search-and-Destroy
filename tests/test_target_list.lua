------------------------------------------------------------------------
-- test_target_list.lua - Tests for TargetList module
-- TDD: These tests define expected behavior. Implementation follows.
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
   -- Reset TargetList state
   TargetList._main_list = {}
   TargetList._type = "none"
end

function tearDown()
   mock.reset_db()
end

------------------------------------------------------------------------
-- detect_type: determine area-based vs room-based CP
------------------------------------------------------------------------

run_test("TargetList.detect_type_area", function()
   -- All locations are area names found in AREA_NAME_XREF
   local info_list = {
      {mob = "a sinister vandal", location = "The Three Pillars of Diatz"},
      {mob = "a mutated goat", location = "The Killing Fields"},
      {mob = "a dancing female patron", location = "Wayward Alehouse"},
   }
   local t = TargetList.detect_type(info_list)
   assert_equal("area", t, "all area names → area type")
end)

run_test("TargetList.detect_type_room", function()
   -- All locations are room names (not in AREA_NAME_XREF)
   local info_list = {
      {mob = "a troll guard", location = "In The Courtyard"},
      {mob = "an orc shaman", location = "Near The Fire Pit"},
      {mob = "a dark knight", location = "The Throne Room"},
   }
   local t = TargetList.detect_type(info_list)
   assert_equal("room", t, "no area names → room type")
end)

run_test("TargetList.detect_type_majority_area", function()
   -- Mix: 2 area names, 1 room name → area wins (majority)
   local info_list = {
      {mob = "a vandal", location = "The Three Pillars of Diatz"},
      {mob = "a goat", location = "The Killing Fields"},
      {mob = "a knight", location = "Some Unknown Room"},
   }
   local t = TargetList.detect_type(info_list)
   assert_equal("area", t, "2 area + 1 room → area")
end)

run_test("TargetList.detect_type_empty", function()
   local t = TargetList.detect_type({})
   assert_equal("none", t, "empty list → none")
end)

------------------------------------------------------------------------
-- build: area-based CP target list
------------------------------------------------------------------------

run_test("TargetList.build_area_basic", function()
   -- Build from cp_check_list with area-based CP
   local check_list = {
      {mob = "a sinister vandal", location = "The Three Pillars of Diatz", dead = false},
      {mob = "a mutated goat", location = "The Killing Fields", dead = false},
      {mob = "a dangerous scorpion", location = "Desert Doom", dead = true},
   }
   TargetList.build(check_list, "area", 45)

   assert_equal(3, TargetList.count(), "3 targets built")

   -- First target
   local t1 = TargetList.get(1)
   assert_not_nil(t1, "target 1 exists")
   assert_equal("a sinister vandal", t1.mob, "target 1 mob")
   assert_equal("area", t1.link_type, "target 1 link_type")
   assert_false(t1.dead, "target 1 alive")
   assert_not_nil(t1.keyword, "target 1 has keyword")
   assert_true(#t1.keyword > 0, "target 1 keyword not empty")

   -- Dead target should be in list
   local t3 = TargetList.get(3)
   assert_not_nil(t3, "target 3 exists")
   assert_true(t3.dead, "target 3 is dead")
end)

run_test("TargetList.build_area_resolves_area_key", function()
   local check_list = {
      {mob = "a sinister vandal", location = "The Three Pillars of Diatz", dead = false},
   }
   TargetList.build(check_list, "area", 45)
   local t = TargetList.get(1)
   assert_equal("diatz", t.area_key, "area key resolved from AREA_NAME_XREF")
end)

run_test("TargetList.resolve_area_key_nil", function()
   assert_nil(TargetList.resolve_area_key(nil), "nil location returns nil")
   assert_nil(TargetList.resolve_area_key(""), "empty location returns nil")
end)

run_test("TargetList.resolve_area_key_known", function()
   local key = TargetList.resolve_area_key("The Three Pillars of Diatz")
   assert_equal("diatz", key, "resolves known area from AREA_NAME_XREF")
end)

run_test("TargetList.build_area_unknown_location", function()
   -- Location that's not in AREA_NAME_XREF or mapper
   local check_list = {
      {mob = "a mystery mob", location = "Totally Unknown Area", dead = false},
   }
   TargetList.build(check_list, "area", 45)
   local t = TargetList.get(1)
   assert_not_nil(t, "unknown target still in list")
   assert_equal("unknown", t.link_type, "unknown location → unknown link_type")
end)

run_test("TargetList.build_area_keyword_generation", function()
   local check_list = {
      {mob = "a sinister vandal", location = "The Three Pillars of Diatz", dead = false},
   }
   TargetList.build(check_list, "area", 45)
   local t = TargetList.get(1)
   -- MobKeyword.guess("a sinister vandal", "diatz") should produce "sinis vanda"
   assert_match("sinis", t.keyword, "keyword starts with sinis")
   assert_match("vanda", t.keyword, "keyword ends with vanda")
end)

run_test("TargetList.build_area_mob_db_lookup", function()
   -- Pre-populate mob DB with a known mob
   DB.record_mob("a sinister vandal", "A Dusty Room", 1255, "diatz")
   local check_list = {
      {mob = "a sinister vandal", location = "The Three Pillars of Diatz", dead = false},
   }
   TargetList.build(check_list, "area", 45)
   local t = TargetList.get(1)
   assert_true(t.found_in_area, "mob found in area via DB")
   assert_true(#t.rooms > 0, "rooms list populated from mob DB")
end)

run_test("TargetList.build_area_mob_db_miss", function()
   -- No mob DB history for this mob
   local check_list = {
      {mob = "a never seen creature", location = "The Three Pillars of Diatz", dead = false},
   }
   TargetList.build(check_list, "area", 45)
   local t = TargetList.get(1)
   assert_false(t.found_in_area, "mob not found in area")
   assert_equal(0, #t.rooms, "no rooms from DB")
end)

------------------------------------------------------------------------
-- build: sorting (alive first, dead last)
------------------------------------------------------------------------

run_test("TargetList.build_sorts_alive_first", function()
   local check_list = {
      {mob = "dead mob", location = "The Three Pillars of Diatz", dead = true},
      {mob = "alive mob", location = "The Killing Fields", dead = false},
   }
   TargetList.build(check_list, "area", 45)
   local t1 = TargetList.get(1)
   local t2 = TargetList.get(2)
   assert_false(t1.dead, "first target is alive")
   assert_true(t2.dead, "second target is dead")
end)

------------------------------------------------------------------------
-- get_alive: filter to alive targets only
------------------------------------------------------------------------

run_test("TargetList.get_alive", function()
   local check_list = {
      {mob = "dead mob", location = "The Three Pillars of Diatz", dead = true},
      {mob = "alive mob 1", location = "The Killing Fields", dead = false},
      {mob = "alive mob 2", location = "Desert Doom", dead = false},
   }
   TargetList.build(check_list, "area", 45)
   local alive = TargetList.get_alive()
   assert_equal(2, #alive, "2 alive targets")
   assert_equal("alive mob 1", alive[1].mob, "first alive mob")
   assert_equal("alive mob 2", alive[2].mob, "second alive mob")
end)

------------------------------------------------------------------------
-- find_by_mob: locate target by mob name
------------------------------------------------------------------------

run_test("TargetList.find_by_mob", function()
   local check_list = {
      {mob = "a sinister vandal", location = "The Three Pillars of Diatz", dead = false},
      {mob = "a mutated goat", location = "The Killing Fields", dead = false},
   }
   TargetList.build(check_list, "area", 45)
   local t = TargetList.find_by_mob("a mutated goat")
   assert_not_nil(t, "found by mob name")
   assert_equal("a mutated goat", t.mob, "correct mob returned")
end)

run_test("TargetList.find_by_mob_miss", function()
   local check_list = {
      {mob = "a sinister vandal", location = "The Three Pillars of Diatz", dead = false},
   }
   TargetList.build(check_list, "area", 45)
   local t = TargetList.find_by_mob("nonexistent mob")
   assert_nil(t, "nil for unknown mob")
end)

------------------------------------------------------------------------
-- update_dead: mark a target as dead
------------------------------------------------------------------------

run_test("TargetList.update_dead", function()
   local check_list = {
      {mob = "a sinister vandal", location = "The Three Pillars of Diatz", dead = false},
   }
   TargetList.build(check_list, "area", 45)
   assert_false(TargetList.get(1).dead, "initially alive")
   TargetList.update_dead("a sinister vandal")
   assert_true(TargetList.get(1).dead, "marked dead after update")
end)

------------------------------------------------------------------------
-- clear: reset list
------------------------------------------------------------------------

run_test("TargetList.clear", function()
   local check_list = {
      {mob = "a sinister vandal", location = "The Three Pillars of Diatz", dead = false},
   }
   TargetList.build(check_list, "area", 45)
   assert_equal(1, TargetList.count(), "1 target before clear")
   TargetList.clear()
   assert_equal(0, TargetList.count(), "0 targets after clear")
end)

------------------------------------------------------------------------
-- build: room-based CP (basic)
------------------------------------------------------------------------

run_test("TargetList.build_room_basic", function()
   local check_list = {
      {mob = "a troll guard", location = "In The Courtyard", dead = false},
   }
   TargetList.build(check_list, "room", 90)
   -- Room-based targets may resolve to "unknown" if mapper has no matching rooms
   -- (our mock mapper returns empty). That's correct behavior.
   local t = TargetList.get(1)
   assert_not_nil(t, "room target exists")
   assert_equal("a troll guard", t.mob, "mob name preserved")
end)

------------------------------------------------------------------------
-- CP check dead flag via build
------------------------------------------------------------------------

run_test("TargetList.build_dead_flag_from_check", function()
   -- Simulate cp check output where one mob is dead
   local check_list = {
      {mob = "a sinister vandal", location = "The Three Pillars of Diatz", dead = false},
      {mob = "a mutated goat", location = "The Killing Fields", dead = true},
   }
   TargetList.build(check_list, "area", 45)
   assert_false(TargetList.get(1).dead, "vandal is alive")
   assert_true(TargetList.get(2).dead, "goat is dead")
end)
