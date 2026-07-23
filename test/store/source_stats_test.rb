# frozen_string_literal: true

require "test_helper"
require "json"

module Store
  # Nabu::Store::SourceStats (P42-0): the write-time census. Two lifecycles,
  # one truth: the loader maintains the table INCREMENTALLY (same transaction
  # as each document write) and `nabu rebuild` re-derives it WHOLESALE — the
  # load-bearing test here drives a whole sequence of loads/withdrawals/
  # restores/relabels through the real Loader and asserts the incrementally
  # maintained table equals a from-scratch wholesale derivation of the same
  # end state, after every step.
  class SourceStatsTest < Minitest::Test
    include StoreTestDB

    def setup
      @db = store_test_db
      @source = Nabu::Store::Source.create(
        slug: "texts", name: "Texts", adapter_class: "TestAdapter", license_class: "nc"
      )
    end

    # -- helpers -------------------------------------------------------------

    def loader
      Nabu::Store::Loader.new(db: @db, source: @source)
    end

    def passage(urn, seq, text: "words", language: "grc")
      Nabu::Passage.new(urn: urn, sequence: seq, language: language,
                        text: text, text_normalized: text)
    end

    def document(urn, passages, language: "grc", license_override: nil)
      doc = Nabu::Document.new(urn: urn, title: urn, language: language,
                               canonical_path: "#{urn}.xml", license_override: license_override)
      passages.each { |row| doc << row }
      doc
    end

    def alpha(text: "alpha words", override: nil)
      document("urn:t:alpha", [passage("urn:t:alpha:1", 0, text: text),
                               passage("urn:t:alpha:2", 1, text: "#{text} two", language: "lat")],
               license_override: override)
    end

    def beta
      document("urn:t:beta", [passage("urn:t:beta:1", 0, language: "chu")], language: "chu")
    end

    # The equivalence oracle: snapshot the incrementally maintained tables,
    # wholesale-derive into the same db, and the rows must match exactly
    # (updated_at/note are bookkeeping, not census facts).
    def assert_equivalent!(context)
      incremental = snapshot
      Nabu::Store::SourceStats.derive!(@db, note: "test wholesale")
      assert_equal snapshot, incremental, "incremental vs wholesale drift #{context}"
    end

    def snapshot
      rows = @db[:source_stats].order(:source_id).all.map do |row|
        row.values_at(:source_id, :live_documents, :live_passages,
                      :withdrawn_documents, :retired_documents) +
          [JSON.parse(row[:license_overrides_json])]
      end
      langs = @db[:source_stats_languages].order(:source_id, :language)
                                          .select_map(%i[source_id language documents passages])
      [rows, langs]
    end

    def stats_row
      @db[:source_stats].first(source_id: @source.id)
    end

    def lang_rows
      @db[:source_stats_languages].where(source_id: @source.id)
                                  .order(:language)
                                  .select_map(%i[language documents passages])
    end

    # -- wholesale derivation ------------------------------------------------

    def test_derive_builds_counts_language_rows_and_license_mix
      loader.load([alpha(override: "open"), beta])
      @db[:source_stats].delete
      @db[:source_stats_languages].delete

      Nabu::Store::SourceStats.derive!(@db, note: "test")

      row = stats_row
      assert_equal 2, row[:live_documents]
      assert_equal 3, row[:live_passages]
      assert_equal 0, row[:withdrawn_documents]
      assert_equal 0, row[:retired_documents]
      assert_equal({ "open" => 1 }, JSON.parse(row[:license_overrides_json]))
      assert_equal "test", row[:note]
      assert_equal [["chu", 1, 1], ["grc", 1, 1], ["lat", 0, 1]], lang_rows
    end

    def test_derive_makes_no_row_for_a_documentless_source
      Nabu::Store::SourceStats.derive!(@db, note: "test")
      assert_nil stats_row, "a source with no documents has no stats row"
    end

    def test_derive_is_a_noop_without_the_table
      @db.drop_table(:source_stats_languages)
      @db.drop_table(:source_stats)
      Nabu::Store::SourceStats.derive!(@db, note: "test") # must not raise
      refute Nabu::Store::SourceStats.available?(@db)
    end

    # -- incremental maintenance through the Loader --------------------------

    def test_insert_maintains_stats_incrementally
      loader.load([alpha, beta])

      row = stats_row
      assert_equal 2, row[:live_documents]
      assert_equal 3, row[:live_passages]
      assert_equal [["chu", 1, 1], ["grc", 1, 1], ["lat", 0, 1]], lang_rows
      assert_equivalent!("after insert")
    end

    def test_idempotent_reload_does_not_double_count
      loader.load([alpha, beta])
      before = snapshot
      loader.load([alpha, beta])

      assert_equal before, snapshot, "an identical reload must not touch stats"
      assert_equivalent!("after idempotent reload")
    end

    def test_full_load_sweep_withdraws_and_stats_follow
      loader.load([alpha, beta])
      loader.load([alpha]) # full load without beta -> beta withdrawn

      row = stats_row
      assert_equal 1, row[:live_documents]
      assert_equal 2, row[:live_passages]
      assert_equal 1, row[:withdrawn_documents]
      assert_equal [["grc", 1, 1], ["lat", 0, 1]], lang_rows,
                   "the withdrawn document's language rows are pruned"
      assert_equivalent!("after sweep")
    end

    def test_restore_after_withdrawal_adds_the_counts_back
      loader.load([alpha, beta])
      loader.load([alpha])
      loader.load([alpha, beta]) # beta restored, identical content

      row = stats_row
      assert_equal 2, row[:live_documents]
      assert_equal 0, row[:withdrawn_documents]
      assert_equal 3, row[:live_passages]
      assert_equivalent!("after restore")
    end

    def test_revision_applies_the_passage_delta_and_language_moves
      loader.load([alpha, beta])
      # beta revised: language moves to orv, one passage added.
      revised = document("urn:t:beta", [passage("urn:t:beta:1", 0, text: "new", language: "orv"),
                                        passage("urn:t:beta:2", 1, language: "orv")], language: "orv")
      loader.load([alpha, revised])

      row = stats_row
      assert_equal 2, row[:live_documents]
      assert_equal 4, row[:live_passages]
      assert_equal [["grc", 1, 1], ["lat", 0, 1], ["orv", 1, 2]], lang_rows,
                   "chu is pruned, orv carries the revised counts"
      assert_equivalent!("after revision")
    end

    def test_license_override_relabel_moves_the_mix_without_content_change
      loader.load([alpha])
      loader.load([alpha(override: "open")])
      assert_equal({ "open" => 1 }, JSON.parse(stats_row[:license_overrides_json]))

      loader.load([alpha]) # override removed upstream
      assert_equal({}, JSON.parse(stats_row[:license_overrides_json]))
      assert_equivalent!("after relabels")
    end

    def test_retirement_flip_maintains_retired_count
      loader.load([alpha, beta])
      ref = Nabu::DocumentRef.new(source_id: "texts", id: "urn:t:beta", path: "beta.xml",
                                  metadata: { Nabu::Adapter::RETAINED_KEY => true })
      adapter = SourceStatsTest::StubAdapter.new(docs: { alpha => nil, beta => ref })
      Nabu::Store::Loader.new(db: @db, source: @source)
                         .load_from(adapter, workdir: "(unused)")

      assert_equal 1, stats_row[:retired_documents]
      assert_equivalent!("after retirement")
    end

    def test_loader_tolerates_a_catalog_without_the_stats_table
      @db.drop_table(:source_stats_languages)
      @db.drop_table(:source_stats)
      report = loader.load([alpha, beta])
      assert_equal 2, report.added, "loads must succeed on a pre-019 catalog"
    end

    # The packet's load-bearing test: a whole life story maintained
    # incrementally must equal the wholesale derivation at every waypoint
    # (the waypoint asserts live inside the step tests above; this one runs
    # the full braid in one sequence, batch mode included).
    def test_equivalence_over_a_full_sequence_in_batch_mode
      batch_loader = Nabu::Store::Loader.new(db: @db, source: @source, tx_batch: 2)
      batch_loader.load([alpha, beta])
      batch_loader.load([alpha(text: "revised words", override: "open")]) # revise + withdraw beta
      batch_loader.load([alpha(text: "revised words", override: "open"), beta]) # restore beta
      assert_equivalent!("after the batch-mode braid")
    end

    # -- migration backfill --------------------------------------------------

    def test_migration_backfills_from_a_populated_pre019_catalog
      db = Sequel.sqlite
      require "sequel/extensions/migration"
      Sequel::Migrator.run(db, Nabu::Store::MIGRATIONS_DIR, target: 18)
      source_id = db[:sources].insert(slug: "old", name: "Old", adapter_class: "T", license_class: "nc")
      live = db[:documents].insert(source_id: source_id, urn: "u:1", language: "grc",
                                   license_override: "open", content_sha256: "a")
      gone = db[:documents].insert(source_id: source_id, urn: "u:2", language: "grc",
                                   content_sha256: "b", withdrawn: true)
      db[:passages].insert(document_id: live, urn: "u:1:1", sequence: 0, language: "grc",
                           text: "t", text_normalized: "t", content_sha256: "c")
      db[:passages].insert(document_id: live, urn: "u:1:2", sequence: 1, language: "grc",
                           text: "t", text_normalized: "t", content_sha256: "d", withdrawn: true)
      db[:passages].insert(document_id: gone, urn: "u:2:1", sequence: 0, language: "grc",
                           text: "t", text_normalized: "t", content_sha256: "e")

      Sequel::Migrator.run(db, Nabu::Store::MIGRATIONS_DIR)

      row = db[:source_stats].first(source_id: source_id)
      assert_equal 1, row[:live_documents]
      assert_equal 1, row[:live_passages], "withdrawn passages and withdrawn docs' passages excluded"
      assert_equal 1, row[:withdrawn_documents]
      assert_equal({ "open" => 1 }, JSON.parse(row[:license_overrides_json]))
      assert_equal "migration 019 backfill", row[:note]
      assert_equal [[source_id, "grc", 1, 1]],
                   db[:source_stats_languages].select_map(%i[source_id language documents passages])
    end

    # A minimal in-memory adapter: yields the given refs (retained or live)
    # and parses back the paired documents — enough to drive the retention
    # path through Loader#load_from.
    class StubAdapter < Nabu::Adapter
      def initialize(docs:)
        @docs = docs
        super()
      end

      def self.manifest
        Nabu::SourceManifest.new(
          id: "stub", name: "Stub", license: "CC0", license_class: "open",
          upstream_url: "https://example.invalid/", parser_family: "plaintext"
        )
      end

      def discover_with_attic(_workdir, on_superseded: nil) # rubocop:disable Lint/UnusedMethodArgument -- the Loader passes it; retention rides ref metadata here
        @docs.map do |doc, ref|
          ref || Nabu::DocumentRef.new(source_id: "stub", id: doc.urn, path: "#{doc.urn}.xml", metadata: {})
        end
      end

      def parse(ref)
        @docs.keys.find { |doc| doc.urn == ref.id } || raise(Nabu::ParseError, "unknown #{ref.id}")
      end
    end
  end
end
