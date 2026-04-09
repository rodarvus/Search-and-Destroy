# Search & Destroy v2 — Testing Guide

## TDD Approach

This project follows strict Test-Driven Development:

1. **Write tests before implementation** — define expected behavior first
2. **Gate phases on green** — all tests must pass before starting new work
3. **Pre-commit hook** — `.git/hooks/pre-commit` runs the full suite, blocks commits on failure
4. **Design analysis before coding** — compare Crowley/WinkleGold approaches, verify game output

## Test Environment

- **Lua 5.1.5** (same as MUSHclient embedded)
- **lsqlite3 3.45.1** — real SQLite for database integration tests
- **lrexlib-pcre 8.39** — PCRE regex validation matching MUSHclient's trigger flavor
- **Tests run standalone** outside MUSHclient: `lua tests/test_runner.lua`
- **Temp DB** created at `/tmp/test_plugins/Search_and_Destroy.db` (cleaned between tests)

## Test Infrastructure

| File | Purpose |
|------|---------|
| `tests/test_runner.lua` | Framework: auto-discovers test_*.lua, `run_test()` with setUp/tearDown, 9 assertion functions |
| `tests/mock_mushclient.lua` | Stubs 30+ MUSHclient APIs with call recording, `mock.reset()` / `mock.reset_db()` |
| `tests/load_plugin.lua` | Extracts Lua from XML CDATA, loads into global environment |
| `tests/test_data.lua` | Verified game output samples: CP info/check, GQ events, hunt, consider, damage, quest |

## Test Suite Summary (542 tests across 11 files)

| File | Tests | Module | Coverage |
|------|-------|--------|----------|
| test_util.lua | 6 | Util | fixsql, trim, split, strip_colours, ellipsify, round |
| test_config.lua | 9 | Config | defaults, load/save, set/get, roundtrip |
| test_db.lua | 21 | DB | schema, seeding, CRUD, transactions, injection prevention, find_mob |
| test_mob_keyword.lua | 12 | MobKeyword | basic guessing, punctuation, exceptions, area filters, hyphens, edge cases |
| test_noexp.lua | 16 | Noexp | init, check_tnl boundaries, set, level 200+, exact cutoff, CP interaction |
| test_state.lua | 33 | State + CP | room/char updates, activity transitions, CP start/clear/info/check/events, noexp-CP |
| test_target_list.lua | 20 | TargetList | detect_type, resolve_area_key, build, sort, get_alive, find_by_mob, clear |
| test_triggers.lua | 41 | Trigger regex | PCRE validation for all 48 XML triggers against verified game output |
| test_nav.lua | 18 | Nav | goto_area, goto_room, Vidblain, fuzzy_match, arrival detection, goto_next |
| test_commands.lua | 27 | Commands | cmd_xcp, cmd_go, cmd_nx, cmd_xrt, cmd_kk, cmd_xset, CP.do_info/do_check |
| test_cp_workflow.lua | 15 | Integration | Full CP lifecycle: request → info → check → select → kill → refresh → complete |

## Testing Matrix: Functions vs Tests

### Fully tested (automated)

| Function | Test(s) |
|----------|---------|
| Util.fixsql | Util.fixsql, DB.fixsql_integration, DB.fixsql_prevents_injection |
| Util.trim | Util.trim |
| Util.split | Util.split |
| Util.strip_colours | Util.strip_colours |
| Util.ellipsify | Util.ellipsify |
| Util.round | Util.round |
| Config.load | Config.load, Config.load_with_stored |
| Config.save | Config.save, Config.save_not_dirty, Config.roundtrip |
| Config.get | Config.load, Config.get_default_fallback |
| Config.set | Config.set, Config.set_invalid, cmd_xset.set_config_value |
| DB.get_path | DB.get_path |
| DB.init | DB.schema_created, DB.schema_version, DB.init_idempotent |
| DB.query | DB.query_empty_result, and many others |
| DB.execute | DB.execute_transaction_success |
| DB.execute_transaction | DB.execute_transaction_success, DB.execute_transaction_rollback |
| DB.get_start_room | DB.get_start_room_default, DB.set_start_room |
| DB.set_start_room | DB.set_start_room |
| DB.get_mob_override | DB.get_mob_override, DB.get_mob_override_miss |
| DB.record_mob | DB.record_mob_and_find |
| DB.find_mob | DB.find_mob |
| DB.record_kill | DB.record_kill |
| MobKeyword.guess | 12 tests covering all 6 stages |
| Noexp.init | Noexp.init_defaults, Noexp.init_custom |
| Noexp.check_tnl | 12 tests covering all branches |
| Noexp.set | Noexp.set_no_change, Noexp.set_broadcasts |
| State.update_room | State.update_room, _maze, _prev, _nil_fields |
| State.update_char | State.update_char, State.update_char_nil |
| State.set_activity | State.set_activity, State.set_activity_same, State.activity_transitions |
| State.set_target | State.set_target |
| State.clear_target | State.clear_target |
| State.broadcast_full | State.broadcast_full |
| CP.start | CP.start, CP.start_double_call_guard, CP.start_noexp_already_off |
| CP.do_info | CP.do_info.enables_triggers_and_sends |
| CP.do_check | CP.do_check.cooldown_guard, CP.do_check.sends_when_ready |
| CP.clear | CP.clear |
| on_cp_info_level/start/line/end | CP.info_parse_flow |
| on_cp_check_line/end | CP.check_parse_flow, CP.check_end_empty_list_guard, _current_target_died, _different_target_died, _all_dead |
| on_cp_request | workflow.cp_request_starts_flow |
| on_cp_mob_killed | CP.mob_killed_refreshes |
| on_cp_complete/cleared/not_on | CP.events_complete_clears, _cleared, _not_on, _not_on_noop |
| on_cp_new_available | CP.events_new_available |
| on_cp_must_level | CP.events_must_level_noexp_off |
| TargetList.detect_type | 4 tests (area, room, majority, empty) |
| TargetList.resolve_area_key | resolve_area_key_nil, _known |
| TargetList.build | 8 tests covering area/room, keyword, DB lookup, sorting, dead flags |
| TargetList.get/count/get_alive | TargetList.build_area_basic, TargetList.get_alive |
| TargetList.find_by_mob | find_by_mob, find_by_mob_miss |
| TargetList.update_dead | TargetList.update_dead |
| TargetList.clear | TargetList.clear |
| Nav.goto_area | 6 tests (basic, dest, unknown, ft2, vidblain, vidblain_already_in) |
| Nav.goto_room | Nav.goto_room_basic |
| Nav.goto_next | 3 tests (basic, at_end, empty_list) |
| Nav.on_room_change | 4 tests (area arrival, not arrived, room arrival, no dest) |
| Nav.fuzzy_match_area | 4 tests (exact, partial, ft2, no match) |
| cmd_xcp | 6 tests (list display, numeric, not_on_cp, bounds, dead skip, unknown) |
| cmd_go | 4 tests (navigate, default, empty, area string) |
| cmd_nx | 3 tests (advance, end, empty) |
| cmd_xrt | 4 tests (navigate, fuzzy, no_arg, unknown) |
| cmd_kk | 2 tests (sends command, no target) |
| cmd_xset | 2 tests (set value, invalid key) + 3 kw tests |
| All 48 trigger patterns | test_triggers.lua (PCRE validation) |
| Full CP workflow | 15 integration scenarios |

### Tested indirectly (through other tests)

| Function | Indirect coverage |
|----------|------------------|
| DB.open | Every DB test opens via DB.init() |
| DB.close | mock.reset_db() in tearDown |
| DB.create_schema | Via DB.init → DB.schema_created |
| DB.seed_start_rooms | Via DB.init → DB.start_rooms_seeded |
| DB.seed_mob_overrides | Via DB.init → DB.mob_overrides_seeded |
| DB.get_version / set_version | Via DB.init → DB.schema_version |
| State.get_room / get_target / get_activity | Used in many tests |
| State.broadcast / broadcast_activity | Verified via mock.calls in State tests |
| Nav.mapper_goto | Called by goto_area/goto_room, verified via mock.calls["Execute"] |
| TargetList.display | Called by cmd_xcp no-arg test (ColourNote verified) |

### Not testable programmatically (requires in-game testing)

| Area | Why |
|------|-----|
| Plugin XML loading in MUSHclient | XML parsing, trigger registration, alias compilation |
| GMCP data flow | Real GMCP handler interaction, data format |
| Mapper speedwalk execution | Real mapper plugin navigation |
| Trigger firing on actual game output | MUSHclient trigger engine behavior |
| Timer behavior (init, safety, save) | MUSHclient timer scheduling |
| Multi-plugin coexistence | Interaction with leveldb, mapper, other plugins |
| Display output formatting | ColourNote/ColourTell visual output |
| Vidblain portal navigation | Real game area transitions |
| Room-based CP room cycling | Mapper room queries + go/nx workflow |
| Noexp game command effect | "noexp" toggle confirmation from game |
| Reconnect/plugin reload recovery | MUSHclient session lifecycle |

---

## In-Game Testing Plan

### Prerequisites

1. Load `Search_and_Destroy_v2.xml` in MUSHclient via Ctrl+Shift+P → Add
2. Verify no Lua errors in MUSHclient output window on load
3. Confirm plugin appears in plugin list with correct version (2.000)

### Phase 1: Plugin Load & Basic Commands

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 1.1 | Plugin loads cleanly | Load plugin | No Lua errors, install banner displayed |
| 1.2 | xhelp works | Type `xhelp` | Command list displayed with descriptions |
| 1.3 | xset shows settings | Type `xset` | All settings listed with defaults |
| 1.4 | xset changes setting | Type `xset debug_mode on`, then `xset debug_mode` | Shows "on", debug output enabled |
| 1.5 | xtest state works | Type `xtest state` | Shows room, activity, level, TNL, noexp, target |
| 1.6 | xtest db works | Type `xtest db` | Shows DB path, schema version, table counts |
| 1.7 | xtest keyword works | Type `xtest keyword a sinister vandal diatz` | Shows guessed keyword |
| 1.8 | GMCP tracking active | Move to a new room | `xtest state` shows updated room ID and area |
| 1.9 | No conflicts with other plugins | Check other plugins still work (leveldb, mapper) | No errors, `keep_evaluating` working |

### Phase 2: Campaign Workflow (Area-Based)

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 2.1 | CP auto-detection | Type `cp` to request a new campaign | "Congratulations" banner, S&D detects "Good luck" trigger, sends cp info + cp check |
| 2.2 | Target list displayed | Type `xcp` | Target list shown with indices, mob names, areas, keywords, dead status |
| 2.3 | Correct area detection | Check target list | All targets show correct area keys (not "unknown") |
| 2.4 | Keyword quality | Compare displayed keywords to `xtest keyword <mob> <area>` | Keywords match, look reasonable |
| 2.5 | Target selection + navigation | Type `xcp 1` | Target set, mapper speedwalk initiated to area start room |
| 2.6 | Navigation arrives | Wait for speedwalk to complete | `xtest state` shows you're in the target area |
| 2.7 | xrt works | Type `xrt <area>` (any known area) | Speedwalk to that area's start room |
| 2.8 | xrt fuzzy match | Type `xrt dia` | Speedwalk to diatz |
| 2.9 | Kill CP mob | Kill a campaign target mob | "Congratulations, that was one of your CAMPAIGN mobs!" triggers refresh |
| 2.10 | Auto-advance after kill | After kill, type `xcp` | Killed target marked dead, next alive target auto-selected |
| 2.11 | kk works | With target selected, type `kk` | Sends kill command with keyword |
| 2.12 | CP complete | Kill all CP mobs | "CONGRATULATIONS!" trigger fires, CP state cleared, `xcp` shows "not on campaign" |
| 2.13 | New CP available | After CP complete, verify game says "You may now take..." | S&D detects, `xtest state` shows ready |

### Phase 3: Noexp Interaction

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 3.1 | Configure noexp | `xset noexp_tnl_cutoff 500` | Setting saved |
| 3.2 | Noexp activates | Kill mobs until TNL < 500 (while NOT on CP) | "Turning noexp ON" message, `noexp` command sent |
| 3.3 | CP start turns noexp off | Request a new CP | "Turning noexp OFF (campaign started)" |
| 3.4 | Noexp stays off during CP | Kill mobs during CP (TNL may drop below cutoff) | Noexp stays OFF, no auto-toggle |
| 3.5 | CP complete re-evaluates | Complete CP, check if TNL still < cutoff | Noexp turns ON again if TNL < cutoff and no CP |
| 3.6 | Must level turns noexp off | If game says "You must level..." | "Turning noexp OFF (must level)" |

### Phase 4: xset kw (Keyword Override)

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 4.1 | Override keyword | With target selected, `xset kw newkeyword` | Keyword updated, confirmed message |
| 4.2 | kk uses new keyword | Type `kk` | Sends kill command with "newkeyword" |
| 4.3 | Override persists after refresh | Kill a different mob, list refreshes | Overridden keyword still present |
| 4.4 | xset kw (no arg) shows current | Type `xset kw` | Shows current keyword for target |

### Phase 5: Edge Cases & Error Handling

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 5.1 | xcp when not on CP | Type `xcp` without CP | Error: "You are not on a campaign" |
| 5.2 | xcp out of bounds | With CP active, `xcp 999` | Error: "Invalid index" |
| 5.3 | xrt unknown area | `xrt zzzzz` | Error: "Unknown area" |
| 5.4 | xrt no arg | `xrt` (no arg) | Error: "Usage: xrt <area>" |
| 5.5 | kk no target | Type `kk` without target | Error: "No target set" |
| 5.6 | go empty list | Type `go 1` without prior xcp | Error: "No room list" |
| 5.7 | Plugin reload mid-CP | Disable + re-enable plugin during CP | Plugin reloads, CP state partially recovered via persisted level |
| 5.8 | CP cleared by user | `cp quit` during active CP | S&D detects "Campaign cleared", state reset |

### Phase 6: Vidblain Navigation (if accessible)

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 6.1 | Navigate to Vidblain area | `xrt asherodan` (or other Vidblain area) | Goes to portal room 11910, enters hole, then navigates to area |
| 6.2 | Already in Vidblain | From within Vidblain, `xrt imperial` | Direct navigation (no portal) |

### Phase 7: Coexistence

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 7.1 | leveldb still works | Kill mobs during CP | leveldb records kills, no errors |
| 7.2 | Mapper still works | Navigate via mapper | Mapper speedwalk works, S&D triggers fire with `keep_evaluating` |
| 7.3 | No trigger conflicts | Complete a full CP | No "trigger already exists" errors, no missing callbacks |

---

## Known Limitations (not testable in Phase 2)

- **Room-based CP go/nx cycling** — Nav._goto_list not populated from mapper queries yet
- **sohtwo area** — "The School of Horror" name shared between soh and sohtwo, level filtering not implemented
- **GQ workflow** — all GQ triggers are stubs (Phase 5)
- **Hunt trick / quick where / smart scan** — stubs (Phase 3/4)
- **Reconnect full recovery** — CP level persisted but full reconnect flow not implemented
- **DamageTracker** — deferred, kill identification uses server cp check response

## Running the Automated Suite

```bash
cd Search-and-Destroy
lua tests/test_runner.lua
```

Expected: `542/542 passed, 0 failed`

The pre-commit hook runs this automatically on every `git commit`.
