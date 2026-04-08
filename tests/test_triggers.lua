------------------------------------------------------------------------
-- test_triggers.lua - PCRE regex validation for all trigger patterns
-- Uses rex_pcre (lrexlib) to test patterns against verified game output.
-- Patterns are hardcoded here as the "intended" correct patterns.
-- If XML patterns don't match, the XML needs fixing.
------------------------------------------------------------------------

if not CONST then
   local load_plugin = require("load_plugin")
   load_plugin()
end

local rex = require("rex_pcre")
local TestData = require("test_data")

function setUp()
   mock.reset()
end

------------------------------------------------------------------------
-- Helper: test that a PCRE pattern matches a string and returns expected captures
------------------------------------------------------------------------
local function pcre_match(pattern, str, flags)
   return rex.match(str, pattern, 1, flags)
end

local function pcre_find(pattern, str, flags)
   return rex.find(str, pattern, 1, flags)
end

-- Case-insensitive flag for rex_pcre
local CF_I = rex.flags().CASELESS

------------------------------------------------------------------------
-- CP INFO triggers
------------------------------------------------------------------------

run_test("trg_cp_info_level", function()
   local pat = [[^Level Taken\.{8}: \[\s+(\d{1,3}) \]$]]
   -- Positive: captures level
   assert_equal("45", pcre_match(pat, "Level Taken........: [  45 ]"), "captures level 45")
   assert_equal("150", pcre_match(pat, "Level Taken........: [ 150 ]"), "captures level 150")
   assert_equal("1", pcre_match(pat, "Level Taken........: [   1 ]"), "captures level 1")
   -- Negative
   assert_nil(pcre_find(pat, "Level Taken: [ 45 ]"), "wrong dot count doesn't match")
   assert_nil(pcre_find(pat, "Something else"), "unrelated line doesn't match")
end)

run_test("trg_cp_info_start", function()
   local pat = [[^The targets for this campaign are:$]]
   assert_not_nil(pcre_find(pat, "The targets for this campaign are:"), "matches start line")
   assert_nil(pcre_find(pat, "The targets for this campaign are: extra"), "no trailing text")
end)

run_test("trg_cp_info_line", function()
   local pat = [[^Find and kill 1 \* (.+) \((.+)\)$]]
   -- Test against all cp_info_area samples
   for _, target in ipairs(TestData.cp_info_area_parsed.targets) do
      local line = "Find and kill 1 * " .. target.mob .. " (" .. target.location .. ")"
      local mob, loc = pcre_match(pat, line)
      assert_equal(target.mob, mob, "mob from: " .. line)
      assert_equal(target.location, loc, "loc from: " .. line)
   end
   -- Negative
   assert_nil(pcre_find(pat, "You still have to kill * a goblin (Test)"), "check line doesn't match info pattern")
end)

run_test("trg_cp_info_end", function()
   -- Negative lookahead: matches lines that are NOT cp info lines
   local pat = [[^(?!Find and kill 1 \* .+ \(.+\))]]
   -- Should match: empty line, random text, cp check line
   assert_not_nil(pcre_find(pat, ""), "empty line matches end")
   assert_not_nil(pcre_find(pat, "Some other line"), "non-info line matches end")
   assert_not_nil(pcre_find(pat, "You still have to kill * a goblin (Test)"), "check line matches end (not an info line)")
   -- Should NOT match: cp info lines
   assert_nil(pcre_find(pat, "Find and kill 1 * a goblin (Test Area)"), "info line does not match end")
end)

------------------------------------------------------------------------
-- CP CHECK triggers
------------------------------------------------------------------------

run_test("trg_cp_check_line", function()
   local pat = [[^You still have to kill \* (.+) \((.+?)(?: - (Dead))?\)$]]
   -- Alive target: group 3 is false (unmatched capture)
   local mob, loc, dead = pcre_match(pat, "You still have to kill * a sinister vandal (The Three Pillars of Diatz)")
   assert_equal("a sinister vandal", mob, "alive mob name")
   assert_equal("The Three Pillars of Diatz", loc, "alive location")
   assert_equal(false, dead, "alive: dead capture is false")
   -- Dead target: group 3 is "Dead"
   mob, loc, dead = pcre_match(pat, "You still have to kill * a mutated goat (The Killing Fields - Dead)")
   assert_equal("a mutated goat", mob, "dead mob name")
   assert_equal("The Killing Fields", loc, "dead location (- Dead stripped)")
   assert_equal("Dead", dead, "dead: captures Dead string")
   -- Negative
   assert_nil(pcre_find(pat, "Find and kill 1 * a goblin (Test)"), "info line doesn't match check")
end)

run_test("trg_cp_check_end", function()
   local pat = [[^(?!You still have to kill \* .+ \(.+?(?: - Dead)?\))]]
   -- Should match non-check lines
   assert_not_nil(pcre_find(pat, ""), "empty line matches end")
   assert_not_nil(pcre_find(pat, "Note: Dead means that the target is dead, not that you have killed it."), "dead note matches end")
   -- Should NOT match check lines
   assert_nil(pcre_find(pat, "You still have to kill * a goblin (Test Area)"), "check line does not match end")
   assert_nil(pcre_find(pat, "You still have to kill * a goblin (Test Area - Dead)"), "dead check line does not match end")
end)

run_test("trg_cp_check_dead_note", function()
   local pat = [[^Note: Dead means that the target is dead, not that you have killed it\.$]]
   assert_not_nil(pcre_find(pat, "Note: Dead means that the target is dead, not that you have killed it."), "dead note matches")
   assert_nil(pcre_find(pat, "Note: something else"), "other note doesn't match")
end)

------------------------------------------------------------------------
-- CP EVENT triggers
------------------------------------------------------------------------

run_test("trg_cp_request", function()
   -- Apostrophes decoded from &#39; at runtime
   local pat = [[^\w.+ tells you 'Good luck in your campaign!'$]]
   assert_not_nil(pcre_find(pat, TestData.cp_events.request), "cp request matches")
   assert_not_nil(pcre_find(pat, "SomeNPC tells you 'Good luck in your campaign!'"), "different NPC name matches")
   assert_nil(pcre_find(pat, "Good luck in your campaign!"), "bare message doesn't match")
end)

run_test("trg_cp_mob_killed", function()
   local pat = [[^Congratulations, that was one of your CAMPAIGN mobs!$]]
   assert_not_nil(pcre_find(pat, TestData.cp_events.mob_killed), "cp mob killed matches")
   assert_nil(pcre_find(pat, TestData.gq_events.mob_killed), "gq mob killed doesn't match cp pattern")
end)

run_test("trg_cp_complete", function()
   local pat = [[^CONGRATULATIONS! You have completed your campaign\.$]]
   assert_not_nil(pcre_find(pat, TestData.cp_events.complete), "cp complete matches")
end)

run_test("trg_cp_cleared", function()
   local pat = [[^Campaign cleared\.$]]
   assert_not_nil(pcre_find(pat, TestData.cp_events.cleared), "cp cleared matches")
end)

run_test("trg_cp_new_available", function()
   -- Matches 4 variants (pattern from Crowley line 9447, identical to ours)
   local pat = [[^(?:(?:## )?You may now take another campaign\.|You may take (?:a campaign at this level|another campaign)\.)$]]
   assert_not_nil(pcre_find(pat, TestData.cp_events.new_available_1), "variant 1: You may now take")
   assert_not_nil(pcre_find(pat, TestData.cp_events.new_available_2), "variant 2: ## You may now take")
   assert_not_nil(pcre_find(pat, TestData.cp_events.new_available_3), "variant 3: a campaign at this level")
   assert_not_nil(pcre_find(pat, TestData.cp_events.new_available_4), "variant 4: another campaign")
end)

run_test("trg_cp_not_on", function()
   local pat = [[^You are not currently on a campaign\.$]]
   assert_not_nil(pcre_find(pat, TestData.cp_events.not_on), "cp not on matches")
end)

run_test("trg_cp_must_level", function()
   local pat = [[^You must level to get a new campaign\.$]]
   assert_not_nil(pcre_find(pat, TestData.cp_events.must_level), "cp must level matches")
end)

run_test("trg_cp_timer", function()
   -- Superhero CP cooldown (from Crowley line 9452, TODO: verify live at superhero)
   local pat = [[^You cannot take another campaign for (?:(?:\d+ hours?, )?\d+ minutes? and )?\d+ seconds?\.$]]
   assert_not_nil(pcre_find(pat, "You cannot take another campaign for 5 minutes and 30 seconds."), "minutes and seconds")
   assert_not_nil(pcre_find(pat, "You cannot take another campaign for 1 hours, 5 minutes and 30 seconds."), "hours minutes seconds")
   assert_not_nil(pcre_find(pat, "You cannot take another campaign for 30 seconds."), "seconds only")
end)

------------------------------------------------------------------------
-- GQ INFO triggers
------------------------------------------------------------------------

run_test("trg_gq_info_quest_name", function()
   local pat = [[^Quest Name\.\.\.\.\.\.\.\.\.: \[ Global quest # (\d{1,5}) \]$]]
   local id = pcre_match(pat, "Quest Name.........: [ Global quest # 12345 ]")
   assert_equal("12345", id, "captures gq id")
end)

run_test("trg_gq_info_extended", function()
   local pat = [[^Quest Status\.\.\.\.\.\.\.: \[ Extended \]$]]
   assert_not_nil(pcre_find(pat, "Quest Status.......: [ Extended ]"), "extended status matches")
end)

run_test("trg_gq_info_level", function()
   local pat = [[^Level range\.\.\.\.\.\.\.\.: \[\s+(\d{1,3}) \] - \[\s+(\d{1,3}) \]$]]
   local min, max = pcre_match(pat, "Level range........: [  40 ] - [  50 ]")
   assert_equal("40", min, "min level")
   assert_equal("50", max, "max level")
end)

run_test("trg_gq_info_line", function()
   local pat = [[^Kill at least (\d+) \* (.+) \((.+)\)\.$]]
   local qty, mob, loc = pcre_match(pat, "Kill at least 2 * a sinister vandal (The Three Pillars of Diatz).")
   assert_equal("2", qty, "quantity")
   assert_equal("a sinister vandal", mob, "mob name")
   assert_equal("The Three Pillars of Diatz", loc, "location")
end)

run_test("trg_gq_info_end", function()
   local pat = [[^---------------------------------------------------------------------------$]]
   assert_not_nil(pcre_find(pat, "---------------------------------------------------------------------------"), "gq info end matches")
   assert_nil(pcre_find(pat, "---"), "short dashes don't match")
end)

------------------------------------------------------------------------
-- GQ CHECK triggers
------------------------------------------------------------------------

run_test("trg_gq_check_line", function()
   local pat = [[^You still have to kill ([1-3]) \* (.+) \((\S.+?)(?: - Dead)?\)$]]
   -- Alive
   local qty, mob, loc = pcre_match(pat, "You still have to kill 2 * a sinister vandal (The Three Pillars of Diatz)")
   assert_equal("2", qty, "qty alive")
   assert_equal("a sinister vandal", mob, "mob alive")
   assert_equal("The Three Pillars of Diatz", loc, "loc alive")
   -- Dead
   qty, mob, loc = pcre_match(pat, "You still have to kill 1 * a mutated goat (The Killing Fields - Dead)")
   assert_equal("1", qty, "qty dead")
   assert_equal("a mutated goat", mob, "mob dead")
   assert_equal("The Killing Fields", loc, "loc dead (- Dead stripped)")
end)

run_test("trg_gq_check_end", function()
   local pat = [[^(?!You still have to kill [1-3] \* .+ \(\S.+?(?: - Dead)?\))]]
   assert_not_nil(pcre_find(pat, ""), "empty line matches gq check end")
   assert_nil(pcre_find(pat, "You still have to kill 2 * a vandal (Test Area)"), "gq check line doesn't match end")
end)

------------------------------------------------------------------------
-- GQ EVENT triggers (verified against leveldb + Crowley)
------------------------------------------------------------------------

run_test("trg_gq_mob_killed", function()
   local pat = [[^Congratulations, that was one of the GLOBAL QUEST mobs!$]]
   assert_not_nil(pcre_find(pat, TestData.gq_events.mob_killed), "gq mob killed matches")
   assert_nil(pcre_find(pat, TestData.cp_events.mob_killed), "cp mob killed doesn't match gq pattern")
end)

run_test("trg_gq_joined", function()
   -- No $ anchor: trailing text follows (leveldb line 427)
   local pat = [[^You have now joined Global Quest # (\d+)\.]]
   local id = pcre_match(pat, TestData.gq_events.joined)
   assert_equal("12345", id, "captures gq id from joined")
end)

run_test("trg_gq_started", function()
   -- Crowley line 9323, Simulate line 4664
   local pat = [[^Global Quest: Global quest # (\d+) for levels (\d{1,3}) to (\d{1,3})(?: - .+)? has now started\.$]]
   local id, min, max = pcre_match(pat, TestData.gq_events.started)
   assert_equal("12345", id, "gq id from started")
   assert_equal("40", min, "min level from started")
   assert_equal("50", max, "max level from started")
   -- With win limit
   id, min, max = pcre_match(pat, TestData.gq_events.started_with_limit)
   assert_equal("12345", id, "gq id from started with limit")
   assert_equal("40", min, "min level from started with limit")
   assert_equal("50", max, "max level from started with limit")
end)

run_test("trg_gq_finished", function()
   local pat = [[^You have finished this global quest\.$]]
   assert_not_nil(pcre_find(pat, TestData.gq_events.finished), "gq finished matches")
end)

run_test("trg_gq_ended", function()
   -- leveldb line 487
   local pat = [[^Global Quest: Global quest # (\d+)(?: \(extended\))? is now over\.$]]
   local id = pcre_match(pat, TestData.gq_events.ended)
   assert_equal("12345", id, "gq id from ended")
   -- Extended
   id = pcre_match(pat, TestData.gq_events.ended_extended)
   assert_equal("12345", id, "gq id from ended extended")
end)

run_test("trg_gq_won", function()
   -- leveldb line 463
   local pat = [[^You were the first to complete this quest!$]]
   assert_not_nil(pcre_find(pat, TestData.gq_events.won), "gq won matches")
end)

run_test("trg_gq_not_started", function()
   local pat = [[^Global Quest # (\d{1,5}) has not yet started\.$]]
   local id = pcre_match(pat, TestData.gq_events.not_started)
   assert_equal("12345", id, "gq id from not started")
end)

run_test("trg_gq_cancelled", function()
   -- leveldb line 499
   local pat = [[^Global Quest: Global quest # (\d+) has been cancelled due to lack of activity\.$]]
   local id = pcre_match(pat, TestData.gq_events.cancelled)
   assert_equal("12345", id, "gq id from cancelled")
end)

run_test("trg_gq_quit", function()
   -- leveldb line 511
   local pat = [[^You are no longer part of Global Quest # (\d+) and will be unable to rejoin\.$]]
   local id = pcre_match(pat, TestData.gq_events.quit)
   assert_equal("12345", id, "gq id from quit")
end)

run_test("trg_gq_not_in", function()
   -- leveldb line 523
   local pat = [[^You are not in a global quest\.$]]
   assert_not_nil(pcre_find(pat, TestData.gq_events.not_in), "gq not in matches")
end)

------------------------------------------------------------------------
-- HUNT TRICK triggers
-- Patterns use ' (apostrophe) in XML as &#39; — decoded at runtime
------------------------------------------------------------------------

run_test("trg_ht_direction", function()
   -- Combined pattern with 5 capture groups across alternations
   -- Apostrophes decoded from &#39;
   local pat = [[^(?:You are (?:almost )?certain that \w.+ is (north|south|east|west|up|down) from here\.|You are confident that \w.+ passed through here, heading (north|south|east|west|up|down)\.|The trail of \w.+ is confusing, but you're reasonably sure \w.+ headed (north|south|east|west|up|down)\.|There are traces of \w.+ having been here\. Perhaps they lead (north|south|east|west|up|down)\?|You have no idea what you're doing, but maybe \w.+ is (north|south|east|west|up|down)\?|You couldn't find a path to \w.+ from here\.)$]]

   -- Helper: find first string capture (direction) from multiple groups
   -- rex_pcre returns false for unmatched capture groups, not nil
   local function get_direction(str)
      local c1, c2, c3, c4, c5 = pcre_match(pat, str)
      if type(c1) == "string" then return c1 end
      if type(c2) == "string" then return c2 end
      if type(c3) == "string" then return c3 end
      if type(c4) == "string" then return c4 end
      if type(c5) == "string" then return c5 end
      return nil
   end

   -- Test each confidence level from TestData
   for _, h in ipairs(TestData.hunt_directions) do
      if h.direction then
         local dir = get_direction(h.line)
         assert_equal(h.direction, dir, "direction from: " .. h.line:sub(1, 40))
      else
         -- Failure case: "couldn't find a path" — matches but no direction captured
         assert_not_nil(pcre_find(pat, h.line), "failure line matches: " .. h.line:sub(1, 40))
         assert_nil(get_direction(h.line), "no direction captured for failure")
      end
   end
end)

run_test("trg_ht_portal", function()
   local pat = [[^(?:You are (?:almost )?certain that \w.+ is through .+\.|You are confident that \w.+ passed through here, heading through .+\.|The trail of \w.+ is confusing, but you're reasonably sure \w.+ headed through .+\.|There are traces of \w.+ having been here\. Perhaps they lead through \w.+\?|You have no idea which way \w.+ went\.)$]]
   -- Portal samples
   assert_not_nil(pcre_find(pat, TestData.hunt_portal[1]), "portal: almost certain through exit")
   assert_not_nil(pcre_find(pat, TestData.hunt_portal[2]), "portal: confident through portal")
   assert_not_nil(pcre_find(pat, TestData.hunt_portal[3]), "portal: no idea which way")
end)

run_test("trg_ht_here", function()
   local pat = [[^\w.+ is here!$]]
   for _, line in ipairs(TestData.hunt_here) do
      assert_not_nil(pcre_find(pat, line), "here: " .. line)
   end
   assert_nil(pcre_find(pat, "You are here!"), "player name doesn't start with \\w.+ pattern... actually it does")
   -- Note: ^\w.+ matches any word char followed by anything. "You are here!" would NOT match
   -- because "You are here!" has spaces before "is here!" — wait, the pattern is ^\w.+ is here!$
   -- Actually the pattern is just ^\w.+ is here!$ — "a sinister vandal is here!" matches.
   -- "You are here!" would not match (no " is here!" substring at end... actually "are here!" != "is here!")
end)

run_test("trg_ht_unable", function()
   local pat = [[^You seem unable to hunt that target for some reason\.$]]
   assert_not_nil(pcre_find(pat, TestData.hunt_unable[1]), "unable matches")
end)

run_test("trg_ht_not_found", function()
   -- Apostrophes decoded from &#39;
   local pat = [[^No one in this area by the name '\w.+'\.$]]
   for _, line in ipairs(TestData.hunt_not_found) do
      assert_not_nil(pcre_find(pat, line), "not found: " .. line)
   end
end)

run_test("trg_ht_fighting", function()
   -- Apostrophes decoded from &#39;
   local pat = [[^(?:Not while you are fighting!|You can't hunt while (?:resting|sitting)\.|You dream about going on a nice hunting trip.*)$]]
   for _, line in ipairs(TestData.hunt_abort) do
      assert_not_nil(pcre_find(pat, line), "abort: " .. line:sub(1, 40))
   end
end)

------------------------------------------------------------------------
-- AUTO HUNT triggers
------------------------------------------------------------------------

run_test("trg_ah_direction", function()
   -- Same as hunt trick direction but WITHOUT "couldn't find a path" failure branch
   local pat = [[^(?:You are (?:almost )?certain that \w.+ is (north|south|east|west|up|down) from here\.|You are confident that \w.+ passed through here, heading (north|south|east|west|up|down)\.|The trail of \w.+ is confusing, but you're reasonably sure \w.+ headed (north|south|east|west|up|down)\.|There are traces of \w.+ having been here\. Perhaps they lead (north|south|east|west|up|down)\?|You have no idea what you're doing, but maybe \w.+ is (north|south|east|west|up|down)\?)$]]
   -- Should match direction lines
   assert_not_nil(pcre_find(pat, TestData.hunt_directions[1].line), "ah direction: highest confidence")
   -- Should NOT match failure line
   assert_nil(pcre_find(pat, TestData.hunt_directions[7].line), "ah direction: failure doesn't match")
end)

run_test("trg_ah_here", function()
   local pat = [[^\w.+ is here!$]]
   assert_not_nil(pcre_find(pat, TestData.hunt_here[1]), "ah here matches")
end)

run_test("trg_ah_not_found", function()
   local pat = [[^No one in this area by the name|^You seem unable to hunt]]
   assert_not_nil(pcre_find(pat, "No one in this area by the name 'vandal'."), "ah not found: no one")
   assert_not_nil(pcre_find(pat, "You seem unable to hunt that target for some reason."), "ah not found: unable")
end)

------------------------------------------------------------------------
-- QUICK WHERE triggers (verified against live game output)
------------------------------------------------------------------------

run_test("trg_qw_match", function()
   -- 30-char padded format (Crowley + WinkleGold + live verified)
   local pat = [[^(.{30}) (.+)$]]
   for _, sample in ipairs(TestData.qw_match) do
      local mob_raw, room = pcre_match(pat, sample.line)
      assert_not_nil(mob_raw, "qw match captures mob from: " .. sample.line)
      assert_not_nil(room, "qw match captures room from: " .. sample.line)
      -- mob_raw is 30 chars with trailing spaces; trim for comparison
      local mob = mob_raw:match("^(.-)%s*$")
      assert_equal(sample.mob, mob, "qw mob (trimmed)")
      assert_equal(sample.room, room, "qw room")
   end
end)

run_test("trg_qw_no_match", function()
   -- Only the verified format (Crowley line 9468)
   local pat = [[^There is no \w.+ around here\.$]]
   for _, line in ipairs(TestData.qw_no_match) do
      assert_not_nil(pcre_find(pat, line), "qw no match: " .. line)
   end
end)

------------------------------------------------------------------------
-- KILL DETECT trigger (moved from grp_noexp)
------------------------------------------------------------------------

run_test("trg_kill_detect_xp", function()
   local pat = [[^You receive (\d+) experience points?\.$]]
   local xp = pcre_match(pat, "You receive 1000 experience points.")
   assert_equal("1000", xp, "captures XP amount")
   xp = pcre_match(pat, "You receive 1 experience point.")
   assert_equal("1", xp, "singular point")
end)

------------------------------------------------------------------------
-- NOEXP triggers
------------------------------------------------------------------------

run_test("trg_noexp_level_up", function()
   -- Verified: Crowley + WinkleGold + leveldb (GMCP-based, no text trigger, but message confirmed)
   local pat = [[^You raise a level! You are now level (\d+)\.$]]
   local level = pcre_match(pat, TestData.level_up)
   assert_equal("51", level, "captures level from level up")
end)

run_test("trg_noexp_powerup", function()
   -- leveldb line 222
   local pat = [[^Congratulations, .+\. You have increased your powerups to (\d+)\.$]]
   local pups = pcre_match(pat, TestData.powerup)
   assert_equal("5", pups, "captures powerup count")
end)
