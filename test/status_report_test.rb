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

  # -- P40-s: the humanizer (unit) --------------------------------------------

  # Under 1000 verbatim; K/M with ONE decimal only when the leading digit is
  # single (1.4K, 16K, 3.0M — the owner's approved mockup). The listed
  # boundaries pin the rounding: 999/1000, 1049 (still 1.0K), 9950 (rounds up
  # to 10K, decimal dropped), 999949 (stays K-tier, 1000K), 1M (1.0M).
  def test_humanize_boundaries
    cases = {
      0 => "0", 42 => "42", 395 => "395", 999 => "999",
      1000 => "1.0K", 1049 => "1.0K", 1400 => "1.4K",
      9950 => "10K", 16_000 => "16K", 395_000 => "395K",
      999_949 => "1000K", 1_000_000 => "1.0M", 3_000_000 => "3.0M",
      12_000_090 => "12M"
    }
    cases.each do |input, expected|
      assert_equal expected, Nabu::StatusReport.humanize(input), "humanize(#{input})"
    end
  end

  # -- P40-s: the compact v2 default ------------------------------------------

  def test_behind_verdict_older_than_a_succeeded_sync_renders_reprobe
    # Owner defect 2026-07-14: a re-synced source still read BEHIND from a
    # pre-sync probe cache — answered noise. In v2 that answered BEHIND is the
    # ?REPROBE mark (the verdict wants a re-run), never OLD.
    db = store_test_db
    ledger = ledger_test_db
    registry = single_source_registry
    registry["fake-src"].sync_source!(db)
    Nabu::Store::Probe.create(source_slug: "fake-src", checked_at: Time.now - 3600,
                              drift: "behind", license: "unchanged", detail: nil)
    ledger[:runs].insert(source_slug: "fake-src", kind: "sync",
                         started_at: Time.now - 60, finished_at: Time.now,
                         added: 0, updated: 0, withdrawn_count: 0, errored: 0,
                         status: "succeeded")
    out = Nabu::StatusReport.render(registry: registry, db: db, ledger: ledger)
    assert_match(/\?REPROBE/, out)
    refute_match(/OLD/, out)
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
        sync_policy: auto
    YAML

    out = Nabu::StatusReport.render(registry: registry, db: nil, ledger: nil)
    # col2 v2: an ENABLED auto source reads a BARE `a` (the word "source" is gone).
    assert_match(/fake-src\s+a\s+no database \(run nabu sync\)/, out)
    refute_match(/\bsource\b/, out, "the word source never prints in v2")
  end

  def test_seeded_db_reports_counts_and_last_run
    db = store_test_db
    ledger = ledger_test_db
    registry = load_registry(<<~YAML)
      fake-src:
        adapter: StatusReportTest::FakeAdapter
        enabled: true
        sync_policy: auto
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
    assert_match(/fake-src\s+a\s/, fake, "enabled auto → bare a")
    assert_match(%r{\s1/2\s}, fake, "fused humanized holdings docs/pass")
    # Compact stamp (year dropped in the current year) + zero-suppressed delta.
    assert_match(/\d{2}-\d{2} \d{2}:\d{2} \+1\b/, fake)
    refute_match(/~0|-0|!0/, fake, "zero delta components are suppressed")
    refute_match(/\bok\b/, fake, "the noise-OK token is gone on a succeeded run")

    never = lines.grep(/never-src/).first
    assert_match(/never-src\s+off\(m\)/, never, "disabled manual → off(m)")
    assert_match(/—/, never, "a never-synced corpus reads the em dash")
    assert_match(/\bnever\b/, never)
  end

  # P23-3b: the registry is AUTHORITATIVE for enablement. A flip with NO sync
  # shows immediately, in both directions — col2 flips bare `m` ↔ `off(m)`.
  def test_registry_enabled_flip_shows_without_a_sync
    db = store_test_db
    stale = load_registry(<<~YAML)
      fake-src:
        adapter: StatusReportTest::FakeAdapter
        enabled: false
    YAML
    stale["fake-src"].sync_source!(db) # db row now carries enabled: false

    flipped = load_registry(<<~YAML)
      fake-src:
        adapter: StatusReportTest::FakeAdapter
        enabled: true
    YAML
    out = Nabu::StatusReport.render(registry: flipped, db: db, ledger: ledger_test_db)
    assert_match(/fake-src\s+m\b/, out, "a registry enabled: true shows bare m, stale db row or not")

    # And the reverse: flipped OFF in the registry, db row still on.
    Nabu::Store::Source.first(slug: "fake-src").update(enabled: true)
    unflipped = load_registry(<<~YAML)
      fake-src:
        adapter: StatusReportTest::FakeAdapter
        enabled: false
    YAML
    out = Nabu::StatusReport.render(registry: unflipped, db: db, ledger: ledger_test_db)
    assert_match(/fake-src\s+off\(m\)/, out)
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
    assert_match(%r{\s0/0\s}, out, "a synced-but-empty corpus reads 0/0, not the em dash")
  end

  # P5-2: retired documents stay in the live docs= count; the compact fused
  # column folds them in (1/2), and the retired detail lives in --long.
  def test_retired_documents_folded_compact_surfaced_in_long
    db = store_test_db
    registry = load_registry(<<~YAML)
      fake-src:
        adapter: StatusReportTest::FakeAdapter
    YAML
    source = registry["fake-src"].sync_source!(db)
    Nabu::Store::Loader.new(db: db, source: source).load([seed_document])
    Nabu::Store::Document.first(urn: "urn:nabu:fake:doc1").update(retired_upstream: true)
    # The direct flag flip above bypasses the loader (the only sanctioned
    # stats writer, P42-0) — re-derive so holdings read the tampered state.
    Nabu::Store::SourceStats.derive!(db, note: "test")

    compact = Nabu::StatusReport.render(registry: registry, db: db, ledger: ledger_test_db)
    assert_match(%r{\s1/2\s}, compact, "retired folds into the fused docs/pass column")
    refute_match(/retired/, compact, "the compact view drops the retired label")

    long = Nabu::StatusReport.render(registry: registry, db: db, ledger: ledger_test_db, long: true)
    assert_match(/docs=1 pass=2 retired=1/, long, "--long surfaces the labeled retired count")
  end

  # P42-0: holdings read the source_stats derived table when it exists; a
  # catalog predating migration 019 falls back to the live aggregates with
  # BYTE-IDENTICAL output — the no-behavior-change contract.
  def test_holdings_render_identically_with_and_without_source_stats
    db = store_test_db
    registry = single_source_registry
    source = registry["fake-src"].sync_source!(db)
    Nabu::Store::Loader.new(db: db, source: source).load([seed_document])
    ledger = ledger_test_db

    with_stats = Nabu::StatusReport.render(registry: registry, db: db, ledger: ledger)
    db.drop_table(:source_stats_languages)
    db.drop_table(:source_stats)
    assert_equal with_stats, Nabu::StatusReport.render(registry: registry, db: db, ledger: ledger),
                 "the pre-019 fallback must render byte-identically"
  end

  # P11-10: a dictionary source renders its entry count as a single humanized
  # number, not docs/pass.
  def test_dictionary_source_reports_entries_not_docs_passages
    db = store_test_db
    registry = load_registry(<<~YAML)
      fake-dict:
        adapter: StatusReportTest::FakeDictAdapter
        enabled: true
        sync_policy: auto
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
    assert_match(/fake-dict\s+a\s+UNPROBED\s+3\s+never/, out)
    refute_match(/fake-dict.*docs=/, out)
  end

  # P12-3: the REAL Bosworth-Toller adapter inherits the dictionary status
  # shape purely through its content_kind declaration.
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
    assert_match(/bosworth-toller\s+off\(m\)\s+UNPROBED\s+2\s+never/, out)
    refute_match(/bosworth-toller.*docs=/, out)
  end

  # A dictionary source that has NEVER synced (no catalog row) reads the em
  # dash — never a misleading zero.
  def test_unsynced_dictionary_source_reports_em_dash
    db = store_test_db
    registry = load_registry(<<~YAML)
      fake-dict:
        adapter: StatusReportTest::FakeDictAdapter
    YAML

    out = Nabu::StatusReport.render(registry: registry, db: db, ledger: ledger_test_db)
    assert_match(/fake-dict\s+off\(m\)\s+UNPROBED\s+—\s+never/, out)
    refute_match(/entries=|docs=/, out)
  end

  # P7-1: a catalog without a ledger reports "no run history" honestly.
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

  # -- P40-s: the liveness exception vocabulary (mark mapping) -----------------
  #
  # Every real verdict state maps to EXACTLY one v2 rendering: silence for the
  # healthy/implied ones (module/local/frozen/ok), or one of the four marks
  # (OLD/DOWN/?REPROBE/UNPROBED). The tests below pin each arrow.

  # No cached probe, never synced → UNPROBED (a live upstream never probed).
  def test_upstream_never_probed_renders_unprobed
    db = store_test_db
    ledger = ledger_test_db
    registry = single_source_registry
    registry["fake-src"].sync_source!(db)

    out = Nabu::StatusReport.render(registry: registry, db: db, ledger: ledger)
    assert_match(%r{fake-src\s+off\(m\)\s+UNPROBED\s+0/0\s+never}, out)
  end

  # ok → SILENT: a fresh CURRENT probe prints no mark at all.
  def test_upstream_current_recent_is_silent
    out = render_with_probe(drift: "current", checked_at: Time.now - (2 * 86_400))
    assert_match(%r{fake-src\s+off\(m\)\s+0/0\s+never}, out)
    refute_match(/up=|OLD|DOWN|REPROBE|UNPROBED/, out, "a healthy ok verdict is silent")
  end

  # behind → OLD(Nd), the loud signal (renames BEHIND, keeps the age).
  def test_upstream_behind_renders_old
    out = render_with_probe(drift: "behind", checked_at: Time.now - (2 * 86_400))
    assert_match(/OLD\(2d\)/, out)
    refute_match(/BEHIND/, out, "v2 renames BEHIND to OLD")
  end

  # stale (a CURRENT verdict past the horizon) → ?REPROBE.
  def test_upstream_current_but_old_renders_reprobe
    out = render_with_probe(drift: "current", checked_at: Time.now - (30 * 86_400))
    assert_match(/\?REPROBE/, out)
    refute_match(/stale/, out)
  end

  # A stale cache never softens a BEHIND — OLD stays loud.
  def test_upstream_behind_stays_loud_even_when_cache_is_old
    out = render_with_probe(drift: "behind", checked_at: Time.now - (30 * 86_400))
    assert_match(/OLD\(30d\)/, out)
    refute_match(/REPROBE/, out)
  end

  # indeterminate (probed, drift not computable) → DOWN.
  def test_upstream_indeterminate_renders_down
    out = render_with_probe(drift: "unknown", checked_at: Time.now - (3 * 86_400))
    assert_match(/DOWN/, out)
    refute_match(/UNPROBED|REPROBE/, out)
  end

  # frozen policy → SILENT (immutable snapshot, cache ignored).
  def test_upstream_frozen_policy_is_silent
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
    assert_match(%r{frozen-src\s+off\(f\)\s+0/0\s+never}, out)
    refute_match(/OLD|BEHIND|DOWN|REPROBE|UNPROBED/, out, "a frozen source is silent")
  end

  # P19-1: a local shelf → SILENT (up=local), col2 `shelf`, records count.
  class LanguageFakeAdapter < Nabu::Adapter
    MANIFEST = Nabu::SourceManifest.new(
      id: "local-language", name: "Language dossiers (local shelf)",
      license: "Owner-authored", license_class: "open",
      upstream_url: "canonical/local-language (local)", parser_family: "language-dossier"
    )
    def self.manifest = MANIFEST
    def self.content_kind = :language
  end

  def test_local_shelf_is_silent_and_shows_records_count
    db = store_test_db
    ledger = ledger_test_db
    registry = load_registry(<<~YAML)
      local-language:
        adapter: StatusReportTest::LanguageFakeAdapter
        kind: shelf
        enabled: true
    YAML
    registry["local-language"].sync_source!(db)
    db[:language_records].insert(lang_code: "chu", kind: "name", body: "OCS", source: "dossier")
    Nabu::Store::Probe.create(source_slug: "local-language", checked_at: Time.now,
                              drift: "behind", license: "unchanged", detail: nil)

    out = Nabu::StatusReport.render(registry: registry, db: db, ledger: ledger)
    # kind: shelf → col2 `shelf`, silent liveness, a single humanized count.
    assert_match(/local-language\s+shelf\s+1\s+never/, out)
    refute_match(/OLD|BEHIND|DOWN|REPROBE|UNPROBED/, out, "kind: shelf wins over any cache row")
  end

  # P24-1: the owner-notes shelf — the same silent local verdict, notes count.
  class NotesFakeAdapter < Nabu::Adapter
    MANIFEST = Nabu::SourceManifest.new(
      id: "local-notes", name: "Owner notes (local shelf)",
      license: "Owner-authored", license_class: "open",
      upstream_url: "canonical/local-notes (local)", parser_family: "urn-notes"
    )
    def self.manifest = MANIFEST
    def self.content_kind = :notes
  end

  def test_notes_shelf_is_silent_and_shows_notes_count
    db = store_test_db
    ledger = ledger_test_db
    registry = load_registry(<<~YAML)
      local-notes:
        adapter: StatusReportTest::NotesFakeAdapter
        kind: shelf
        enabled: true
    YAML
    registry["local-notes"].sync_source!(db)
    db[:urn_notes].insert(urn: "urn:nabu:ccmh:mar:mt", note: "collate first", topic: "notes",
                          added: "2026-07-16", provenance: "local-notes/notes.yml")

    out = Nabu::StatusReport.render(registry: registry, db: db, ledger: ledger)
    assert_match(/local-notes\s+shelf\s+1\s+never/, out)
    refute_match(/docs=/, out)
  end

  # -- P39-0 carried to v2: kind grouping, module rows, last-contact ----------

  # Rows are GROUPED BY KIND — modules, then shelves, then sources.
  def test_rows_grouped_by_kind_modules_shelves_sources
    db = store_test_db
    registry = load_registry(<<~YAML)
      zsrc:
        adapter: StatusReportTest::FakeAdapter
        enabled: true
        sync_policy: auto
      ashelf:
        adapter: StatusReportTest::LanguageFakeAdapter
        kind: shelf
        enabled: true
      amod:
        adapter: StatusReportTest::FakeAdapter
        kind: module
        enabled: false
        sync_policy: manual
    YAML

    out = Nabu::StatusReport.render(registry: registry, db: db, ledger: ledger_test_db)
    slugs = out.lines.map { |line| line[/^\S+/] }
    assert_equal %w[amod ashelf zsrc], slugs, "modules, then shelves, then sources"
  end

  # A kind: module reads col2 `module`, is SILENT, and shows NO holdings.
  def test_module_row_is_silent_with_no_holdings
    db = store_test_db
    registry = load_registry(<<~YAML)
      amod:
        adapter: StatusReportTest::FakeAdapter
        kind: module
        enabled: false
        sync_policy: manual
    YAML
    registry["amod"].sync_source!(db)

    out = Nabu::StatusReport.render(registry: registry, db: db, ledger: ledger_test_db)
    assert_match(/amod\s+module\s+never/, out)
    refute_match(/docs=|—|UNPROBED/, out, "a module mints no catalog rows — no holdings, no mark")
  end

  # An unprobed source with a last successful sync collapses to UNPROBED in the
  # compact view (both never-synced and synced-but-unprobed are "never probed").
  # The last-contact age lives in the detail view (?(5d)).
  def test_unprobed_but_synced_is_unprobed_compact_and_dated_in_detail
    db = store_test_db
    ledger = ledger_test_db
    registry = single_source_registry
    source = registry["fake-src"].sync_source!(db)
    Nabu::Store::Run.create(
      source_slug: source.slug, kind: "sync",
      started_at: Time.now - (5 * 86_400), finished_at: Time.now - (5 * 86_400),
      status: "succeeded", added: 0, updated: 0, withdrawn_count: 0, errored: 0
    )

    out = Nabu::StatusReport.render(registry: registry, db: db, ledger: ledger)
    assert_match(/UNPROBED/, out)

    detail = Nabu::StatusReport.render_source(registry: registry, db: db, ledger: ledger, slug: "fake-src")
    assert_match(/liveness:\s+up=\?\(5d\)/, detail, "the last-contact age is kept in the detail block")
  end

  # A ledger predating source_probes degrades to UNPROBED, no crash.
  def test_upstream_ledger_without_probe_table_degrades_to_unprobed
    db = store_test_db
    ledger = ledger_missing_probe_table
    registry = single_source_registry
    registry["fake-src"].sync_source!(db)

    out = Nabu::StatusReport.render(registry: registry, db: db, ledger: ledger)
    assert_match(/UNPROBED/, out)
  end

  # -- P40-s: zero-suppression of the delta -----------------------------------

  def test_delta_zero_suppression
    db = store_test_db
    ledger = ledger_test_db
    registry = single_source_registry
    registry["fake-src"].sync_source!(db)

    # A mixed run prints only the non-zero components, no parens.
    Nabu::Store::Run.create(
      source_slug: "fake-src", kind: "sync", started_at: Time.now - 60, finished_at: Time.now,
      status: "succeeded", added: 1418, updated: 0, withdrawn_count: 0, errored: 27
    )
    mixed = Nabu::StatusReport.render(registry: registry, db: db, ledger: ledger)
    assert_match(/\+1418 !27\b/, mixed)
    refute_match(/~0|-0|\(\+/, mixed, "zeros suppressed, no parens")

    # An all-zero run prints the stamp and NOTHING for the delta.
    Nabu::Store::Run.create(
      source_slug: "fake-src", kind: "sync", started_at: Time.now - 30, finished_at: Time.now,
      status: "succeeded", added: 0, updated: 0, withdrawn_count: 0, errored: 0
    )
    zeroed = Nabu::StatusReport.render(registry: registry, db: db, ledger: ledger)
    line = zeroed.lines.map(&:chomp).grep(/fake-src/).first
    assert_match(/\d{2}-\d{2} \d{2}:\d{2}$/, line, "an all-zero delta prints nothing after the stamp")
  end

  # A non-succeeded run keeps its status word INLINE (errors show on the row).
  def test_failed_run_status_inline
    db = store_test_db
    ledger = ledger_test_db
    registry = single_source_registry
    registry["fake-src"].sync_source!(db)
    Nabu::Store::Run.create(
      source_slug: "fake-src", kind: "sync", started_at: Time.now - 60, finished_at: Time.now,
      status: "failed", added: 0, updated: 0, withdrawn_count: 0, errored: 3
    )
    out = Nabu::StatusReport.render(registry: registry, db: db, ledger: ledger)
    assert_match(/!3 failed\b/, out)
  end

  # -- P40-s: the extended views ----------------------------------------------

  # `status <source>`: the full labeled detail block, healthy liveness and
  # thousands-separated exact counts included.
  def test_render_source_full_labeled_detail
    db = store_test_db
    ledger = ledger_test_db
    registry = single_source_registry
    source = registry["fake-src"].sync_source!(db)
    Nabu::Store::Loader.new(db: db, source: source).load([seed_document])
    Nabu::Store::Probe.create(source_slug: "fake-src", checked_at: Time.now - (2 * 86_400),
                              drift: "current", license: "unchanged", detail: nil)
    Nabu::Store::Run.create(
      source_slug: "fake-src", kind: "sync", started_at: Time.now - 60, finished_at: Time.now,
      status: "succeeded", added: 1, updated: 0, withdrawn_count: 0, errored: 0
    )

    out = Nabu::StatusReport.render_source(registry: registry, db: db, ledger: ledger, slug: "fake-src")
    assert_match(/^fake-src\s+\(Fake Source\)/, out)
    assert_match(/kind:\s+source/, out)
    assert_match(/enabled:\s+no/, out)
    assert_match(/cadence:\s+manual/, out)
    assert_match(/liveness:\s+up=ok\(2d\)/, out, "the detail view keeps the healthy verdict")
    assert_match(/docs:\s+1/, out)
    assert_match(/pass:\s+2/, out)
    assert_match(/license:\s+attribution/, out)
    assert_match(/last sync:\s+\d{4}-\d{2}-\d{2} \d{2}:\d{2}\s+\(\+1 ~0 -0 !0\)/, out, "full delta incl. zeros")
    assert_match(/status:\s+succeeded/, out)
  end

  # Thousands separators in the detail counts (the owner's example shape).
  def test_render_source_thousands_separators
    db = store_test_db
    ledger = ledger_test_db
    registry = load_registry(<<~YAML)
      fake-dict:
        adapter: StatusReportTest::FakeDictAdapter
        enabled: true
        sync_policy: auto
    YAML
    source = registry["fake-dict"].sync_source!(db)
    dictionary = Nabu::Store::Dictionary.create(source_id: source.id, slug: "lsj",
                                                title: "LSJ", language: "grc")
    # A count that must render with separators: 1,234.
    1234.times do |i|
      Nabu::Store::DictionaryEntry.create(
        dictionary_id: dictionary.id, urn: "urn:nabu:dict:lsj:n#{i}", entry_id: "n#{i}",
        key_raw: "k#{i}", headword: "h#{i}", headword_folded: "h#{i}",
        gloss: "g", body: "b", content_sha256: "s#{i}", revision: 1, withdrawn: false
      )
    end

    out = Nabu::StatusReport.render_source(registry: registry, db: db, ledger: ledger, slug: "fake-dict")
    assert_match(/entries:\s+1,234/, out)
  end

  def test_render_source_unknown_slug_returns_nil
    registry = single_source_registry
    assert_nil Nabu::StatusReport.render_source(registry: registry, db: store_test_db,
                                                ledger: ledger_test_db, slug: "nope")
  end

  # `--long`: the extended detail as a labeled table for every row — verbose
  # liveness (healthy states), exact labeled counts, license class, full delta.
  def test_long_table_labeled_detail_for_every_row
    db = store_test_db
    ledger = ledger_test_db
    registry = single_source_registry
    source = registry["fake-src"].sync_source!(db)
    Nabu::Store::Loader.new(db: db, source: source).load([seed_document])
    Nabu::Store::Probe.create(source_slug: "fake-src", checked_at: Time.now - (2 * 86_400),
                              drift: "current", license: "unchanged", detail: nil)
    Nabu::Store::Run.create(
      source_slug: "fake-src", kind: "sync", started_at: Time.now - 60, finished_at: Time.now,
      status: "succeeded", added: 1, updated: 0, withdrawn_count: 0, errored: 0
    )

    out = Nabu::StatusReport.render(registry: registry, db: db, ledger: ledger, long: true)
    # The P39-0 table shape: enablement+cadence, kind, verbose up=, labeled
    # counts, license class, full stamp + full delta (zeros included).
    assert_match(/fake-src\s+off\(m\)\s+source\s+up=ok\(2d\)\s+docs=1 pass=2\s+attribution/, out)
    assert_match(/\d{4}-\d{2}-\d{2} \d{2}:\d{2} \(\+1 ~0 -0 !0\)/, out)
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
