# CLAUDE.md — Search & Destroy v2

## Overview

Search & Destroy v2 is a ground-up rewrite of the Aardwolf MUD campaign/quest helper plugin, combining the best of Crowley's and WinkleGold's implementations. Core plugin: `Search_and_Destroy_v2.xml`. Repository: `rodarvus/Search-and-Destroy`.

## MANDATORY PROCESS — Read Before Every Task

### Stop-and-Check Guardrail

When the user reports a bug, requests a feature, or describes unexpected behavior:

1. **STOP.** Do not write or edit any code. Do not propose fixes.
2. **Enter plan mode.** Use the plan tool to structure your analysis.
3. **Investigate.** Read the relevant code. Understand the problem fully.
4. **Analyze references.** Compare how Crowley (`Search_and_Destroy.xml`) and WinkleGold (`WinkleGold_Search_Destroy.xml`, `WinkleGold_Mapper_Extender.xml`) handle the same situation.
5. **Present options.** Show the user what you found, with pros/cons. Wait for their decision.
6. **Write tests FIRST.** After the user approves an approach, write failing tests with proper headers before any implementation.
7. **Implement.** Only after tests exist and fail for the right reason.
8. **Verify.** Run `lua tests/test_runner.lua` — all tests must pass (currently 542+).

**This process applies to EVERY change, no matter how small or obvious it seems.** The urgency to "just fix it" is the exact failure mode this guardrail prevents.

### Development Principles (STRICT — no exceptions)

1. **TDD** — Write tests before implementation. Gate phases on green tests. Never break existing tests.
2. **Design Analysis** — For every feature, analyze Crowley's and WinkleGold's approach before choosing implementation. Present structured comparison.
3. **Verify Game Output** — Never guess Aardwolf message formats. Cross-reference Crowley, WinkleGold, and leveldb. If ambiguous, ask the user to verify live.
4. **No Vibe-Coding** — Do not make non-obvious decisions without consulting the user. Present options, not assumptions.
5. **Validate Against Live DBs** — Use Aardwolf.db, SnDdb.db, WinkleGold_Database.db to verify design assumptions.
6. **Reuse Reference Code** — Adapt battle-tested code from Crowley/WinkleGold instead of reinventing.
7. **Doc Headers** — All tests and functions must have documentation headers. **Stale headers are worse than no headers.** Every code change must include header updates for all affected functions and tests — this is not a separate step, it is part of the change itself.

### Test Headers Format

```lua
--- Test: <what the test validates>
-- Setup: <preconditions>
-- Input: <arguments or data>
-- Expected: <assertions>
-- Covers: <function(s) tested>
run_test("Name", function()
```

### Function Headers Format

```lua
--- <what the function does>
-- @param <name> <description>
-- @return <description>
-- Side effects: <state changes, broadcasts, DB writes, commands sent>
-- Tested by: <test name(s)>
function Module.name(args)
```

## Project Structure

- `Search_and_Destroy_v2.xml` — Core plugin (all modules in single XML CDATA)
- `tests/` — Test suite (run with `lua tests/test_runner.lua`)
  - `test_runner.lua` — Framework with setUp/tearDown, 9 assertion functions
  - `mock_mushclient.lua` — Mocks 30+ MUSHclient APIs, real lsqlite3/rex_pcre
  - `load_plugin.lua` — Extracts Lua from XML CDATA for testing
  - `test_data.lua` — Verified sample MUD output
  - `test_*.lua` — Test files (auto-discovered)
- `Search_and_Destroy.xml` — Crowley's reference (not tracked in git)
- `WinkleGold_*.xml` — WinkleGold's reference (not tracked in git)
- `analysis_comparison.md` — Feature matrix and comparison

## Technical Environment

- **In MUSHclient:** Lua 5.1, `sqlite3` is a built-in global (do NOT `require "lsqlite3"`), `json` via `require "json"`
- **Standalone tests:** Lua 5.1.5, `lsqlite3` and `rex_pcre` via require (handled by mock_mushclient.lua)
- Pre-commit hook runs full test suite
- Plugin state saved in MUSHclient `/state/` directory

## Key References

- `memory/MEMORY.md` — Full project memory index (architecture, design decisions, interfaces)
- `memory/implementation_status.md` — Phase progress and file inventory
- Plan file: `/home/rodarvus/.claude/plans/serialized-kindling-kazoo.md`
