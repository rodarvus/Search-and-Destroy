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
- **Mapper DB fixture** at `/tmp/test_data/Aardwolf.db` (created/destroyed per test file)

## Test Infrastructure

| File | Purpose |
|------|---------|
| `tests/test_runner.lua` | Framework: auto-discovers test_*.lua, `run_test()` with setUp/tearDown, 9 assertion functions |
| `tests/mock_mushclient.lua` | Stubs 30+ MUSHclient APIs with call recording, `mock.reset()` / `mock.reset_db()` |
| `tests/load_plugin.lua` | Extracts Lua from XML CDATA, loads into global environment |
| `tests/test_data.lua` | Verified game output samples: CP info/check, GQ events, hunt, consider, damage, quest |

## Test Suite Summary (774 assertions across 14 files)

| File | Module | Coverage |
|------|--------|----------|
| test_util.lua | Util | fixsql, trim, split, strip_colours, ellipsify, round |
| test_config.lua | Config | defaults, load/save, set/get, roundtrip |
| test_db.lua | DB | schema, seeding, CRUD, transactions, injection prevention, find_mob |
| test_mob_keyword.lua | MobKeyword | basic guessing, punctuation, exceptions, area filters, hyphens, edge cases |
| test_noexp.lua | Noexp | init, check_tnl boundaries, set, level 200+, exact cutoff, CP interaction |
| test_state.lua | State + CP | room/char updates (incl. string-num coercion), activity transitions, CP start/clear/info/check/events, noexp-CP |
| test_target_list.lua | TargetList | detect_type, resolve_area_key, build, sort, get_alive, find_by_mob, clear |
| test_triggers.lua | Trigger regex | PCRE validation for all 48 XML triggers against verified game output |
| test_nav.lua | Nav | goto_area, goto_room, Vidblain, fuzzy_match, arrival detection, goto_next, search_rooms (ordered by uid), build_goto_list, build_goto_list_from_rooms, display_goto_list |
| test_commands.lua | Commands | cmd_xcp (list/select/pickup/bounds/dead/unknown/DB-history/auto-go-on-1/multi-room-wait/no-history paths/HT-in-parallel/HT-cancel-on-reselect/string-num arrival), cmd_go (incl. cancels HT), cmd_nx (incl. cancels HT, advances after string-num arrival), cmd_xrt, cmd_kk, cmd_xset, CP.do_info/do_check |
| test_cp_workflow.lua | Integration | Full CP lifecycle, cold-pickup auto-display, kill-refresh silent, no-history navigates-then-discovers, single-room auto-navigate |
| test_hunt_trick.lua | HuntTrick | start (basic/indexed/no-prefix/no_hunt/trigger-group), does_not_reset_others (parallel-safe), cmd_ht.resets_others (manual exclusivity), reset, is_active, direction, here/unable/not_found (chain + no_chain), abort, cmd_ht (no target/target/arg/indexed/abort/zero) |
| test_quick_where.lua | QuickWhere | start (basic/indexed/no-prefix/trigger-group), does_not_reset_others (parallel-safe), cmd_qw.resets_others, start_exact (basic/auto_go), reset, check_match (exact pos/neg/long, keyword pos/neg/multi), on_qw_match (exact/keyword/retry/max100, single-room auto-navigate, multi-room wait), on_qw_no_match, cmd_qw |
| test_auto_hunt.lua | AutoHunt | start (basic/trigger-group), does_not_reset_others, cmd_ah.resets_others, reset, direction (move+hunt/door/2nd-group/inactive), here, not_found, cmd_ah |

## Testing Matrix: Functions vs Tests

### Phase 1: Foundation

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
| All 48 trigger patterns | test_triggers.lua (PCRE validation) |

### Phase 2: Campaign Pipeline

| Function | Test(s) |
|----------|---------|
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
| cmd_xcp | 9 tests (list/select/pickup/bounds/dead/unknown/ht-arrive/qw-arrive/off) |
| cmd_go | 4 tests (navigate, default, empty, area string) |
| cmd_nx | 3 tests (advance, end, empty) |
| cmd_xrt | 4 tests (navigate, fuzzy, no_arg, unknown) |
| cmd_kk | 2 tests (sends command, no target) |
| cmd_xset | 2 tests (set value, invalid key) + 3 kw tests |
| Full CP workflow | 15 integration scenarios |

### Phase 3: Hunting Tools

| Function | Test(s) |
|----------|---------|
| Nav.mapper_db_path | Nav.mapper_db_path |
| Nav.search_rooms | 6 tests (found, no_match, wrong_area, result_fields, nil_args, no_db) |
| Nav.build_goto_list | 3 tests (basic, empty, skips_invalid) |
| HuntTrick.start | 5 tests (basic/indexed/no-prefix/resets-others/no_hunt + trigger group) |
| HuntTrick.reset | HuntTrick.reset_clears_state |
| HuntTrick.is_active | HuntTrick.is_active |
| on_ht_direction | 2 tests (inactive_ignored, increments_and_hunts) |
| on_ht_here | 2 tests (chains_to_qw_exact, no_target_notifies) |
| on_ht_unable | 2 tests (chains_to_qw_exact, no_target_notifies) |
| on_ht_not_found | 2 tests (first_target_fallback, not_first_no_qw) |
| on_ht_abort | on_ht_abort.resets |
| cmd_ht | 6 tests (no_target/target/arg/indexed/abort/zero) |
| QuickWhere.start | 4 tests (basic/indexed/no-prefix/resets + trigger group) |
| QuickWhere.start_exact | 2 tests (basic, auto_go) |
| QuickWhere.reset | QuickWhere.reset_clears_state |
| QuickWhere.check_match | 6 tests (exact pos/neg/long, keyword pos/neg/multi) |
| on_qw_match | 6 tests (exact/keyword/retry/max100/auto_go/no_auto_go) |
| on_qw_no_match | on_qw_no_match.resets |
| cmd_qw | 6 tests (no_target/target/arg/indexed/abort/zero) |
| AutoHunt.start | 2 tests (basic/resets + trigger group) |
| AutoHunt.reset | AutoHunt.reset_clears_state |
| on_ah_direction | 4 tests (move+hunt/door/2nd-group/inactive) |
| on_ah_here | on_ah_here.completes |
| on_ah_not_found | on_ah_not_found.aborts |
| cmd_ah | 6 tests (cancel/abort/zero/no_target/target/arg) |
| Integration: xcp→HT→QW | workflow.xcp_ht_to_qw_chain |
| Integration: xcp→QW | workflow.xcp_qw_direct |
| Integration: HT here→QW | workflow.ht_here_chains_qw |
| Integration: HT fallback→QW | workflow.ht_not_found_fallback_qw |

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
| Hunt trick trigger timing | Trigger group enable/disable with real game output |
| Auto-hunt door opening | Real door detection via GMCP exits |
| Quick where mob matching | 30-char field alignment with live game output |

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
| 2.1 | CP auto-detection | Type `cp` to request a new campaign | S&D detects "Good luck" trigger, sends cp info + cp check |
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
| 2.12 | CP complete | Kill all CP mobs | "CONGRATULATIONS!" trigger fires, CP state cleared |
| 2.13 | New CP available | After CP complete, verify game says "You may now take..." | S&D detects |

### Phase 3: Hunting Tools (post-redesign)

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 3.1 | xcp with S&D history (multiple rooms) | Pick a CP target the plugin has seen before | Room list shown with index/roomid/name/freq, no auto-navigate, HT starts in parallel |
| 3.2 | xcp with S&D history (single room) | Pick a CP target with only one historical room | Room list shown (1 entry), auto-navigates to that room, HT starts in parallel |
| 3.3 | xcp with no history, in target area | Be in target area, pick a CP target the plugin has not seen | `where keyword` sent directly, no `mapper goto`, HT starts in parallel |
| 3.4 | xcp with no history, out of area | Be elsewhere, pick a CP target the plugin has not seen | `mapper goto` to target area, then on arrival `where keyword` sent + HT starts |
| 3.5 | QW match, multiple rooms | After `where` finds the mob in N>1 rooms | List shown, no auto-navigate, user picks via `go`/`nx` |
| 3.6 | QW match, single room | After `where` finds the mob in 1 room | Auto-navigates immediately |
| 3.7 | go after list shown | Type `go` or `go N` | Navigate to room N (`go` defaults to 1), cancels HT |
| 3.8 | nx advances | Type `nx` after arriving at a list room | Advances to next room in list, cancels HT |
| 3.9 | Manual ht | With target, type `ht` | HT exclusive: cancels QW/AH, sends `hunt keyword` |
| 3.10 | Manual ht with arg | Type `ht guard` | HT starts with "guard" keyword |
| 3.11 | Manual qw | With target, type `qw` | QW exclusive: cancels HT/AH, runs `where keyword` |
| 3.12 | Manual qw exact | With target, type `qw` after HT unable | QW matches exact mob name |
| 3.13 | Auto-hunt | Type `ah` with target | AH exclusive: cancels HT/QW, sends `hunt keyword`, follows directions |
| 3.14 | AH door handling | AH encounters closed door | `open <dir>` sent before movement |
| 3.15 | Abort commands | `ht 0` / `qw 0` / `ah 0` | Each tool stops, notification shown |
| 3.16 | xcp re-select cancels HT | xcp 1, then xcp 2 mid-flight | HT for target 1 cancelled, HT for target 2 starts |
| 3.17 | Cold mid-CP pickup | Load plugin mid-campaign, type `xcp` | `cp info` + `cp check` chain runs, target list auto-displays once |

### Phase 4: Noexp Interaction

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 4.1 | Configure noexp | `xset noexp_tnl_cutoff 500` | Setting saved |
| 4.2 | Noexp activates | Kill mobs until TNL < 500 (while NOT on CP) | "Turning noexp ON" message, `noexp` command sent |
| 4.3 | CP start turns noexp off | Request a new CP | "Turning noexp OFF (campaign started)" |
| 4.4 | Noexp stays off during CP | Kill mobs during CP (TNL may drop below cutoff) | Noexp stays OFF, no auto-toggle |
| 4.5 | CP complete re-evaluates | Complete CP, check if TNL still < cutoff | Noexp turns ON again if TNL < cutoff and no CP |
| 4.6 | Must level turns noexp off | If game says "You must level..." | "Turning noexp OFF (must level)" |

### Phase 5: xset kw (Keyword Override)

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 5.1 | Override keyword | With target selected, `xset kw newkeyword` | Keyword updated, confirmed message |
| 5.2 | kk uses new keyword | Type `kk` | Sends kill command with "newkeyword" |
| 5.3 | Override persists after refresh | Kill a different mob, list refreshes | Overridden keyword still present |
| 5.4 | xset kw (no arg) shows current | Type `xset kw` | Shows current keyword for target |

### Phase 6: Edge Cases & Error Handling

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 6.1 | xcp when not on CP | Type `xcp` without CP | Error: "You are not on a campaign" |
| 6.2 | xcp out of bounds | With CP active, `xcp 999` | Error: "Invalid index" |
| 6.3 | xrt unknown area | `xrt zzzzz` | Error: "Unknown area" |
| 6.4 | xrt no arg | `xrt` (no arg) | Error: "Usage: xrt <area>" |
| 6.5 | kk no target | Type `kk` without target | Error: "No target set" |
| 6.6 | go empty list | Type `go 1` without prior xcp | Error: "No room list" |
| 6.7 | ht no target | Type `ht` without target | Error: "no target" |
| 6.8 | qw no target | Type `qw` without target | Error: "no target" |
| 6.9 | ah no target | Type `ah` without target | Error: "no target" |
| 6.10 | Plugin reload mid-CP | Disable + re-enable plugin during CP | Plugin reloads, CP state partially recovered |
| 6.11 | CP cleared by user | `cp quit` during active CP | S&D detects "Campaign cleared", state reset |

### Phase 7: Vidblain Navigation (if accessible)

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 7.1 | Navigate to Vidblain area | `xrt asherodan` (or other Vidblain area) | Goes to portal room 11910, enters hole, then navigates to area |
| 7.2 | Already in Vidblain | From within Vidblain, `xrt imperial` | Direct navigation (no portal) |

### Phase 8: Coexistence

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 8.1 | leveldb still works | Kill mobs during CP | leveldb records kills, no errors |
| 8.2 | Mapper still works | Navigate via mapper | Mapper speedwalk works, S&D triggers fire with `keep_evaluating` |
| 8.3 | No trigger conflicts | Complete a full CP | No "trigger already exists" errors, no missing callbacks |

---

## Known Limitations (Phase 4+)

- **SmartScan (qs)** — stub, not implemented (Phase 4)
- **Quest module** — GMCP comm.quest handler is debug stub (Phase 4)
- **GQ workflow** — all GQ triggers/callbacks are stubs (Phase 5)
- **GUI miniwindow** — not started (Phase 6)
- **Auto-hunt step limiting** — WinkleGold feature, deferred
- **Auto-hunt confidence filter** — WinkleGold feature, deferred
- **QW mob frequency sorting** — room results not sorted by seen_count yet
- **QW lookup_not_found_mob** — no SnD DB fallback when where finds nothing
- **sohtwo area** — "The School of Horror" name shared between soh and sohtwo, level filtering not implemented
- **DamageTracker** — deferred, kill identification uses server cp check response
- **Reconnect full recovery** — CP level persisted but full reconnect flow not implemented

## Running the Automated Suite

```bash
cd Search-and-Destroy
lua tests/test_runner.lua
```

Expected: `774/774 passed, 0 failed`

The pre-commit hook runs this automatically on every `git commit`.
