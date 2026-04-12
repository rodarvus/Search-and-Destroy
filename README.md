# Search & Destroy v2

**Status: Work in Progress** - Phase 3 (Hunting Tools) complete and in-game tested. The plugin is functional for campaigns but not yet ready for general use.

## What is this?

Search & Destroy v2 is a new MUSHclient plugin for [Aardwolf MUD](http://www.aardwolf.com/) that automates campaign, global quest, and quest mob targeting, navigation, and hunting. It is the core quality-of-life loop for leveling: take a campaign, find the mobs, navigate to them, kill them, repeat.

This is a ground-up rewrite that takes the best ideas and learnings from two existing Search & Destroy implementations:

- **Crowley's Search & Destroy** - The community-maintained version with mob database, smart scan, GUI, sound, and auto-update.
- **WinkleGold's Search & Destroy ecosystem** - A multi-plugin architecture with hunt trick, mob database, mapper extender, and GUI.

The goal is to combine the strengths of both into a cleaner, more maintainable, and more testable plugin with a comprehensive automated test suite.

## Current Status

| Phase | Name | Status | Tests |
|-------|------|--------|-------|
| 1 | Foundation | **Complete** | 220 |
| 2 | Campaign Pipeline | **Complete** | 569 |
| 3 | Hunting Tools | **Complete + in-game tested** | 774 |
| 4 | Smart Features | **Item A (SmartScan) complete** | 934 |
| 5 | GQ Support | Not started | - |
| 6 | GUI Plugin | Not started | - |
| 7 | Polish | Not started | - |

**Total: 934/934 tests passing.**

## Project Plan

### Phase 1: Foundation (Complete)

Core infrastructure that everything else builds on:

- **CONST** - Plugin IDs, broadcast numbers, 240+ default area start rooms, mob keyword exceptions, area filters, noquest/vidblain area lists
- **Util** - GMCP wrapper, SQL escaping, string utilities, colored output helpers
- **Config** - User settings with load/save persistence via MUSHclient variables
- **DB** - SQLite database with schema versioning, migration support, mob tracking, start room and mob override management
- **State** - Central state container tracking room, character, activity, target, with GUI broadcast protocol
- **MobKeyword** - Deterministic keyword guessing with DB overrides, hardcoded exceptions, area-specific filters
- **Noexp** - Auto-noexp toggling based on TNL cutoff, level 200+ bypass
- **Test suite** - 220 tests covering all modules, with real SQLite integration testing

### Phase 2: Campaign Pipeline (Complete)

The core gameplay loop — take CP, parse targets, navigate, kill, repeat:

- **TargetList** - Parse CP info/check output into a unified target list with keyword guessing, mapper DB lookups with CONST fallback, mob history integration, area-based vs room-based CP detection
- **AREA_NAME_XREF** - ~280 area long name to area key mappings, validated against live mapper DB
- **Trigger patterns** - All 48 triggers validated via PCRE (rex_pcre) against verified game output
- **CP** - Campaign info/check trigger callbacks with noexp interaction, CP state machine (start → parse → build → kill → refresh → complete), safety timer recovery
- **DamageTracker** - Deferred (server cp check response is ground truth for kill identification)
- **Nav** - Speedwalk to area start rooms via mapper, Vidblain portal handling, fuzzy area matching, arrival detection
- **Commands** - `xcp` (list display + target selection), `go`, `nx`, `xrt`, `kk`, `xset kw`
- **Deep review** - Gap analysis against Crowley/WinkleGold/live DBs, code audit, test review, documentation headers

### Phase 3: Hunting Tools (Complete + in-game tested)

Finding mobs within an area, then a redesign based on live testing:

- **Nav.search_rooms** - Direct Aardwolf.db queries for room lookup by name and area, deterministic ORDER BY uid, goto_list building for room navigation
- **HuntTrick** - Progressive hunt cycling (1.mob, 2.mob, ...) with direction/portal/here/unable handling, optional QuickWhere chain (disabled when run in parallel from xcp), no_hunt override support
- **QuickWhere** - Where iteration with 30-char exact and keyword matching, mapper DB room search, auto-navigation only when exactly one room matches
- **AutoHunt** - Auto-hunt with direction following, door opening via GMCP exit detection
- **cmd_xcp redesign (post in-game test)** - Three-path flow: room-based CP (single room), S&D mob history (DB-first, no `where` needed), or discovery via `where` (in-area direct, out-of-area navigate-then-where). HT runs in parallel for additional info, never clobbers the goto_list. Auto-navigates only when there is exactly one candidate room — multiple matches show a list and wait for `go`/`nx`. The `xcp_action_mode` config setting was dropped.
- **`mapper goto` does its own pathfinding** - The plugin no longer routes through area start rooms; relies on the mapper's shortest-path calculation from anywhere on the MUD.
- **Cancellation semantics** - `cmd_go`, `cmd_nx`, and `cmd_xcp <new N>` cancel any in-flight HT (user is taking manual control).
- **Bug fixes from live testing** - rmid type coercion (Aardwolf GMCP can deliver `room.info.num` as a string, breaking numeric comparisons), cold mid-CP pickup auto-displays the target list (no more typing `xcp` twice), search_rooms ordering (was undefined order — `nx` was non-deterministic).
- **Deep review** - Bug fixes, test gap fills, documentation headers, TESTING.md rewrite

### Phase 4: Smart Features (in progress)

Intelligence and automation:

- **SmartScan (Item A — complete)** - Tags `{scan}`/`{/scan}`/`{roomchars}` markers gagged. Scan output parsed into per-room blocks (current room + nearby up to 3 rooms deep × 6 directions). 13 consider triggers re-render with [CP]/[GQ] tags + difficulty colors (matches Crowley exactly). `qs` command: smart-scan on activity (with auto-`con` fallback for noscan/hidden mobs), filtered scan when targeted out-of-activity, plain scan otherwise. Scanned mobs persist to S&D mobs DB so the Phase 3 DB-first `xcp` flow grows over time. New `Display` module hosts the tag helper. New `display_overwrite` config setting (default `on`) toggles re-rendering.
- **B (planned)** - [CP]/[GQ]/[Q] tag prefix in live `where` output (reuses Display.tag_for_mob).
- **C (planned)** - Quest module: GMCP comm.quest handler, auto-target on quest start, 1-min timer warning, `xq` alias.
- **D (planned)** - PK room visual warning (re-color room name on entry).
- **E (planned)** - Noexp gaps (GMCP config.noexp integration).

### Phase 5: GQ Support

Global quest integration:

- **GQ** - Join/start/end/extended events, info/check parsing
- State transitions between CP and GQ with state preservation
- Wire up GQ aliases

### Phase 6: GUI Plugin

Visual interface (separate plugin file):

- Target list miniwindow with colors, hotspots, click-to-navigate
- Action buttons (xcp, go, kk, nx, qs, qw, ht, check)
- Quest display, noexp readout, right-click context menu
- Receives state from core via BroadcastPlugin protocol

### Phase 7: Polish

Production readiness:

- Auto-update system
- Full `xtest` debug command suite
- Data migration tool (import from Crowley's SnDdb.db)
- Help system

## Architecture

**2-plugin design:**

1. `Search_and_Destroy_v2.xml` (Core) - All game logic, 17 modules organized as Lua tables
2. `Search_and_Destroy_GUI.xml` (Phase 6) - Display-only miniwindow

**Communication:** Core broadcasts state to GUI via `BroadcastPlugin` (messages 100-107). GUI sends commands back via `Execute()`.

**Database:** `Search_and_Destroy.db` (SQLite) with 4 tables: mobs, areas, mob_overrides, start_rooms. Schema versioned via `PRAGMA user_version`.

## Testing

The project uses Test-Driven Development with a comprehensive standalone test suite that runs outside MUSHclient.

**Requirements:**
- Lua 5.1 (same version embedded in MUSHclient)
- lsqlite3 (for real database integration tests)
- lrexlib-pcre (for PCRE trigger regex validation)

**Running tests:**
```bash
cd Search-and-Destroy
lua tests/test_runner.lua
```

A git pre-commit hook automatically runs the test suite and blocks commits on any failure.

## Commands

| Command | Description |
|---------|-------------|
| `xcp [N]` | Select target N from list (or show list) |
| `go [area/N]` | Navigate to target area or room N |
| `nx` | Execute next action on current target |
| `ht [N] [mob]` | Hunt trick: cycle hunt N.mob |
| `qw [mob]` | Quick where: locate mob |
| `qs` | Quick scan: scan + consider |
| `ah [mob]` | Auto-hunt: follow hunt directions |
| `kk` | Quick kill current target |
| `xrt [area]` | Run to area start room |
| `xset [setting]` | View/change settings |
| `xhelp` | Show all commands |

## Credits

### Original Search & Destroy

- **WinkleWinkle** - Created the very first Search & Destroy plugin for Aardwolf MUD
- **Nokfah** - Fixed compatibility after Fiendish's mapper database changes
- **Starling** - Major fork with significant enhancements
- **Pwar** - Independent version with its own mob database
- **Rauru** - Another independent version

### Crowley's Search & Destroy

Crowley took over maintenance to ensure Search & Destroy remained a legal, community-supported plugin. His version added substantial features over many releases (v5.0-5.99):

- **Crowley** - Maintainer. Added mob database, smart scan, quest target support, sound integration, GUI target window with hotspots, auto-update system, in-game help and changelog, color customization, and extensive bug fixes ([AardCrowley/Search-and-Destroy](https://github.com/AardCrowley/Search-and-Destroy))
- **Naricain** - Contributions to Crowley's version, sound setup
- **Karathos** - Color code stripping in mob table notes

### WinkleGold's Search & Destroy Ecosystem

WinkleGold (KoopaTroopa/xeryax) created a multi-plugin Search & Destroy ecosystem with a different architectural approach:

- **WinkleGold** - Hunt trick implementation, mob name guessing algorithm, mapper extender with mob frequency tracking, GUI miniwindow with hotspot system, spellup integration

### Sound Assets

- Sound effects obtained from https://www.zapsplat.com

### This Version

- **Rodarvus** - Author of Search & Destroy v2
- **Claude (Anthropic)** - AI pair programming assistant

## License

This plugin is free to use and modify. It is not a bot and does not violate Aardwolf's rules.
