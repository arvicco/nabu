# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# `nabu rebuild` core (P1-5). Rebuild manages its own file-backed SQLite, so —
# unlike the in-memory store tests — these build a real db file under a tmpdir
# and reconnect to it to inspect the result. TestAdapter is the source; the
# registry is built from a sources.yml written into the tmpdir.
class RebuildTest < Minitest::Test
  # TestAdapter variant that quarantines one specific ref (a "parser
  # regression" on rebuild). Top-level-resolvable via its full nested name.
  class PoisonAdapter < TestAdapter
    def parse(document_ref)
      raise Nabu::ParseError, "poisoned" if document_ref.id == "urn:nabu:test_adapter:bad"

      super
    end
  end

  # A short TestAdapter document: line 1 title, remaining lines passages.
  ILIAD = "Iliad\nμῆνιν\nἄειδε\n"
  ODYSSEY = "Odyssey\nἄνδρα\n"

  def setup
    @root = Dir.mktmpdir("nabu-rebuild")
    @canonical = File.join(@root, "canonical")
    @db_dir = File.join(@root, "db")
    @sources_path = File.join(@root, "sources.yml")
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  # -- acceptance: reproducible modulo ids ---------------------------------

  def test_rebuild_reproduces_identical_passage_rows_modulo_ids
    write_sources(<<~YAML)
      corpus:
        adapter: TestAdapter
        enabled: true
    YAML
    write_canonical("corpus", "one.txt" => ILIAD, "two.txt" => ODYSSEY)

    first = rebuilder.run
    assert_equal %w[corpus], first.outcomes.map(&:slug)
    assert_equal 2, first.outcomes.first.report.added # two documents
    snapshot_before = passage_snapshot
    assert_equal 3, snapshot_before.size # μῆνιν, ἄειδε, ἄνδρα

    second = rebuilder.run

    # A second rebuild off the same canonical dir yields byte-identical passage
    # content, and revisions reset to 1 both times (fresh load, never revised).
    assert_equal snapshot_before, passage_snapshot
    assert(snapshot_before.all? { |row| row.fetch(:revision) == 1 })
    assert_equal %w[corpus], second.outcomes.map(&:slug)
  end

  # -- fulltext index is rebuilt too (P4-1) --------------------------------

  def test_rebuild_populates_the_fulltext_index
    write_sources(<<~YAML)
      corpus:
        adapter: TestAdapter
        enabled: true
    YAML
    write_canonical("corpus", "one.txt" => ILIAD, "two.txt" => ODYSSEY)

    result = rebuilder.run

    assert_equal 3, result.indexed, "μῆνιν, ἄειδε, ἄνδρα indexed"
    with_fulltext do |ft|
      assert_equal 3, ft[:passages_fts].count
      # Diacritic-stripped query finds the polytonic passage (Indexer folds).
      hits = ft[:passages_fts].where(Sequel.lit("passages_fts MATCH ?", "μηνιν")).all
      assert_equal 1, hits.size
    end
  end

  # -- date/place axis is rebuilt from canonical (P15-2) -------------------

  def test_rebuild_regenerates_the_document_axes
    write_sources(<<~YAML)
      corpus:
        adapter: TestAdapter
        enabled: true
    YAML
    write_canonical("corpus", "one.txt" => ILIAD, "two.txt" => ODYSSEY)

    result = rebuilder.run

    # The TestAdapter corpus carries no HGV/goo300k/IMP urns, so zero rows — but
    # the pass RAN (a Summary, so `nabu rebuild` regenerates the axis) and the
    # table exists in the fresh catalog.
    refute_nil result.axes
    assert_equal 0, result.axes.total
    db = Nabu::Store.connect(catalog_path)
    assert db.table_exists?(:document_axes)
    assert_equal 0, db[:document_axes].count
  ensure
    db&.disconnect
  end

  # -- facets are rebuilt from the replayed documents (P17-2) ----------------

  def test_rebuild_regenerates_document_facets_and_edh_axis_end_to_end
    write_sources(<<~YAML)
      edh:
        adapter: Nabu::Adapters::Edh
        enabled: false
        sync_policy: frozen
    YAML
    # The checked-in edh fixture IS the canonical layout — replaying it
    # exercises the whole chain: parse (EAGLE terms + CSV join) → loader
    # (metadata_json) → FacetBuilder (facet rows) + EdhDates (axis rows).
    FileUtils.mkdir_p(@canonical)
    FileUtils.cp_r(Nabu::TestSupport.fixtures("edh"), File.join(@canonical, "edh"))
    FileUtils.rm_f(Dir[File.join(@canonical, "edh", "{README.md,manifest.yml}")])

    result = rebuilder.run

    assert_equal 3, result.outcomes.first.report.added
    refute_nil result.facets
    assert_equal 3, result.facets.documents
    assert_equal 12, result.facets.rows, "genre+province+material+object_type × 3 records"
    assert_equal 3, result.axes.edh
    db = Nabu::Store.connect(catalog_path)
    epitaphs = db[:document_facets].where(facet: "genre", value: "epitaph").count
    assert_equal 1, epitaphs
    assert_equal 12, db[:document_facets].count
  ensure
    db&.disconnect
  end

  def test_rebuild_facets_pass_runs_even_when_nothing_is_faceted
    write_sources(<<~YAML)
      corpus:
        adapter: TestAdapter
        enabled: true
    YAML
    write_canonical("corpus", "one.txt" => ILIAD)

    result = rebuilder.run

    refute_nil result.facets
    assert_equal 0, result.facets.rows
    db = Nabu::Store.connect(catalog_path)
    assert db.table_exists?(:document_facets)
    assert_equal 0, db[:document_facets].count
  ensure
    db&.disconnect
  end

  # -- dry-run touches nothing ---------------------------------------------

  def test_plan_lists_actions_and_changes_nothing
    write_sources(<<~YAML)
      corpus:
        adapter: TestAdapter
      ghost:
        adapter: TestAdapter
    YAML
    write_canonical("corpus", "one.txt" => ILIAD)

    rebuilder.run # build a db first
    path = catalog_path
    before_mtime = File.mtime(path)
    before_bytes = File.binread(path)

    plan = rebuilder.plan

    assert_equal path, plan.db_path
    assert plan.db_exists
    assert_equal [["corpus", :replay], ["ghost", :skip_no_canonical]], plan.items
    # The db file is untouched: same mtime, same bytes.
    assert_equal before_mtime, File.mtime(path)
    assert_equal before_bytes, File.binread(path)
  end

  # -- skip when no canonical data -----------------------------------------

  def test_sources_without_canonical_data_are_skipped
    write_sources(<<~YAML)
      corpus:
        adapter: TestAdapter
      empty-src:
        adapter: TestAdapter
      absent-src:
        adapter: TestAdapter
    YAML
    write_canonical("corpus", "one.txt" => ILIAD)
    FileUtils.mkdir_p(File.join(@canonical, "empty-src")) # exists but empty

    result = rebuilder.run

    assert_equal %w[corpus], result.outcomes.map(&:slug)
    assert_equal %w[absent-src empty-src], result.skips.map(&:slug).sort
    assert(result.skips.all? { |skip| skip.reason == :no_canonical })
    # A skip is not a run: only the replayed source gets a runs row / sources row.
    with_ledger { assert_equal 1, Nabu::Store::Run.count }
    with_db { assert_equal %w[corpus], Nabu::Store::Source.select_order_map(:slug) }
  end

  # -- errored > 0 surfaces a warning --------------------------------------

  def test_quarantined_document_surfaces_a_warning
    write_sources(<<~YAML)
      corpus:
        adapter: RebuildTest::PoisonAdapter
    YAML
    write_canonical("corpus", "good.txt" => ILIAD, "bad.txt" => "Bad\nx\n")

    result = rebuilder.run

    outcome = result.outcomes.fetch(0)
    assert_equal 1, outcome.report.added   # good.txt loaded
    assert_equal 1, outcome.report.errored # bad.txt quarantined
    assert_predicate outcome, :warning?
    assert_equal [outcome], result.warnings
    # The batch still succeeded (quarantine never aborts): a run row exists.
    with_ledger { assert_equal 1, Nabu::Store::Run.where(status: "succeeded").count }
  end

  # -- disabled source with local data is still replayed -------------------

  def test_disabled_source_with_canonical_data_is_replayed
    write_sources(<<~YAML)
      corpus:
        adapter: TestAdapter
        enabled: false
    YAML
    write_canonical("corpus", "one.txt" => ILIAD)

    result = rebuilder.run

    assert_equal %w[corpus], result.outcomes.map(&:slug)
    assert_empty result.skips
    assert_equal 2, passage_snapshot.size
    # sync_source! seeds the row's enabled from the registry entry (disabled).
    with_db { refute Nabu::Store::Source.first(slug: "corpus").enabled }
  end

  # -- dictionary sources replay too (P11-4, the rebuild-safety pin) --------

  def test_rebuild_replays_a_dictionary_source_identically
    write_sources(<<~YAML)
      lexica:
        adapter: Nabu::Adapters::Lexica
        enabled: false
    YAML
    FileUtils.mkdir_p(@canonical)
    FileUtils.cp_r(Nabu::TestSupport.fixtures("lexica"), File.join(@canonical, "lexica"))

    first = rebuilder.run
    assert_equal %w[lexica], first.outcomes.map(&:slug)
    assert_equal 8, first.outcomes.first.report.added
    before = dictionary_snapshot
    refute_empty before.first, "expected dictionary entries after rebuild"

    rebuilder.run

    # db = f(canonical): a second rebuild re-mints ids but reproduces entries
    # and citations byte-identically, revisions reset to 1.
    assert_equal before, dictionary_snapshot
    with_db { assert(Nabu::Store::DictionaryEntry.all.all? { |row| row.revision == 1 }) }
  end

  # -- one succeeded run row per rebuilt source ----------------------------

  def test_writes_one_succeeded_rebuild_run_row_per_rebuilt_source
    write_sources(<<~YAML)
      alpha:
        adapter: TestAdapter
      beta:
        adapter: TestAdapter
    YAML
    # Distinct filenames per source keep the minted urns from colliding on the
    # global documents.urn index (TestAdapter mints urns from the filename).
    write_canonical("alpha", "a.txt" => ILIAD)
    write_canonical("beta", "b.txt" => ODYSSEY)

    result = rebuilder.run

    assert_equal %w[alpha beta], result.outcomes.map(&:slug)
    runs = with_ledger do
      Nabu::Store::Run.order(:id).all.map { |run| [run.source_slug, run.kind, run.status] }
    end
    assert_equal [%w[alpha rebuild succeeded], %w[beta rebuild succeeded]], runs
  end

  # -- the ledger survives rebuild (P7-1) -----------------------------------

  def test_rebuild_never_touches_seeded_ledger_history
    write_sources(<<~YAML)
      corpus:
        adapter: TestAdapter
        enabled: true
    YAML
    write_canonical("corpus", "one.txt" => ILIAD)
    at = Time.utc(2026, 7, 1)
    seed_ledger do
      Nabu::Store::Run.create(source_slug: "corpus", kind: "sync", started_at: at, finished_at: at,
                              added: 5, updated: 1, errored: 0, status: "succeeded")
      Nabu::Store::Pin.create(source_slug: "corpus", repo_url: "https://example/corpus",
                              last_sync_sha: "pinned-sha", license_baseline_sha256: "lic-sha")
      Nabu::Store::Revision.create(urn: "urn:nabu:test_adapter:one:1", event: "revised",
                                   old_sha: "aaa", new_sha: "bbb", at: at)
    end

    rebuilder.run

    with_ledger do
      # The seeded sync history is intact; the rebuild appended its own
      # kind=rebuild run row and nothing else.
      sync_runs = Nabu::Store::Run.where(source_slug: "corpus", kind: "sync").all
      assert_equal 1, sync_runs.size
      assert_equal 5, sync_runs.first.added
      pin = Nabu::Store::Pin.first(source_slug: "corpus")
      assert_equal "pinned-sha", pin.last_sync_sha
      assert_equal "lic-sha", pin.license_baseline_sha256
      assert_equal 1, Nabu::Store::Revision.count, "a replay only inserts: no new durable revisions"
      assert_equal "revised", Nabu::Store::Revision.first.event
      assert_equal 1, Nabu::Store::Run.where(kind: "rebuild").count
    end
    # And the catalog really was rebuilt fresh around it.
    with_db { assert_equal 1, Nabu::Store::Document.where(withdrawn: false).count }
  end

  # -- the links journal survives rebuild (P16-1) ----------------------------

  def test_rebuild_never_touches_the_links_journal_and_edges_still_resolve
    write_sources(<<~YAML)
      corpus:
        adapter: TestAdapter
        enabled: true
    YAML
    write_canonical("corpus", "one.txt" => ILIAD)
    rebuilder.run # first build: the catalog exists, urns minted

    journal = Nabu::Store::LinksJournal.open!(config.links_path)
    run_id = Nabu::Store::LinksJournal.record_run!(
      journal, producer: "parallels", scope: "urn:nabu:test_adapter",
               params: { min_score: 0.05 }, code_version: "t/1"
    )
    Nabu::Store::LinksJournal.write_edge!(
      journal, from_urn: "urn:nabu:test_adapter:one:1", to_urn: "urn:nabu:test_adapter:one:2",
               kind: "parallel", score: 1.5, run_id: run_id
    )
    journal.disconnect
    bytes_before = File.binread(config.links_path)

    rebuilder.run # the catalog is dropped and re-minted; the journal must not move

    assert_equal bytes_before, File.binread(config.links_path),
                 "rebuild leaves the links journal byte-identical"
    # And the urn-keyed edge still resolves against the REBUILT catalog (fresh
    # row ids, same urns) — the reason links are urn-keyed, not id-keyed.
    journal = Nabu::Store::LinksJournal.open_readonly(config.links_path)
    with_db do |db|
      result = Nabu::Query::Links.new(catalog: db, journal: journal).run("urn:nabu:test_adapter:one:1")
      edge = result.groups.fetch("parallel").first
      assert_equal "urn:nabu:test_adapter:one:2", edge.urn
      assert_predicate edge, :resolved?, "the counterpart resolves through the re-minted catalog"
    end
    journal.disconnect
  end

  # Trend continuity across the rebuild boundary: source ids are re-minted by
  # the rebuild, but runs are slug-keyed, so history reads continuously.
  def test_run_history_is_continuous_across_id_reminting
    write_sources(<<~YAML)
      corpus:
        adapter: TestAdapter
        enabled: true
    YAML
    write_canonical("corpus", "one.txt" => ILIAD)

    rebuilder.run
    first_id = with_db { Nabu::Store::Source.first(slug: "corpus").id }
    seed_ledger do
      Nabu::Store::Run.create(source_slug: "corpus", kind: "sync", started_at: Time.now,
                              finished_at: Time.now, added: 2, status: "succeeded")
    end

    rebuilder.run # drops the catalog; the source row is re-minted

    second_id = with_db { Nabu::Store::Source.first(slug: "corpus").id }
    with_ledger do
      slug_runs = Nabu::Store::Run.where(source_slug: "corpus")
      assert_equal 1, slug_runs.where(kind: "sync").count, "sync history crossed the rebuild boundary"
      assert_equal 2, slug_runs.where(kind: "rebuild").count
    end
    # The invariant the slug-keying protects against: ids DO change on rebuild
    # for a fresh file db (both are 1 here — assert only that history never
    # referenced them).
    assert_kind_of Integer, first_id
    assert_kind_of Integer, second_id
  end

  # A pre-P7-1 catalog still carries runs/source_repos: rebuild must lift them
  # into the ledger BEFORE deleting the file, or the history dies with it.
  def test_rebuild_lifts_legacy_history_before_dropping_the_catalog
    write_sources(<<~YAML)
      corpus:
        adapter: TestAdapter
        enabled: true
    YAML
    write_canonical("corpus", "one.txt" => ILIAD)
    build_legacy_catalog

    rebuilder.run

    with_ledger do
      lifted = Nabu::Store::Run.where(source_slug: "corpus", kind: "sync").all
      assert_equal 1, lifted.size, "the legacy catalog's run history was lifted, not dropped"
      assert_equal 9, lifted.first.added
      assert_equal "legacy-sha", Nabu::Store::Pin.first(source_slug: "corpus").last_sync_sha
    end
  end

  # -- helpers -------------------------------------------------------------

  private

  def rebuilder
    Nabu::Rebuild.new(config: config, registry: Nabu::SourceRegistry.load(@sources_path))
  end

  def config
    Nabu::Config.new(
      canonical_dir: @canonical, db_dir: @db_dir,
      sources_path: @sources_path, config_path: "(test)"
    )
  end

  def catalog_path = config.catalog_path

  def write_sources(yaml) = File.write(@sources_path, yaml)

  def write_canonical(slug, files)
    dir = File.join(@canonical, slug)
    FileUtils.mkdir_p(dir)
    files.each { |name, content| File.write(File.join(dir, name), content) }
  end

  # Reconnect to the rebuilt file db and yield it, rebinding the models.
  def with_db
    db = Nabu::Store.connect(catalog_path)
    Nabu::Store.setup!(db)
    yield db
  ensure
    db&.disconnect
  end

  # Reconnect to the history ledger and yield, rebinding the ledger models.
  def with_ledger
    db = Nabu::Store::Ledger.connect(config.history_path)
    Nabu::Store::Ledger.setup!(db)
    yield db
  ensure
    db&.disconnect
  end

  # Create (and migrate) the ledger file, run the seeding block, disconnect.
  def seed_ledger(&)
    db = Nabu::Store::Ledger.open!(config.history_path)
    yield
  ensure
    db&.disconnect
  end

  # A pre-P7-1 catalog file (migrations 001–004: runs/source_repos still in
  # it) seeded with one source + run + last_sync_sha pin.
  def build_legacy_catalog
    FileUtils.mkdir_p(File.dirname(catalog_path))
    db = Nabu::Store.connect(catalog_path)
    require "sequel/extensions/migration"
    Sequel::Migrator.run(db, Nabu::Store::MIGRATIONS_DIR, target: 4,
                                                          allow_missing_migration_files: true)
    sid = db[:sources].insert(slug: "corpus", name: "corpus", adapter_class: "TestAdapter",
                              license_class: "open", upstream_url: "https://example/corpus",
                              last_sync_sha: "legacy-sha")
    db[:runs].insert(source_id: sid, started_at: Time.now, finished_at: Time.now,
                     added: 9, status: "succeeded")
    db.disconnect
  end

  # Reconnect to the rebuilt fulltext index file and yield the handle.
  def with_fulltext
    ft = Nabu::Store.connect_fulltext(config.fulltext_path)
    yield ft
  ensure
    ft&.disconnect
  end

  # Passage rows reduced to the content-bearing columns (ids excluded).
  # Entries + citations modulo re-minted ids: content columns only, citation
  # rows keyed by their owning entry's urn.
  def dictionary_snapshot
    with_db do
      entries = Nabu::Store::DictionaryEntry.order(:urn).all.map do |entry|
        entry.values.slice(:urn, :entry_id, :key_raw, :headword, :headword_folded,
                           :gloss, :body, :content_sha256, :withdrawn)
      end
      citations = Nabu::Store::DictionaryCitation
                  .join(:dictionary_entries, id: :dictionary_entry_id)
                  .order(Sequel[:dictionary_entries][:urn], Sequel[:dictionary_citations][:seq])
                  .select_map([Sequel[:dictionary_entries][:urn], :seq, :urn_raw, :cts_work, :citation, :label])
      [entries, citations]
    end
  end

  def passage_snapshot
    with_db do
      Nabu::Store::Passage.order(:urn).all.map do |passage|
        passage.values.slice(
          :urn, :sequence, :language, :text, :text_normalized,
          :annotations_json, :content_sha256, :revision
        )
      end
    end
  end
end
