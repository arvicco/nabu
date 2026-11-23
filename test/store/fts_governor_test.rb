# frozen_string_literal: true

require "test_helper"
require "logger"
require "stringio"
require "tmpdir"

module Store
  # Nabu::Store::Indexer::FtsGovernor — our code owns the merge schedule
  # during every governed bulk write. The 2026-11-11 stall: a 3.77M-row
  # refresh's insert flood outran automerge, a level reached crisismerge
  # (16 segments) and the engine merged it TO COMPLETION inside one
  # sqlite3_step (3h+, 26 GB of WAL). The governor holds every level at
  # half that line and the total far under the 2000-segment hard cap, so
  # neither engine heuristic ever finds a mountain.
  class FtsGovernorTest < Minitest::Test
    include StoreTestDB

    Indexer = Nabu::Store::Indexer
    Structure = Nabu::Store::FtsStructure::Structure

    Spy = Struct.new(:stages) do
      def stage(label, **) = (self.stages ||= []) << label
      def load_tick(*); end
    end

    def setup
      @catalog = store_test_db
      @fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
      @source = Nabu::Store::Source.create(slug: "s", name: "S", adapter_class: "TestAdapter",
                                           license_class: "open")
    end

    def teardown
      @fulltext.disconnect
    end

    # -- the decision (fabricated structures) ------------------------------

    def structure(*segment_counts)
      seg = { segid: 1, pgno_first: 1, pgno_last: 1, tombstone_pages: 0, entry_tombstones: 0, entries: 0 }
      levels = segment_counts.map { |count| { merge: 0, segments: Array.new(count) { seg } } }
      Structure.new(cookie: 0, v2: true, write_counter: 0, levels: levels,
                    total_segments: segment_counts.sum)
    end

    def pressure(struct, **limits)
      Indexer.governor_pressure(struct, level_limit: limits.fetch(:level, 8), total_limit: limits.fetch(:total, 1200))
    end

    def test_a_level_over_the_limit_is_pressure
      found = pressure(structure(3, 9, 2))

      assert_equal({ level: 1, segments: 9 }, found)
    end

    def test_the_total_over_the_line_is_pressure_even_with_every_level_under
      found = pressure(structure(6, 6, 6), total: 15)

      assert_equal({ total: 18 }, found)
    end

    def test_under_both_limits_is_no_pressure
      assert_nil pressure(structure(8, 8, 1)), "AT the limit is fine — only past it fires"
      assert_nil pressure(nil), "an absent structure record is no pressure"
    end

    def test_the_limits_sit_far_from_the_engine_triggers
      assert_equal 8, Indexer::GOVERNOR_LEVEL_LIMIT, "half of the engine's crisismerge 16"
      assert_equal 25, Indexer::GOVERNOR_CHECK_EVERY_BATCHES
      assert_operator Nabu::Store::FtsStructure::SEGMENT_WARN, :<, 2000
    end

    # -- the live loop against a real contentless table --------------------

    def create_flood_table
      @fulltext.run(Indexer::CREATE_TABLE)
      # TEST-ONLY: automerge off makes every committed insert flush one
      # level-0 segment and nothing consolidate on its own — the
      # deterministic flood the governor must keep bounded. Production
      # never touches automerge (the 2026-10-01 wedge).
      @fulltext[:passages_fts].insert(passages_fts: "automerge", rank: 0)
    end

    def flood_row(id) = { rowid: id, text_normalized: "word#{id} common", language: "0langgrc", source: "0srcs" }

    def sql_log
      io = StringIO.new
      logger = Logger.new(io)
      @fulltext.loggers << logger
      yield
      io.string
    ensure
      @fulltext.loggers.delete(logger)
    end

    def merge_statements(log) = log.lines.grep(/'merge', #{Indexer::MERGE_CHUNK_PAGES}/o)

    def test_the_governor_consolidates_a_flooded_level_in_bounded_chunks
      create_flood_table
      spy = Spy.new([])
      governor = Indexer::FtsGovernor.new(fulltext: @fulltext, table: :passages_fts, progress: spy,
                                          cadence: 1, level_limit: 4, total_limit: 1200)
      log = sql_log do
        (1..24).each do |id|
          @fulltext.transaction { @fulltext[:passages_fts].insert(flood_row(id)) }
          governor.tick!
        end
      end

      announced = /fts governor: passages_fts — level \d+ at \d+ segments, consolidating/

      assert(spy.stages.any? { |label| label.match?(announced) },
             "the governor announces what it found (got #{spy.stages.inspect})")
      refute_empty merge_statements(log), "the relief is positive ('merge', N) chunks"
      assert_equal merge_statements(log).size, governor.relief_chunks
      final = Nabu::Store::FtsStructure.read(@fulltext, :passages_fts)

      assert_operator final.total_segments, :<, 24, "fewer segments than the ungoverned flood's 24"
      assert(final.levels.all? { |level| level[:segments].size <= 4 },
             "every level is back under the limit")
      assert_equal 24, @fulltext[:passages_fts].count, "merges never lose a row"
    end

    # rebuild!'s streaming pass holds one wrapping transaction: relief
    # chunks still run there, but no checkpoint is attempted (it could not
    # reclaim an open transaction's frames).
    def test_relief_inside_a_transaction_merges_but_skips_the_checkpoint
      create_flood_table
      6.times { |i| @fulltext.transaction { @fulltext[:passages_fts].insert(flood_row(i + 1)) } }
      governor = Indexer::FtsGovernor.new(fulltext: @fulltext, table: :passages_fts, cadence: 1,
                                          level_limit: 2, total_limit: 1200)
      checkpoints = 0
      original = Indexer.method(:checkpoint_wal!)
      Indexer.define_singleton_method(:checkpoint_wal!) do |*args, **kw|
        checkpoints += 1
        original.call(*args, **kw)
      end
      begin
        @fulltext.transaction { governor.tick! }
      ensure
        Indexer.define_singleton_method(:checkpoint_wal!, original)
      end

      assert_operator governor.relief_chunks, :>, 0
      assert_equal 0, checkpoints
      assert_operator Nabu::Store::FtsStructure.read(@fulltext, :passages_fts).total_segments, :<, 6
    end

    # -- the recorded fts_relief stage (the relief-debt forecast) ----------
    # Each relief is ledgered as stage "fts_relief" (kind "sync", scope
    # the table) with rows = the over-limit level's page count, read from
    # the same O(1) structure record the pressure decision read BEFORE
    # relief started — so StageTimings accumulates a seconds-per-page rate
    # and a big append's relief debt becomes a priced line.

    def with_ledger
      dir = Dir.mktmpdir("nabu-relief")
      ledger = Nabu::Store::Ledger.open!(File.join(dir, "history.sqlite3"))
      yield ledger
    ensure
      ledger&.disconnect
      FileUtils.rm_rf(dir) if dir
    end

    def relief_rows(ledger)
      ledger[Nabu::Store::StageTimings::TABLE].where(stage: "fts_relief").order(:id).all
    end

    def test_a_relief_records_the_over_limit_levels_pages_read_before_it_started
      create_flood_table
      6.times { |i| @fulltext.transaction { @fulltext[:passages_fts].insert(flood_row(i + 1)) } }
      before = Nabu::Store::FtsStructure.read(@fulltext, :passages_fts)
      found = Indexer.governor_pressure(before, level_limit: 2, total_limit: 1200)
      expected = before.levels[found[:level]][:segments].sum { |seg| seg[:pgno_last] - seg[:pgno_first] + 1 }
      with_ledger do |ledger|
        governor = Indexer::FtsGovernor.new(fulltext: @fulltext, table: :passages_fts, cadence: 1,
                                            level_limit: 2, total_limit: 1200, ledger: ledger)
        chunks = governor.check!

        assert_operator chunks, :>, 0
        rows = relief_rows(ledger)
        assert_equal 1, rows.size, "one relief, one row"
        assert_equal %w[sync passages_fts], [rows.first[:kind], rows.first[:scope]]
        assert_equal expected, rows.first[:rows]
        assert_operator expected, :>, 0
        assert_operator rows.first[:seconds], :>=, 0
        assert_in_delta rows.first[:seconds] / expected, Nabu::Store::StageTimings.rate(ledger, kind: "sync",
                                                                                                stage: "fts_relief")
      end
    end

    def test_the_total_line_relief_records_the_whole_structures_pages
      create_flood_table
      6.times { |i| @fulltext.transaction { @fulltext[:passages_fts].insert(flood_row(i + 1)) } }
      expected = Nabu::Store::FtsStructure.read(@fulltext, :passages_fts).pages
      with_ledger do |ledger|
        Indexer::FtsGovernor.new(fulltext: @fulltext, table: :passages_fts, level_limit: 100, total_limit: 3,
                                 ledger: ledger).check!

        assert_equal([expected], relief_rows(ledger).map { |row| row[:rows] })
      end
    end

    def test_a_calm_structure_records_no_relief
      create_flood_table
      2.times { |i| @fulltext.transaction { @fulltext[:passages_fts].insert(flood_row(i + 1)) } }
      with_ledger do |ledger|
        Indexer::FtsGovernor.new(fulltext: @fulltext, table: :passages_fts, ledger: ledger).check!

        assert_empty relief_rows(ledger)
      end
    end

    # Recording only: the relief a ledger-less governor runs is the very
    # same merge sequence (no behavior change to relief itself).
    def test_the_recorder_leaves_the_relief_itself_unchanged
      runs = [nil, :ledger].map do |mode|
        @fulltext.drop_table?(:passages_fts)
        create_flood_table
        6.times { |i| @fulltext.transaction { @fulltext[:passages_fts].insert(flood_row(i + 1)) } }
        relieve = lambda do |ledger|
          governor = Indexer::FtsGovernor.new(fulltext: @fulltext, table: :passages_fts, level_limit: 2,
                                              total_limit: 1200, ledger: ledger)
          log = sql_log { governor.check! }
          [governor.relief_chunks, merge_statements(log).size,
           Nabu::Store::FtsStructure.read(@fulltext, :passages_fts).levels.map { |level| level[:segments].size }]
        end
        mode ? with_ledger { |ledger| relieve.call(ledger) } : relieve.call(nil)
      end

      assert_equal runs.first, runs.last
    end

    # The refresh path's eager consolidation threads its ledger through.
    def test_the_eager_consolidation_records_its_relief
      create_flood_table
      6.times { |i| @fulltext.transaction { @fulltext[:passages_fts].insert(flood_row(i + 1)) } }
      with_ledger do |ledger|
        Indexer.eager_consolidate!(@fulltext, level_limit: 2, ledger: ledger)

        assert_equal 1, relief_rows(ledger).size
      end
    end

    def test_small_writes_cost_one_structure_read_per_cadence_and_no_merges
      @fulltext.run(Indexer::CREATE_TABLE)
      governor = Indexer::FtsGovernor.new(fulltext: @fulltext, table: :passages_fts)
      reads = 0
      original = Nabu::Store::FtsStructure.method(:read)
      Nabu::Store::FtsStructure.define_singleton_method(:read) do |*args|
        reads += 1
        original.call(*args)
      end
      log = nil
      begin
        # The small write's real shape: its batches inside the slice's
        # one atomic transaction.
        log = sql_log do
          @fulltext.transaction do
            (1..30).each do |id|
              @fulltext[:passages_fts].insert(flood_row(id))
              governor.tick!
            end
          end
        end
      ensure
        Nabu::Store::FtsStructure.define_singleton_method(:read, original)
      end

      assert_equal 1, reads, "30 batches at the default cadence of 25 = one structure read"
      assert_empty merge_statements(log), "a healthy structure never draws a merge"
      assert_equal 0, governor.relief_chunks
    end

    # -- the wiring: who gets governed -------------------------------------

    def make_passage(urn:, text:, sequence:, language: "grc")
      @doc ||= Nabu::Store::Document.create(source_id: @source.id, urn: "urn:d:s", title: "t", language: "grc",
                                            content_sha256: "x", revision: 1, withdrawn: false)
      Nabu::Store::Passage.create(document_id: @doc.id, urn: urn, sequence: sequence, language: language,
                                  text: text, text_normalized: text, content_sha256: "x", revision: 1,
                                  withdrawn: false, annotations_json: "{}")
    end

    def observing_governors
      governors = []
      original = Indexer.method(:fts_governor)
      Indexer.define_singleton_method(:fts_governor) do |*args, **kwargs|
        original.call(*args, **kwargs).tap { |governor| governors << governor if governor }
      end
      yield governors
    ensure
      Indexer.define_singleton_method(:fts_governor, original)
    end

    def test_the_rebuild_and_both_refresh_shapes_govern_the_contentless_tables
      make_passage(urn: "urn:d:s:1", text: "alpha", sequence: 0)
      make_passage(urn: "urn:d:s:2", text: "王道", sequence: 1, language: "lzh")
      observing_governors do |governors|
        Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext, cjk_slugs: ["s"])

        assert_equal %i[passages_fts passages_cjk], governors.map(&:table).uniq.sort.reverse,
                     "the rebuild-scale pass governs both contentless tables"
        assert(governors.all? { |governor| governor.batches.positive? }, "every governed loop ticks")

        governors.clear
        Indexer.refresh_source!(catalog: @catalog, fulltext: @fulltext, slug: "s", cjk_slugs: ["s"])

        assert_includes governors.map(&:table), :passages_fts, "the ordinary slice refresh is governed"
        refute_includes governors.map(&:table), :passages_cjk,
                        "the cjk lane is rebuild-cadence — a refresh never writes (or governs) it"

        governors.clear
        Indexer.refresh_source!(catalog: @catalog, fulltext: @fulltext, slug: "s", cjk_slugs: ["s"],
                                bulk_threshold: 1)

        assert_includes governors.map(&:table), :passages_fts, "the bulk slice refresh is governed"
      end
    end

    def test_a_legacy_contentful_table_never_gets_a_governor_pass
      make_passage(urn: "urn:d:s:1", text: "alpha", sequence: 0)
      Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext)
      @fulltext.drop_table(:passages_fts)
      @fulltext.run(<<~SQL)
        CREATE VIRTUAL TABLE passages_fts USING fts5(
          text_normalized, language, source, urn UNINDEXED, passage_id UNINDEXED,
          tokenize = 'unicode61 remove_diacritics 2'
        )
      SQL

      assert_nil Indexer.fts_governor(@fulltext, :passages_fts)
      observing_governors do |governors|
        Indexer.refresh_source!(catalog: @catalog, fulltext: @fulltext, slug: "s", bulk_threshold: 1)

        assert_empty governors, "the contentful legacy shape keeps the old untouched path"
      end
    end
  end
end
