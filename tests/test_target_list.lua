------------------------------------------------------------------------
-- test_target_list.lua - Tests for TargetList module
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
   TargetList._main_list = {}
   TargetList._type = "none"
end

function tearDown()
   mock.reset_db()
end

------------------------------------------------------------------------
-- detect_type: determine area-based vs room-based CP
------------------------------------------------------------------------

--- Test: All locations are known area names → "area" type
-- Input: 3 targets with locations matching AREA_NAME_XREF entries
-- Expected: "area"
-- Covers: TargetList.detect_type()
run_test("TargetList.detect_type_area", function()
   local info_list = {
      {mob = "a sinister vandal", location = "The Three Pillars of Diatz"},
      {mob = "a mutated goat", location = "The Killing Fields"},
      {mob = "a dancing female patron", location = "Wayward Alehouse"},
   }
   local t = TargetList.detect_type(info_list)
   assert_equal("area", t, "all area names → area type")
end)

--- Test: No locations match area names → "room" type
-- Input: 3 targets with room names not in AREA_NAME_XREF
-- Expected: "room"
-- Covers: TargetList.detect_type()
run_test("TargetList.detect_type_room", function()
   local info_list = {
      {mob = "a troll guard", location = "In The Courtyard"},
      {mob = "an orc shaman", location = "Near The Fire Pit"},
      {mob = "a dark knight", location = "The Throne Room"},
   }
   local t = TargetList.detect_type(info_list)
   assert_equal("room", t, "no area names → room type")
end)

--- Test: Majority area names wins tie (2 area, 1 room → "area")
-- Input: 2 known area names + 1 unknown
-- Expected: "area" (area_count >= room_count)
-- Covers: TargetList.detect_type() majority voting
run_test("TargetList.detect_type_majority_area", function()
   local info_list = {
      {mob = "a vandal", location = "The Three Pillars of Diatz"},
      {mob = "a goat", location = "The Killing Fields"},
      {mob = "a knight", location = "Some Unknown Room"},
   }
   local t = TargetList.detect_type(info_list)
   assert_equal("area", t, "2 area + 1 room → area")
end)

--- Test: Empty list returns "none"
-- Input: empty info_list
-- Expected: "none"
-- Covers: TargetList.detect_type() empty guard
run_test("TargetList.detect_type_empty", function()
   local t = TargetList.detect_type({})
   assert_equal("none", t, "empty list → none")
end)

------------------------------------------------------------------------
-- build: area-based CP target list
------------------------------------------------------------------------

--- Test: Build creates correct number of targets with keywords and dead flags
-- Input: 3 targets (2 alive, 1 dead) in known areas
-- Expected: 3 targets, alive first, each with keyword and correct dead flag
-- Covers: TargetList.build(), TargetList.count(), TargetList.get()
run_test("TargetList.build_area_basic", function()
   local check_list = {
      {mob = "a sinister vandal", location = "The Three Pillars of Diatz", dead = false},
      {mob = "a mutated goat", location = "The Killing Fields", dead = false},
      {mob = "a dangerous scorpion", location = "Desert Doom", dead = true},
   }
   TargetList.build(check_list, "area", 45)
   assert_equal(3, TargetList.count(), "3 targets built")
   local t1 = TargetList.get(1)
   assert_not_nil(t1, "target 1 exists")
   assert_equal("a sinister vandal", t1.mob, "target 1 mob")
   assert_equal("area", t1.link_type, "target 1 link_type")
   assert_false(t1.dead, "target 1 alive")
   assert_not_nil(t1.keyword, "target 1 has keyword")
   assert_true(#t1.keyword > 0, "target 1 keyword not empty")
   local t3 = TargetList.get(3)
   assert_not_nil(t3, "target 3 exists")
   assert_true(t3.dead, "target 3 is dead")
end)

--- Test: Build resolves area key from AREA_NAME_XREF
-- Input: target in "The Three Pillars of Diatz"
-- Expected: area_key = "diatz"
-- Covers: TargetList.build() → TargetList.resolve_area_key()
run_test("TargetList.build_area_resolves_area_key", function()
   local check_list = {
      {mob = "a sinister vandal", location = "The Three Pillars of Diatz", dead = false},
   }
   TargetList.build(check_list, "area", 45)
   local t = TargetList.get(1)
   assert_equal("diatz", t.area_key, "area key resolved from AREA_NAME_XREF")
end)

--- Test: resolve_area_key returns nil for nil/empty input
-- Input: nil, ""
-- Expected: nil for both
-- Covers: TargetList.resolve_area_key() nil guard
run_test("TargetList.resolve_area_key_nil", function()
   assert_nil(TargetList.resolve_area_key(nil), "nil location returns nil")
   assert_nil(TargetList.resolve_area_key(""), "empty location returns nil")
end)

--- Test: resolve_area_key returns correct key for known area using XREF only
-- Input: "The Three Pillars of Diatz"
-- Expected: "diatz", no mapper query made (XREF lookup only)
-- Covers: TargetList.resolve_area_key() AREA_NAME_XREF lookup
run_test("TargetList.resolve_area_key_known", function()
   mock.reset()
   local key = TargetList.resolve_area_key("The Three Pillars of Diatz")
   assert_equal("diatz", key, "resolves known area from AREA_NAME_XREF")
   -- Should NOT call mapper (no CallPlugin / map_query)
   assert_nil(mock.calls["CallPlugin"], "no mapper query for XREF-resolvable area")
end)

--- Test: Unknown location produces target with link_type "unknown"
-- Input: target in "Totally Unknown Area" (not in XREF or mapper)
-- Expected: target exists but link_type = "unknown"
-- Covers: TargetList.build() unknown area handling
run_test("TargetList.build_area_unknown_location", function()
   local check_list = {
      {mob = "a mystery mob", location = "Totally Unknown Area", dead = false},
   }
   TargetList.build(check_list, "area", 45)
   local t = TargetList.get(1)
   assert_not_nil(t, "unknown target still in list")
   assert_equal("unknown", t.link_type, "unknown location → unknown link_type")
end)

--- Test: Build generates keywords via MobKeyword.guess
-- Input: "a sinister vandal" in "diatz"
-- Expected: keyword contains "sinis" and "vanda" fragments
-- Covers: TargetList.build() → MobKeyword.guess()
run_test("TargetList.build_area_keyword_generation", function()
   local check_list = {
      {mob = "a sinister vandal", location = "The Three Pillars of Diatz", dead = false},
   }
   TargetList.build(check_list, "area", 45)
   local t = TargetList.get(1)
   assert_match("sinis", t.keyword, "keyword starts with sinis")
   assert_match("vanda", t.keyword, "keyword ends with vanda")
end)

--- Test: Build populates rooms from mob DB when mob history exists
-- Setup: pre-populate DB with mob sighting in diatz
-- Expected: found_in_area=true, rooms list non-empty
-- Covers: TargetList.build() → DB.find_mob() integration
run_test("TargetList.build_area_mob_db_lookup", function()
   DB.record_mob("a sinister vandal", "A Dusty Room", 1255, "diatz")
   local check_list = {
      {mob = "a sinister vandal", location = "The Three Pillars of Diatz", dead = false},
   }
   TargetList.build(check_list, "area", 45)
   local t = TargetList.get(1)
   assert_true(t.found_in_area, "mob found in area via DB")
   assert_true(#t.rooms > 0, "rooms list populated from mob DB")
end)

--- Test: Build handles mob not in DB (no history)
-- Input: mob never recorded in DB
-- Expected: found_in_area=false, rooms empty
-- Covers: TargetList.build() DB miss path
run_test("TargetList.build_area_mob_db_miss", function()
   local check_list = {
      {mob = "a never seen creature", location = "The Three Pillars of Diatz", dead = false},
   }
   TargetList.build(check_list, "area", 45)
   local t = TargetList.get(1)
   assert_false(t.found_in_area, "mob not found in area")
   assert_equal(0, #t.rooms, "no rooms from DB")
end)

------------------------------------------------------------------------
-- Sorting
------------------------------------------------------------------------

--- Test: Build sorts alive targets before dead targets
-- Input: dead first, alive second in input order
-- Expected: alive at index 1, dead at index 2 after sort
-- Covers: TargetList.build() stable sort (alive before dead)
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
-- get_alive
------------------------------------------------------------------------

--- Test: get_alive returns only alive targets in order
-- Input: 1 dead + 2 alive targets
-- Expected: 2-element list with alive targets only, in input order
-- Covers: TargetList.get_alive()
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
-- find_by_mob
------------------------------------------------------------------------

--- Test: find_by_mob returns matching target
-- Input: search for "a mutated goat" in 2-target list
-- Expected: returns target with matching mob name
-- Covers: TargetList.find_by_mob()
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

--- Test: find_by_mob returns nil for unknown mob
-- Input: search for nonexistent mob name
-- Expected: nil
-- Covers: TargetList.find_by_mob() miss
run_test("TargetList.find_by_mob_miss", function()
   local check_list = {
      {mob = "a sinister vandal", location = "The Three Pillars of Diatz", dead = false},
   }
   TargetList.build(check_list, "area", 45)
   local t = TargetList.find_by_mob("nonexistent mob")
   assert_nil(t, "nil for unknown mob")
end)

------------------------------------------------------------------------
-- update_dead
------------------------------------------------------------------------

--- Test: update_dead marks a live target as dead
-- Setup: build with alive target, then update_dead
-- Expected: target.dead changes from false to true
-- Covers: TargetList.update_dead()
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
-- clear
------------------------------------------------------------------------

--- Test: clear empties the target list
-- Setup: build with 1 target, then clear
-- Expected: count = 0
-- Covers: TargetList.clear()
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
-- Room-based CP
------------------------------------------------------------------------

--- Test: Room-based build creates target even without mapper data
-- Input: room name not in mapper (mock returns empty)
-- Expected: target exists with mob name preserved, may be "unknown" type
-- Covers: TargetList.build() with cp_type="room"
run_test("TargetList.build_room_basic", function()
   local check_list = {
      {mob = "a troll guard", location = "In The Courtyard", dead = false},
   }
   TargetList.build(check_list, "room", 90)
   local t = TargetList.get(1)
   assert_not_nil(t, "room target exists")
   assert_equal("a troll guard", t.mob, "mob name preserved")
end)

------------------------------------------------------------------------
-- Dead flag from cp check
------------------------------------------------------------------------

--- Test: Dead flag from cp check correctly propagates through build
-- Input: 2 targets, one alive and one dead
-- Expected: dead flag preserved on correct target after sort
-- Covers: TargetList.build() dead flag handling
run_test("TargetList.build_dead_flag_from_check", function()
   local check_list = {
      {mob = "a sinister vandal", location = "The Three Pillars of Diatz", dead = false},
      {mob = "a mutated goat", location = "The Killing Fields", dead = true},
   }
   TargetList.build(check_list, "area", 45)
   assert_false(TargetList.get(1).dead, "vandal is alive")
   assert_true(TargetList.get(2).dead, "goat is dead")
end)
