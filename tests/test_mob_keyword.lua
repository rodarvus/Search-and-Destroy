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

run_test("MobKeyword.guess_basic", function()
   local kw

   -- Single word mob
   kw = MobKeyword.guess("spider", "")
   assert_true(#kw > 0, "single word produces keyword")
   assert_match("^spi", kw, "single word starts with beginning of word")

   -- Two word mob with article - single word "vandal" (6 chars), 70% = 4.2 -> 4 chars
   kw = MobKeyword.guess("a vandal", "")
   assert_match("^vand", kw, "article 'a' stripped, uses remaining word")

   -- Multi-word mob with article
   kw = MobKeyword.guess("a sinister vandal", "")
   assert_match("^sinis", kw, "multi-word: first part from 'sinister'")
   assert_match("vanda$", kw, "multi-word: second part from 'vandal'")

   -- Article "the"
   kw = MobKeyword.guess("the dark knight", "")
   assert_match("dark", kw, "'the' stripped")
   assert_match("knigh", kw, "second word included")

   -- Article "an"
   kw = MobKeyword.guess("an orc shaman", "")
   assert_match("orc", kw, "'an' stripped, orc in result")

   -- Multiple articles
   kw = MobKeyword.guess("some of the guards", "")
   assert_match("^guar", kw, "multiple articles stripped")
end)

run_test("MobKeyword.guess_punctuation", function()
   local kw

   -- Possessives
   kw = MobKeyword.guess("Dorothy's uncle", "")
   assert_no_match("'", kw, "possessive removed")

   -- Commas in mob names
   kw = MobKeyword.guess("Lwji, the warrior", "")
   assert_no_match(",", kw, "comma removed")
end)

run_test("MobKeyword.guess_empty", function()
   assert_equal("", MobKeyword.guess(nil, ""), "nil input returns empty")
   assert_equal("", MobKeyword.guess("", ""), "empty input returns empty")
end)

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

run_test("MobKeyword.guess_area_filters", function()
   local kw

   -- hatchling: "X dragon egg" -> "X egg"
   kw = MobKeyword.guess("red dragon egg", "hatchling")
   assert_match("red", kw, "hatchling filter strips 'dragon'")
   assert_match("egg", kw, "hatchling filter keeps 'egg'")

   -- bonds: "X dragon" -> "X" (single word "black" = 5 chars, 70% = 3)
   kw = MobKeyword.guess("black dragon", "bonds")
   assert_match("^bla", kw, "bonds filter strips 'dragon'")
   assert_no_match("drago", kw, "bonds filter removed dragon")

   -- wooble: "sea X" -> "X" (single word "serpent" = 7 chars, 70% = 4)
   kw = MobKeyword.guess("sea serpent", "wooble")
   assert_match("^serp", kw, "wooble filter strips 'sea'")
end)

run_test("MobKeyword.guess_sohtwo_filters", function()
   local kw

   kw = MobKeyword.guess("evil something", "sohtwo")
   assert_match("^evi", kw, "sohtwo evil filter works")
end)

run_test("MobKeyword.guess_hyphens", function()
   local kw

   kw = MobKeyword.guess("a black-footed pine marten", "some_other_area")
   assert_match("blac", kw, "hyphen mob: first word fragment present")
   assert_match("marte", kw, "hyphen mob: last word fragment present")
   assert_no_match("%-", kw, "hyphen mob: no literal hyphens in result")

   -- Simple hyphenated word
   kw = MobKeyword.guess("a half-elf", "")
   assert_match("half", kw, "simple hyphen: first part")
   assert_match("elf", kw, "simple hyphen: second part")
end)

run_test("MobKeyword.guess_all_articles", function()
   local kw

   kw = MobKeyword.guess("a the an", "")
   assert_equal("a the an", kw, "all-article mob falls back to original")

   kw = MobKeyword.guess("some of the", "")
   assert_equal("some of the", kw, "all omit-words falls back to original")
end)

run_test("MobKeyword.guess_area_filter_to_single", function()
   local kw

   kw = MobKeyword.guess("black dragon", "bonds")
   assert_equal("bla", kw, "bonds: 'black' at 70% = 3 chars")

   kw = MobKeyword.guess("black knight", "bonds")
   assert_match("blac", kw, "bonds: non-dragon keeps first word")
   assert_match("knigh", kw, "bonds: non-dragon keeps last word")
end)

run_test("MobKeyword.guess_quotation_marks", function()
   local kw

   kw = MobKeyword.guess('"the chosen one"', "")
   assert_no_match('"', kw, "quotation marks stripped")
   assert_match("chose", kw, "quoted mob: first word correct")
   assert_match("one", kw, "quoted mob: last word correct")
end)

run_test("MobKeyword.guess_parentheses", function()
   local kw

   kw = MobKeyword.guess("(Helper) Fenix", "some_area")
   assert_no_match("%(", kw, "parentheses stripped")
   assert_match("helpe", kw, "paren mob: first word")
   assert_match("fenix", kw, "paren mob: last word")
end)

run_test("MobKeyword.guess_long_mob_name", function()
   local kw

   kw = MobKeyword.guess("a grizzled goblin dressed in skins", "some_area")
   assert_match("^grizz", kw, "long mob: first word truncated to 5")
   assert_match("skins$", kw, "long mob: last word (5 chars, kept whole)")
end)
