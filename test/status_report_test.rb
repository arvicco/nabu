# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

class StatusReportTest < Minitest::Test
  include StoreTestDB

  # Resolvable adapter so registry entries can sync a real sources row.
  class FakeAdapter < Nabu::Adapter
    MANIFEST = Nabu::SourceManifest.new(
      id: "fake-src", name: "Fake Source", license: "CC BY 4.0",
      license_class: "attribution", upstream_url: "https://example.invalid/fake",
      parser_family: "plaintext"
    )

    def self.manifest
      MANIFEST
    end
  end

  # A dictionary-shaped source (P11-10): content_kind :dictionary routes the
  # status row to the entries count instead of docs/passages.
  class FakeDictAdapter < Nabu::Adapter
    MANIFEST = Nabu::SourceManifest.new(
      id: "fake-dict", name: "Fake Lexicon", license: "CC BY-SA 4.0",
      license_class: "attribution", upstream_url: "https://example.invalid/dict",
      parser_family: "lexicon-tei"
    )

    def self.manifest
      MANIFEST
    end

    def self.content_kind = :dictionary
  end

  def test_empty_registry_says_so
    registry = load_registry("# nothing\n")
    assert_equal "No sources registered.", Nabu::StatusReport.render(registry: registry, db: nil, ledger: nil)
  end

  def test_registry_without_db_notes_missing_database
    registry = load_registry(<<~YAML)
      fake-src:
        adapter: StatusReportTest::FakeAdapter
        enabled: true
        sync_policy: live
    YAML

    out = Nabu::StatusReport.render(registry: registry, db: nil, ledger: nil)
    assert_match(/fake-src/, out)
    assert_match(/\bon\b/, out)
    assert_match(/live/, out)
    assert_match(/no database \(run nabu sync\)/, out)
  end

  def test_seeded_db_reports_counts_and_last_run
    db = store_test_db
    ledger = ledger_test_db
    registry = load_registry(<<~YAML)
      fake-src:
        adapter: StatusReportTest::FakeAdapter
        enabled: true
        sync_policy: live
      never-src:
        adapter: StatusReportTest::FakeAdapter
    YAML

    source = registry["fake-src"].sync_source!(db)
    Nabu::Store::Loader.new(db: db, source: source).load([seed_document])
    Nabu::Store::Run.create(
      source_slug: source.slug, kind: "sync", started_at: Time.now - 60, finished_at: Time.now,
      status: "succeeded", added: 1, updated: 0, withdrawn_count: 0, errored: 0
    )

    out = Nabu::StatusReport.render(registry: registry, db: db, ledger: ledger)
    lines = out.lines.map(&:chomp)

    fake = lines.grep(/fake-src/).first
    assert_match(/\bon\b/, fake)
    assert_match(/live/, fake)
    assert_match(/docs=1 pass=2/, fake)
    assert_match(/last \d{4}-\d{2}-\d{2} \d{2}:\d{2} ok \(\+1 ~0 -0 !0\)/, fake)

    never = lines.grep(/never-src/).first
    assert_match(/\boff\b/, never)
    assert_match(/manual/, never)
    assert_match(/never synced/, never)
  end

  def test_withdrawn_rows_excluded_from_counts
    db = store_test_db
    registry = load_registry(<<~YAML)
      fake-src:
        adapter: StatusReportTest::FakeAdapter
    YAML
    source = registry["fake-src"].sync_source!(db)
    loader = Nabu::Store::Loader.new(db: db, source: source)
    loader.load([seed_document])
    # Re-load an empty batch: the document (and its passages) get withdrawn.
    loader.load([])

    out = Nabu::StatusReport.render(registry: registry, db: db, ledger: ledger_test_db)
    assert_match(/docs=0 pass=0/, out)
  end

  # P5-2: retired (upstream-scrapped, attic-kept) documents stay in the live
  # counts AND are surfaced as their own count.
  def test_retired_documents_counted_live_and_reported
    db = store_test_db
    registry = load_registry(<<~YAML)
      fake-src:
        adapter: StatusReportTest::FakeAdapter
    YAML
    source = registry["fake-src"].sync_source!(db)
    Nabu::Store::Loader.new(db: db, source: source).load([seed_document])
    Nabu::Store::Document.first(urn: "urn:nabu:fake:doc1").update(retired_upstream: true)

    out = Nabu::StatusReport.render(registry: registry, db: db, ledger: ledger_test_db)
    assert_match(/docs=1 pass=2 retired=1/, out)
  end

  # P11-10: a dictionary source renders its entry count, not docs=0 passages=0
  # (its 168k entries are dictionary_entries, not documents/passages).
  def test_dictionary_source_reports_entries_not_docs_passages
    db = store_test_db
    registry = load_registry(<<~YAML)
      fake-dict:
        adapter: StatusReportTest::FakeDictAdapter
        enabled: true
        sync_policy: live
    YAML
    source = registry["fake-dict"].sync_source!(db)
    dictionary = Nabu::Store::Dictionary.create(source_id: source.id, slug: "lsj",
                                                title: "LSJ", language: "grc")
    3.times do |i|
      Nabu::Store::DictionaryEntry.create(
        dictionary_id: dictionary.id, urn: "urn:nabu:dict:lsj:n#{i}", entry_id: "n#{i}",
        key_raw: "k#{i}", headword: "h#{i}", headword_folded: "h#{i}",
        gloss: "g", body: "b", content_sha256: "s#{i}", revision: 1, withdrawn: false
      )
    end
    # A withdrawn entry must not inflate the count.
    Nabu::Store::DictionaryEntry.create(
      dictionary_id: dictionary.id, urn: "urn:nabu:dict:lsj:gone", entry_id: "gone",
      key_raw: "k", headword: "h", headword_folded: "h", gloss: "g", body: "b",
      content_sha256: "z", revision: 1, withdrawn: true
    )

    out = Nabu::StatusReport.render(registry: registry, db: db, ledger: ledger_test_db)
    assert_match(/fake-dict\s+on\s+live\s+up=\S+\s+entries=3/, out)
    refute_match(/fake-dict.*docs=/, out)
  end

  # P12-3: the REAL Bosworth-Toller adapter inherits the dictionary status
  # shape purely through its content_kind declaration — no status code changed
  # for the third shelf occupant.
  def test_bosworth_toller_inherits_the_dictionary_status_shape
    db = store_test_db
    registry = load_registry(<<~YAML)
      bosworth-toller:
        adapter: Nabu::Adapters::BosworthToller
        enabled: false
        sync_policy: manual
    YAML
    source = registry["bosworth-toller"].sync_source!(db)
    dictionary = Nabu::Store::Dictionary.create(
      source_id: source.id, slug: "bosworth-toller",
      title: "An Anglo-Saxon Dictionary (Bosworth & Toller)", language: "ang"
    )
    2.times do |i|
      Nabu::Store::DictionaryEntry.create(
        dictionary_id: dictionary.id, urn: "urn:nabu:dict:bosworth-toller:#{i + 1}",
        entry_id: (i + 1).to_s, key_raw: "æ#{i}", headword: "æ#{i}", headword_folded: "ae#{i}",
        gloss: "g", body: "b", content_sha256: "s#{i}", revision: 1, withdrawn: false
      )
    end

    out = Nabu::StatusReport.render(registry: registry, db: db, ledger: ledger_test_db)
    assert_match(/bosworth-toller\s+off\s+manual\s+up=\S+\s+entries=2/, out)
    refute_match(/bosworth-toller.*docs=/, out)
  end

  # A dictionary source that has never synced still renders honestly as
  # entries=0 (right shape, no misleading docs=0 passages=0).
  def test_unsynced_dictionary_source_reports_zero_entries
    db = store_test_db
    registry = load_registry(<<~YAML)
      fake-dict:
        adapter: StatusReportTest::FakeDictAdapter
    YAML

    out = Nabu::StatusReport.render(registry: registry, db: db, ledger: ledger_test_db)
    assert_match(/fake-dict.*entries=0/, out)
    refute_match(/docs=/, out)
  end

  # P7-1: a catalog without a ledger (fresh machine mid-bootstrap, or a
  # rebuild-only setup that never synced) reports "no run history" honestly.
  def test_missing_ledger_reports_no_run_history
    db = store_test_db
    registry = load_registry(<<~YAML)
      fake-src:
        adapter: StatusReportTest::FakeAdapter
    YAML
    registry["fake-src"].sync_source!(db)

    out = Nabu::StatusReport.render(registry: registry, db: db, ledger: nil)
    assert_match(/no run history/, out)
  end

  # -- P14-12: the upstream drift column (up=…) --------------------------------

  # No cached probe row for a source → up=?(unprobed): the owner has not yet run
  # `nabu health --remote` / `status --remote`, so drift is genuinely unknown.
  def test_upstream_never_probed_renders_question_never
    db = store_test_db
    ledger = ledger_test_db
    registry = single_source_registry
    registry["fake-src"].sync_source!(db)

    out = Nabu::StatusReport.render(registry: registry, db: db, ledger: ledger)
    assert_match(/fake-src\s+off\s+manual\s+up=\?\(unprobed\)/, out)
  end

  # A fresh CURRENT probe reads quiet: up=ok(Nd), age always shown.
  def test_upstream_current_recent_renders_ok_with_age
    out = render_with_probe(drift: "current", checked_at: Time.now - (2 * 86_400))
    assert_match(/fake-src\s+off\s+manual\s+up=ok\(2d\)/, out)
  end

  # BEHIND is the loud signal — the whole point of the feature.
  def test_upstream_behind_renders_loud_behind
    out = render_with_probe(drift: "behind", checked_at: Time.now - (2 * 86_400))
    assert_match(/up=BEHIND\(2d\)/, out)
  end

  # A CURRENT verdict older than the staleness horizon is no longer trustworthy:
  # up=stale(Nd) — an "ok" too old to base a sync decision on.
  def test_upstream_current_but_old_renders_stale
    out = render_with_probe(drift: "current", checked_at: Time.now - (30 * 86_400))
    assert_match(/up=stale\(30d\)/, out)
  end

  # A stale cache never softens a BEHIND — an alarm does not go stale.
  def test_upstream_behind_stays_loud_even_when_cache_is_old
    out = render_with_probe(drift: "behind", checked_at: Time.now - (30 * 86_400))
    assert_match(/up=BEHIND\(30d\)/, out)
    refute_match(/stale/, out)
  end

  # An indeterminate verdict (never synced / unreachable / multi) shows ? with
  # its age: probed, but drift could not be computed.
  def test_upstream_indeterminate_renders_question_with_age
    out = render_with_probe(drift: "unknown", checked_at: Time.now - (3 * 86_400))
    assert_match(/up=\?\(3d\)/, out)
  end

  # A frozen-policy source is a dead-project snapshot: no probe is expected, so
  # it renders up=frozen regardless of any cache row.
  def test_upstream_frozen_policy_renders_frozen
    db = store_test_db
    ledger = ledger_test_db
    registry = load_registry(<<~YAML)
      frozen-src:
        adapter: StatusReportTest::FakeAdapter
        enabled: false
        sync_policy: frozen
    YAML
    registry["frozen-src"].sync_source!(db)
    # Even with a BEHIND cache row present, policy wins.
    Nabu::Store::Probe.create(source_slug: "frozen-src", checked_at: Time.now,
                              drift: "behind", license: "unchanged", detail: nil)

    out = Nabu::StatusReport.render(registry: registry, db: db, ledger: ledger)
    assert_match(/frozen-src\s+off\s+frozen\s+up=frozen/, out)
    refute_match(/BEHIND/, out)
  end

  # A ledger that predates the source_probes table (a read-only status before
  # any health --remote migrated it) degrades to never-probed, no crash.
  def test_upstream_ledger_without_probe_table_degrades_to_never
    db = store_test_db
    ledger = ledger_missing_probe_table
    registry = single_source_registry
    registry["fake-src"].sync_source!(db)

    out = Nabu::StatusReport.render(registry: registry, db: db, ledger: ledger)
    assert_match(/up=\?\(unprobed\)/, out)
  end

  private

  def single_source_registry
    load_registry(<<~YAML)
      fake-src:
        adapter: StatusReportTest::FakeAdapter
    YAML
  end

  def render_with_probe(drift:, checked_at:, license: "unchanged", detail: nil)
    db = store_test_db
    ledger = ledger_test_db
    registry = single_source_registry
    registry["fake-src"].sync_source!(db)
    Nabu::Store::Probe.create(source_slug: "fake-src", checked_at: checked_at,
                              drift: drift, license: license, detail: detail)
    Nabu::StatusReport.render(registry: registry, db: db, ledger: ledger)
  end

  # A ledger migrated to 001 only (runs/pins/revisions, no source_probes).
  def ledger_missing_probe_table
    db = Nabu::Store::Ledger.connect("sqlite::memory:")
    Dir.mktmpdir do |dir|
      track = File.join(dir, "m")
      FileUtils.mkdir_p(track)
      FileUtils.cp(
        File.expand_path("../db/ledger_migrate/001_initial_ledger.rb", __dir__),
        File.join(track, "001_initial_ledger.rb")
      )
      require "sequel/extensions/migration"
      Sequel::Migrator.run(db, track)
    end
    Nabu::Store::Ledger.setup!(db)
    db
  end

  def seed_document
    document = Nabu::Document.new(
      urn: "urn:nabu:fake:doc1", language: "grc", title: "Doc One",
      canonical_path: "/canonical/fake/doc1.txt"
    )
    document << Nabu::Passage.new(
      urn: "urn:nabu:fake:doc1:1", language: "grc", text: "μῆνιν",
      text_normalized: "μηνιν", sequence: 0
    )
    document << Nabu::Passage.new(
      urn: "urn:nabu:fake:doc1:2", language: "grc", text: "ἄειδε",
      text_normalized: "αειδε", sequence: 1
    )
    document
  end

  def load_registry(yaml)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "sources.yml")
      File.write(path, yaml)
      return Nabu::SourceRegistry.load(path)
    end
  end
end
