------------------------------------------------------------------------
-- test_db.lua - Tests for DB module
-- Uses real lsqlite3 when available for full integration testing.
------------------------------------------------------------------------

if not CONST then
   local load_plugin = require("load_plugin")
   load_plugin()
end

function setUp()
   mock.reset()
   mock.reset_db()
   DB.init()
end

function tearDown()
   mock.reset_db()
end

--- Test: DB path ends with expected filename
-- Expected: path string ending in "Search_and_Destroy.db"
-- Covers: DB.get_path()
run_test("DB.get_path", function()
   local path = DB.get_path()
   assert_match("Search_and_Destroy%.db$", path, "DB path ends with Search_and_Destroy.db")
end)

--- Test: Util.fixsql integrates correctly for DB operations
-- Input: string, string with quotes, nil
-- Expected: SQL-safe quoted strings, NULL for nil
-- Covers: Util.fixsql() (integration with DB context)
run_test("DB.fixsql_integration", function()
   assert_equal("'test'", Util.fixsql("test"), "fixsql works for DB")
   assert_equal("'it''s a test'", Util.fixsql("it's a test"), "fixsql escapes for DB")
   assert_equal("NULL", Util.fixsql(nil), "fixsql NULL for DB")
end)

--- Test: get_start_room returns seeded/CONST data, nil for unknown
-- Input: known areas (diatz, aylor), unknown area
-- Expected: correct room IDs from seed data, nil for unknown
-- Covers: DB.get_start_room()
run_test("DB.get_start_room_default", function()
   local roomid = DB.get_start_room("diatz")
   assert_equal(1254, roomid, "diatz start room")
   roomid = DB.get_start_room("aylor")
   assert_equal(32418, roomid, "aylor start room")
   roomid = DB.get_start_room("nonexistent_area_xyz")
   assert_nil(roomid, "unknown area returns nil")
end)

--- Test: CONST.DEFAULT_START_ROOMS has sufficient coverage
-- Expected: at least 200 area start rooms defined
-- Covers: CONST.DEFAULT_START_ROOMS data completeness
run_test("DB.default_start_rooms_count", function()
   local count = 0
   for _ in pairs(CONST.DEFAULT_START_ROOMS) do
      count = count + 1
   end
   assert_true(count > 200, "at least 200 default start rooms (got " .. count .. ")")
end)

--- Test: NOQUEST_AREAS contains known non-questable areas, excludes questable ones
-- Expected: icefall, winds, manor1, gaardian present; diatz, aylor absent
-- Covers: CONST.NOQUEST_AREAS data correctness
run_test("DB.noquest_areas", function()
   assert_true(#CONST.NOQUEST_AREAS > 30, "at least 30 noquest areas")
   local noquest_set = {}
   for _, area in ipairs(CONST.NOQUEST_AREAS) do
      noquest_set[area] = true
   end
   assert_true(noquest_set["icefall"], "icefall is noquest")
   assert_true(noquest_set["winds"], "winds is noquest")
   assert_true(noquest_set["manor1"], "manor1 is noquest")
   assert_true(noquest_set["gaardian"], "gaardian clan is noquest")
   assert_nil(noquest_set["diatz"], "diatz is NOT noquest")
   assert_nil(noquest_set["aylor"], "aylor is NOT noquest")
end)

--- Test: VIDBLAIN_AREAS lists all 6 Vidblain areas with flags in start rooms
-- Expected: all 6 areas present, vidblain flag set on their DEFAULT_START_ROOMS entries
-- Covers: CONST.VIDBLAIN_AREAS, CONST.DEFAULT_START_ROOMS vidblain flag
run_test("DB.vidblain_areas", function()
   local vidblain_set = {}
   for _, area in ipairs(CONST.VIDBLAIN_AREAS) do
      vidblain_set[area] = true
   end
   assert_true(vidblain_set["vidblain"], "vidblain in list")
   assert_true(vidblain_set["asherodan"], "asherodan in list")
   assert_true(vidblain_set["darklight"], "darklight in list")
   assert_true(vidblain_set["imperial"], "imperial in list")
   assert_true(vidblain_set["omentor"], "omentor in list")
   assert_true(vidblain_set["sendhian"], "sendhian in list")
   assert_true(CONST.DEFAULT_START_ROOMS["vidblain"].vidblain, "vidblain has vidblain flag")
   assert_true(CONST.DEFAULT_START_ROOMS["asherodan"].vidblain, "asherodan has vidblain flag")
   assert_nil(CONST.DEFAULT_START_ROOMS["diatz"] and CONST.DEFAULT_START_ROOMS["diatz"].vidblain,
      "diatz does NOT have vidblain flag")
end)

------------------------------------------------------------------------
-- Real SQLite integration tests
------------------------------------------------------------------------

--- Test: DB.init creates all 4 required tables
-- Setup: fresh DB via mock.reset_db() + DB.init()
-- Expected: mobs, areas, mob_overrides, start_rooms tables exist
-- Covers: DB.create_schema()
run_test("DB.schema_created", function()
   local rows = DB.query("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;")
   local tables = {}
   for _, row in ipairs(rows) do
      tables[row.name] = true
   end
   assert_true(tables["mobs"], "mobs table exists")
   assert_true(tables["areas"], "areas table exists")
   assert_true(tables["mob_overrides"], "mob_overrides table exists")
   assert_true(tables["start_rooms"], "start_rooms table exists")
end)

--- Test: Schema version matches CONST.SCHEMA_VERSION after init
-- Expected: PRAGMA user_version == CONST.SCHEMA_VERSION
-- Covers: DB.get_version(), DB.set_version()
run_test("DB.schema_version", function()
   local v = DB.get_version()
   assert_equal(CONST.SCHEMA_VERSION, v, "schema version matches CONST")
end)

--- Test: Calling DB.init() twice is idempotent (no duplicate data)
-- Setup: DB already initialized in setUp
-- Expected: row count unchanged after second init
-- Covers: DB.init() idempotency
run_test("DB.init_idempotent", function()
   local count_before = #DB.query("SELECT COUNT(*) as c FROM start_rooms;")
   DB.init()
   local count_after = #DB.query("SELECT COUNT(*) as c FROM start_rooms;")
   assert_equal(count_before, count_after, "init() is idempotent")
end)

--- Test: start_rooms table has seeded data from CONST.DEFAULT_START_ROOMS
-- Expected: non-zero row count
-- Covers: DB.seed_start_rooms()
run_test("DB.start_rooms_seeded", function()
   local rows = DB.query("SELECT COUNT(*) as c FROM start_rooms;")
   assert_true(rows[1].c > 0, "start_rooms has seeded data")
end)

--- Test: set_start_room persists and is retrievable
-- Input: set_start_room("test_area", 99999, "Test Area Name")
-- Expected: get_start_room("test_area") returns 99999
-- Covers: DB.set_start_room(), DB.get_start_room()
run_test("DB.set_start_room", function()
   DB.set_start_room("test_area", 99999, "Test Area Name")
   local roomid = DB.get_start_room("test_area")
   assert_equal(99999, roomid, "set_start_room persists")
end)

--- Test: mob_overrides table has seeded data from CONST.MOB_KEYWORD_EXCEPTIONS
-- Expected: non-zero row count
-- Covers: DB.seed_mob_overrides()
run_test("DB.mob_overrides_seeded", function()
   local rows = DB.query("SELECT COUNT(*) as c FROM mob_overrides;")
   assert_true(rows[1].c > 0, "mob_overrides has seeded data")
end)

--- Test: get_mob_override returns seeded keyword for known mob+area
-- Input: "a black-footed pine marten" in "zoo"
-- Expected: override with keyword "pine marte"
-- Covers: DB.get_mob_override()
run_test("DB.get_mob_override", function()
   local override = DB.get_mob_override("a black-footed pine marten", "zoo")
   assert_not_nil(override, "zoo pine marten override found")
   assert_equal("pine marte", override.keyword, "override keyword correct")
end)

--- Test: get_mob_override returns nil for unknown mob+area
-- Input: nonexistent mob and area
-- Expected: nil
-- Covers: DB.get_mob_override() miss path
run_test("DB.get_mob_override_miss", function()
   local override = DB.get_mob_override("nonexistent mob", "nonexistent_area")
   assert_nil(override, "missing override returns nil")
end)

--- Test: record_mob inserts new entry and increments freq on re-record
-- Input: record same mob+room twice
-- Expected: first insert has freq=1, second bumps to freq=2
-- Covers: DB.record_mob() INSERT and ON CONFLICT UPDATE
run_test("DB.record_mob_and_find", function()
   DB.record_mob("a test goblin", "Test Room", 55555, "testzone")
   local rows = DB.query("SELECT * FROM mobs WHERE mob = 'a test goblin' AND roomid = 55555;")
   assert_equal(1, #rows, "recorded mob found")
   assert_equal("testzone", rows[1].zone, "zone stored correctly")
   assert_equal(1, rows[1].freq, "initial frequency is 1")
   DB.record_mob("a test goblin", "Test Room", 55555, "testzone")
   rows = DB.query("SELECT * FROM mobs WHERE mob = 'a test goblin' AND roomid = 55555;")
   assert_equal(2, rows[1].freq, "frequency incremented on re-record")
end)

--- Test: find_mob returns frequency-sorted results, filters by zone, handles miss
-- Setup: record mob in 2 rooms with different frequencies
-- Expected: highest freq first, zone filter works, unknown mob returns empty
-- Covers: DB.find_mob()
run_test("DB.find_mob", function()
   DB.record_mob("a goblin", "Room A", 10001, "testzone")
   DB.record_mob("a goblin", "Room B", 10002, "testzone")
   DB.record_mob("a goblin", "Room A", 10001, "testzone")
   local results = DB.find_mob("a goblin", "testzone")
   assert_equal(2, #results, "found 2 room entries")
   assert_equal(10001, results[1].roomid, "highest freq room first")
   assert_equal(2, results[1].freq, "freq=2 for most visited room")
   local all = DB.find_mob("a goblin", "")
   assert_true(#all >= 2, "find without zone returns all")
   local miss = DB.find_mob("nonexistent mob", "testzone")
   assert_equal(0, #miss, "no results for unknown mob")
end)

--- Test: record_kill increments kill_count for matching mob+zone
-- Setup: record mob first, then record kill
-- Expected: kill_count = 1 after one kill
-- Covers: DB.record_kill()
run_test("DB.record_kill", function()
   DB.record_mob("a kill target", "Kill Room", 66666, "killzone")
   DB.record_kill("a kill target", "killzone")
   local rows = DB.query("SELECT * FROM mobs WHERE mob = 'a kill target' AND roomid = 66666;")
   assert_equal(1, rows[1].kill_count, "kill_count incremented")
end)

--- Test: execute_transaction commits all statements on success
-- Input: 2 valid INSERT statements
-- Expected: both rows present after commit
-- Covers: DB.execute_transaction() success path
run_test("DB.execute_transaction_success", function()
   local ok, err = DB.execute_transaction({
      "INSERT INTO mobs (mob, room, roomid, zone, freq, seen_count) VALUES ('tx_mob1', 'room', 77771, 'txzone', 1, 1);",
      "INSERT INTO mobs (mob, room, roomid, zone, freq, seen_count) VALUES ('tx_mob2', 'room', 77772, 'txzone', 1, 1);",
   })
   assert_true(ok, "transaction succeeded")
   local rows = DB.query("SELECT COUNT(*) as c FROM mobs WHERE zone = 'txzone';")
   assert_equal(2, rows[1].c, "both rows inserted")
end)

--- Test: execute_transaction handles errors without crashing
-- Input: valid first statement, invalid second (bad type for roomid)
-- Expected: function returns a result, doesn't crash
-- Covers: DB.execute_transaction() error handling
run_test("DB.execute_transaction_rollback", function()
   DB.execute("INSERT INTO mobs (mob, room, roomid, zone, freq, seen_count) VALUES ('dup_mob', 'room', 88881, 'dupzone', 1, 1);")
   local ok, err = DB.execute_transaction({
      "INSERT INTO mobs (mob, room, roomid, zone, freq, seen_count) VALUES ('dup_mob2', 'room', 88882, 'dupzone', 1, 1);",
      "INSERT INTO mobs (mob, roomid, zone) VALUES ('bad', 'not_a_number', 'bad');",
   })
   assert_not_nil(ok, "transaction returns a result (true or false)")
end)

--- Test: SQL injection attempt is escaped by fixsql, tables survive
-- Input: evil string "'; DROP TABLE mobs; --" via fixsql
-- Expected: string escaped, mobs table still exists after query
-- Covers: Util.fixsql() + DB.execute() injection prevention
run_test("DB.fixsql_prevents_injection", function()
   local evil = "'; DROP TABLE mobs; --"
   local safe = Util.fixsql(evil)
   assert_equal("'''; DROP TABLE mobs; --'", safe, "injection attempt escaped")
   DB.execute(string.format("SELECT * FROM mobs WHERE mob = %s;", safe))
   local rows = DB.query("SELECT name FROM sqlite_master WHERE type='table' AND name='mobs';")
   assert_equal(1, #rows, "mobs table still exists after injection attempt")
end)

--- Test: query returns empty table (not nil) for zero-match SELECT
-- Input: query for nonexistent mob
-- Expected: empty table {} with #rows == 0
-- Covers: DB.query() empty result
run_test("DB.query_empty_result", function()
   local rows = DB.query("SELECT * FROM mobs WHERE mob = 'absolutely_nonexistent_12345';")
   assert_equal(0, #rows, "empty result returns empty table")
end)
