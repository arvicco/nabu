# frozen_string_literal: true

require "test_helper"

module Store
  # Nabu::Store::FtsStructure (P112-3, Q114): the fts5 structure-record
  # parser behind the segment gauges. The 2026-10-01 wedge taught that
  # fts5 caps TOTAL segments at 2000 and that nothing surfaces the count
  # before the cap kills writes ("database or disk is full") — these
  # gauges make segment pressure visible to health long before that.
  class FtsStructureTest < Minitest::Test
    def setup
      @db = Nabu::Store.connect_fulltext("sqlite::memory:")
      @db.run(<<~SQL)
        CREATE VIRTUAL TABLE t USING fts5(
          body, content = '', contentless_delete = 1, tokenize = 'unicode61'
        )
      SQL
    end

    def teardown
      @db.disconnect
    end

    def read = Nabu::Store::FtsStructure.read(@db, :t)

    def test_reads_a_fresh_tables_structure
      structure = read

      assert_predicate structure, :v2?, "contentless_delete tables carry the V2 structure"
      assert_equal 0, structure.total_segments
      assert_empty(structure.levels.flat_map { |l| l[:segments] })
    end

    def test_counts_segments_as_transactions_accumulate
      # automerge off: every committed write flushes its own level-0
      # segment and nothing consolidates — the count is deterministic.
      @db[:t].insert(t: "automerge", rank: 0)
      base = read.total_segments
      3.times { |i| @db.transaction { @db[:t].insert(rowid: i + 1, body: "word#{i}") } }

      structure = read

      assert_equal base + 3, structure.total_segments,
                   "each committed insert flushes one level-0 segment under automerge=0"
      assert_equal structure.total_segments,
                   structure.levels.sum { |l| l[:segments].size },
                   "the header total agrees with the per-level lists"
    end

    def test_reports_tombstone_pages_after_a_contentless_delete
      @db[:t].insert(t: "automerge", rank: 0)
      @db.transaction { @db[:t].insert(rowid: 1, body: "doomed word") }
      @db.transaction { @db[:t].insert(rowid: 2, body: "second word") }
      assert_equal 0, read.tombstone_pages

      @db[:t].where(rowid: 1).delete

      assert_operator read.tombstone_pages, :>, 0,
                      "a contentless delete mints tombstone pages the V2 record counts"
    end

    def test_gauges_summarize_for_health
      @db[:t].insert(t: "automerge", rank: 0)
      2.times { |i| @db.transaction { @db[:t].insert(rowid: i + 1, body: "word#{i}") } }

      gauges = Nabu::Store::FtsStructure.gauges(@db, :t)

      assert_equal 2, gauges[:segments]
      assert_operator gauges[:pages], :>, 0
      assert_equal 0, gauges[:tombstone_pages]
      assert_in_delta 0.0, gauges[:tombstone_share]
    end

    def test_missing_table_reads_nil
      assert_nil Nabu::Store::FtsStructure.read(@db, :absent)
      assert_nil Nabu::Store::FtsStructure.gauges(@db, :absent)
    end

    # The production tables' shape: the passages_fts rebuild mints a
    # parsable structure (guards against silent format drift — if fts5
    # ever changes the record, this fails loudly rather than health
    # reporting garbage).
    def test_parses_the_real_passages_fts_shape
      @db.run(Nabu::Store::Indexer::CREATE_TABLE)
      @db[:passages_fts].insert(rowid: 1, text_normalized: "μηνιν αειδε θεα",
                                language: "0langgrc", source: "0srcs")

      structure = Nabu::Store::FtsStructure.read(@db, :passages_fts)

      assert_operator structure.total_segments, :>=, 1
      assert_operator structure.write_counter, :>=, 1
    end
  end
end
