------------------------------------------------------------------------
-- test_mob_keyword.lua - Tests for MobKeyword.guess()
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

--- Test: Basic keyword guessing — single word, articles, multi-word
-- Input: "spider", "a vandal", "a sinister vandal", "the dark knight", "an orc shaman", "some of the guards"
-- Expected: articles stripped, single word = 70% length, multi-word = first5+last5
-- Covers: MobKeyword.guess() stages 3-6
run_test("MobKeyword.guess_basic", function()
   local kw
   kw = MobKeyword.guess("spider", "")
   assert_true(#kw > 0, "single word produces keyword")
   assert_match("^spi", kw, "single word starts with beginning of word")
   kw = MobKeyword.guess("a vandal", "")
   assert_match("^vand", kw, "article 'a' stripped, uses remaining word")
   kw = MobKeyword.guess("a sinister vandal", "")
   assert_match("^sinis", kw, "multi-word: first part from 'sinister'")
   assert_match("vanda$", kw, "multi-word: second part from 'vandal'")
   kw = MobKeyword.guess("the dark knight", "")
   assert_match("dark", kw, "'the' stripped")
   assert_match("knigh", kw, "second word included")
   kw = MobKeyword.guess("an orc shaman", "")
   assert_match("orc", kw, "'an' stripped, orc in result")
   kw = MobKeyword.guess("some of the guards", "")
   assert_match("^guar", kw, "multiple articles stripped")
end)

--- Test: Punctuation removal — possessives and commas
-- Input: "Dorothy's uncle", "Lwji, the warrior"
-- Expected: no apostrophes or commas in output
-- Covers: MobKeyword.guess() stage 3 (punctuation cleaning)
run_test("MobKeyword.guess_punctuation", function()
   local kw
   kw = MobKeyword.guess("Dorothy's uncle", "")
   assert_no_match("'", kw, "possessive removed")
   kw = MobKeyword.guess("Lwji, the warrior", "")
   assert_no_match(",", kw, "comma removed")
end)

--- Test: Nil and empty input return empty string
-- Input: nil, ""
-- Expected: "" for both
-- Covers: MobKeyword.guess() nil/empty guard
run_test("MobKeyword.guess_empty", function()
   assert_equal("", MobKeyword.guess(nil, ""), "nil input returns empty")
   assert_equal("", MobKeyword.guess("", ""), "empty input returns empty")
end)

--- Test: Hardcoded exceptions from CONST.MOB_KEYWORD_EXCEPTIONS (7 areas)
-- Input: known exception mobs with their areas
-- Expected: exact hardcoded keyword for each
-- Covers: MobKeyword.guess() stage 2 (CONST exceptions via DB override)
run_test("MobKeyword.guess_exceptions_hardcoded", function()
   local kw
   kw = MobKeyword.guess("a very large portrait", "aardington")
   assert_equal("large port", kw, "aardington portrait exception")
   kw = MobKeyword.guess("the little white rabbit", "anthrox")
   assert_equal("rabb", kw, "anthrox rabbit exception")
   kw = MobKeyword.guess("a dangerous scorpion", "ddoom")
   assert_equal("scorp", kw, "ddoom scorpion exception")
   kw = MobKeyword.guess("Evil Lasher", "sohtwo")
   assert_equal("thearchitect", kw, "sohtwo Evil Lasher exception")
   kw = MobKeyword.guess("a scrumptious chicken pot pie", "hell")
   assert_equal("chicken pot pie", kw, "hell chicken pot pie exception")
   kw = MobKeyword.guess("the snuckle", "snuckles")
   assert_equal("male snuckle", kw, "snuckles snuckle exception")
   kw = MobKeyword.guess("a black-footed pine marten", "zoo")
   assert_equal("pine marte", kw, "zoo pine marten exception")
end)

--- Test: Area-specific filters (hatchling, bonds, wooble)
-- Input: dragon-related mobs in hatchling/bonds, sea mob in wooble
-- Expected: area filter strips specific words before keyword generation
-- Covers: MobKeyword.guess() stage 5 (CONST.AREA_KEYWORD_FILTERS)
run_test("MobKeyword.guess_area_filters", function()
   local kw
   kw = MobKeyword.guess("red dragon egg", "hatchling")
   assert_match("red", kw, "hatchling filter strips 'dragon'")
   assert_match("egg", kw, "hatchling filter keeps 'egg'")
   kw = MobKeyword.guess("black dragon", "bonds")
   assert_match("^bla", kw, "bonds filter strips 'dragon'")
   assert_no_match("drago", kw, "bonds filter removed dragon")
   kw = MobKeyword.guess("sea serpent", "wooble")
   assert_match("^serp", kw, "wooble filter strips 'sea'")
end)

--- Test: sohtwo area filter reduces "evil X" to "evil"
-- Input: "evil something" in sohtwo (no hardcoded exception for this mob)
-- Expected: filter reduces to "evil", then 70% truncation
-- Covers: MobKeyword.guess() sohtwo-specific filter
run_test("MobKeyword.guess_sohtwo_filters", function()
   local kw
   kw = MobKeyword.guess("evil something", "sohtwo")
   assert_match("^evi", kw, "sohtwo evil filter works")
end)

--- Test: Hyphens converted to spaces, no literal hyphens in output
-- Input: "a black-footed pine marten" (non-zoo area), "a half-elf"
-- Expected: hyphens become spaces, first5+last5 fragments, no hyphens
-- Covers: MobKeyword.guess() hyphen→space conversion
run_test("MobKeyword.guess_hyphens", function()
   local kw
   kw = MobKeyword.guess("a black-footed pine marten", "some_other_area")
   assert_match("blac", kw, "hyphen mob: first word fragment present")
   assert_match("marte", kw, "hyphen mob: last word fragment present")
   assert_no_match("%-", kw, "hyphen mob: no literal hyphens in result")
   kw = MobKeyword.guess("a half-elf", "")
   assert_match("half", kw, "simple hyphen: first part")
   assert_match("elf", kw, "simple hyphen: second part")
end)

--- Test: All-article mob name falls back to original (nothing to guess from)
-- Input: "a the an", "some of the" (all words are omit words)
-- Expected: returns original mob name unchanged
-- Covers: MobKeyword.guess() all-stripped fallback
run_test("MobKeyword.guess_all_articles", function()
   local kw
   kw = MobKeyword.guess("a the an", "")
   assert_equal("a the an", kw, "all-article mob falls back to original")
   kw = MobKeyword.guess("some of the", "")
   assert_equal("some of the", kw, "all omit-words falls back to original")
end)

--- Test: Area filter reducing to single word applies 70% truncation
-- Input: "black dragon" in bonds → filter strips "dragon" → "black" (5 chars, 70%=3)
-- Expected: "bla" (3 chars); non-dragon "black knight" keeps both words
-- Covers: MobKeyword.guess() single-word result after area filter
run_test("MobKeyword.guess_area_filter_to_single", function()
   local kw
   kw = MobKeyword.guess("black dragon", "bonds")
   assert_equal("bla", kw, "bonds: 'black' at 70% = 3 chars")
   kw = MobKeyword.guess("black knight", "bonds")
   assert_match("blac", kw, "bonds: non-dragon keeps first word")
   assert_match("knigh", kw, "bonds: non-dragon keeps last word")
end)

--- Test: Quotation marks stripped, correct keyword generated
-- Input: '"the chosen one"' (with literal quotes)
-- Expected: "chose one" (quotes stripped, "the" omitted, first5+last3)
-- Covers: MobKeyword.guess() quotation mark removal
run_test("MobKeyword.guess_quotation_marks", function()
   local kw
   kw = MobKeyword.guess('"the chosen one"', "")
   assert_equal("chose one", kw, "quoted mob: exact keyword after quote stripping")
end)

--- Test: Parentheses stripped, correct keyword generated
-- Input: "(Helper) Fenix" in non-sohtwo area
-- Expected: "helpe fenix" (parens stripped, first5+last5)
-- Covers: MobKeyword.guess() parentheses removal
run_test("MobKeyword.guess_parentheses", function()
   local kw
   kw = MobKeyword.guess("(Helper) Fenix", "some_area")
   assert_equal("helpe fenix", kw, "paren mob: exact keyword after paren stripping")
end)

--- Test: Long mob name uses first 5 + last 5 chars
-- Input: "a grizzled goblin dressed in skins" (many words, "in" omitted)
-- Expected: "grizz skins" (first5 of "grizzled" + last5 of "skins")
-- Covers: MobKeyword.guess() multi-word truncation with omit word removal
run_test("MobKeyword.guess_long_mob_name", function()
   local kw
   kw = MobKeyword.guess("a grizzled goblin dressed in skins", "some_area")
   assert_match("^grizz", kw, "long mob: first word truncated to 5")
   assert_match("skins$", kw, "long mob: last word (5 chars, kept whole)")
end)
