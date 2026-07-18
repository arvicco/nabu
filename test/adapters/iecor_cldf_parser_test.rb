# frozen_string_literal: true

require "test_helper"

# The cldf-csv parser family (P18-5, .docs/surveys/pie-survey.md §1/§7): IE-CoR's
# CLDF multi-table CSV join (cognatesets × cognates × forms × languages ×
# parameters × loans) read into dictionary entries — one entry per cognate
# set, one DictionaryReflex per member form — plus the language-info rider
# (one language note per catalog-facing code, from languages.csv).
#
# Fixture policy pins exercised here (the survey's §7 sketch, all against
# byte-verbatim trimmed upstream rows):
# - set 6458 "heart": the 11-witness golden (polytonic grc ×2 varieties,
#   dual-script got, Bohorič-ſ sl, spaced-slash hit stem alternants);
# - set 1171 "skin": the Turkic loan event → borrowed=true on member edges;
# - set 1846 "back": Root_Form_calc fallback headword (no curated root);
# - set 2280 "full": a singleton (one member, no held-pair edge);
# - set 1105 "ash": the comma-multiform chu record (попєлъ, пєпєлъ — the
#   split policy) and the ?-doubt + inline-laryngeal root ?*pel(h₁)-.
class IecorCldfParserTest < Minitest::Test
  FIXTURES = File.join(Nabu::TestSupport.fixtures("iecor"), "cldf")

  def result
    @result ||= Nabu::Adapters::IecorCldfParser.new.read(FIXTURES)
  end

  def entries
    result.entries
  end

  def entry(set_id)
    entries.find { |e| e.entry_id == set_id } || flunk("cognate set #{set_id} missing")
  end

  # --- entries: one per cognate set, upstream file order -------------------------

  def test_one_entry_per_cognate_set_in_file_order
    assert_equal %w[1105 1171 1846 2280 6458], entries.map(&:entry_id)
    assert_equal %w[ine], entries.map(&:language).uniq
  end

  def test_headword_is_the_curated_root_verbatim_asterisk_and_all
    heart = entry("6458")
    assert_equal "*k̑erd-", heart.headword
    assert_equal "*k̑erd-", heart.key_raw
  end

  # The cross-witness fold: IE-CoR *k̑erd- (k + U+0311) and kaikki *ḱerd-
  # (U+1E31) must meet at the same folded key, hyphen kept — both sides of
  # the shelf convention store root headwords with the trailing hyphen.
  def test_root_headwords_fold_to_the_kaikki_convention
    assert_equal "kerd-", entry("6458").headword_folded
    assert_equal Nabu::Normalize.search_form("ḱerd-", language: "ine-pro"),
                 entry("6458").headword_folded
  end

  # ?-doubt prefix and inline parenthesized laryngeal: ?*pel(h₁)- displays
  # verbatim but folds with the doubt/asterisk prefix and the parens
  # stripped — the key kaikki's *pelh₁- would fold to.
  def test_doubt_and_paren_roots_fold_clean
    ash = entry("1105")
    assert_equal "?*pel(h₁)-", ash.headword
    assert_equal "pelh₁-", ash.headword_folded
  end

  def test_calc_root_fallback_when_no_curated_root
    back = entry("1846")
    assert_equal "nùgara", back.headword
    assert_equal "nugara", back.headword_folded
    assert_equal 1, back.reflexes.size # Lithuanian member (fixture-trimmed)
    assert_equal "lit", back.reflexes.first.lang_code
  end

  def test_gloss_is_root_gloss_or_the_concept
    assert_equal "heart", entry("6458").gloss
    assert_equal "back", entry("1846").gloss
  end

  def test_body_names_set_concept_and_root_language
    body = entry("6458").body
    assert_includes body, "cognate set 6458"
    assert_includes body, "heart"
    assert_includes body, "Proto-Indo-European"
  end

  # --- reflexes: the member edges -------------------------------------------------

  def test_heart_set_carries_the_eleven_held_witnesses
    heart = entry("6458")
    langs = heart.reflexes.map(&:language)
    %w[grc lat got chu orv sl ang san xcl hit].each do |code|
      assert_includes langs, code
    end
    assert_equal 2, langs.count("grc"), "Greek: Ancient AND Greek: New Testament"
  end

  def test_native_script_word_with_roman_form
    heart = entry("6458")
    chu = heart.reflexes.find { |r| r.language == "chu" } || flunk("chu reflex missing")
    assert_equal "срьдьцє", chu.word
    assert_equal "srĭdĭce", chu.roman
    assert_equal "srьdьce", chu.word_folded # P27-2: the cross-script chu skeleton
    assert_equal "sridice", chu.roman_folded
    got = heart.reflexes.find { |r| r.language == "got" } || flunk("got reflex missing")
    assert_equal "𐌷𐌰𐌹𐍂𐍄𐍉", got.word
    assert_equal "hairto", got.roman # the script bridge to the PROIEL gold lemma
    assert_equal "hairto", got.roman_folded
  end

  def test_bohoric_slovene_folds_through_the_long_s_rule
    sl = entry("6458").reflexes.find { |r| r.language == "sl" } || flunk("sl reflex missing")
    assert_equal "ſerzè", sl.word # native_script is empty; Form verbatim
    assert_nil sl.roman
    assert_equal "serze", sl.word_folded
  end

  # Spaced-slash stem alternants (hit ker / kard(i)-) split into one reflex
  # per alternant, native transliteration paired by index; parens and the
  # trailing stem hyphen strip out of the FOLD only (word stays verbatim).
  def test_hittite_slash_alternants_split_with_paren_and_hyphen_strip
    hit = entry("6458").reflexes.select { |r| r.language == "hit" }
    assert_equal %w[ke-er kar-ti-i̯a-aš], hit.map(&:word)
    assert_equal ["ker", "kard(i)-"], hit.map(&:roman)
    assert_equal %w[ker kardi], hit.map(&:roman_folded)
  end

  # The comma-multiform policy: попєлъ, пєпєлъ is TWO reflexes, native and
  # roman split in parallel.
  def test_comma_multiforms_split_into_parallel_reflexes
    ash = entry("1105").reflexes.select { |r| r.language == "chu" }
    assert_equal %w[попєлъ пєпєлъ], ash.map(&:word)
    assert_equal %w[popelŭ pepelŭ], ash.map(&:roman)
    assert_equal %w[popelu pepelu], ash.map(&:roman_folded)
  end

  def test_singletons_are_included
    single = entry("2280")
    # one member judgment; the slash alternants of šūu- / šūuau̯- both mint
    assert_equal %w[hit], single.reflexes.map(&:language).uniq
    assert_equal "?*seu̯H-", single.headword
  end

  # --- the loan layer (loans.csv → borrowed) --------------------------------------

  def test_loan_event_sets_flag_every_member_edge_borrowed
    skin = entry("1171")
    assert_equal [true], skin.reflexes.map(&:borrowed).uniq,
                 "a loans.csv event ORs into every member edge (survey §1)"
    assert_includes skin.body, "Turkic"
  end

  def test_non_loan_sets_parse_borrowed_false
    assert_equal [false], entry("6458").reflexes.map(&:borrowed).uniq
  end

  # --- lang codes and the 12-variety map ------------------------------------------

  def test_variety_map_and_verbatim_codes
    heart = entry("6458")
    orv = heart.reflexes.find { |r| r.lang_code == "orv" } || flunk("orv reflex missing")
    assert_equal "orv", orv.language
    sl = heart.reflexes.find { |r| r.language == "sl" }
    assert_equal "slv", sl.lang_code, "upstream ISO code verbatim; mapped tag is ours"
    assert_equal "Slovene: Early Modern", sl.lang_name
  end

  # --- the language-info rider ------------------------------------------------------

  def test_language_notes_cover_every_variety_with_reflexes_grouped_by_code
    notes = result.language_notes
    codes = notes.map(&:lang_code)
    assert_equal codes.uniq, codes, "one note per catalog-facing code"
    %w[hit chu san grc lat xcl orv sl ang got gmy lit].each do |code|
      assert_includes codes, code
    end
    grc = notes.find { |n| n.lang_code == "grc" }
    assert_equal "iecor", grc.kind
    assert_equal "iecor", grc.source
    assert_includes grc.body, "Greek: Ancient"
    assert_includes grc.body, "Greek: New Testament"
    assert_includes grc.body, "anci1242" # the Glottocode travels
    chu = notes.find { |n| n.lang_code == "chu" }
    assert_includes chu.body, "Old Church Slavonic"
    assert_includes chu.body, "historical"
    assert_includes chu.body, "Balto-Slavic"
  end

  def test_read_is_deterministic_across_passes
    first = Nabu::Adapters::IecorCldfParser.new.read(FIXTURES)
    second = Nabu::Adapters::IecorCldfParser.new.read(FIXTURES)
    assert_equal first.entries.map(&:entry_id), second.entries.map(&:entry_id)
    assert_equal first.entries.map(&:headword), second.entries.map(&:headword)
    assert_equal first.language_notes.map(&:body), second.language_notes.map(&:body)
  end
end
