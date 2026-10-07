# frozen_string_literal: true

require "test_helper"

# The StarLing IE package's LEXSTAT/ tables (P113-2): lexicostatistical
# wordlists WITH cognation numbers, shipped inside IE.exe beside the five
# etymological bases and never parsed before. Two upstream table shapes,
# both riding the starling many-shelves-one-source pattern:
#
# - TEN WIDE WORDLISTS (balt, celt, dard, germ, ind, iran, mix, pi, rom,
#   slav): NUMBER (the wordlist item, 1..110) + WORD (its English meaning)
#   + one form column per language, each followed by its <COL>NUM cognation
#   number. A positive number IS an entry id in the etymology base the
#   table's .inf names (`proto = ...baltet.dbf` / germet / piet / the three
#   LEXSTAT etymology tables); file position 0 is the per-language date row
#   (century values: GOT 4, AEG 8, JAT 18, modern columns 20). Grain: ONE
#   ENTRY PER FORM CELL (headword = the form verbatim, gloss = the meaning,
#   body = language + item + cognation + date line), shelf language = the
#   branch code (declared coarseness: entry language is not persisted per
#   entry; the column's code drives only the fold).
# - THREE Indo-Iranian ETYMOLOGY TABLES (dardet, indet, iranet): the BASES
#   shape (PROTO/MEANING/PRNUM → piet + per-language columns) — the
#   cognation targets of dard/ind/iran, landed as ordinary BASES rows.
#
# Fixtures (test/fixtures/starling/LEXSTAT/, README "The LEXSTAT tables"):
# trimmed REAL balt.dbf (8 of 118 records), germ.dbf (6 of 154) and
# iranet.dbf (4 of 498) — inline-only tables (no .var siblings upstream).
class StarlingLexstatTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("starling")

  def adapter = Nabu::Adapters::Starling.new

  def parse(slug)
    ref = adapter.discover(FIXTURES).find { |r| r.metadata.fetch("dictionary") == slug }
    refute_nil ref, "#{slug} must be discovered from the fixture tree"
    adapter.parse(ref)
  end

  def entries(slug) = parse(slug).entries.to_h { |e| [e.entry_id, e] }

  # --- the census -------------------------------------------------------------------

  # census: 13, 2026-10-01, .dbf tables in canonical/starling/LEXSTAT/ (IE.exe):
  # 10 wordlists + 3 Indo-Iranian etymology tables (the other 31 files there
  # are their .inf siblings + 5 images). Entry projection, dry-parsed at full
  # scale: 23,096 wordlist form cells + 1,426 etymology records.
  LEXSTAT_SHELVES = 13

  def test_the_lexstat_shelf_census_is_pinned
    wordlists = Nabu::Adapters::StarlingLexstat::TABLES.keys
    etymology = Nabu::Adapters::Starling::BASES.select { |_, base| base[:dir] == "LEXSTAT" }.keys
    assert_equal LEXSTAT_SHELVES, wordlists.size + etymology.size
    assert_equal %w[starling-lexstat-balt starling-lexstat-celt starling-lexstat-dard
                    starling-lexstat-germ starling-lexstat-ind starling-lexstat-iran
                    starling-lexstat-mix starling-lexstat-pi starling-lexstat-rom
                    starling-lexstat-slav], wordlists
    assert_equal %w[starling-dardet starling-indet starling-iranet], etymology
  end

  # --- the wordlist shape: balt ----------------------------------------------------

  def test_parse_balt_yields_the_baltic_wordlist_shelf_one_entry_per_form_cell
    document = parse("starling-lexstat-balt")
    assert_kind_of Nabu::DictionaryDocument, document
    assert_equal "bat", document.language, "the branch code — declared coarseness"
    assert_match(/Baltic/, document.title)
    assert_equal %w[1.lit 1.let 1.jat 2.lit 2.let 26.lit 26.let 26.lit-b 58.lit 58.let
                    64.lit 64.let 64.jat 106.lit 106.let 106.jat],
                 document.map(&:entry_id),
                 "item-major, column order; the date row (file position 0) mints nothing; " \
                 "the -666 form-less JAT cells mint nothing; the second 'fat n.' row is a synonym slot"
  end

  def test_balt_entry_carries_form_meaning_language_cognation_and_date
    entry = entries("starling-lexstat-balt")["58.lit"]
    assert_equal "kãklas", entry.headword
    assert_equal "kãklas", entry.key_raw
    assert_equal "neck", entry.gloss, "WORD is the gloss lane"
    assert_equal "lt", entry.language, "the column's code drives the fold"
    assert_equal "kaklas", entry.headword_folded
    assert_includes entry.body, "Language: Lithuanian"
    assert_includes entry.body, "Wordlist item: #58 neck"
    assert_includes entry.body, "Baltic etymology: #1634",
                    "the cognation number IS a starling-baltet entry id — #1634 *kakla- is IN this fixture set"
    assert_includes entry.body, "Century (header row): 20"
    assert_empty entry.reflexes, "wordlist cells mint no reflex edges"
  end

  def test_balt_non_positive_cognation_numbers_ride_verbatim_without_a_crosslink
    by_id = entries("starling-lexstat-balt")
    let = by_id["64.let"]
    assert_equal "cilveks", let.headword
    assert_includes let.body, "Cognation number: -1"
    refute_includes let.body, "Baltic etymology", "only a positive number names a base entry"
    jat = by_id["64.jat"]
    assert_equal "xsv", jat.language, "Yatvingian (the .inf alias) — ISO xsv"
    assert_includes jat.body, "Language: Yatvingian"
    assert_includes jat.body, "Baltic etymology: #1065"
    assert_includes jat.body, "Century (header row): 18"
    assert_includes by_id["106.jat"].body, "Cognation number: -5"
  end

  def test_balt_synonym_rows_take_a_stable_file_order_suffix_without_a_collision_note
    by_id = entries("starling-lexstat-balt")
    assert_equal "riebalaĩ", by_id["26.lit"].headword
    synonym = by_id["26.lit-b"]
    assert_equal "taukaĩ", synonym.headword
    assert_equal "fat n.", synonym.gloss
    assert_includes synonym.body, "Baltic etymology: #1395"
    refute_includes synonym.body, "collision", "synonym slots are upstream design, not a defect"
  end

  # --- the wordlist shape: germ ----------------------------------------------------

  def test_parse_germ_yields_the_germanic_wordlist_shelf
    document = parse("starling-lexstat-germ")
    assert_equal "gem", document.language
    assert_equal 49, document.size, "12 + 12 + 11 (bark: the -100 GOT cell has no form) + 12 + 2"
    by_id = document.entries.to_h { |e| [e.entry_id, e] }
    refute by_id.key?("3.got"), "a cognation number without a form mints nothing"
    gothic = by_id["58.got"]
    assert_equal "hals", gothic.headword
    assert_equal "got", gothic.language
    assert_includes gothic.body, "Language: Gothic"
    assert_includes gothic.body, "Germanic etymology: #390",
                    "germ.inf proto = germet — #390 *xálsa-z is IN this fixture set"
    assert_includes gothic.body, "Century (header row): 4"
    assert_equal "nek", by_id["58.hol-b"].headword
    assert_includes by_id["58.hol-b"].body, "Germanic etymology: #874"
    assert_equal "swēora", by_id["58.aeg-b"].headword
    assert_equal "ang", by_id["58.aeg-b"].language
  end

  def test_germ_multiform_cells_stay_verbatim_and_fold_the_first_form
    by_id = entries("starling-lexstat-germ")
    ahd = by_id["2.ahd"]
    assert_equal "asca, asga", ahd.headword, "the cell verbatim"
    assert_equal "asca", ahd.headword_folded, "the FIRST variant is the lookup key"
    assert_equal "Old High German", ahd.body[/Language: (.*)/, 1]
    assert_includes by_id["2.rks"].body, "Cognation number: -1"
    assert_equal "Riksmal", by_id["2.rks"].body[/Language: (.*)/, 1]
    assert_equal "non", by_id["1.ais"].language, "Old Icelandic rides the Old Norse code"
    assert_equal "al(le)", by_id["1.hol"].headword
    assert_equal "alle", by_id["1.hol"].headword_folded, "optional-segment parens open in the fold"
  end

  # --- the etymology-table shape: iranet --------------------------------------------

  def test_parse_iranet_yields_the_ira_pro_etymology_shelf
    document = parse("starling-iranet")
    assert_equal "ira-pro", document.language
    by_id = document.entries.to_h { |e| [e.entry_id, e] }
    assert_equal %w[1 3 127], by_id.keys,
                 "the fully-empty NUMBER-0 slot mints nothing (censused: iranet ×18, every other base ×0)"
    entry = by_id["1"]
    assert_equal "hama", entry.headword
    assert_equal "*hama", entry.key_raw
    assert_equal "all", entry.gloss
    assert_includes entry.body, "Persian: hama hama", "the form + etymon cell rides verbatim"
    assert_includes entry.body, "Ossetic: äppät"
    assert_includes entry.body, "REF: *hama-kaϑa всем домом Аб.", "the unaliased REF column keeps its siglum"
    assert_includes entry.body, "IE etymology: #3005"
    assert_empty entry.reflexes, "form + etymon cells — body-only by verdict"
    stub = by_id["127"]
    assert_equal "#127", stub.headword, "headword-less records keep their slot (the piet/caucet rule)"
    assert_equal "nose", stub.gloss
    assert_includes stub.body, "REF: Gil. dəmåɣ ?"
  end

  # --- conformance ------------------------------------------------------------------

  def test_entry_ids_are_unique_stable_and_output_is_nfc
    %w[starling-lexstat-balt starling-lexstat-germ starling-iranet].each do |slug|
      first = parse(slug).map(&:entry_id)
      assert_equal first.uniq, first
      assert_equal first, parse(slug).map(&:entry_id)
      parse(slug).each do |entry|
        assert entry.headword.unicode_normalized?(:nfc)
        assert entry.body.unicode_normalized?(:nfc)
        refute_empty entry.headword_folded
        # dBase numeric cells read as binary bytes; an id built from them
        # must still be UTF-8 (it doubles as the fold of a token-less
        # cell — dard's bare "?" forms — which validation requires UTF-8).
        assert_equal Encoding::UTF_8, entry.entry_id.encoding, entry.entry_id if slug.include?("lexstat")
      end
    end
  end

  def test_every_lexstat_column_sigil_has_a_language_row
    known = Nabu::Adapters::StarlingLexstat::LANGUAGES
    %w[balt germ].each do |table|
      parser = Nabu::Adapters::StarlingDbfParser.new(dbf_path: File.join(FIXTURES, "LEXSTAT", "#{table}.dbf"))
      names = parser.fields.map(&:name)
      columns = names.select { |name| names.include?("#{name}NUM") && name != "NUMBER" }
      refute_empty columns
      columns.each { |column| assert known.key?(column), "#{table}.#{column} needs a LANGUAGES row" }
    end
  end

  def test_an_unknown_column_sigil_quarantines_rather_than_guessing
    error = assert_raises(Nabu::ParseError) do
      Nabu::Adapters::StarlingLexstat.new.parse(
        slug: "starling-lexstat-balt", path: File.join(FIXTURES, "LEXSTAT", "balt.dbf"),
        languages: Nabu::Adapters::StarlingLexstat::LANGUAGES.except("JAT")
      )
    end
    assert_match(/JAT/, error.message)
  end
end
