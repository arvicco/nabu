# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# The flat-csv parser family (P29-0): stdlib-CSV streaming over a plain
# headered CSV artifact — the OpenEtruscan/Larth shape (one record per
# inscription/vocabulary row; quoted fields may span lines). Header
# validation is loud (a renamed upstream column must never silently yield
# nil-filled rows), malformed CSV raises Nabu::ParseError.
class FlatCsvParserTest < Minitest::Test
  FIXTURE = File.join(Nabu::TestSupport.fixtures("open-etruscan"),
                      "corpus", "openetruscan_clean.csv")

  def test_streams_rows_as_string_keyed_hashes_in_file_order
    rows = Nabu::Adapters::FlatCsvParser.new.each_row(FIXTURE).to_a
    assert_equal 10, rows.size
    assert_equal "CIE 2609", rows.first.fetch("id")
    assert_equal "clean", rows.first.fetch("data_quality")
    assert_equal "ve:puce:f", rows.first.fetch("canonical_transliterated")
  end

  def test_quoted_multi_line_fields_stay_one_record
    rows = Nabu::Adapters::FlatCsvParser.new.each_row(FIXTURE).to_a
    lamina = rows.find { |row| row.fetch("id") == "CIE 52a, b" }
    refute_nil lamina, "the quoted, comma-carrying id is one record"
    assert_includes lamina.fetch("raw_text"), "--- Lamina B ---",
                    "newlines inside a quoted field must not split the record"
  end

  def test_missing_required_headers_raise_parse_error_naming_them
    parser = Nabu::Adapters::FlatCsvParser.new(required_headers: %w[id no_such_column])
    error = assert_raises(Nabu::ParseError) { parser.each_row(FIXTURE).to_a }
    assert_match(/no_such_column/, error.message)
    assert_match(/openetruscan_clean\.csv/, error.message)
  end

  def test_malformed_csv_raises_parse_error
    Dir.mktmpdir do |dir|
      path = File.join(dir, "broken.csv")
      File.write(path, "id,text\n\"unclosed quote,oops\n")
      assert_raises(Nabu::ParseError) do
        Nabu::Adapters::FlatCsvParser.new.each_row(path).to_a
      end
    end
  end

  def test_returns_an_enumerator_without_a_block
    enum = Nabu::Adapters::FlatCsvParser.new.each_row(FIXTURE)
    assert_kind_of Enumerator, enum
    assert_equal enum.to_a.size, enum.count
  end
end
