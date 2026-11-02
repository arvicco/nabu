# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# The ganjoor-sqlite parser family over the trimmed real release database
# (test/fixtures/ganjoor/ganjoor.s3db — the full DDL, eleven poems' rows).
class GanjoorSqliteParserTest < Minitest::Test
  FIXTURE = File.join(Nabu::TestSupport.fixtures("ganjoor"), "ganjoor.s3db")
  Parser = Nabu::Adapters::GanjoorSqliteParser

  def setup
    @parser = Parser.new(FIXTURE)
  end

  def teardown
    @parser.close
  end

  def test_reads_the_poet_and_cat_tables
    assert_equal [2, 5, 7, 12, 22, 35, 501], @parser.poets.keys
    hafez = @parser.poets.fetch(2)
    assert_equal "حافظ", hafez.name
    assert_equal 9, hafez.cat_id
    assert_equal %w[حافظ غزلیات], @parser.cat_path(24).map(&:text)
    assert_equal "https://ganjoor.net/hafez/ghazal", @parser.cat_path(24).last.url
    assert_equal 2, @parser.poet_for_cat(24).id
  end

  def test_enumerates_poems_in_id_order
    ids = @parser.each_poem.map(&:id)
    assert_equal ids.sort, ids
    assert_equal 11, ids.size
    poem = @parser.poem(2130)
    assert_equal "غزل شمارهٔ ۱", poem.title
    assert_equal "https://ganjoor.net/hafez/ghazal/sh1", poem.url
  end

  def test_poem_ids_with_text_excludes_a_row_less_poem
    with_text = @parser.poem_ids_with_text
    refute_includes with_text, 59_493, "Saeb's listed poem carries no verse rows"
    assert_includes with_text, 2130
  end

  def test_couplets_pair_right_and_left_hemistichs
    record = @parser.record(2130)
    assert_equal 7, record.units.size
    first = record.units.first
    assert_equal :couplet, first.form
    assert_equal [1, 2], first.vorders
    assert_equal 2, first.lines.size
    assert_equal Nabu::Normalize.nfc("اَلا یا اَیُّهَا السّاقی اَدِرْ کَأساً و ناوِلْها"),
                 Nabu::Normalize.nfc(first.lines.first), "Hafez's Arabic opening hemistich, harakat and all"
    refute first.lines.first.unicode_normalized?(:nfc),
           "the reader hands rows over VERBATIM — upstream's shadda+vowel order is not NFC; " \
           "normalizing is the adapter boundary's job"
  end

  def test_centered_lines_pair_into_band_units
    record = @parser.record(2996)
    assert_equal 15, record.units.size
    assert_equal %i[couplet band], record.units.first(2).map(&:form)
    assert_equal [3, 4], record.units[1].vorders
  end

  def test_prose_paragraphs_and_comments
    golestan = @parser.record(41_334)
    assert_equal %i[prose couplet], golestan.units.map(&:form)
    rudaki = @parser.record(25_300)
    assert_equal 3, rudaki.comments.size, "position 5 rows are editorial notes, never units"
    assert_equal 2, rudaki.units.size
    assert_match(/سعید نفیسی/, rudaki.comments.first)
  end

  def test_grouping_rule_edges
    rows = [[1, 0, "a"], [2, 0, "b"], [3, 1, "c"], [4, 1, "d"], [5, 1, "  "], [6, 4, "e"], [7, -1, "f"]]
    record = Parser.group(rows)
    assert_equal [%w[a], %w[b c], %w[d], %w[e], %w[f]], record.units.map(&:lines),
                 "an unpaired hemistich stands alone; a closer never reaches back past a unit"
    assert_equal %i[couplet couplet couplet line prose], record.units.map(&:form)
    assert_equal 1, record.blank_rows
  end

  # The release's invisible-only rows (regression, the real codepoints):
  # poem 105811 vorder 5 is a lone U+00A0, poem 51262 vorder 104 a lone
  # ZWNJ (U+200C), poem 501256 vorder 93 a lone U+001D.
  def test_invisible_only_rows_are_blank
    rows = [[1, 0, "a"], [2, 1, " "], [3, 0, "‌"], [4, 1, "b"], [5, 4, "\u001d"], [6, 5, "‌"],
            [7, 0, " c "]]
    record = Parser.group(rows)
    assert_equal [%w[a], %w[b], %w[c]], record.units.map(&:lines), "edge no-break spaces strip too"
    assert_equal 3, record.blank_rows
    assert_empty record.comments
  end

  def test_unknown_position_is_a_parse_error
    error = assert_raises(Nabu::ParseError) { Parser.group([[1, 9, "x"]], label: "poem 1") }
    assert_match(/unknown verse position 9/, error.message)
  end

  def test_a_non_database_raises_parse_error
    Dir.mktmpdir do |dir|
      path = File.join(dir, "ganjoor.s3db")
      File.write(path, "not sqlite")
      assert_raises(Nabu::ParseError) { Parser.new(path).poets }
    end
  end
end
