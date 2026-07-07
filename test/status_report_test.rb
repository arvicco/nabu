# frozen_string_literal: true

require "test_helper"
require "tmpdir"

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
    assert_match(/enabled/, out)
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
    assert_match(/enabled/, fake)
    assert_match(/live/, fake)
    assert_match(/docs=1 passages=2/, fake)
    assert_match(/last run .*succeeded \(\+1 ~0 -0 !0\)/, fake)

    never = lines.grep(/never-src/).first
    assert_match(/disabled/, never)
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
    assert_match(/docs=0 passages=0/, out)
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
    assert_match(/docs=1 passages=2 retired=1/, out)
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

  private

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
