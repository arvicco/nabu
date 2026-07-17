# frozen_string_literal: true

require "test_helper"

module Adapters
  # Nabu::Adapters::CorphSqlParser (P25-0) — the corph-sql parser family: a
  # streaming walker over a MySQL/phpMyAdmin dump's INSERT statements. It
  # never slurps the file (the real dump is 39 MB), never evaluates SQL, and
  # yields one { column => value } hash per row of the requested table.
  # Exercised against the REAL trimmed dump in test/fixtures/corph/ (texts
  # 0003/0008/0067/0077 plus the stray Text_ID "6" sentence — see the fixture
  # README), which preserves the upstream statement chunking (multi-statement
  # tables) and escape reality (\', \r\n, NULL, integer columns).
  class CorphSqlParserTest < Minitest::Test
    FIXTURE = File.join(Nabu::TestSupport.fixtures("corph"), "chronhibdev_2020.sql")

    def parser
      Nabu::Adapters::CorphSqlParser.new(FIXTURE)
    end

    # -- row walking ----------------------------------------------------------

    def test_each_row_yields_every_row_of_the_requested_table
      expected = { "TEXT" => 4, "SENTENCES" => 119, "MORPHOLOGY" => 613,
                   "LEMMATA" => 373, "BIBLIOGRAPHY" => 6, "VARIATIONS" => 9 }
      expected.each do |table, count|
        assert_equal count, parser.each_row(table).count,
                     "#{table} row count (the fixture's trimmed reality)"
      end
    end

    def test_rows_survive_the_upstream_statement_chunking
      # The trimmed LEMMATA rows span 23 ORIGINAL INSERT statements (the
      # phpMyAdmin chunking preserved verbatim); every statement's rows must
      # arrive, with no duplicates.
      ids = parser.each_row("LEMMATA").map { |row| row.fetch("ID") }
      assert_equal ids.uniq.size, ids.size, "no row may be yielded twice"
      assert_equal 373, ids.size
    end

    def test_each_row_without_a_block_returns_an_enumerator
      rows = parser.each_row("TEXT")
      assert_kind_of Enumerator, rows
      assert_equal %w[0003 0008 0067 0077], rows.map { |row| row.fetch("Text_ID") }.sort
    end

    def test_an_unknown_table_yields_nothing
      assert_empty parser.each_row("NO_SUCH_TABLE").to_a
    end

    # -- value decoding -------------------------------------------------------

    def test_columns_are_keyed_by_the_statement_column_list
      row = parser.each_row("BIBLIOGRAPHY").first
      assert_equal %w[ID Abbreviation Reference Pdf_Link Image Sort_ID], row.keys
    end

    def test_integer_and_null_values_decode_natively
      row = parser.each_row("BIBLIOGRAPHY").first
      assert_kind_of Integer, row.fetch("ID")
      assert_nil row.fetch("Sort_ID"), "SQL NULL must decode to nil, never the string \"NULL\""
    end

    def test_backslash_escaped_quotes_decode
      # TEXT 0003's Dating_Criteria carries the real upstream \' escape:
      # "(Donall O\'Davoren)".
      text = parser.each_row("TEXT").find { |row| row.fetch("Text_ID") == "0003" }
      assert_includes text.fetch("Dating_Criteria"), "O'Davoren",
                      "\\' must decode to a literal apostrophe"
    end

    def test_escaped_newlines_decode_to_real_newlines
      # S0077-3's Textual_Unit is a multi-line computus table dumped with
      # literal \r\n escapes — they must decode to real CRLF characters.
      row = parser.each_row("SENTENCES").find { |r| r.fetch("Text_Unit_ID") == "S0077-3" }
      assert_includes row.fetch("Textual_Unit"), "conputandis.\r\noin Kalendae"
    end

    def test_commas_and_parens_inside_strings_never_split_values
      row = parser.each_row("BIBLIOGRAPHY").find { |r| r.fetch("Abbreviation") == "Murray & Bhreathnach 2005" }
      assert_includes row.fetch("Reference"), "E. Bhreathnach (ed.), The Kingship and Landscape of Tara"
      assert_kind_of Integer, row.fetch("ID")
    end

    # -- damage ---------------------------------------------------------------

    def test_a_truncated_dump_raises_parse_error
      Dir.mktmpdir do |dir|
        path = File.join(dir, "truncated.sql")
        # Cut the real fixture mid-statement: the last kept tuple loses its
        # ");" terminator, so the statement never closes.
        lines = File.readlines(FIXTURE)
        last = lines.rindex { |line| line.rstrip.end_with?(");") && line.start_with?("(") }
        File.write(path, lines[0..last].join.sub(/\);\s*\z/, ", "))
        error = assert_raises(Nabu::ParseError) do
          Nabu::Adapters::CorphSqlParser.new(path).each_row("VARIATIONS").to_a
        end
        assert_match(/unterminated/i, error.message)
      end
    end
  end
end
