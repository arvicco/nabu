# frozen_string_literal: true

require "test_helper"
require "stringio"
require "nabu/parquet"

# Nabu::Parquet — the minimal streaming reader. Two files, one content:
# the PleIAs/French-PD-Books trimmed shard (upstream's own writer,
# fastparquet 2023.10.1, SNAPPY, one v1 page per column — README in
# test/fixtures/pleias-french-books/) and the same table re-written by
# parquet-cpp with 1 KiB pages and one-row write batches
# (test/fixtures/parquet/README.md), so the page walk is exercised on
# real multi-page chunks.
class ParquetTest < Minitest::Test
  UPSTREAM = File.join(Nabu::TestSupport.fixtures("pleias-french-books"), "fetch", "gallica_mono_1.parquet")
  MULTIPAGE = File.join(Nabu::TestSupport.fixtures("parquet"), "multipage.parquet")
  IDS = %w[bpt6k63598352 bpt6k9671998b bpt6k54293789 bpt6k96930955].freeze

  def open_file(path, &) = File.open(path, "rb") { |io| yield Nabu::Parquet.new(io) }

  def test_the_footer_names_the_flat_schema_and_row_count
    open_file(UPSTREAM) do |pq|
      assert_equal 4, pq.num_rows
      assert_match(/fastparquet-python version 2023\.10\.1/, pq.created_by)
      assert_equal %w[file_id ocr title date author page_count word_count character_count complete_text],
                   pq.column_names
    end
  end

  def test_string_and_integer_columns_decode
    open_file(UPSTREAM) do |pq|
      assert_equal IDS, pq.column("file_id")
      assert_equal %w[1783 1626 1652 1563], pq.column("date")
      assert_equal [16, 12, 34, 12], pq.column("page_count")
      assert_equal [1776, 6448, 3490, 6423], pq.column("character_count")
      assert_equal "None", pq.column("author")[2], "upstream stringified Python's None — data, not a null"
    end
  end

  def test_the_text_column_streams_only_the_wanted_rows
    open_file(UPSTREAM) do |pq|
      seen = []
      pq.each_value("complete_text", want: Set[1, 3]) { |row, value| seen << [row, value] }
      assert_equal [1, 3], seen.map(&:first)
      text = seen.first.last.force_encoding(Encoding::UTF_8)
      assert_predicate text, :valid_encoding?
      assert_equal 6448, text.length, "upstream's character_count is the text's length"
      assert text.start_with?("\nLETTRES \nPATENTES DV ROY"), text[0, 40].inspect
    end
  end

  def test_a_multipage_chunk_reads_identically
    open_file(MULTIPAGE) do |multi|
      assert_equal 4, multi.page_count("complete_text"), "the re-write gives each text value its own page"
      open_file(UPSTREAM) do |upstream|
        assert_equal 1, upstream.page_count("complete_text")
        upstream.column_names.each do |name|
          assert_equal upstream.column(name), multi.column(name), name
        end
      end
    end
  end

  def test_a_non_parquet_file_raises
    error = assert_raises(Nabu::Parquet::Error) { Nabu::Parquet.new(StringIO.new("not a parquet file at all")) }
    assert_match(/no PAR1 trailer/, error.message)
  end

  def test_an_unknown_column_raises
    open_file(UPSTREAM) { |pq| assert_raises(Nabu::Parquet::Error) { pq.column("language") } }
  end

  def test_hybrid_levels_decode_both_run_kinds
    # RLE run of 3 ones (header 3<<1=6, value byte 1), then one bit-packed
    # group (header 1<<1|1=3) of eight levels 1,0,1,1,0,0,0,1 (LSB first).
    bytes = [6, 1, 3, 0b10001101].pack("C*")
    assert_equal [1, 1, 1, 1, 0, 1, 1, 0, 0, 0, 1], Nabu::Parquet::Hybrid.decode(bytes, count: 11, width: 1)
  end
end
