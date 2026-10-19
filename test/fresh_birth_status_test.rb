# frozen_string_literal: true

require "test_helper"

# Every status surface and desk fallback chain that reads the catalog, pinned
# against a JUST-MIGRATED EMPTY database (test/support/fresh_birth.rb) — the
# state a rebuild's drop leaves, and the state a rebuild that died in its
# index stage leaves on the fulltext side. The class these tests kill: a
# fallback path that turns ABSENCE into ZERO (or into silence), or a status
# claim derived from db/ that forgets a durable fact the permanent folders
# (the ledger, canonical/) still carry.
#
# A new status surface or absent-index hint gets its *_fresh_db_status test
# here, at birth.
class FreshBirthStatusTest < Minitest::Test
  include FreshBirth

  # -- nabu status: the compact holdings cell ---------------------------------

  # A row whose sources row does not exist in this catalog was never loaded
  # here: every content kind reads "—". The shelf kinds count catalog-wide
  # tables, so before this guard a never-loaded shelf printed "0" — the
  # shelf's absence masked as an empty shelf.
  def test_never_loaded_rows_of_every_kind_read_dash_fresh_db_status
    registry = load_registry(<<~YAML)
      corpus:
        adapter: TestAdapter
      lang-shelf:
        adapter: Nabu::Adapters::LocalLanguage
        kind: shelf
      notes-shelf:
        adapter: Nabu::Adapters::LocalNotes
        kind: shelf
    YAML

    out = Nabu::StatusReport.render(registry: registry, db: fresh_catalog, ledger: fresh_ledger)

    %w[corpus lang-shelf notes-shelf].each do |slug|
      line = out.lines.find { |l| l.start_with?("#{slug} ") }
      assert_match(/—/, line, "#{slug}: a never-loaded row reads absent")
      refute_match(/\s0\s*$/, line, "#{slug}: never a zero for a row this catalog never loaded")
    end
  end

  # The healthy path is unchanged: a LOADED shelf row still counts its rows,
  # zero included (a loaded-but-empty shelf genuinely holds nothing).
  def test_a_loaded_shelf_row_still_counts_fresh_db_status
    catalog = fresh_catalog
    registry = load_registry(<<~YAML)
      notes-shelf:
        adapter: Nabu::Adapters::LocalNotes
        kind: shelf
    YAML
    registry["notes-shelf"].sync_source!(catalog)

    out = Nabu::StatusReport.render(registry: registry, db: catalog, ledger: fresh_ledger)
    assert_match(/^notes-shelf\s+shelf\s+0\s/, out)
  end

  # -- nabu status: durable facts outside db/ ----------------------------------

  # The run history lives in the LEDGER, which a rebuild never drops: a
  # fresh catalog must still report the last sync and its status from it.
  def test_last_sync_reads_the_surviving_ledger_fresh_db_status
    ledger = fresh_ledger
    finished = Time.now - 3600
    ledger[:runs].insert(source_slug: "corpus", kind: "sync", started_at: finished - 60,
                         loaded_at: finished - 10, finished_at: finished, added: 3, status: "succeeded")
    registry = load_registry("corpus:\n  adapter: TestAdapter\n")

    detail = Nabu::StatusReport.render_source(registry: registry, db: fresh_catalog, ledger: ledger, slug: "corpus")

    assert_match(/last sync:\s+#{finished.strftime('%Y-%m-%d %H:%M')}/, detail)
    assert_match(/status:\s+succeeded/, detail)
  end

  # A kind: module's holding is its canonical tree, not a catalog pin a
  # rebuild resets: held on disk reads held on a fresh catalog; only a
  # missing tree reads "not synced".
  def test_a_held_module_reads_held_on_a_fresh_catalog_fresh_db_status
    canonical = fresh_canonical_dir
    FileUtils.mkdir_p(File.join(canonical, "amod"))
    File.write(File.join(canonical, "amod", "data.yml"), "x: 1\n")
    registry = load_registry(<<~YAML)
      amod:
        adapter: TestAdapter
        kind: module
      bmod:
        adapter: TestAdapter
        kind: module
    YAML
    catalog = fresh_catalog

    held = Nabu::StatusReport.render_source(registry: registry, db: catalog, ledger: fresh_ledger,
                                            slug: "amod", canonical_dir: canonical)
    missing = Nabu::StatusReport.render_source(registry: registry, db: catalog, ledger: fresh_ledger,
                                               slug: "bmod", canonical_dir: canonical)

    assert_match(/holds:\s+module \(held\)/, held)
    assert_match(/holds:\s+module \(not synced\)/, missing)
  end

  # -- nabu health: the instrument that disconfirms -----------------------------

  # The ledger says a sync succeeded; the fresh catalog holds nothing. That
  # is the half-loaded signature and must be LOUD — never a quiet zero.
  def test_a_succeeded_run_over_an_empty_catalog_is_loud_fresh_db_status
    ledger = fresh_ledger
    ledger[:runs].insert(source_slug: "corpus", kind: "sync", started_at: Time.now, finished_at: Time.now,
                         added: 3, status: "succeeded")
    registry = load_registry("corpus:\n  adapter: TestAdapter\n")
    checker = Nabu::Health::Invariants.new(registry: registry, catalog: fresh_catalog, fulltext: nil, ledger: ledger)

    finding = checker.for_source(registry["corpus"]).compact.find { |f| f.kind == :synced_unpopulated }
    refute_nil finding
    assert_equal :loud, finding.severity
  end

  # A run that died after its load (open row: running + loaded_at) is not a
  # "succeeded" one — the populated-check must not read it as a success
  # promising rows, and status must show the word.
  def test_an_open_run_row_never_reads_succeeded_fresh_db_status
    ledger = fresh_ledger
    ledger[:runs].insert(source_slug: "corpus", kind: "sync", started_at: Time.now - 60,
                         loaded_at: Time.now - 30, status: "running")
    registry = load_registry("corpus:\n  adapter: TestAdapter\n")

    detail = Nabu::StatusReport.render_source(registry: registry, db: fresh_catalog, ledger: ledger, slug: "corpus")
    assert_match(/status:\s+running/, detail)
  end

  # -- the MCP status tool --------------------------------------------------------

  def test_mcp_status_answers_on_a_fresh_catalog_fresh_db_status
    catalog = fresh_catalog
    result = Nabu::MCP::Tools.new(catalog: catalog, fulltext: nil).call("nabu_status", {})

    refute result[:isError]
    assert_equal [], JSON.parse(result[:content][0][:text]).fetch("sources")
  end

  # -- desk fallback chains: precompiled tables, never a scan -----------------------

  def test_language_census_reads_unbuilt_fresh_db_status
    census = Nabu::Query::LanguageCensus.new(catalog: fresh_catalog)

    assert_equal :unbuilt, census.curve("grc").status
    assert_equal :unbuilt, census.mixing.status
  end

  def test_lemma_profile_reads_unbuilt_fresh_db_status
    assert_equal :unbuilt, Nabu::Query::LemmaProfile.new(catalog: fresh_catalog).run("λόγος").status
  end

  # Empty derived indexes mean "not yet derived", never "the authority holds
  # nothing" — their readers fall back on that predicate.
  def test_place_and_person_indexes_read_unpopulated_fresh_db_status
    catalog = fresh_catalog

    refute Nabu::Store::PlaceIndex.populated?(catalog)
    refute Nabu::Store::PersonIndex.populated?(catalog)
  end

  # The char card's corpus panel reads ONLY the precompiled postings: an
  # absent index answers nil (the CLI's not-indexed hint) — and so must a
  # born-empty one. Before this guard the bare table answered {} and the
  # panel went silent, as if no passage carried the glyph.
  def test_char_card_corpus_is_unindexed_absent_or_born_empty_fresh_db_status
    catalog = fresh_catalog
    [nil, born_empty_fulltext].each do |fulltext|
      card = Nabu::Query::Char.new(catalog: catalog, fulltext: fulltext).run("中")
      label = fulltext ? "born-empty" : "absent"
      assert_nil card.corpus, "#{label} postings: not indexed, never an empty attestation"
      assert_nil card.corpus_by_source, "#{label} postings: the per-source split likewise"
    end
  end

  # A born-empty fulltext is not an index the incremental path may extend.
  def test_a_born_empty_fulltext_is_not_incremental_ready_fresh_db_status
    refute Nabu::Store::Indexer.incremental_ready?(born_empty_fulltext)
  end

  # nabu health's corpus state: a catalog with no index is :no_index, never
  # :present.
  def test_local_check_corpus_without_an_index_fresh_db_status
    check = Nabu::Health::LocalCheck.new(registry: load_registry("corpus:\n  adapter: TestAdapter\n"),
                                         catalog: fresh_catalog, fulltext: nil, ledger: fresh_ledger,
                                         golden_queries: [])
    assert_equal :no_index, check.run.corpus
  end

  private

  def load_registry(yaml)
    dir = fresh_canonical_dir
    path = File.join(dir, "sources.yml")
    File.write(path, yaml)
    Nabu::SourceRegistry.load(path)
  end
end
