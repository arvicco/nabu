# frozen_string_literal: true

require "test_helper"
require "digest"
require "logger"
require "stringio"

module Store
  # The passages_fts write-path classifier (Indexer::REWRITE_CEILING note):
  # a run's fts write is classified by the rows it DELETES from the built
  # structure — none: a capless tail append; up to the ceiling: delete +
  # append in place; past it (or past the ledger-priced shadow): the
  # append-only shadow, unchanged. Every path is pinned against the same
  # oracles: ranked/filtered/folded probe queries answer exactly as a
  # fresh rebuild of the same catalog does (rows AND order AND score),
  # fts5's own integrity-check passes, and the row-sha sidecar's
  # membership equals the table's actual rowids.
  class FtsWritePathTest < Minitest::Test
    include StoreTestDB

    Indexer = Nabu::Store::Indexer

    Spy = Struct.new(:stages) do
      def stage(label, **) = (self.stages ||= []) << label
      def load_tick(*); end
    end

    # Ranked (bm25 order), filtered (the language and source sentinel
    # columns), folded (remove_diacritics: "μηνιν" finds "μῆνιν"), prefix
    # and phrase forms.
    PROBES = [
      "λογοσ",
      "αρετ*",
      '"λογοσ αρετη"',
      "μηνιν",
      %(λογοσ AND language : ("0langgrc")),
      %(αρετη AND language : ("0langlat")),
      %(λογοσ AND source : ("0srcold")),
      %(λογοσ AND source : ("0srcnew")),
      "fresh OR revised"
    ].freeze

    def setup
      @catalog = store_test_db
      @fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
      @ledger = Nabu::Store::Ledger.migrate!(Sequel.sqlite)
    end

    def teardown
      @fulltext.disconnect
      @ledger.disconnect
    end

    # -- fixture --------------------------------------------------------------

    def source(slug)
      Nabu::Store::Source.first(slug: slug) ||
        Nabu::Store::Source.create(slug: slug, name: slug, adapter_class: "TestAdapter", license_class: "open")
    end

    def document(slug)
      urn = "urn:d:#{slug}"
      Nabu::Store::Document.first(urn: urn) ||
        Nabu::Store::Document.create(source_id: source(slug).id, urn: urn, title: "t", language: "grc",
                                     content_sha256: "x", revision: 1, withdrawn: false)
    end

    # Varied lengths and term frequencies, so bm25 orders non-trivially.
    def text_for(seq)
      words = (["λογοσ"] * ((seq % 3) + 1)) + (["αρετη"] * (seq % 2)) + %w[μῆνιν θεα][0, seq % 3] + ["w#{seq}"]
      words.join(" ")
    end

    # +rows+ passages appended to +slug+'s document (multi_insert: the kill
    # test needs more than one BATCH_SIZE of rows).
    def seed(slug, rows, from: 0, language: "grc")
      doc = document(slug)
      @catalog[:passages].multi_insert((from...(from + rows)).map do |seq|
        urn = "#{doc.urn}:#{seq}"
        text = text_for(seq)
        { document_id: doc.id, urn: urn, sequence: seq, language: seq.even? ? language : "lat", text: text,
          text_normalized: text, content_sha256: Digest::SHA256.hexdigest("#{urn}|#{text}"), revision: 1,
          withdrawn: false, annotations_json: "{}" }
      end)
    end

    # Revise the first +count+ of +slug+'s passages (new text, new sha)
    # and withdraw the next +withdraw+.
    def revise(slug, count, withdraw: 0)
      ids = @catalog[:passages].where(document_id: document(slug).id).order(:id).select_map(:id)
      ids.first(count).each do |id|
        text = "revised #{id} λογοσ"
        @catalog[:passages].where(id: id).update(text_normalized: text, text: text,
                                                 content_sha256: Digest::SHA256.hexdigest(text))
      end
      @catalog[:passages].where(id: ids[count, withdraw]).update(withdrawn: true) if withdraw.positive?
    end

    def rebuild!(fulltext = @fulltext) = Indexer.rebuild!(catalog: @catalog, fulltext: fulltext)

    def refresh!(slug, **)
      Indexer.refresh_source!(catalog: @catalog, fulltext: @fulltext, slug: slug, ledger: @ledger, **)
    end

    # The standing corpus: "old" indexed, 40 rows.
    def indexed_corpus
      seed("old", 40)
      rebuild!
    end

    # -- the oracles ----------------------------------------------------------

    def probe(fulltext, query)
      fulltext[:passages_fts].where(Sequel.lit("passages_fts MATCH ?", query))
                             .select(Sequel.lit("rowid").as(:rowid), Sequel.lit("bm25(passages_fts)").as(:score))
                             .order(Sequel.lit("rank"), Sequel.lit("rowid")).all
                             .map { |row| [row[:rowid], row[:score].round(9)] }
    end

    def rowids(fulltext) = fulltext[:passages_fts].select_map(Sequel.lit("rowid")).sort

    def sidecar(fulltext) = fulltext[Indexer::ROW_SHAS_TABLE].select_map(:rowid).sort

    def assert_oracles(path)
      fresh = Nabu::Store.connect_fulltext("sqlite::memory:")
      rebuild!(fresh)
      PROBES.each do |query|
        expected = probe(fresh, query)
        assert_equal expected, probe(@fulltext, query),
                     "after the #{path} path, #{query.inspect} answers as a fresh rebuild (rows, order, score)"
      end
      refute_empty probe(@fulltext, "λογοσ"), "the probes are not vacuous"
      @fulltext[:passages_fts].insert(passages_fts: "integrity-check") # raises on a corrupt index
      assert_equal rowids(fresh), rowids(@fulltext), "after the #{path} path, the identical rowid set"
      assert_equal rowids(@fulltext), sidecar(@fulltext),
                   "after the #{path} path, the sidecar's membership IS the table's rowids"
    ensure
      fresh&.disconnect
    end

    def stage_rows(stage) = @ledger[Nabu::Store::StageTimings::TABLE].where(stage: stage).all

    def path_lines(spy) = spy.stages.grep(/\Afts write path:/)

    def sql_log
      io = StringIO.new
      logger = Logger.new(io)
      @fulltext.loggers << logger
      yield
      io.string
    ensure
      @fulltext.loggers.delete(logger)
    end

    # -- path 1: append (nothing deleted) ---------------------------------------

    def test_a_new_source_appends_with_no_row_cap_and_no_delete
      indexed_corpus
      seed("new", 30)
      spy = Spy.new([])
      log = sql_log { refresh!("new", rewrite_ceiling: 0, progress: spy) }

      assert_equal ["fts write path: new — append (30 written, 0 deleted; forecast n/a)"], path_lines(spy),
                   "deleted == 0 appends even at a 0-row ceiling — written rows never pick the path"
      refute_match(/DELETE FROM `passages_fts`/, log, "a pure tail append issues no fts delete")
      refute(spy.stages.any? { |line| line.include?("shadow build") }, spy.stages.inspect)
      assert_equal [["new", 30]], stage_rows("fts_append").map { |row| [row[:scope], row[:rows]] },
                   "the path is ledgered with its timing and the rows it wrote"
      assert_empty stage_rows("fts_shadow")
      assert_oracles(:append)
    end

    def test_a_delta_of_pure_additions_appends
      indexed_corpus
      seed("old", 5, from: 40)
      delta = Nabu::Store::IndexDelta.new
      @catalog[:passages].where { sequence >= 40 }.select_map(%i[id urn]).each { |id, urn| delta.upsert(id, urn) }
      spy = Spy.new([])
      refresh!("old", delta: delta, progress: spy)

      assert_equal ["fts write path: old — append (5 written, 0 deleted; forecast n/a)"], path_lines(spy)
      assert_oracles(:append)
    end

    # The eager consolidation: the append's segments are consolidated on
    # OUR clock by the governor's own bounded chunks until every level is
    # back at or under its limit — BEFORE the one-chunk merge probe.
    def test_the_append_consolidates_eagerly_back_under_the_governor_limit
      indexed_corpus
      # TEST-ONLY engine config: automerge off so each committed refresh
      # leaves its own level-0 segment, usermerge 2 so a positive merge
      # may consolidate a fixture-sized level (production never touches
      # either). The limit is lowered to 1 for the same reason.
      @fulltext[:passages_fts].insert(passages_fts: "automerge", rank: 0)
      @fulltext[:passages_fts].insert(passages_fts: "usermerge", rank: 2)
      spy = Spy.new([])
      merges = []
      original = Indexer.method(:merge_chunk!)
      Indexer.define_singleton_method(:merge_chunk!) do |*args|
        original.call(*args).tap { |changes| merges << [spy.stages.last, changes] }
      end
      begin
        3.times do |i|
          seed("new#{i}", 3)
          refresh!("new#{i}", consolidation_limit: 1, progress: spy)
        end
      ensure
        Indexer.define_singleton_method(:merge_chunk!, original)
      end

      assert(spy.stages.any? { |line| line.match?(/\Afts governor: passages_fts — level 0 at 2 segments/) },
             "the eager loop announces the pressure it relieves (#{spy.stages.inspect})")
      eager = merges.select { |stage, _| stage.start_with?("fts governor") }
      refute_empty eager, "the relief ran positive merge chunks"
      assert_operator eager.first.last, :>=, Indexer::MERGE_NOOP_LINE, "the first relief chunk merged for real"
      relief = spy.stages.index { |line| line.start_with?("fts governor") }
      probe = spy.stages.each_index.find { |i| i > relief && spy.stages[i].include?("merge consolidation probe") }
      assert_operator relief, :<, probe, "the eager relief runs before that refresh's one-chunk probe"
      structure = Nabu::Store::FtsStructure.read(@fulltext, :passages_fts)
      assert(structure.levels.all? { |level| level[:segments].size <= 1 },
             "every level is back at or under the (lowered) governor limit")
      assert_equal 3, stage_rows("fts_append").size
      assert_oracles(:append)
    end

    # -- path 2: rewrite (0 < deleted ≤ ceiling) ---------------------------------

    def test_a_revision_at_the_ceiling_rewrites_in_place
      indexed_corpus
      revise("old", 6, withdraw: 4)
      seed("old", 2, from: 40)
      spy = Spy.new([])
      refresh!("old", rewrite_ceiling: 40, progress: spy)

      # Whole-slice grain: the 40 indexed rows go, the 38 live rows return.
      assert_equal ["fts write path: old — rewrite (38 written, 40 deleted; forecast rewrite unpriced vs " \
                    "shadow unpriced)"], path_lines(spy)
      assert_equal [["old", 78]], stage_rows("fts_rewrite").map { |row| [row[:scope], row[:rows]] },
                   "the rewrite ledgers the rows it touched (deleted + written)"
      assert_empty stage_rows("fts_shadow")
      assert_oracles(:rewrite)
    end

    def test_a_delta_revision_counts_only_the_indexed_rows_it_dooms
      indexed_corpus
      revise("old", 3)
      seed("old", 2, from: 40)
      delta = Nabu::Store::IndexDelta.new
      ids = @catalog[:passages].order(:id).select_map(%i[id urn])
      (ids.first(3) + ids.last(2)).each { |id, urn| delta.upsert(id, urn) }
      spy = Spy.new([])
      refresh!("old", delta: delta, progress: spy)

      assert_equal ["fts write path: old — rewrite (5 written, 3 deleted; forecast rewrite unpriced vs " \
                    "shadow unpriced)"], path_lines(spy),
                   "two of the five changed ids are new — the sidecar says the index never held them"
      assert_oracles(:rewrite)
    end

    # -- path 3: shadow (past the ceiling, or past its forecast) ------------------

    def test_past_the_ceiling_the_shadow_runs_unchanged
      indexed_corpus
      revise("old", 6, withdraw: 4)
      spy = Spy.new([])
      refresh!("old", rewrite_ceiling: 39, progress: spy)

      assert_equal ["fts write path: old — shadow (36 written, 40 deleted; forecast n/a)"], path_lines(spy)
      assert(spy.stages.any? { |line| line.include?("passages_fts shadow build") }, spy.stages.inspect)
      assert_equal([["old", 36]], stage_rows("fts_shadow").map { |row| [row[:scope], row[:rows]] })
      assert_empty stage_rows("fts_rewrite")
      assert_equal 0, Nabu::Store::FtsStructure.gauges(@fulltext, :passages_fts)[:tombstone_pages]
      assert_oracles(:shadow)
    end

    # The ledger prices both sides: a rewrite whose last rated run says it
    # would cost more than the whole shadow takes the shadow.
    def plant_rates(rewrite:, shadow:)
      timings = Nabu::Store::StageTimings
      timings.record!(@ledger, kind: "sync", scope: "elsewhere", stage: "fts_rewrite", seconds: rewrite, rows: 1)
      timings.record!(@ledger, kind: "sync", scope: "corpus", stage: "fts_shadow", seconds: shadow, rows: 1)
    end

    def test_a_rewrite_forecast_past_the_shadow_forecast_flips_to_the_shadow
      indexed_corpus
      revise("old", 6, withdraw: 4)
      plant_rates(rewrite: 10.0, shadow: 1.0)
      spy = Spy.new([])
      refresh!("old", progress: spy)

      # rewrite: (40 deleted + 36 written) × 10 s; shadow: (40 indexed − 40 + 36) × 1 s.
      assert_equal ["fts write path: old — shadow (36 written, 40 deleted; forecast rewrite ~12m40s vs " \
                    "shadow ~36.0s)"], path_lines(spy)
      assert_equal 2, stage_rows("fts_shadow").size, "the planted row plus the run's own"
      assert_oracles(:shadow)
    end

    def test_a_cheaper_rewrite_forecast_stays_in_place
      indexed_corpus
      revise("old", 6, withdraw: 4)
      plant_rates(rewrite: 0.1, shadow: 1.0)
      spy = Spy.new([])
      refresh!("old", progress: spy)

      assert_equal ["fts write path: old — rewrite (36 written, 40 deleted; forecast rewrite ~7.6s vs " \
                    "shadow ~36.0s)"], path_lines(spy)
      assert_oracles(:rewrite)
    end

    # -- the sidecar-incomplete fallback (shadow_ready? false) --------------------

    def incomplete_sidecar
      indexed_corpus
      seed("other", 4)
      refresh!("other")
      @fulltext[Indexer::ROW_SHAS_TABLE].where(source_id: source("other").id).delete # predates the sidecar
      revise("old", 6, withdraw: 4)
    end

    def test_an_over_ceiling_write_without_a_complete_sidecar_writes_in_place_announced
      incomplete_sidecar
      spy = Spy.new([])
      refresh!("old", rewrite_ceiling: 0, progress: spy)

      line = path_lines(spy).first.to_s
      assert_match(%r{\Afts write path: old — fallback \(36 written, 40 deleted; forecast n/a\) — .*sidecar incomplete},
                   line)
      assert_empty stage_rows("fts_shadow"), "no shadow could name other's membership"
      assert_equal([["old", 76]], stage_rows("fts_rewrite").map { |row| [row[:scope], row[:rows]] })
      assert_equal 4, @fulltext[:passages_fts].where(rowid: @catalog[:passages].where(document_id: document("other").id)
                                                                               .select_map(:id)).count,
                   "other keeps its rows — a shadow would have lost them"
    end

    def test_a_forecast_flip_without_a_complete_sidecar_stays_a_rewrite
      incomplete_sidecar
      plant_rates(rewrite: 10.0, shadow: 1.0)
      spy = Spy.new([])
      refresh!("old", progress: spy)

      assert_match(/\Afts write path: old — rewrite /, path_lines(spy).first.to_s)
      assert_equal 1, stage_rows("fts_shadow").size, "only the planted row — no shadow ran"
    end

    # -- the decision table (the classifier over counts) ----------------------------

    def test_the_decision_table
      indexed_corpus
      old = [source("old").id]
      decide = lambda do |deleted, written: 5, ledger: nil|
        Indexer.fts_write_path(@catalog, @fulltext, member_ids: old, written: written, deleted: deleted,
                                                    ceiling: 10, ledger: ledger).path
      end

      assert_equal :append, decide.call(0, written: 50_000_000), "nothing deleted: append, whatever is written"
      assert_equal :rewrite, decide.call(1)
      assert_equal :rewrite, decide.call(10), "AT the ceiling stays a rewrite"
      assert_equal :shadow, decide.call(11)
      plant_rates(rewrite: 10.0, shadow: 1.0)
      assert_equal :shadow, decide.call(10, ledger: @ledger), "the forecast flip"
      assert_equal :rewrite, decide.call(10), "no ledger, no flip"
      seed("other", 2)
      refresh!("other")
      @fulltext[Indexer::ROW_SHAS_TABLE].where(source_id: source("other").id).delete
      assert_equal :fallback, decide.call(11), "past the ceiling, shadow_ready? false"
      assert_equal :rewrite, decide.call(10, ledger: @ledger), "the flip needs a shadow the sidecar can support"
    end

    # A source whose own slice predates the sidecar cannot vouch for its
    # deletions: every doomed id counts, never a falsely-free append.
    def test_an_unrecorded_own_slice_counts_every_doomed_row
      indexed_corpus
      @fulltext[Indexer::ROW_SHAS_TABLE].where(source_id: source("old").id).delete
      seed("old", 2, from: 40)
      spy = Spy.new([])
      refresh!("old", progress: spy)

      assert_match(/\Afts write path: old — rewrite \(42 written, 42 deleted/, path_lines(spy).first.to_s)
      assert_oracles(:rewrite)
    end

    # The index refresh preflight forecasts exactly what the run decides.
    def test_the_shadow_forecast_follows_the_classifier
      indexed_corpus
      seed("new", 30)
      forecast = lambda do |slugs, **opts|
        Indexer.fts_shadow_forecasts(catalog: @catalog, fulltext: @fulltext, slugs: slugs, **opts)
      end

      assert_empty forecast.call(%w[new], rewrite_ceiling: 0), "an append is never a shadow"
      revise("old", 6, withdraw: 4)
      assert_empty forecast.call(%w[old], rewrite_ceiling: 40)
      assert_equal [["old", 36]], forecast.call(%w[old], rewrite_ceiling: 39).map { |f| [f.scope, f.rows] },
                   "the shadow holds old's 36 live rows; unindexed new has no recorded rows to carry"
      plant_rates(rewrite: 10.0, shadow: 1.0)
      assert_equal %w[old], forecast.call(%w[old], ledger: @ledger).map(&:scope), "the flip is forecast too"
    end

    # -- the kill test ------------------------------------------------------------
    # A bulk run (statement-autocommit batches) killed between batches: the
    # first batch landed whole, the second's fts and lemma rows landed but
    # not its sidecar shas (the one way the sidecar sits BEHIND the index).
    # The table keeps serving; the next run heals — and must count the
    # landed-but-unrecorded tail as deleted, or a "free" append would index
    # those rowids twice.

    def killed_at_the_second_batch(&)
      shas = 0
      original = Indexer.method(:write_row_shas)
      Indexer.define_singleton_method(:write_row_shas) do |*args, **kw|
        shas += 1
        raise Nabu::Error, "simulated kill between batches" if shas == 2

        original.call(*args, **kw)
      end
      begin
        assert_raises(Nabu::Error, &)
      ensure
        Indexer.define_singleton_method(:write_row_shas, original)
      end
    end

    def assert_kill_heals(slug, path)
      assert Indexer.slice_pending?(@fulltext, slug), "the killed run reads pending"
      refute_empty probe(@fulltext, "λογοσ"), "the table stays queryable after the kill"
      @fulltext[:passages_fts].insert(passages_fts: "integrity-check")
      spy = Spy.new([])
      refresh!(slug, bulk_threshold: 1, progress: spy)

      line = path_lines(spy).first.to_s
      assert_match(/\Afts write path: #{slug} — rewrite \(500 written, 500 deleted/, line,
                   "the heal re-does exactly the unrecorded tail, deleting what of it landed (#{path})")
      refute Indexer.slice_pending?(@fulltext, slug), "the next run completes"
      assert_oracles(path)
    end

    def test_a_killed_append_stays_queryable_and_the_next_run_completes
      indexed_corpus
      seed("new", Indexer::BATCH_SIZE + 500)
      killed_at_the_second_batch { refresh!("new", bulk_threshold: 1) }

      assert_kill_heals("new", :append)
    end

    def test_a_killed_rewrite_stays_queryable_and_the_next_run_completes
      seed("old", Indexer::BATCH_SIZE + 500)
      rebuild!
      revise("old", Indexer::BATCH_SIZE + 500)
      killed_at_the_second_batch { refresh!("old", bulk_threshold: 1) }

      assert_kill_heals("old", :rewrite)
    end
  end
end
