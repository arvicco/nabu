# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "digest"

# The P18-7 mechanical invariants: each one forced red (the motivating silent
# state, seeded on fixture dbs) then green (the healthy shape produces NO
# finding — zero-signal silence). LocalCheckTest covers the fold into `nabu
# health`'s report; this exercises the checks themselves.
class InvariantsTest < Minitest::Test
  include StoreTestDB

  def setup
    @ledger = ledger_test_db
    @db = store_test_db
    @now = Time.utc(2026, 7, 14)
  end

  # -- last-run honesty ------------------------------------------------------

  def test_failed_last_run_is_loud_with_the_error_detail
    source = seed_source("coptic-scriptorium")
    seed_run(source, status: "succeeded", finished_at: @now - 86_400)
    seed_run(source, status: "failed", notes: "SQLite3::BusyException: database is locked", finished_at: @now)

    finding = find(:failed_run, entry("coptic-scriptorium"))
    assert_predicate finding, :loud?
    assert_match(/FAILED/, finding.message)
    assert_match(/BusyException/, finding.message)
    assert_match(/re-run/, finding.message)
  end

  def test_a_source_whose_latest_run_succeeded_has_no_failed_run_finding
    source = seed_source("ok")
    seed_run(source, status: "failed", finished_at: @now - 86_400)
    seed_run(source, status: "succeeded", finished_at: @now)
    seed_docs(source, 2)

    assert_nil find(:failed_run, entry("ok"))
  end

  # The Coptic case: the failed sync left 152 partial docs that nobody saw.
  # Provenance rows written during the failed run name it a PARTIAL LOAD.
  def test_failed_run_with_rows_written_during_it_is_a_partial_load
    source = seed_source("coptic-scriptorium")
    seed_run(source, status: "failed", started_at: @now - 60, finished_at: @now)
    doc = seed_docs(source, 1).first
    @db[:provenance].insert(document_id: doc[:id], event: "loaded", at: @now - 30)

    finding = find(:partial_load, entry("coptic-scriptorium"))
    assert_predicate finding, :loud?
    assert_match(/partial load: 1 catalog row/, finding.message)
  end

  def test_failed_run_that_wrote_nothing_is_not_a_partial_load
    source = seed_source("clean-fail")
    doc = seed_docs(source, 1).first
    @db[:provenance].insert(document_id: doc[:id], event: "loaded", at: @now - 3_600) # BEFORE the failed run
    seed_run(source, status: "failed", started_at: @now - 60, finished_at: @now)

    assert_nil find(:partial_load, entry("clean-fail"))
  end

  # -- synced-vs-populated (P23-3a refinement of enabled-vs-populated) --------

  # The half-loaded-catalog signature: the ledger says a run succeeded, the
  # (fresh) catalog holds nothing for the source.
  def test_source_with_ok_latest_run_and_zero_rows_is_loud
    source = seed_source("hollow")
    seed_run(source, status: "succeeded")

    finding = find(:synced_unpopulated, entry("hollow"))
    assert_predicate finding, :loud?
    assert_match(/zero documents/, finding.message)
  end

  # The liv case (2026-07-14): a DISABLED source synced anyway to zero rows —
  # succeeded run, empty shelf, silent because the old invariant watched
  # `enabled` sources only. Enablement is irrelevant: a succeeded run PROMISES
  # rows, whatever the flag says.
  def test_disabled_source_with_ok_latest_run_and_zero_rows_is_loud_too
    source = seed_source("liv")
    seed_run(source, status: "succeeded")

    finding = find(:synced_unpopulated, entry("liv", enabled: false))
    assert_predicate finding, :loud?
  end

  def test_populated_or_never_run_sources_are_silent
    populated = seed_source("populated")
    seed_run(populated, status: "succeeded")
    seed_docs(populated, 1)
    assert_nil find(:synced_unpopulated, entry("populated"))

    seed_source("never-run")
    assert_nil find(:synced_unpopulated, entry("never-run"))
  end

  # A FAILED latest run is last_run_honesty's story (one loud finding, not
  # two): the zero-rows check gates on the LATEST run having succeeded, so an
  # older ok run behind a fresh failure stays out of this finding.
  def test_failed_latest_run_is_not_a_synced_unpopulated_finding
    source = seed_source("fail-after-ok")
    seed_run(source, status: "succeeded", finished_at: @now - 86_400)
    seed_run(source, status: "failed", finished_at: @now)

    assert_nil find(:synced_unpopulated, entry("fail-after-ok"))
    refute_nil find(:failed_run, entry("fail-after-ok"))
  end

  def test_dictionary_entries_count_as_populated
    source = seed_source("lexica")
    seed_run(source, status: "succeeded")
    seed_dictionary(source, entries: 3)

    assert_nil find(:synced_unpopulated, entry("lexica"))
  end

  # P24-1: the owner-notes shelf is populated by urn_notes rows — its own
  # grain, never the documents/entries test (which would read forever-empty).
  class NotesKindAdapter < Nabu::Adapter
    def self.content_kind = :notes
  end

  def test_urn_notes_count_as_populated_for_the_notes_shelf
    source = seed_source("local-notes")
    seed_run(source, status: "succeeded")

    finding = find(:synced_unpopulated, entry("local-notes", adapter: "InvariantsTest::NotesKindAdapter"))
    assert_predicate finding, :loud?, "a succeeded run over an empty notes shelf is the hollow signature"

    @db[:urn_notes].insert(urn: "urn:t:1", note: "n", topic: "notes",
                           added: "2026-07-16", provenance: "local-notes/notes.yml")
    assert_nil find(:synced_unpopulated, entry("local-notes", adapter: "InvariantsTest::NotesKindAdapter"))
  end

  # -- flag-vs-artifact: fuzzy_index vs trigram ------------------------------

  # The real day-long state: fuzzy_index flipped ON, no trigram table built.
  def test_fuzzy_flag_without_trigram_table_is_loud
    seed_indexed_source("papyri-ddbdp")
    @fulltext.drop_table(Nabu::Store::Indexer::TRIGRAM_TABLE)

    finding = find(:fuzzy_unindexed, entry("papyri-ddbdp", fuzzy: true))
    assert_predicate finding, :loud?
    assert_match(/trigram index is absent/, finding.message)
  end

  # Flag flipped after the last reindex: the scope table proves the miss.
  def test_fuzzy_flag_outside_the_built_scope_is_loud
    seed_indexed_source("papyri-ddbdp", fuzzy_slugs: []) # indexed WITHOUT the source
    finding = find(:fuzzy_unindexed, entry("papyri-ddbdp", fuzzy: true))
    assert_predicate finding, :loud?
    assert_match(/not in the trigram scope/, finding.message)
  end

  def test_fuzzy_flag_with_a_built_trigram_index_is_silent
    seed_indexed_source("papyri-ddbdp", fuzzy_slugs: ["papyri-ddbdp"])
    assert_nil find(:fuzzy_unindexed, entry("papyri-ddbdp", fuzzy: true))
  end

  def test_unflagged_source_never_checks_the_trigram_index
    seed_indexed_source("perseus-greek")
    @fulltext.drop_table(Nabu::Store::Indexer::TRIGRAM_TABLE)
    assert_nil find(:fuzzy_unindexed, entry("perseus-greek"))
  end

  # -- flag-vs-artifact: timeline extractor families vs document_axes -------------

  def test_timeline_family_with_zero_rows_is_loud
    source = seed_source("edh")
    seed_docs(source, 2)

    finding = find(:timeline_missing, entry("edh"))
    assert_predicate finding, :loud?
    assert_match(/timeline extractor \(edh\)/, finding.message)
    assert_match(/nabu rebuild/, finding.message)
  end

  def test_timeline_family_with_rows_is_silent_and_non_family_sources_never_check
    source = seed_source("edh")
    doc = seed_docs(source, 1).first
    @db[:document_axes].insert(document_id: doc[:id], not_before: 100, not_after: 200,
                               axis_source: "edh")
    assert_nil find(:timeline_missing, entry("edh"))

    plain = seed_source("perseus-greek")
    seed_docs(plain, 1)
    assert_nil find(:timeline_missing, entry("perseus-greek"))
  end

  # -- flag-vs-artifact: reflex-bearing adapters vs dictionary_reflexes -------

  # The cu case: reflex extraction shipped, 0 rows pending resync.
  def test_reflex_bearing_adapter_with_zero_reflex_rows_is_loud
    source = seed_source("wiktionary-cu")
    seed_dictionary(source, entries: 2)

    finding = find(:reflexes_missing, entry("wiktionary-cu", adapter: "Nabu::Adapters::WiktionaryCu"))
    assert_predicate finding, :loud?
    assert_match(/dictionary_reflexes has 0 rows/, finding.message)
    assert_match(/--parse-only/, finding.message)
  end

  def test_reflex_rows_present_is_silent_and_non_reflex_adapters_never_check
    source = seed_source("wiktionary-cu")
    entry_id = seed_dictionary(source, entries: 1).first
    @db[:dictionary_reflexes].insert(dictionary_entry_id: entry_id, seq: 0,
                                     lang_code: "ru", word: "бог")
    assert_nil find(:reflexes_missing, entry("wiktionary-cu", adapter: "Nabu::Adapters::WiktionaryCu"))

    lexica = seed_source("lexica")
    seed_dictionary(lexica, entries: 1)
    assert_nil find(:reflexes_missing, entry("lexica", adapter: "Nabu::Adapters::Lexica"))
  end

  # -- flag-vs-artifact: language_names census vs loaded reflexes -------------

  def test_reflexes_without_the_language_census_is_loud
    source = seed_source("wiktionary-cu")
    entry_id = seed_dictionary(source, entries: 1).first
    @db[:dictionary_reflexes].insert(dictionary_entry_id: entry_id, seq: 0,
                                     lang_code: "ru", word: "бог")

    finding = find(:language_census_missing, entry("wiktionary-cu", adapter: "Nabu::Adapters::WiktionaryCu"))
    assert_predicate finding, :loud?
    assert_match(/language_names census is empty/, finding.message)
  end

  def test_census_present_is_silent
    source = seed_source("wiktionary-cu")
    entry_id = seed_dictionary(source, entries: 1).first
    @db[:dictionary_reflexes].insert(dictionary_entry_id: entry_id, seq: 0,
                                     lang_code: "ru", word: "бог")
    dictionary_id = @db[:dictionaries].where(source_id: source[:id]).get(:id)
    @db[:language_names].insert(dictionary_id: dictionary_id, lang_code: "ru",
                                name: "Russian", occurrences: 1)

    assert_nil find(:language_census_missing, entry("wiktionary-cu", adapter: "Nabu::Adapters::WiktionaryCu"))
  end

  # -- quarantine creep joins the per-source findings --------------------------

  def test_quarantine_creep_surfaces_per_source
    seed_source("creeper")
    @ledger[:quarantine_baselines].insert(source_slug: "creeper", baseline: 1_200,
                                          anchor: 1_000, recorded_at: @now)
    finding = find(:quarantine_creep, entry("creeper"))
    assert_predicate finding, :loud?
  end

  # -- pending migrations (global) ---------------------------------------------

  def test_fully_migrated_dbs_produce_no_global_findings
    assert_empty invariants.global
  end

  def test_catalog_behind_the_migration_dir_is_a_soft_finding
    stale = Nabu::Store.connect("sqlite::memory:")
    require "sequel/extensions/migration"
    Sequel::Migrator.run(stale, Nabu::Store::MIGRATIONS_DIR, target: 10, allow_missing_migration_files: true)

    findings = invariants(catalog: stale).global
    finding = findings.find { |f| f.kind == :pending_migrations }
    assert finding, "expected a pending-migrations finding"
    assert_predicate finding, :soft?
    assert_match(/catalog migrations pending: schema at 10/, finding.message)
  ensure
    stale&.disconnect
  end

  def test_ledger_behind_the_migration_dir_is_a_soft_finding
    stale = Nabu::Store::Ledger.connect("sqlite::memory:")
    require "sequel/extensions/migration"
    Sequel::Migrator.run(stale, Nabu::Store::Ledger::MIGRATIONS_DIR, target: 4)

    finding = invariants(ledger: stale).global.find { |f| f.kind == :pending_migrations }
    assert finding
    assert_match(/ledger migrations pending: schema at 4/, finding.message)
  ensure
    stale&.disconnect
  end

  def test_absent_dbs_produce_no_global_findings
    checker = Nabu::Health::Invariants.new(registry: nil, catalog: nil, fulltext: nil, ledger: nil)
    assert_empty checker.global
  end

  private

  # -- local shelves (P19-1): dossier files vs records; pins vs the tree ------

  def local_entry
    entry("local-language", adapter: "Nabu::Adapters::LocalLanguage").with(sync_policy: "local")
  end

  def local_invariants(root)
    Nabu::Health::Invariants.new(registry: nil, catalog: @db, fulltext: @fulltext,
                                 ledger: @ledger, canonical_dir: root)
  end

  def seed_local_pin(rel, sha)
    @ledger[:pins].insert(source_slug: "local-language", repo_url: "local:#{rel}", last_sync_sha: sha)
  end

  def write_dossier(root, rel, body)
    dir = File.join(root, "local-language")
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, rel), body)
    Digest::SHA256.hexdigest(body)
  end

  def test_dossiers_on_disk_with_zero_records_is_loud
    Dir.mktmpdir do |root|
      source = seed_source("local-language")
      seed_run(source, status: "succeeded")
      write_dossier(root, "chu.md", "---\ncode: chu\n---\nprose\n")

      finding = local_invariants(root).for_source(local_entry).find { |f| f.kind == :dossiers_unindexed }
      assert_predicate finding, :loud?
      assert_match(/zero derived language records/, finding.message)

      @db[:language_records].insert(lang_code: "chu", kind: "context", body: "prose", source: "dossier")
      assert_nil(local_invariants(root).for_source(local_entry).find { |f| f.kind == :dossiers_unindexed })
    end
  end

  def test_pinned_dossier_vanished_without_attic_is_loud
    Dir.mktmpdir do |root|
      seed_source("local-language")
      sha = write_dossier(root, "chu.md", "---\ncode: chu\n---\nprose\n")
      seed_local_pin("chu.md", sha)
      seed_local_pin("zle.md", "feedbeef")

      finding = local_invariants(root).for_source(local_entry).find { |f| f.kind == :dossiers_vanished }
      assert_predicate finding, :loud?
      assert_match(/zle\.md/, finding.message)
      assert_match(/attic/, finding.message)
    end
  end

  def test_pinned_dossier_retired_into_the_attic_is_quiet
    Dir.mktmpdir do |root|
      seed_source("local-language")
      write_dossier(root, File.join(Nabu::Adapter::ATTIC_DIRNAME, "zle.md"), "---\ncode: zle\n---\nold\n")
      seed_local_pin("zle.md", "feedbeef")

      assert_nil(local_invariants(root).for_source(local_entry).find { |f| f.kind == :dossiers_vanished })
    end
  end

  def test_edited_dossier_reads_soft_stale_naming_the_rescan
    Dir.mktmpdir do |root|
      seed_source("local-language")
      write_dossier(root, "chu.md", "---\ncode: chu\n---\nedited since the scan\n")
      seed_local_pin("chu.md", "0" * 64)

      finding = local_invariants(root).for_source(local_entry).find { |f| f.kind == :dossiers_stale }
      assert_predicate finding, :soft?
      assert_match(/sync local-language/, finding.message)
    end
  end

  def test_local_checks_skip_without_a_canonical_dir
    seed_source("local-language")
    seed_local_pin("chu.md", "0" * 64)
    findings = invariants.for_source(local_entry)
    assert_empty(findings.select { |f| %i[dossiers_vanished dossiers_stale dossiers_unindexed].include?(f.kind) })
  end

  def invariants(catalog: @db, fulltext: @fulltext, ledger: @ledger)
    Nabu::Health::Invariants.new(registry: nil, catalog: catalog, fulltext: fulltext, ledger: ledger)
  end

  def find(kind, entry)
    invariants.for_source(entry).find { |finding| finding.kind == kind }
  end

  def entry(slug, enabled: true, fuzzy: false, adapter: "TestAdapter")
    Nabu::SourceRegistry::Entry.new(
      slug: slug, adapter_class_name: adapter, enabled: enabled,
      sync_policy: "manual", fuzzy_index: fuzzy
    )
  end

  def seed_source(slug)
    id = @db[:sources].insert(slug: slug, name: slug, adapter_class: "X",
                              license_class: "open", enabled: true)
    { id: id, slug: slug }
  end

  def seed_run(source, status:, started_at: @now, finished_at: @now, notes: nil)
    @ledger[:runs].insert(source_slug: source[:slug], kind: "sync", started_at: started_at,
                          finished_at: finished_at, status: status, notes: notes)
  end

  def seed_docs(source, count)
    count.times.map do |i|
      @seq = (@seq || 0) + 1
      id = @db[:documents].insert(source_id: source[:id], urn: "urn:t:#{source[:slug]}:#{@seq}",
                                  content_sha256: "x", withdrawn: false)
      { id: id, index: i }
    end
  end

  def seed_dictionary(source, entries:)
    dictionary_id = @db[:dictionaries].insert(source_id: source[:id], slug: source[:slug],
                                              title: "D", language: "grc")
    entries.times.map do |i|
      @db[:dictionary_entries].insert(
        dictionary_id: dictionary_id, urn: "urn:nabu:dict:#{source[:slug]}:e#{i}",
        entry_id: "e#{i}", key_raw: "k", headword: "h", headword_folded: "h",
        body: "b", content_sha256: "x", withdrawn: false
      )
    end
  end

  # A source with one live indexed passage; builds @fulltext with the trigram
  # pass scoped to +fuzzy_slugs+.
  def seed_indexed_source(slug, fuzzy_slugs: [slug])
    source = seed_source(slug)
    doc = seed_docs(source, 1).first
    @db[:passages].insert(document_id: doc[:id], urn: "urn:t:#{slug}:p1", sequence: 0,
                          language: "grc", text: "μῆνιν ἄειδε θεά", text_normalized: "μηνιν αειδε θεα",
                          content_sha256: "x", withdrawn: false)
    @fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
    Nabu::Store::Indexer.rebuild!(catalog: @db, fulltext: @fulltext, fuzzy_slugs: fuzzy_slugs)
    source
  end
end
