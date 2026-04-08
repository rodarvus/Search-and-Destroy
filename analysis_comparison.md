# Search & Destroy Plugin Comparison: Crowley vs WinkleGold

## 1. Executive Summary

Both plugins descend from **WinkleWinkle's original Search & Destroy** plugin for Aardwolf MUD. Their lineage diverged:

- **Crowley's S&D** (v5.99.4) evolved through Starling's major fork, then Nokfah's fix, and finally Crowley's ongoing maintenance. It's a **single monolithic plugin** (~10,110 lines) that consolidates all functionality -- campaign/GQ/quest management, hunting, navigation, GUI, database, and auto-noexp -- into one file.

- **WinkleGold's S&D** is a **4-plugin ecosystem** (~2,500+ lines total across files) that separates concerns: core hunting (S&D), campaign/navigation (Mapper Extender), visual display (GUI), and spellup automation (Spellup). They communicate via BroadcastPlugin messages and share a SQLite database.

**Key differences at a glance:**

| Aspect | Crowley | WinkleGold |
|--------|---------|------------|
| Architecture | Monolithic (1 file) | Multi-plugin (4 files + DB) |
| Lines of code | ~10,110 | ~2,500+ across 4 plugins |
| Own database | SnDdb.db (mobs, area, mob_keyword_exceptions) | WinkleGold_Database.db (mobs, mobsubs, startrooms, players) |
| GUI | Built-in miniwindow | Separate GUI plugin |
| Spellup | None | Dedicated spellup plugin |
| Auto-update | Yes (GitHub-based) | No |
| Sound effects | Yes | No |
| Damage tracking | 98 damage verb triggers | None (relies on MUD messages) |
| Accessibility | None | VI Assist integration |
| Keyboard shortcuts | None | Alt+F, Alt+G, Alt+1-9 |

---

## 2. Architecture Comparison

### Crowley: Monolithic Single Plugin

```
┌─────────────────────────────────────────────────┐
│         Search_and_Destroy.xml (~10K lines)     │
│                                                 │
│  ┌───────────┐ ┌──────────┐ ┌───────────────┐  │
│  │ CP/GQ/    │ │ Hunt     │ │ Miniwindow    │  │
│  │ Quest Mgr │ │ Trick/QW │ │ GUI + Hotspot │  │
│  └───────────┘ └──────────┘ └───────────────┘  │
│  ┌───────────┐ ┌──────────┐ ┌───────────────┐  │
│  │ Auto-Hunt │ │ Smart    │ │ Noexp / Sound │  │
│  │ / AutoNav │ │ Scan/Con │ │ / Vidblain    │  │
│  └───────────┘ └──────────┘ └───────────────┘  │
│  ┌───────────┐ ┌──────────┐ ┌───────────────┐  │
│  │ Mob DB    │ │ Area     │ │ Auto-Update   │  │
│  │ (SQLite)  │ │ Index    │ │ System        │  │
│  └───────────┘ └──────────┘ └───────────────┘  │
│                                                 │
│  170+ triggers, 50+ aliases, 50+ globals        │
└─────────────────────────────────────────────────┘
         ↕                    ↕
    SnDdb.db           GMCP Handler
```

**Pros:**
- Single file to install, update, and debug
- No inter-plugin communication overhead
- All state in one place -- no serialization/broadcast needed
- Self-contained auto-update mechanism

**Cons:**
- 10K lines is hard to navigate and maintain
- Can't replace parts independently (e.g., swap just the GUI)
- All-or-nothing: can't use hunt trick without getting campaign management
- 50+ global variables with no encapsulation
- Single point of failure -- a bug anywhere can break everything

### WinkleGold: Multi-Plugin Ecosystem

```
┌──────────────┐  ┌──────────────────┐  ┌──────────────┐
│  S&D Core    │  │ Mapper Extender  │  │ Extender GUI │
│              │  │                  │  │              │
│ Hunt Trick   │──│ CP/GQ Management │──│ Miniwindow   │
│ Auto Hunt    │  │ Room Search      │  │ Target List  │
│ Quick Where  │  │ Area Navigation  │  │ Click-to-Go  │
│ Quick Scan   │  │ Auto-Noexp       │  │ Colors/Fonts │
│ Mob Subs     │  │ Mob Frequency    │  │ Quest Display│
│ Quest Track  │  │ Vidblain Hack    │  │              │
└──────────────┘  └──────────────────┘  └──────────────┘
       ↕                  ↕                    ↕
  Broadcasts: 668    Broadcasts: 667,669,670,680
       ↕                  ↕
┌──────────────────────────────┐  ┌──────────────┐
│    WinkleGold_Database.db    │  │   Spellup    │
│ mobs (14,738) | mobsubs      │  │ Auto-cast    │
│ startrooms   | players       │  │ Combat aware │
└──────────────────────────────┘  └──────────────┘
```

**Pros:**
- Clean separation of concerns
- Can update/replace individual components
- Smaller files are easier to read and maintain
- Spellup is a genuinely separate concern, properly isolated
- Database shared cleanly between plugins

**Cons:**
- 4 plugins to install and keep in sync
- BroadcastPlugin serialization adds overhead and fragility
- Circular dependency risk (S&D <-> Mapper Extender <-> GUI)
- If one plugin crashes, others may be left in bad state
- No centralized update mechanism
- Trigger group state can desync across plugins

---

## 3. Feature Matrix

| Feature | Crowley | WinkleGold | Better Implementation |
|---------|---------|------------|----------------------|
| **Campaign (CP) Management** | Full: cp info/check parsing, target building, area vs room detection, kill tracking | Full: cp check parsing, mapper DB queries, level filtering, frequency data | **Tie** - Crowley is more self-contained; WinkleGold adds mob frequency/probability data |
| **Global Quest (GQ)** | Full: join/start/end/extended tracking, multi-target, effective level calc | Full: join/start/end tracking, same core parsing | **Crowley** - handles extended time, effective level, more edge cases |
| **Regular Quest** | Full: GMCP comm.quest integration, quest timer, auto-targeting | Partial: relayed from S&D to GUI, basic display | **Crowley** - deeper quest state machine (qstat 0-3), quest timer countdown |
| **Hunt Trick** | Full: progressive hunt, direction following, portal/door support | Full: progressive hunt, index tracking, `ht find` recall | **WinkleGold** - cleaner implementation, `ht find` is useful |
| **Quick Where** | Full: area search, retries, fuzzy matching | Full: indexed results, exact matching, `x_qw` prefix | **Tie** - both solid, slightly different approaches |
| **Auto Hunt** | Full: background hunting, step tracking, door opening, direction voting | Full: step limiting (`ahs`), direction confidence voting, GMCP exit awareness | **Tie** - WinkleGold has explicit step limits; Crowley handles more edge cases |
| **Smart Scan / Consider** | Full: scan+consider combo, difficulty analysis, 13 difficulty patterns | Basic: `qs` quick scan only, defers to `cons` for NoScan mobs | **Crowley** - significantly more sophisticated with smart scan combining scan+consider |
| **Area Navigation** | Full: `xrun`/`xrt`, execute-in-area polling, speed settings | Full: `xrt`/`xrunto`, `xroutes` (show all routes!), speed walk/run | **WinkleGold** - `xroutes` showing all marked areas is excellent |
| **Start Rooms** | ~200+ hardcoded + DB override via `xset mark` | ~200+ hardcoded + DB table + `xset mark` | **WinkleGold** - dedicated `startrooms` DB table is cleaner |
| **Mob Database** | SQLite: mob name, room, roomid, zone, seen/kill counts | SQLite: roomid, mobname, frequency; 14,738 entries | **WinkleGold** - frequency-based probability is more useful for targeting |
| **Mob Keyword System** | Keyword guessing (remove suffixes), `mob_keyword_exceptions` DB table | Mob name guessing + `mobsubs` table with NoHunt/NoWhere/NoScan/RoomId flags | **WinkleGold** - mobsubs with behavioral flags is far more flexible |
| **Auto-Noexp** | Full: TNL cutoff, auto-toggle, GMCP config.noexp monitoring | Full: TNL threshold, level detection, mayTakeCP tracking | **Tie** - similar implementations |
| **Miniwindow GUI** | Built-in: resizable, draggable, target links, action buttons, circle readout, quest timer, noexp display, right-click menu | Separate plugin: resizable, draggable, target list, action buttons (go/qs/nx/ak/check), right-click menu with color picker | **Crowley** - more polished with circle readout, quest timer, noexp display; but WinkleGold's separation is architecturally cleaner |
| **Sound Effects** | Yes: target nearby, other target sounds, soundpack integration | No | **Crowley** - unique feature |
| **Spellup Automation** | No | Yes: dedicated plugin with state machine, spell queue, combat exceptions, no-auto list | **WinkleGold** - unique feature (though arguably separate concern) |
| **Vidblain Navigation** | Yes: level threshold, maze handling, special routing | Yes: portal hack via room 11910 | **Crowley** - more configurable with level settings |
| **Auto-Update** | Yes: GitHub-based, `snd update`, `snd force update [branch]` | No | **Crowley** - unique feature |
| **SQL Utilities** | Yes: `runsql`, `execsql` for ad-hoc queries | No | **Crowley** - useful for debugging |
| **Debug/Test Framework** | Extensive: `xtest` commands to simulate CP/GQ/quest, debug mode, mock GQ | Basic: `sd debug`, `ext debug` toggle flags | **Crowley** - much more comprehensive testing tools |
| **Configuration** | Extensive: 20+ `xset` options, right-click color picker, font config, window state | Moderate: `xset` options, right-click color/font picker, keyboard shortcuts | **Crowley** - more options; **WinkleGold** - keyboard shortcuts |
| **Keyboard Shortcuts** | None | Alt+F (xcp), Alt+G (next), Alt+1-9 (target select) | **WinkleGold** - unique feature |
| **Accessibility (VI)** | None | VI Assist integration for screen readers | **WinkleGold** - unique feature |
| **Damage Tracking** | 98 damage verb triggers -> last_mob_damaged -> last_mob_killed | None (relies on CP/GQ kill messages from MUD) | **Crowley** - unique and valuable for kill confirmation |
| **PK Room Warnings** | No | Yes: `xset pk` toggle shows PK flags on rooms | **WinkleGold** - useful safety feature |
| **GQ Reporting** | No | Yes: `qqreport <channel>` reports targets to channel | **WinkleGold** - nice social feature |
| **Room Notes** | Yes: `rn` per-room and per-area notes | Basic: `roomnote` | **Crowley** - more flexible with area-wide notes |
| **Mob Search** | Yes: `ms`/`xmob` search mob database | Yes: `fm`/`fma` find mob in current/all areas | **Tie** |
| **Area Index** | Yes: `xset index areas` parses "areas" command output | Yes: `xareas` parses "areas" command output | **Tie** |

---

## 4. Database Comparison

### Crowley's SnDdb.db

```sql
-- Schema version 4 (with migration support)
CREATE TABLE mobs (
    mob     TEXT COLLATE NOCASE,    -- Mob name
    room    TEXT COLLATE NOCASE,    -- Room name
    roomid  INTEGER,                -- Room ID
    zone    TEXT,                    -- Area ID
    seen_count INTEGER,             -- Times encountered
    kill_count INTEGER,             -- Times killed
    UNIQUE(mob, roomid)
);

CREATE TABLE area (
    name      TEXT,     -- Area long name
    key       TEXT,     -- Area ID (arid)
    minlvl    INTEGER,  -- Min level
    maxlvl    INTEGER,  -- Max level
    lock      INTEGER,  -- Quest lock level
    startRoom INTEGER,  -- Starting room ID
    noquest   TEXT,     -- Non-quest area flag
    vidblain  TEXT,     -- Vidblain area flag
    userKey   TEXT      -- User-defined alternative ID
);

CREATE TABLE mob_keyword_exceptions (
    area_name TEXT,
    mob_name  TEXT,
    keyword   TEXT,
    UNIQUE(area_name, mob_name)
);
```

**Strengths:**
- `seen_count` / `kill_count` provide historical data
- `area` table stores level ranges, flags, and start rooms in one place
- Schema version tracking with migration support
- COLLATE NOCASE on mob/room names

**Weaknesses:**
- No indexes on common query columns
- No mob frequency/probability data
- `mob_keyword_exceptions` is limited to just keyword overrides

### WinkleGold's WinkleGold_Database.db

```sql
CREATE TABLE mobs (
    roomid    INTEGER NOT NULL,
    mobname   TEXT NOT NULL,
    freq      INTEGER NOT NULL DEFAULT 0,  -- Mob frequency in room
    updatedby TEXT(20),                     -- "plugin" or manual
    PRIMARY KEY (roomid, mobname)
);
-- 14,738 rows

CREATE TABLE mobsubs (
    mobname  TEXT NOT NULL,
    areaid   TEXT NOT NULL,
    subname  TEXT NOT NULL,      -- Short substitute name
    nohunt   TEXT NOT NULL DEFAULT 'N',  -- Can't hunt this mob
    nowhere  TEXT NOT NULL DEFAULT 'N',  -- Not found by 'where'
    noscan   TEXT NOT NULL DEFAULT 'N',  -- Use 'cons' instead
    roomid   TEXT,               -- Override: go to this room
    comment  TEXT,               -- User notes
    PRIMARY KEY (mobname, areaid)
);

CREATE TABLE startrooms (
    areaname     INTEGER,   -- Should be TEXT (bug)
    arealongname INTEGER,   -- Should be TEXT (bug)
    roomid       INTEGER
);

CREATE TABLE players (
    playername TEXT PRIMARY KEY NOT NULL
);
```

**Strengths:**
- `freq` column enables probability-based targeting (huge advantage)
- `mobsubs` with behavioral flags (nohunt/nowhere/noscan/roomid) is far more flexible than keyword-only exceptions
- Proper PRIMARY KEY constraints
- 14,738 mob entries = substantial pre-populated data

**Weaknesses:**
- `startrooms` has INTEGER types for TEXT columns (schema bug)
- `players` table appears unused (0 rows)
- No area level range table (stored in plugin state instead)
- No schema version tracking or migration support
- No COLLATE NOCASE on text columns

### Database Recommendation for New Plugin

```sql
-- Unified schema taking best of both:

CREATE TABLE mobs (
    mob       TEXT NOT NULL COLLATE NOCASE,
    room      TEXT COLLATE NOCASE,
    roomid    INTEGER NOT NULL,
    zone      TEXT NOT NULL,
    freq      INTEGER NOT NULL DEFAULT 0,
    seen_count INTEGER NOT NULL DEFAULT 0,
    kill_count INTEGER NOT NULL DEFAULT 0,
    updated_at INTEGER,  -- Unix timestamp
    PRIMARY KEY (mob, roomid)
);
CREATE INDEX idx_mobs_zone ON mobs(zone);
CREATE INDEX idx_mobs_roomid ON mobs(roomid);

CREATE TABLE areas (
    key        TEXT PRIMARY KEY,
    name       TEXT NOT NULL,
    minlvl     INTEGER DEFAULT 0,
    maxlvl     INTEGER DEFAULT 300,
    lock_level INTEGER DEFAULT 0,
    start_room INTEGER,
    noquest    INTEGER DEFAULT 0,  -- Boolean
    vidblain   INTEGER DEFAULT 0,  -- Boolean
    user_key   TEXT
);

CREATE TABLE mob_overrides (
    mob_name   TEXT NOT NULL COLLATE NOCASE,
    area_id    TEXT NOT NULL,
    keyword    TEXT,           -- Short name override
    no_hunt    INTEGER DEFAULT 0,
    no_where   INTEGER DEFAULT 0,
    no_scan    INTEGER DEFAULT 0,
    goto_room  INTEGER,        -- Override room to navigate to
    comment    TEXT,
    PRIMARY KEY (mob_name, area_id)
);

CREATE TABLE start_rooms (
    area_key      TEXT NOT NULL,
    area_longname TEXT,
    roomid        INTEGER NOT NULL,
    user_set      INTEGER DEFAULT 0,  -- 1 if user-marked
    PRIMARY KEY (area_key)
);

-- Schema versioning
PRAGMA user_version = 1;
```

---

## 5. GMCP Integration Comparison

| GMCP Module | Crowley | WinkleGold |
|-------------|---------|------------|
| `char.status` | State, level (auto-noexp check for level < 200) | State, level, HP/mana (all 4 plugins) |
| `char.base` | Not used | Tier, skills (Mapper Extender) |
| `char.vitals` | Not used | HP/mana/moves state checks |
| `room.info` | Room ID, zone, exits, details (maze detect), name | Room ID, zone, exits, coordinates |
| `room.area` | Not used | Area metadata (Mapper Extender) |
| `comm.quest` | Quest target, area, room, timer, status | Relayed from S&D to GUI via broadcast 150/151 |
| `config.noexp` | Monitors "YES"/"NO" for display | Monitors for auto-toggle |
| `config` | noexp only | NoExp status (Mapper Extender) |

**Crowley's approach:** Direct GMCP access via `gmcp()` helper function. Single `OnPluginBroadcast()` handler processes all messages.

**WinkleGold's approach:** Each plugin has its own `OnPluginBroadcast()` handler. GMCP data accessed via `CallPlugin(mapper_id, "gmcpval", ...)`. More indirect but allows each plugin to react independently.

**Edge Cases:**
- Crowley handles maze rooms via `room.info.details` parsing -- WinkleGold doesn't
- WinkleGold monitors more GMCP modules (char.base, char.vitals, room.area)
- Neither handles GMCP disconnection/reconnection gracefully

---

## 6. Code Quality Comparison

| Aspect | Crowley | WinkleGold |
|--------|---------|------------|
| **Naming** | Mixed camelCase/snake_case; cryptic abbreviations (ht, qw, xcp) | Similar mix; slightly more readable function names |
| **Global Variables** | 50+ globals, no encapsulation | Fewer per plugin, but still many globals; slightly better due to plugin isolation |
| **Comments** | Sparse inline; some function headers; some outdated | Moderate; debug output serves as documentation |
| **Error Handling** | `dbcheck()` wrapper for DB; `fixsql()` for escaping; some silent failures | Basic: graceful fallbacks with warning messages; less DB error handling |
| **SQL Safety** | String concatenation with `fixsql()` escaping | String concatenation with basic escaping; similar risk level |
| **Testing** | Extensive `xtest` framework (simulate CP/GQ/quest, mock data) | Basic debug toggles only |
| **Code Organization** | Roughly grouped by feature but no clear module boundaries | Clean separation via plugins, but tight coupling undermines this |
| **Function Size** | Many functions > 50 lines; `xg_draw_window()` likely > 200 | Smaller functions generally; GUI render still large |
| **Dead Code** | Many `xtest_*` functions left in production | Less dead code, but unused recovery capture in Spellup |
| **Magic Numbers** | Window dimensions, timer intervals | "17" for line spacing, "11" for level tolerance |
| **Hardcoded Data** | `areaDefaultStartRooms` (~800 lines), `areaNameXref` (~500 lines) | ~200 hardcoded start rooms in Mapper Extender |
| **State Management** | Complex: 50+ `mcvar_*` persisted variables | Split across plugins: less per plugin but harder to reason about globally |

---

## 7. Bugs and Issues Identified

### Crowley - Critical

1. **No DB indexes** - Common queries on `mobs` table (by mob name, roomid, zone) have no indexes. With a growing database, queries will slow significantly.
2. **Race condition in xcp_retry** - Kill-during-update scenario uses `xcp_retry_stat` flag, but logic is complex and may miss edge cases where target list changes between kill detection and list refresh.
3. **98 damage verb triggers always active** - These fire on every line of combat output, parsing mob names constantly. Performance impact in heavy combat.

### Crowley - Moderate

4. **Fragile output parsing** - Hard dependency on exact MUD output format for cp info/check, gq info/check. Any MUD output format change breaks the plugin.
5. **Hard-coded area tables** - 1,300+ lines of hardcoded area data that becomes stale as Aardwolf evolves. Should be fully database-resident.
6. **Full window redraw on every update** - No dirty-rect optimization. With many targets, redraw becomes expensive.
7. **SQL string concatenation** - `fixsql()` escaping is basic; potential for edge-case SQL injection with unusual mob names.

### Crowley - Minor

8. **Mixed naming conventions** - camelCase, snake_case, and abbreviations used inconsistently.
9. **Testing code in production** - `xtest_*` functions and `mock_gquests` add complexity without user value.
10. **Sound file paths hardcoded** - No validation; silent failure if files missing.
11. **"I suspect" error messages** - Confusing user-facing language in some error paths.

### WinkleGold - Critical

1. **Bug in hunt_trick()** (S&D line ~760) - `ht.full_name = get_short_mob_name()` assigns the short name to the full_name variable. Should be `get_full_mob_name()`.
2. **startrooms table schema bug** - `areaname` and `arealongname` declared as INTEGER but should be TEXT. SQLite's type affinity masks this, but it's technically wrong.
3. **N-squared CP/GQ processing** - Each campaign check queries the mapper database for every mob in every matching room. With large campaign lists, this creates a performance bottleneck.

### WinkleGold - Moderate

4. **Trigger group desync across plugins** - If one plugin crashes, others may have trigger groups left in enabled/disabled state with no recovery mechanism.
5. **Circular broadcast dependency** - S&D broadcasts mob names (668) -> Mapper Extender searches -> GUI displays -> GUI sends commands back. A broadcast error can cascade.
6. **No auto-update** - Users must manually update all 4 plugins, keeping versions in sync.
7. **GUI window overflow** - If CP/GQ has > ~17 items, the window extends beyond screen bounds. No scrolling implemented.
8. **Recovery data captured but never used** (Spellup) - Triggers `RecoveriesStart/Capture/End` exist but data is discarded.

### WinkleGold - Minor

9. **Hardcoded plugin IDs** - Not configurable; if a dependency plugin changes ID, code breaks.
10. **No timeout on where trick** - Dynamic triggers created but not aggressively cleaned up.
11. **Combat exception list not user-configurable** (Spellup) - Hardcoded to 5 specific spells.
12. **V2 clan skill requires manual SN entry** (Spellup) - No auto-detection.
13. **Window resize uses uninitialized globals** (GUI) - `startx, starty` in ResizeMoveCallback.
14. **SQL injection via mob names** - Basic escaping, same risk as Crowley.

---

## 8. Recommendations for New Plugin

### Architecture Decision: Hybrid Approach

**Recommendation: 2-plugin design** (core + GUI)

- **Core plugin** (~one file): All logic -- hunting, CP/GQ/quest management, navigation, database, noexp, settings. This avoids WinkleGold's inter-plugin communication overhead while keeping things more focused than Crowley's monolith.
- **GUI plugin** (separate file): Miniwindow display only. Receives state via broadcast, sends commands back. This allows GUI replacement/customization without touching logic.
- **Do NOT include spellup** - it's a genuinely separate concern. If wanted, it should be a standalone plugin with no S&D dependency.

**Rationale:** The WinkleGold 4-plugin model creates too much coupling overhead for what is fundamentally one workflow. But Crowley's 10K-line monolith is hard to maintain. A 2-plugin split at the logic/presentation boundary is the sweet spot.

### Features to Take from Each Plugin

**From Crowley:**
- Damage verb tracking (98 triggers -> kill confirmation). This is invaluable for reliable mob kill detection beyond just CP/GQ messages.
- Smart Scan + Consider combo (difficulty analysis with 13 patterns)
- Quest state machine (qstat 0-3) with timer countdown
- Room notes system (per-room and per-area)
- Auto-update from GitHub
- `runsql`/`execsql` debug utilities
- Schema version tracking with migration support
- Sound effects (optional, configurable)
- Comprehensive xtest debug framework (but clean up for production)

**From WinkleGold:**
- Mob frequency/probability data in database (`freq` column)
- `mobsubs` with behavioral flags (nohunt/nowhere/noscan/goto_room)
- Keyboard shortcuts (Alt+F, Alt+G, Alt+1-9)
- `xroutes` command (show all marked area routes)
- PK room warnings
- `qqreport` (GQ target reporting to channel)
- `ht find` (recall last hunt trick result)
- Step-limited auto hunt (`ahs mob steps`)
- VI Assist integration (accessibility)
- Cleaner plugin broadcast architecture for GUI separation

### Must-Fix Bugs

1. **Add database indexes** on all commonly queried columns
2. **Fix hunt_trick full_name/short_name assignment** bug
3. **Fix startrooms schema** (TEXT not INTEGER)
4. **Implement scrolling** in GUI for long target lists
5. **Add trigger group recovery** on plugin load (reset all groups to known state)
6. **Use parameterized queries** or proper escaping for all SQL
7. **Optimize damage triggers** - consider a single regex with alternation instead of 98 separate triggers
8. **Add GMCP reconnection handling**

### Missing Features to Add

1. **Target prioritization** - Sort targets by: distance (closest first), mob frequency (most likely rooms first), area difficulty (easiest first), or user preference.
2. **Statistics dashboard** - Track mobs killed/hour, campaigns completed/hour, average campaign time, XP/hour.
3. **Scrollable target list** in GUI with page up/down.
4. **Import/export** for mob overrides and start rooms (share with other players).
5. **Tab-based GUI** - Tabs for CP, GQ, Quest, Stats, Settings instead of one cramped window.
6. **Undo navigation** - Go back to previous room if you navigated to wrong target.
7. **Area blacklist** - Never navigate to specific areas (PK, broken, personal preference).
8. **Mob difficulty memory** - Track which mobs you struggled with and warn on future encounters.
9. **Campaign timer** - Track how long current campaign has been active.
10. **Integration with leveldb/argus** - If applicable, share data with your other plugins.

### Code Quality Standards

1. **Use a module pattern** for Lua code organization:
   ```lua
   local CP = {}  -- Campaign module
   local GQ = {}  -- Global Quest module
   local Nav = {} -- Navigation module
   local DB = {}  -- Database module
   local UI = {}  -- UI helpers (in core plugin)
   ```
2. **No global variables** - Use module tables or a single `state` table.
3. **Consistent naming** - `snake_case` for functions and variables (Lua convention).
4. **Parameterized SQL** - Use prepared statements or at minimum robust escaping.
5. **Add indexes** to all database tables on query columns.
6. **Schema migrations** - Version-tracked with forward migration functions.
7. **Error boundaries** - `pcall()` around database operations and GMCP parsing.
8. **Constants file** - All magic numbers, plugin IDs, broadcast message numbers in one place.
9. **Minimize hardcoded area data** - Store in database, populate on first run, update via `xareas`.
10. **Comment public functions** - Brief doc comment on purpose, parameters, return values.

---

## Appendix A: Plugin IDs and Dependencies

### Crowley
| Component | Plugin ID |
|-----------|-----------|
| Search & Destroy | 30000000537461726C696E67 |
| GMCP Handler (dep) | 3e7dedbe37e44942dd46d264 |
| GMCP Mapper (dep) | b6eae87ccedd84f510b74714 |
| Z-Order (dep) | 462b665ecb569efbf261422f |
| Soundpack (optional) | 23832d1089f727f5f34abad8 |

### WinkleGold
| Component | Plugin ID |
|-----------|-----------|
| S&D Core | e50b1d08a0cfc0ee9c442001 |
| Mapper Extender | b6eae87ccedd84f510b74715 |
| Extender GUI | 3f498d929793c12cb70f5999 |
| Spellup | e50b1d08a0cfc0ee9c442002 |
| GMCP Handler (dep) | 3e7dedbe37e44942dd46d264 |
| GMCP Mapper (dep) | b6eae87ccedd84f510b74714 |
| Z-Order (dep) | 462b665ecb569efbf261422f |
| VI Assist (optional) | 6000a4c6f0e71d31fecf523d |

## Appendix B: Broadcast Message Numbers

| Msg # | Sender | Receiver | Data | Purpose |
|-------|--------|----------|------|---------|
| 150 | WG S&D | WG GUI | quest info table | Quest tracking |
| 151 | WG S&D | WG GUI | (empty) | Quest mob killed |
| 668 | WG S&D | WG Mapper | mob name string | Mob name for search |
| 667 | WG Mapper | WG GUI | GQ list (serialized) | Display GQ items |
| 669 | WG Mapper | WG GUI | CP list (serialized) | Display CP items |
| 670 | WG Mapper | WG GUI | index number | Mode (cp/gq) |
| 680 | WG Mapper | WG GUI | index number | Highlight selection |

## Appendix C: Command Reference Comparison

| Action | Crowley Command | WinkleGold Command |
|--------|----------------|-------------------|
| Help | `xhelp` | `search help` / `ww help` |
| Campaign check | `cp i` / `cp ch` | `xcp` / `cp c` |
| Go to CP target | `xcp` / `xcp <N>` | `xcp <N>` |
| GQ check | `gq i` / `gq ch` / `gg` / `qq` | `qq` / `gq c` |
| Go to GQ target | `xcp` (auto-detects) | `qq <N>` |
| Hunt trick | `ht [index] [mob]` | `ht [index] [mob]` |
| Abort hunt | `hta` / `ht0` | `ht a` |
| Find last hunt | N/A | `ht f` / `ht find` |
| Auto hunt | `ah <mob>` | `ah <mob>` |
| Auto hunt w/ steps | N/A | `ahs <mob> <steps>` |
| Abort auto hunt | `ah0` / `aha` | `ah a` |
| Quick where | `qw [index] [mob]` | `qw [index.]<mob>` |
| Quick scan | `qs` | `qs` |
| Quick kill | `qk` / `ak` / `kk` | `ak` / `autokill` |
| Run to area | `xrt <area>` | `xrt <area>` / `xrunto <area>` |
| Show all routes | N/A | `xroutes` |
| Next target | `nx` | `nx` |
| Go to room | `go <index>` | `go <index>` |
| Mark start room | `xset mark <name> [roomid]` | `xset mark` |
| Search mobs | `ms <name>` | `fm <name>` / `fma <name>` |
| Room note | `rn` / `roomnote` | `roomnote` |
| Set noexp | `xset noexp <value>` | `xset noexp <value>` |
| Area index | `xset index areas` | `xareas` |
| Mob substitution | N/A (keyword only: `xset kw`) | `mobsub <N>` / `delmobsub <N>` |
| Debug mode | `xtest debug` | `sd debug` / `ext debug` |
| Update plugin | `snd update` | N/A |
| Report GQ | N/A | `qqreport <channel>` |
| Toggle PK display | N/A | `xset pk` |
| Window reset | `xset winreset` | `xset reset gui` |
| SQL query | `runsql <query>` | N/A |
| Vidblain toggle | `xset vidblain` | `xset vidblain` |
| Show keyword | `xset kw` | N/A |
| Sound toggle | `xset sound` | N/A |
| Silent mode | `xset silent` | `xset silentmode` |

---

## Addendum: Phase 2 Design Analysis (2026-04-08)

### Trigger Pattern Accuracy

Cross-referencing Crowley, WinkleGold, and the leveldb plugin revealed several incorrect patterns in our Phase 1 triggers:

| Pattern | Issue | Resolution |
|---------|-------|------------|
| Quick where match | Used "X is in Y" prose; actual output is 30-char padded tabular | Adopted Crowley/WinkleGold `.{30}` format (verified live) |
| Quick where no-match | Included hallucinated "No one by that name" variant | Removed; only "There is no X around here." is real (Crowley) |
| Level-up | "Congratulations, hero" matches no real message | Corrected to "You raise a level!" (Crowley/WinkleGold) |
| GQ joined | "You have joined" missing "now" | "You have now joined" (leveldb, Crowley) |
| GQ started | Simple "has now started!" | Full format with level range (Crowley line 9323) |
| GQ ended | "has ended/been won" conflated two events | "is now over" for ended; "first to complete" for personal win (leveldb) |

**Key lesson:** leveldb plugin is the most authoritative and recent source for Aardwolf message formats. Cross-reference all three sources before committing to a pattern.

### CP Parsing: Crowley vs WinkleGold

| Aspect | Crowley | WinkleGold | Our Choice |
|--------|---------|------------|------------|
| Parse cp info | Yes (gets level) | No | Yes — level needed for room-based CP filtering |
| Parse cp check | Yes | Yes (primary) | Yes — authoritative list with dead flags |
| Area detection | Static areaNameXref table (~260 entries) | Mapper DB UNION query | Mapper DB first, CONST.AREA_NAME_XREF fallback |
| Mob name parsing | Character-by-character with paren counter | Regex `[^\(]+` (breaks on parens in names) | Greedy regex backtracking (handles parens correctly) |
| Dead flag | Parsed in callback via string check | Regex named capture `(?<isdead>)` | Regex capturing group `(?: - (Dead))?` |
| Keyword timing | Upfront during list build | Lazy on target selection | Upfront (Crowley's approach — keywords ready for display) |
| Room-based duplicates | One entry per possibility, `unlikely` flag | Multiple entries, `removed_guesses` | Multiple entries, most likely marked with `likely` flag and sorted first (WinkleGold's battle-tested approach) |

### Hunt Trick Design (WinkleGold — authoritative)

WinkleGold's hunt trick implementation is well-designed and battle-tested:
- `hunt N.<keyword>` cycles through numbered instances of mobs with same keyword
- "Unable to hunt" = **SUCCESS** (game blocks hunting CP targets directly)
- "Direction" response = wrong mob, increment N and retry
- "No one by that name" = exhausted, keyword wrong
- After finding correct N, follows up with `qw N.<keyword>`
- Three triggers: continue (direction), complete (unable=found), abort (not found/fighting)

### GQ Lifecycle (from Crowley + leveldb)

Crowley tracks join and start as separate events with `gqid_joined`/`gqid_started` variables. GQ triggers only activate when both have occurred for the same GQ number. This handles:
- Join before start: wait until GQ starts to parse targets
- Join after start: immediate target parsing
- GQ end while joined: cleanup state

New triggers added based on leveldb: won, cancelled, quit, not_in.

### xrt Command Clarification

`xrt` (xrun_to) is a speedwalk command, NOT a retarget command:
1. Look up area start room (user-marked or default from DB)
2. Fall back to mapper DB (exact area key, then fuzzy name match)
3. Execute `mapper goto <roomid>`
4. Handle Vidblain special case (need to runto vidblain continent first)
