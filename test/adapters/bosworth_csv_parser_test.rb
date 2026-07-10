# frozen_string_literal: true

require "test_helper"
require "tempfile"

# The bosworth-csv parser family (P12-3): the first non-TEI dictionary
# ingestion path — one semicolon-separated, all-fields-quoted CSV
# (id;headword;body) with multi-line project-XML bodies. All assertions run
# against the real trimmed dump slice in test/fixtures/bosworth-toller/.
class BosworthCsvParserTest < Minitest::Test
  FIXTURE = File.join(Nabu::TestSupport.fixtures("bosworth-toller"), "bosworth_entries_export.csv")

  def entries
    @entries ||= Nabu::Adapters::BosworthCsvParser.new.entries(FIXTURE)
  end

  def entry(id)
    entries.find { |e| e.entry_id == id } || flunk("fixture entry #{id} not parsed")
  end

  def test_parses_every_fixture_row_into_a_dictionary_entry
    assert_equal 270, entries.size
    assert(entries.all?(Nabu::DictionaryEntry))
    assert_equal "1", entries.first.entry_id # file order preserved
    assert_equal "A", entries.first.headword
  end

  def test_entry_ids_are_the_csv_id_column_and_unique
    ids = entries.map(&:entry_id)
    assert_equal ids.uniq, ids
    assert_includes ids, "31437" # the Þ letter entry
    refute_includes ids, "5" # upstream id gaps are real, never invented
  end

  def test_headword_is_nfc_and_key_raw_is_the_csv_headword_verbatim
    aethele = entry("940")
    assert_equal "æðele", aethele.headword
    assert_equal "æðele", aethele.key_raw
    entries.each do |e|
      assert e.headword.unicode_normalized?(:nfc)
      assert e.body.unicode_normalized?(:nfc)
      assert_equal "ang", e.language
    end
  end

  def test_headwords_fold_per_the_ang_rule_with_hyphens_dropped
    assert_equal "aethele", entry("940").headword_folded
    assert_equal "thing", entry("31866").headword_folded
    assert_equal "th", entry("31437").headword_folded # Þ, downcased then folded
    assert_equal "aeghwaether", entry("514").headword_folded # ǽg-hwæðer: hyphen dropped, medial ð
    assert_equal "theahhwaethere", entries.find { |e| e.headword == "þeáh-hwæðere" }.headword_folded
  end

  def test_homographs_stay_separate_entries_sharing_a_folded_headword
    ae_group = entries.select { |e| e.headword == "ǽ" }
    assert_equal %w[308 309 310], ae_group.map(&:entry_id)
    assert_equal ["ae"], ae_group.map(&:headword_folded).uniq
  end

  def test_gloss_prefers_the_english_equiv_then_the_first_def
    assert_equal "noble", entry("940").gloss # first <equiv lang="eng">
    assert_equal "a thing", entry("31866").gloss # first <def>, trailing comma trimmed
  end

  def test_gloss_is_nil_for_untagged_entries
    assert_nil entry("31437").gloss # the Þ letter entry has no <def>/<equiv>
  end

  def test_body_is_linearized_plain_text_with_sense_breaks
    body = entry("31866").body # þing, sense tree I..
    refute_includes body, "<sense"
    refute_includes body, "<def"
    assert_match(/\nI\.\s/, body)
    assert_includes body, "a single object, material or immaterial"
  end

  def test_body_skips_the_technical_search_and_sort_fields
    body = entry("940").body
    refute_includes body, "aetþele" # the upstream <sort> key
    assert_includes body, "æðele"   # the <orth> display form stays
  end

  def test_body_decodes_double_encoded_entities
    body = entry("1").body # the "A" letter entry
    assert_includes body, "Grimm's" # &amp;#39;
    assert_includes body, "—"       # &amp;mdash;
    refute_includes body, "&#39;"
    refute_includes body, "&amp;"
  end

  def test_untagged_flat_bodies_still_yield_text
    entries.each do |e|
      refute e.body.strip.empty?, "entry #{e.entry_id} linearized to empty body"
    end
  end

  def test_citations_start_empty_no_oe_crosswalk_yet
    assert(entries.all? { |e| e.citations.empty? })
  end

  def test_malformed_csv_raises_parse_error
    Tempfile.create(["bt", ".csv"]) do |f|
      f.write(%("id";"headword";"body"\r\n"9";"x";"unclosed\r\n))
      f.flush
      assert_raises(Nabu::ParseError) { Nabu::Adapters::BosworthCsvParser.new.entries(f.path) }
    end
  end

  def test_row_with_missing_fields_raises_parse_error
    Tempfile.create(["bt", ".csv"]) do |f|
      f.write(%("id";"headword";"body"\r\n"9";"";"<entry/>"\r\n))
      f.flush
      assert_raises(Nabu::ParseError) { Nabu::Adapters::BosworthCsvParser.new.entries(f.path) }
    end
  end
end
