# frozen_string_literal: true

require "test_helper"

# The hdic-tsv parser family (P32-4): #-commented TSVs with a column-name
# row, generic over per-database column names; every populated column rides
# the body (the TBID/SYID/YYID cross-links stay), headword-less rows skip
# by rule, and the TSJ wakun database joins by tsj_id as body lines.
class HdicTsvParserTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("hdic")

  def parser = Nabu::Adapters::HdicTsvParser.new

  def ktb_entries
    @ktb_entries ||= parser.entries(
      File.join(FIXTURES, "KTB.tsv"),
      id_column: "TBID", entry_column: "Entry", def_column: "TB_def", language: "lzh"
    )
  end

  def tsj_entries
    @tsj_entries ||= parser.entries(
      File.join(FIXTURES, "TSJ_definitions.tsv"),
      id_column: "TSJ2ID", entry_column: "Entry_word", def_column: "SJ_def", language: "lzh",
      wakun: File.join(FIXTURES, "TSJ_wakun.tsv")
    )
  end

  def test_ktb_mints_one_entry_per_row_with_upstream_ids_verbatim
    assert_equal 12, ktb_entries.size
    first = ktb_entries.first
    assert_equal "1_016_A51", first.entry_id
    assert_equal "一", first.headword
    assert_equal "lzh", first.language
    assert_includes first.body, "TB_def: 於逸反。少也，初也，同也。"
  end

  def test_cross_dictionary_link_columns_ride_the_body_verbatim
    first = ktb_entries.first
    assert_includes first.body, "SYID: a005a101",
                    "the project's own KTB→SYP link — the crosswalk must not be projected away"
    definition_line = first.body.lines.first
    assert definition_line.start_with?("TB_def: "), "definition first, then the other columns"
  end

  def test_gloss_is_the_first_sentence_of_the_definition
    assert_equal "於逸反", ktb_entries.first.gloss
  end

  def test_headwordless_rows_skip_by_rule
    ids = tsj_entries.map(&:entry_id)
    assert_equal 12, tsj_entries.size, "13 fixture rows, one with an empty Entry_word cell"
    refute_includes ids, "s0811a303a", "the censused entry-less definition fragment"
  end

  def test_wakun_database_rows_join_by_tsj_id_as_body_lines
    kanae = tsj_entries.find { |entry| entry.entry_id == "s0104a705" }
    assert_equal "鬵", kanae.headword
    assert_includes kanae.body, "wakun: "
    assert_includes kanae.body, "カナヘ（鬵）"
    assert_includes kanae.body, "[sj_w00001]"
    without = tsj_entries.find { |entry| entry.entry_id == "s0104a601" }
    refute_includes without.body, "wakun: ", "only wakun-attested entries carry the rider"
  end

  def test_krm_composite_headwords_stay_verbatim
    entries = parser.entries(
      File.join(FIXTURES, "KRM.tsv"),
      id_column: "KRID_n", entry_column: "Entry", def_column: "Def", language: "jpn"
    )
    assert_equal 12, entries.size
    composite = entries.find { |entry| entry.entry_id == "F00002" }
    assert_equal "一／人", composite.headword, "KRM's slot notation is upstream reality"
  end

  def test_output_is_nfc_and_ids_unique
    [ktb_entries, tsj_entries].each do |entries|
      assert_equal entries.map(&:entry_id).uniq, entries.map(&:entry_id)
      entries.each do |entry|
        assert entry.headword.unicode_normalized?(:nfc)
        assert entry.body.unicode_normalized?(:nfc)
      end
    end
  end
end
