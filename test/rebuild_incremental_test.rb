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
      # Per-source stamps; the __corpus-builders__ sentinel (P89-1) rides the
      # same table and has its own test below.
      stamps = db[:derivation_stamps].exclude(slug: builders_slug).order(:slug).all
      assert_equal(%w[alpha beta lexica], stamps.map { |row| row[:slug] })
      stamps.each do |row|
        assert_match(/\A\h{64}\z/, row[:fingerprint])
        assert_equal latest_migration, row[:migration_level]
        refute_nil row[:stamped_at]
      end
    end
  end

  # P50-r1 (owner ruling D50-a): both rebuild flavors mirror the replay's
  # canonical identity onto the sources row — the last-INGEST record the
  # `nabu data build` stale-ingest guard reads (sync writes the same column).
  def test_replays_record_the_ingest_identity_on_the_sources_row
    full_rebuilder.run
    with_db do |db|
      db[:sources].order(:slug).all.each do |row|
        stamp = db[:derivation_stamps].first(slug: row[:slug])
        assert_equal stamp[:canonical_identity], row[:last_ingest_identity],
                     "#{row[:slug]}: sources.last_ingest_identity must equal the stamp's canonical identity"
      end
    end

    write_canonical("beta", "b.txt" => "Odyssey\nἄνδρα πολύτροπον\n")
    incremental_rebuilder.run
    with_db do |db|
      assert_equal Nabu::DerivationFingerprint.canonical_identity(File.join(@canonical, "beta")),
                   db[:sources].first(slug: "beta")[:last_ingest_identity],
                   "a dirty replay must re-record the identity it just derived from"
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
    with_db do |db|
      assert_equal 3, db[:derivation_stamps].exclude(slug: builders_slug).count,
                   "the re-derive re-stamps"
    end
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

  # -- P89-1 (№R-54 (c)): the corpus-builder carve-out ---------------------

  def test_full_rebuild_mints_the_builders_sentinel
    full_rebuilder.run

    with_db do |db|
      row = db[:derivation_stamps].first(slug: builders_slug)
      refute_nil row, "the full rebuild must mint the __corpus-builders__ sentinel"
      assert_equal Nabu::DerivationFingerprint.builders_digest, row[:fingerprint]
    end
  end

  def test_a_builder_file_change_reruns_corpus_builders_without_dirtying_sources
    full_rebuilder.run
    before_passages = raw_rows(:passages)

    result = with_changed_builder_file("metadata_dates.rb") { incremental_rebuilder.run }

    assert_empty result.outcomes, "a builder-only edit must not replay any source (№R-54)"
    assert_equal %w[alpha beta lexica], result.cleans.map(&:slug).sort
    refute_nil result.axes, "the covering mechanism: builders re-run on their own digest drift"
    refute_nil result.facets
    assert_equal before_passages, raw_rows(:passages), "no source row may move"

    # The sentinel re-minted at the drifted digest: a second run inside the
    # same diversion is fully clean, builders included.
    second = with_changed_builder_file("metadata_dates.rb") { incremental_rebuilder.run }
    assert_empty second.outcomes
    assert_nil second.axes, "builders must not re-run once their digest is stamped"
  end

  def test_dry_run_reports_builders_drift
    full_rebuilder.run

    plan = with_changed_builder_file("metadata_dates.rb") { incremental_rebuilder.plan }

    assert plan.builders_dirty, "the dry run must announce the builders re-run honestly"
    assert(plan.verdicts.all? { |v| v.state == :clean }, "no source verdict may dirty")
    refute incremental_rebuilder.plan.builders_dirty, "clean when the digest matches the sentinel"
  end

  # -- P89-1 (№R-54 (b)): the --trust-derivations bridge -------------------

  def test_trust_derivations_restamps_shared_core_drift_without_replay
    full_rebuilder.run
    before_passages = raw_rows(:passages)
    before_fts = fts_snapshot

    result = with_changed_shared_core do
      incremental_rebuilder(trust_derivations: true, code_voucher: voucher(true)).run
    end

    assert_empty result.outcomes, "trust must not replay a shared-core-only drift"
    assert_equal %w[alpha beta lexica], result.trusted.map(&:slug).sort
    assert_equal before_passages, raw_rows(:passages), "trust must not touch a row"
    assert_equal before_fts, fts_snapshot, "trust must not touch the index"

    # The re-minted stamps hold: a PLAIN incremental inside the same
    # diversion sweeps clean — the ~16 h wall is paid off in stamps alone.
    followup = with_changed_shared_core { incremental_rebuilder.run }
    assert_empty followup.outcomes
    assert_equal %w[alpha beta lexica], followup.cleans.map(&:slug).sort
  end

  def test_trusted_sources_leave_a_durable_stage_line_as_they_happen
    # Owner feedback 2026-08-30: the 142-source trust sweep was invisible
    # in the transcript — only the end summary carried it. Each trust now
    # opens a stage (which the reporter closes durably at the next one).
    full_rebuilder.run
    labels = []
    probe = Nabu::ProgressReporter.new(on_stage: ->(label, _eta) { labels << label })

    with_changed_shared_core do
      incremental_rebuilder(trust_derivations: true, code_voucher: voucher(true)).run(progress: probe)
    end

    %w[alpha beta lexica].each do |slug|
      assert(labels.any? { |l| l.include?(slug) && l.include?("trusted") },
             "#{slug}'s trust must announce as a stage; saw: #{labels.inspect}")
    end
  end

  def test_trust_derivations_replays_when_the_voucher_cannot_vouch
    # The tshet-uinh shape: the source's OWN parser files changed after the
    # stamp — trust must fall through to an honest replay, never a re-stamp.
    full_rebuilder.run

    result = with_changed_shared_core do
      incremental_rebuilder(trust_derivations: true, code_voucher: voucher(false)).run
    end

    assert_equal %w[alpha beta lexica], result.outcomes.map(&:slug).sort
    assert_empty result.trusted
  end

  def test_trust_vouches_against_the_eldest_stamp_never_each_stamps_own_time
    # The lying-stamp hazard (the 2026-08-29 tshet-uinh specimen): a long
    # run stamps late from disk bytes while its rows come from code loaded
    # at start. The voucher must therefore be asked about the ELDEST stamp
    # (≈ run start), not the trusted source's own stamped_at.
    full_rebuilder.run
    eldest = Time.now - 86_400
    with_db(write: true) do |db|
      db[:derivation_stamps].where(slug: "alpha").update(stamped_at: eldest)
    end

    asked = []
    probe = Object.new.tap do |stub|
      stub.define_singleton_method(:vouches?) do |since:, **|
        asked << since
        true
      end
    end
    with_changed_shared_core do
      incremental_rebuilder(trust_derivations: true, code_voucher: probe).run
    end

    refute_empty asked
    asked.each do |since|
      assert_in_delta eldest.to_f, Time.parse(since.to_s).to_f, 1.0,
                      "every vouch must use the eldest stamp as its horizon"
    end
  end

  def test_trust_derivations_never_trusts_canonical_or_fold_drift
    add_jpn_source
    full_rebuilder.run
    write_canonical("beta", "b.txt" => "Odyssey\nἄνδρα πολύτροπον\n")

    result = with_changed_fold_file("jpn.rb") do
      incremental_rebuilder(trust_derivations: true, code_voucher: voucher(true)).run
    end

    assert_equal %w[beta gamma], result.outcomes.map(&:slug).sort,
                 "canonical drift (beta) and fold drift (gamma) are real data changes — always replayed"
    assert_empty result.trusted
    assert_equal %w[alpha lexica], result.cleans.map(&:slug).sort
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

  # -- P70: dirty runs re-derive the sibling dbs like the full rebuild -----

  def test_dirty_incremental_rederives_lect_journal_and_links
    full_rebuilder.run
    # A config ruling awaiting derivation + stray journal-only rows that a
    # re-derivation must kill (they are backed by neither config nor mine).
    Nabu::LectRulings.append!(config.lect_rulings_path,
                              urn: "urn:nabu:alpha:a", code: "grc", lect_id: "grc:koine")
    lects = Nabu::Store::LectJournal.open!(config.lects_journal_path)
    lects[:lect_assignments].insert(urn: "urn:stray", code: "grc", lect_id: "grc:doric",
                                    basis: "owner", created_at: Time.now)
    lects.disconnect
    links = Nabu::Store::LinksJournal.open!(config.links_path)
    run_id = links[:link_runs].insert(producer: "manual", scope: "manual", params_json: "{}",
                                      code_version: "0", created_at: Time.now)
    links[:links].insert(from_urn: "urn:stray", to_urn: "urn:stray2", kind: "reference",
                         run_id: run_id, created_at: Time.now)
    links.disconnect

    write_canonical("beta", "b.txt" => "Odyssey\nἄνδρα πολύτροπον\n")
    result = incremental_rebuilder.run

    assert_empty result.link_failures
    lects = Nabu::Store::LectJournal.open!(config.lects_journal_path)
    rows = lects[:lect_assignments].select_hash(:urn, :lect_id)
    lects.disconnect
    assert_equal "grc:koine", rows["urn:nabu:alpha:a"], "the config ruling must land in the journal"
    refute rows.key?("urn:stray"), "a journal-only row is backed by nothing — the re-derivation kills it"
    links = Nabu::Store::LinksJournal.open!(config.links_path)
    assert_equal 0, links[:links].where(from_urn: "urn:stray").count,
                 "a journal-only link is backed by nothing — the re-mine kills it"
    links.disconnect
  end

  # P71-6: the lect journal re-derives on EVERY incremental run — a
  # hand-edited ruling propagates on a CLEAN sweep too (the journal
  # stage is seconds-scale; only links stays dirty-gated).
  def test_clean_incremental_still_rederives_a_hand_edited_ruling
    full_rebuilder.run
    Nabu::LectRulings.append!(config.lect_rulings_path,
                              urn: "urn:nabu:alpha:a", code: "grc", lect_id: "grc:koine")

    result = incremental_rebuilder.run

    assert_empty result.outcomes, "nothing was dirty — a clean sweep"
    lects = Nabu::Store::LectJournal.open!(config.lects_journal_path)
    rows = lects[:lect_assignments].select_hash(:urn, :lect_id)
    lects.disconnect
    assert_equal "grc:koine", rows["urn:nabu:alpha:a"],
                 "the hand-edited ruling lands without a dirty source"
  end

  def test_incremental_refuses_a_malformed_rulings_file_before_any_replay
    full_rebuilder.run
    FileUtils.mkdir_p(File.dirname(config.lect_rulings_path))
    File.write(config.lect_rulings_path, "rulings:\n- urn: urn:d:1\n")
    write_canonical("beta", "b.txt" => "Odyssey\nchanged\n")
    before = File.binread(catalog_path)

    assert_raises(Nabu::Error) { incremental_rebuilder.run }

    assert_equal before, File.binread(catalog_path), "the refusal must precede any replay work"
  end

  # -- helpers -------------------------------------------------------------

  private

  def config(db_dir: @db_dir)
    Nabu::Config.new(
      canonical_dir: @canonical, db_dir: db_dir,
      sources_path: @sources_path, config_path: File.join(@root, "config", "nabu.yml")
    )
  end

  def registry = Nabu::SourceRegistry.load(@sources_path)

  def full_rebuilder(db_dir: @db_dir)
    Nabu::Rebuild.new(config: config(db_dir: db_dir), registry: registry)
  end

  def incremental_rebuilder(trust_derivations: false, code_voucher: nil)
    Nabu::IncrementalRebuild.new(config: config, registry: registry,
                                 trust_derivations: trust_derivations, code_voucher: code_voucher)
  end

  def builders_slug = Nabu::Store::DerivationStamp::BUILDERS_SLUG

  # A CodeVoucher stand-in with a fixed verdict (the git-backed real one has
  # its own test file).
  def voucher(verdict)
    Object.new.tap do |stub|
      stub.define_singleton_method(:vouches?) { |**| verdict }
    end
  end

  # Simulate a shared-core code change (the №R-54 type specimen: a store/
  # file edited mid-flight) by diverting the private instance digest.
  def with_changed_shared_core
    original = Nabu::DerivationFingerprint.instance_method(:shared_core_digest)
    Nabu::DerivationFingerprint.define_method(:shared_core_digest) { "diverted-core" }
    Nabu::DerivationFingerprint.send(:private, :shared_core_digest)
    yield
  ensure
    Nabu::DerivationFingerprint.define_method(:shared_core_digest, original)
    Nabu::DerivationFingerprint.send(:private, :shared_core_digest)
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

  # The builders-digest counterpart of with_changed_fold_file (P89-1).
  def with_changed_builder_file(basename)
    singleton = Nabu::DerivationFingerprint.singleton_class
    original = Nabu::DerivationFingerprint.method(:builder_file_digest)
    singleton.define_method(:builder_file_digest) do |path|
      File.basename(path) == basename ? "changed-#{basename}" : original.call(path)
    end
    yield
  ensure
    singleton.define_method(:builder_file_digest, original)
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

  # passages_fts is contentless (P93-1) — nothing readable but rowids
  # (= passage ids), so the content snapshot maps them through the same
  # db_dir's catalog to urn + text (the id-independent comparison the
  # comparator note below demands).
  def fts_snapshot(db_dir: @db_dir)
    ft = Nabu::Store.connect_fulltext(File.join(db_dir, "fulltext.sqlite3"), readonly: true)
    cat = Nabu::Store.connect(File.join(db_dir, "catalog.sqlite3"), readonly: true)
    ids = ft[:passages_fts].select_map(Sequel.lit("rowid"))
    cat[:passages].where(id: ids).select_order_map(%i[urn text_normalized])
  ensure
    cat&.disconnect
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
