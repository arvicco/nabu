# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# `nabu rebuild --incremental` (P36-1). THE INVARIANT IS SACRED: the full
# rebuild remains the reference; an incremental rebuild must land the catalog
# and index in a state content-equivalent to a fresh full rebuild of the same
# canonical tree (counts + content shas — row ids and revision counters are
# bookkeeping full rebuild re-mints by design). Clean sources must be left
# untouched at ROW IDENTITY (same ids, same bytes), not merely same counts.
class RebuildIncrementalTest < Minitest::Test
  ILIAD = "Iliad\nμῆνιν\nἄειδε\n"
  ODYSSEY = "Odyssey\nἄνδρα\n"
  THEOGONY = "Theogony\nμουσάων\n"

  def setup
    @root = Dir.mktmpdir("nabu-incremental")
    @canonical = File.join(@root, "canonical")
    @db_dir = File.join(@root, "db")
    @sources_path = File.join(@root, "sources.yml")
    write_sources(<<~YAML)
      alpha:
        adapter: TestAdapter
      beta:
        adapter: TestAdapter
      lexica:
        adapter: Nabu::Adapters::Lexica
    YAML
    write_canonical("alpha", "a.txt" => ILIAD)
    write_canonical("beta", "b.txt" => ODYSSEY)
    FileUtils.cp_r(Nabu::TestSupport.fixtures("lexica"), File.join(@canonical, "lexica"))
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  # -- stamps: full rebuild writes them ------------------------------------

  def test_full_rebuild_stamps_every_replayed_source
    full_rebuilder.run

    with_db do |db|
      stamps = db[:derivation_stamps].order(:slug).all
      assert_equal(%w[alpha beta lexica], stamps.map { |row| row[:slug] })
      stamps.each do |row|
        assert_match(/\A\h{64}\z/, row[:fingerprint])
        assert_equal latest_migration, row[:migration_level]
        refute_nil row[:stamped_at]
      end
    end
  end

  # -- the sacred invariant ------------------------------------------------

  def test_incremental_skips_clean_sources_and_rederives_only_the_dirty_one
    full_rebuilder.run
    before_alpha = raw_rows(:passages, source: "alpha")
    before_lexica = raw_rows(:dictionary_entries)

    # Dirty ONE source: a changed byte in beta's canonical tree.
    write_canonical("beta", "b.txt" => "Odyssey\nἄνδρα πολύτροπον\n")

    result = incremental_rebuilder.run

    assert_equal %w[beta], result.outcomes.map(&:slug)
    assert_equal %w[alpha lexica], result.cleans.map(&:slug).sort
    # P42-4: a dirty replay shifted the distribution — planner stats refreshed.
    assert_equal "catalog + index", result.analyzed&.scope
    # Clean sources are untouched at ROW IDENTITY: ids, revisions, bytes.
    assert_equal before_alpha, raw_rows(:passages, source: "alpha")
    assert_equal before_lexica, raw_rows(:dictionary_entries)
    # The dirty source really re-derived.
    texts = raw_rows(:passages, source: "beta").map { |row| row[:text] }
    assert_includes texts, "ἄνδρα πολύτροπον"

    # And the final state ≡ a fresh full rebuild of the same tree.
    assert_incremental_state_equals_fresh_full_rebuild
  end

  def test_incremental_with_nothing_dirty_is_a_no_op_on_rows_and_index
    full_rebuilder.run
    before_passages = raw_rows(:passages)
    before_fts = fts_snapshot

    result = incremental_rebuilder.run

    assert_empty result.outcomes
    assert_equal %w[alpha beta lexica], result.cleans.map(&:slug).sort
    assert_equal before_passages, raw_rows(:passages)
    assert_equal before_fts, fts_snapshot
    assert_nil result.axes, "corpus-wide builders must not run when nothing is dirty"
    assert_nil result.facets
    assert_nil result.analyzed, "a clean-swept run touched no rows — no ANALYZE (P42-4)"
  end

  def test_a_missing_stamp_means_dirty
    full_rebuilder.run
    with_db(write: true) { |db| db[:derivation_stamps].where(slug: "beta").delete }

    result = incremental_rebuilder.run

    assert_equal %w[beta], result.outcomes.map(&:slug)
    assert_equal %w[alpha lexica], result.cleans.map(&:slug).sort
    with_db { |db| assert_equal 3, db[:derivation_stamps].count, "the re-derive re-stamps" }
  end

  def test_a_fold_wiring_change_dirties_every_source
    # normalize.rb is the global fold wiring — it stays corpus-wide (P39-1).
    full_rebuilder.run

    result = with_changed_fold_file("normalize.rb") { incremental_rebuilder.run }

    assert_equal %w[alpha beta lexica], result.outcomes.map(&:slug).sort
    assert_empty result.cleans
  end

  # -- fold-digest granularity (P39-1) -------------------------------------

  def test_a_jpn_fold_module_change_dirties_only_jpn_sources
    add_jpn_source
    full_rebuilder.run

    result = with_changed_fold_file("jpn.rb") { incremental_rebuilder.run }

    assert_equal %w[gamma], result.outcomes.map(&:slug)
    assert_equal %w[alpha beta lexica], result.cleans.map(&:slug).sort
  end

  def test_a_hani_fold_module_change_dirties_jpn_sources_too
    # jpn composes THROUGH hani (the generated table bakes Hani.fold in), so
    # a hani change dirties the jpn source; grc/lat sources stay clean.
    add_jpn_source
    full_rebuilder.run

    result = with_changed_fold_file("hani.rb") { incremental_rebuilder.run }

    assert_equal %w[gamma], result.outcomes.map(&:slug)
    assert_equal %w[alpha beta lexica], result.cleans.map(&:slug).sort
  end

  def test_a_dirty_fold_verdict_names_the_changed_module
    add_jpn_source
    full_rebuilder.run

    plan = with_changed_fold_file("jpn.rb") { incremental_rebuilder.plan }

    verdicts = plan.verdicts.to_h { |v| [v.slug, [v.state, v.reason]] }
    assert_equal [:dirty, "fold(jpn.rb)"], verdicts.fetch("gamma")
    assert_equal [:clean, nil], verdicts.fetch("alpha")
  end

  def test_a_schema_behind_catalog_refuses_incremental_loudly
    full_rebuilder.run
    with_db(write: true) { |db| db[:schema_info].update(version: latest_migration - 1) }

    error = assert_raises(Nabu::Error) { incremental_rebuilder.run }
    assert_match(/full rebuild/, error.message)
  end

  def test_no_catalog_refuses_incremental
    error = assert_raises(Nabu::Error) { incremental_rebuilder.run }
    assert_match(/full rebuild/, error.message)
  end

  def test_orphan_rows_for_an_unreplayable_source_refuse_incremental
    full_rebuilder.run
    # The owner deletes a canonical tree: a full rebuild would drop its rows,
    # so an incremental one must refuse rather than silently diverge.
    FileUtils.remove_entry(File.join(@canonical, "beta"))

    error = assert_raises(Nabu::Error) { incremental_rebuilder.run }
    assert_match(/beta/, error.message)
    assert_match(/full rebuild/, error.message)
  end

  # -- dry run -------------------------------------------------------------

  def test_incremental_plan_reports_verdicts_and_touches_nothing
    full_rebuilder.run
    write_canonical("beta", "b.txt" => "Odyssey\nἄνδρα πολύτροπον\n")
    catalog_bytes = File.binread(catalog_path)

    plan = incremental_rebuilder.plan

    assert_nil plan.refusal
    verdicts = plan.verdicts.to_h { |v| [v.slug, [v.state, v.reason]] }
    assert_equal [:clean, nil], verdicts.fetch("alpha")
    assert_equal %i[dirty canonical], verdicts.fetch("beta")
    assert_equal [:clean, nil], verdicts.fetch("lexica")
    assert_equal catalog_bytes, File.binread(catalog_path), "plan must write nothing"
  end

  def test_incremental_plan_reports_the_schema_refusal
    full_rebuilder.run
    with_db(write: true) { |db| db[:schema_info].update(version: latest_migration - 1) }

    plan = incremental_rebuilder.plan

    assert_match(/full rebuild/, plan.refusal)
  end

  # -- helpers -------------------------------------------------------------

  private

  def config(db_dir: @db_dir)
    Nabu::Config.new(
      canonical_dir: @canonical, db_dir: db_dir,
      sources_path: @sources_path, config_path: "(test)"
    )
  end

  def registry = Nabu::SourceRegistry.load(@sources_path)

  def full_rebuilder(db_dir: @db_dir)
    Nabu::Rebuild.new(config: config(db_dir: db_dir), registry: registry)
  end

  def incremental_rebuilder
    Nabu::IncrementalRebuild.new(config: config, registry: registry)
  end

  def catalog_path = config.catalog_path

  def latest_migration = Nabu::DerivationFingerprint.migration_level

  def write_sources(yaml) = File.write(@sources_path, yaml)

  # Register the jpn-minting source beside the shared trio (the granularity
  # tests' CJK counterpart; existing tests keep their exact slug lists).
  def add_jpn_source
    write_sources(<<~YAML)
      alpha:
        adapter: TestAdapter
      beta:
        adapter: TestAdapter
      lexica:
        adapter: Nabu::Adapters::Lexica
      gamma:
        adapter: JpnTestAdapter
    YAML
    write_canonical("gamma", "g.txt" => "草枕\n學問はどこまでも\n")
  end

  # Simulate a content change to ONE fold file (no minitest/mock in this
  # suite): divert its digest; define, yield, restore.
  def with_changed_fold_file(basename)
    singleton = Nabu::DerivationFingerprint.singleton_class
    original = Nabu::DerivationFingerprint.method(:fold_file_digest)
    singleton.define_method(:fold_file_digest) do |path|
      File.basename(path) == basename ? "changed-#{basename}" : original.call(path)
    end
    yield
  ensure
    singleton.define_method(:fold_file_digest, original)
  end

  def write_canonical(slug, files)
    dir = File.join(@canonical, slug)
    FileUtils.mkdir_p(dir)
    files.each { |name, content| File.write(File.join(dir, name), content) }
  end

  def with_db(write: false, db_dir: @db_dir)
    db = Nabu::Store.connect(File.join(db_dir, "catalog.sqlite3"), readonly: !write)
    yield db
  ensure
    db&.disconnect
  end

  # Whole rows (ids, revisions and all) — the row-identity comparator for
  # "clean sources are untouched".
  def raw_rows(table, source: nil, db_dir: @db_dir)
    with_db(db_dir: db_dir) do |db|
      dataset = db[table]
      if source
        source_id = db[:sources].where(slug: source).get(:id)
        dataset = if table == :passages
                    dataset.where(document_id: db[:documents].where(source_id: source_id).select(:id))
                  else
                    dataset.where(source_id: source_id)
                  end
      end
      dataset.order(:id).all
    end
  end

  def fts_snapshot(db_dir: @db_dir)
    ft = Nabu::Store.connect_fulltext(File.join(db_dir, "fulltext.sqlite3"), readonly: true)
    ft[:passages_fts].select_order_map(%i[urn text_normalized])
  ensure
    ft&.disconnect
  end

  # Content-equivalence comparator (modulo re-minted ids/revisions): urn-keyed
  # content columns for documents, passages and dictionary entries, plus the
  # index, axes and facet projections.
  def content_state(db_dir)
    state = with_db(db_dir: db_dir) do |db|
      {
        documents: db[:documents].join(:sources, id: :source_id)
                                 .select_order_map(%i[slug urn language title content_sha256 withdrawn]),
        passages: db[:passages].select_order_map(%i[urn sequence language text text_normalized
                                                    content_sha256 withdrawn]),
        dictionary_entries: db[:dictionary_entries].select_order_map(%i[urn entry_id headword gloss
                                                                        body content_sha256 withdrawn]),
        axes: db[:document_axes].count,
        facets: db[:document_facets].count
      }
    end
    state.merge(fts: fts_snapshot(db_dir: db_dir))
  end

  def assert_incremental_state_equals_fresh_full_rebuild
    fresh_dir = File.join(@root, "db-fresh")
    full_rebuilder(db_dir: fresh_dir).run
    assert_equal content_state(fresh_dir), content_state(@db_dir),
                 "incremental result must be content-equivalent to a fresh full rebuild"
  end
end
