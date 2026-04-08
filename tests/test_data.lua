------------------------------------------------------------------------
-- test_data.lua - Sample MUD output for trigger and parser testing
------------------------------------------------------------------------

TestData = {}

------------------------------------------------------------------------
-- CP INFO sample output (area-based)
------------------------------------------------------------------------
TestData.cp_info_area = {
   "Level Taken........: [  45 ]",
   "The targets for this campaign are:",
   "Find and kill 1 * a sinister vandal (The Three Pillars of Diatz)",
   "Find and kill 1 * a mutated goat (The Killing Fields)",
   "Find and kill 1 * a dancing female patron (Wayward Alehouse)",
   "Find and kill 1 * a grizzled goblin dressed in skins (The Goblin Fortress)",
   "Find and kill 1 * a dangerous scorpion (Desert Doom)",
   "",
}

TestData.cp_info_area_parsed = {
   level = 45,
   targets = {
      {mob = "a sinister vandal",                    location = "The Three Pillars of Diatz"},
      {mob = "a mutated goat",                       location = "The Killing Fields"},
      {mob = "a dancing female patron",              location = "Wayward Alehouse"},
      {mob = "a grizzled goblin dressed in skins",   location = "The Goblin Fortress"},
      {mob = "a dangerous scorpion",                 location = "Desert Doom"},
   },
}

------------------------------------------------------------------------
-- CP INFO sample output (room-based)
------------------------------------------------------------------------
TestData.cp_info_room = {
   "Level Taken........: [  90 ]",
   "The targets for this campaign are:",
   "Find and kill 1 * a troll guard (In The Courtyard)",
   "Find and kill 1 * an orc shaman (Near The Fire Pit)",
   "Find and kill 1 * a dark knight (The Throne Room)",
   "",
}

------------------------------------------------------------------------
-- CP CHECK sample output
------------------------------------------------------------------------
TestData.cp_check = {
   "You still have to kill * a sinister vandal (The Three Pillars of Diatz)",
   "You still have to kill * a mutated goat (The Killing Fields - Dead)",
   "You still have to kill * a dancing female patron (Wayward Alehouse)",
   "Note: Dead means that the target is dead, not that you have killed it.",
   "",
}

TestData.cp_check_parsed = {
   {mob = "a sinister vandal",       location = "The Three Pillars of Diatz", dead = false},
   {mob = "a mutated goat",          location = "The Killing Fields",         dead = true},
   {mob = "a dancing female patron", location = "Wayward Alehouse",           dead = false},
}

------------------------------------------------------------------------
-- GQ INFO sample output
------------------------------------------------------------------------
TestData.gq_info = {
   "Quest Name.........: [ Global quest # 12345 ]",
   "Quest Status.......: [ Extended ]",
   "Level range........: [  40 ] - [  50 ]",
   "Kill at least 2 * a sinister vandal (The Three Pillars of Diatz).",
   "Kill at least 1 * a mutated goat (The Killing Fields).",
   "---------------------------------------------------------------------------",
}

------------------------------------------------------------------------
-- GQ CHECK sample output
------------------------------------------------------------------------
TestData.gq_check = {
   "You still have to kill 2 * a sinister vandal (The Three Pillars of Diatz)",
   "You still have to kill 1 * a mutated goat (The Killing Fields - Dead)",
   "",
}

------------------------------------------------------------------------
-- Hunt direction messages (6 confidence levels)
------------------------------------------------------------------------
TestData.hunt_directions = {
   -- Highest confidence
   {line = "You are almost certain that a sinister vandal is north from here.",
    direction = "north", confidence = 6},
   {line = "You are certain that a troll guard is south from here.",
    direction = "south", confidence = 6},
   -- High confidence
   {line = "You are confident that a dark knight passed through here, heading east.",
    direction = "east", confidence = 5},
   -- Medium confidence
   {line = "The trail of a mutated goat is confusing, but you're reasonably sure it headed west.",
    direction = "west", confidence = 4},
   -- Low confidence
   {line = "There are traces of an orc shaman having been here. Perhaps they lead up?",
    direction = "up", confidence = 3},
   -- Lowest confidence
   {line = "You have no idea what you're doing, but maybe a cave spider is down?",
    direction = "down", confidence = 2},
   -- Failure
   {line = "You couldn't find a path to a dark knight from here.",
    direction = nil, confidence = 1},
}

TestData.hunt_portal = {
   "You are almost certain that a troll is through exit.",
   "You are confident that a guard passed through here, heading through portal.",
   "You have no idea which way a dark elf went.",
}

TestData.hunt_here = {
   "a sinister vandal is here!",
   "a dark knight is here!",
}

TestData.hunt_unable = {
   "You seem unable to hunt that target for some reason.",
}

TestData.hunt_not_found = {
   "No one in this area by the name 'vandal'.",
   "No one in this area by the name 'dark knight'.",
}

TestData.hunt_abort = {
   "Not while you are fighting!",
   "You can't hunt while resting.",
   "You can't hunt while sitting.",
   "You dream about going on a nice hunting trip, with pony rides, and campfires too.",
}

------------------------------------------------------------------------
-- Consider outcomes (13 levels, easiest to hardest)
------------------------------------------------------------------------
TestData.consider = {
   {line = "You would stomp a tiny rat into the ground.",
    mob = "a tiny rat", level = 1},
   {line = "a small dog would be easy, but is it even worth the work out?",
    mob = "a small dog", level = 2},
   {line = "No Problem! a cave spider is weak compared to you.",
    mob = "a cave spider", level = 3},
   {line = "a bandit looks a little worried about the idea.",
    mob = "a bandit", level = 4},
   {line = "a dark knight should be a fair fight!",
    mob = "a dark knight", level = 5},
   {line = "a troll guard snickers nervously.",
    mob = "a troll guard", level = 6},
   {line = "a dragon chuckles at the thought of you fighting it.",
    mob = "a dragon", level = 7},
   {line = "Best run away from a lich lord while you can!",
    mob = "a lich lord", level = 8},
   {line = "Challenging a demon prince would be either very brave or very stupid.",
    mob = "a demon prince", level = 9},
   {line = "a balrog would crush you like a bug!",
    mob = "a balrog", level = 10},
   {line = "a death knight would dance on your grave!",
    mob = "a death knight", level = 11},
   {line = "an ancient wyrm says 'BEGONE FROM MY SIGHT unworthy!'",
    mob = "an ancient wyrm", level = 12},
   {line = "You would be completely annihilated by a titan!",
    mob = "a titan", level = 13},
}

------------------------------------------------------------------------
-- Damage verb lines (representative samples)
------------------------------------------------------------------------
TestData.damage_verbs = {
   -- Basic lowercase verbs
   {line = "Your slash tickles a goblin! [42]", verb = "tickles", mob = "a goblin"},
   {line = "Your pierce hits a dark knight! [128]", verb = "hits", mob = "a dark knight"},
   {line = "Your bash mauls a troll. [256]", verb = "mauls", mob = "a troll"},
   {line = "Your slash mangles a spider! [512]", verb = "mangles", mob = "a spider"},
   -- Uppercase verbs
   {line = "Your slash DECIMATES a guard! [1024]", verb = "DECIMATES", mob = "a guard"},
   {line = "Your bash OBLITERATES a soldier! [2048]", verb = "OBLITERATES", mob = "a soldier"},
   -- Decorated verbs
   {line = "Your slash ** SHREDS ** a knight! [4096]", verb = "SHREDS", mob = "a knight"},
   {line = "Your pierce **** DESTROYS **** a demon! [8192]", verb = "DESTROYS", mob = "a demon"},
   -- Special patterns
   {line = "Your spell does UNSPEAKABLE things to a lich! [16384]",
    verb = "UNSPEAKABLE", mob = "a lich"},
   {line = "You assassinate a guard with cold efficiency.", verb = "assassinate", mob = "a guard"},
}

------------------------------------------------------------------------
-- Quest GMCP data samples
------------------------------------------------------------------------
TestData.quest_gmcp = {
   -- Quest started
   {action = "start", targ = "a sinister vandal",
    room = "In The Courtyard", area = "The Three Pillars of Diatz",
    timer = 60},
   -- Quest completed
   {action = "comp", targ = "", room = "", area = "", timer = 0},
   -- Quest failed
   {action = "fail", targ = "", room = "", area = "", timer = 0},
   -- Next quest ready
   {action = "ready", targ = "", room = "", area = "", timer = 0},
   -- Quest wait
   {action = "wait", targ = "", room = "", area = "", timer = 120},
}

------------------------------------------------------------------------
-- CP event messages
------------------------------------------------------------------------
TestData.cp_events = {
   mob_killed = "Congratulations, that was one of your CAMPAIGN mobs!",
   complete = "CONGRATULATIONS! You have completed your campaign.",
   cleared = "Campaign cleared.",
   new_available_1 = "You may now take another campaign.",
   new_available_2 = "## You may now take another campaign.",
   new_available_3 = "You may take a campaign at this level.",
   new_available_4 = "You may take another campaign.",
   not_on = "You are not currently on a campaign.",
   must_level = "You must level to get a new campaign.",
}

------------------------------------------------------------------------
-- GQ event messages
------------------------------------------------------------------------
TestData.gq_events = {
   mob_killed = "Congratulations, that was one of the GLOBAL QUEST mobs!",
   joined = "You have joined Global Quest # 12345.",
   started = "Global Quest # 12345 has now started!",
   finished = "You have finished this global quest.",
   ended = "Global Quest # 12345 has ended.",
   won = "Global Quest # 12345 has been won.",
   not_started = "Global Quest # 12345 has not yet started.",
}

return TestData
