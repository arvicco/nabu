# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

module Store
  # The history ledger (P7-1): db/history.sqlite3, the non-derived operational
  # db that `nabu rebuild` never touches. Its own migration track
  # (db/ledger_migrate + its own schema_info, since it is its own file), its
  # own models (Run, Pin, Revision), and the one-shot lift-and-shift that
  # carries runs/baselines/pins out of a pre-P7-1 catalog.
  class LedgerTest < Minitest::Test
    include StoreTestDB

    def setup
      @ledger = ledger_test_db
    end

    # -- schema ---------------------------------------------------------------

    def test_ledger_migrations_create_all_tables
      %i[runs pins revisions].each do |table|
        assert @ledger.table_exists?(table), "expected ledger table #{table} to exist"
      end
    end

    def test_runs_are_slug_keyed_with_a_kind
      @ledger[:runs].insert(source_slug: "perseus-greek", kind: "sync", started_at: Time.now, status: "succeeded")
      @ledger[:runs].insert(source_slug: "perseus-greek", kind: "rebuild", started_at: Time.now, status: "running")
      assert_equal 2, @ledger[:runs].where(source_slug: "perseus-greek").count
    end

    def test_runs_kind_check_rejects_bad_value
      assert_raises(Sequel::DatabaseError) do
        @ledger[:runs].insert(source_slug: "s", kind: "bogus", started_at: Time.now, status: "running")
      end
    end

    def test_runs_status_check_rejects_bad_value
      assert_raises(Sequel::DatabaseError) do
        @ledger[:runs].insert(source_slug: "s", kind: "sync", started_at: Time.now, status: "bogus")
      end
    end

    def test_pins_composite_unique_index_enforced
      @ledger[:pins].insert(source_slug: "ud", repo_url: "https://github.com/acme/one", last_sync_sha: "a")
      assert_raises(Sequel::DatabaseError) do
        @ledger[:pins].insert(source_slug: "ud", repo_url: "https://github.com/acme/one", last_sync_sha: "b")
      end
    end

    def test_revisions_urn_index_present
      assert(@ledger.indexes(:revisions).values.any? { |i| i[:columns] == [:urn] })
    end

    # -- models ---------------------------------------------------------------

    def test_models_bind_to_the_ledger
      run = Nabu::Store::Run.create(source_slug: "s", kind: "sync", started_at: Time.now)
      pin = Nabu::Store::Pin.create(source_slug: "s", repo_url: "https://x", last_sync_sha: "sha")
      rev = Nabu::Store::Revision.create(urn: "urn:x:1", event: "revised", old_sha: "a", new_sha: "b", at: Time.now)

      assert_equal "running", run.refresh.status
      assert_equal "sha", pin.refresh.last_sync_sha
      assert_equal "revised", rev.refresh.event
    end

    # -- open! bootstraps a fresh machine --------------------------------------

    def test_open_bang_creates_migrates_and_binds
      Dir.mktmpdir("nabu-ledger") do |root|
        path = File.join(root, "db", "history.sqlite3")
        db = Nabu::Store::Ledger.open!(path)
        assert File.exist?(path), "open! must create the ledger file"
        assert db.table_exists?(:runs)
        assert_equal 0, Nabu::Store::Run.count, "a fresh ledger is empty history, not an error"
        db.disconnect
      end
    end

    # -- lift-and-shift from a pre-P7-1 catalog --------------------------------

    def test_lift_carries_runs_baselines_and_pins_out_of_a_legacy_catalog
      catalog = legacy_catalog
      sid = seed_legacy_source(catalog, slug: "perseus-greek", upstream_url: "https://github.com/a/b",
                                        last_sync_sha: "headsha", license_baseline_sha256: "licsha")
      catalog[:runs].insert(source_id: sid, started_at: Time.now, finished_at: Time.now,
                            added: 7, updated: 1, withdrawn_count: 0, errored: 2, status: "succeeded")
      mid = seed_legacy_source(catalog, slug: "ud", upstream_url: "https://github.com/org", last_sync_sha: "x")
      catalog[:source_repos].insert(source_id: mid, repo_url: "https://github.com/org/one",
                                    last_sync_sha: "one-sha", license_baseline_sha256: "one-lic")
      catalog[:source_repos].insert(source_id: mid, repo_url: "https://github.com/org/two",
                                    last_sync_sha: "two-sha")

      Nabu::Store::Ledger.lift!(catalog: catalog, ledger: @ledger)

      run = @ledger[:runs].first
      assert_equal "perseus-greek", run[:source_slug], "runs are re-keyed by slug, not by re-mintable id"
      assert_equal "sync", run[:kind]
      assert_equal 7, run[:added]
      assert_equal 2, run[:errored]

      pins = @ledger[:pins].to_hash(:repo_url)
      # The single-repo source's sources-columns pin lands keyed by upstream_url.
      assert_equal "headsha", pins.fetch("https://github.com/a/b")[:last_sync_sha]
      assert_equal "licsha", pins.fetch("https://github.com/a/b")[:license_baseline_sha256]
      # The multi-repo source's source_repos rows land per repo_url; its
      # aggregate sources-columns sha is NOT duplicated onto the org url.
      assert_equal "one-lic", pins.fetch("https://github.com/org/one")[:license_baseline_sha256]
      assert_equal "two-sha", pins.fetch("https://github.com/org/two")[:last_sync_sha]
      refute pins.key?("https://github.com/org"), "no pin for the un-probeable org url"
    ensure
      catalog&.disconnect
    end

    def test_lift_skips_a_ledger_that_already_has_history
      catalog = legacy_catalog
      sid = seed_legacy_source(catalog, slug: "src", upstream_url: "https://x", last_sync_sha: "sha")
      catalog[:runs].insert(source_id: sid, started_at: Time.now, status: "succeeded")
      Nabu::Store::Run.create(source_slug: "src", kind: "sync", started_at: Time.now, status: "succeeded")
      Nabu::Store::Pin.create(source_slug: "src", repo_url: "https://x", last_sync_sha: "newer")

      Nabu::Store::Ledger.lift!(catalog: catalog, ledger: @ledger)

      assert_equal 1, @ledger[:runs].count, "a populated ledger is never re-lifted into (no duplicates)"
      assert_equal "newer", @ledger[:pins].first[:last_sync_sha]
    ensure
      catalog&.disconnect
    end

    # The full on-disk shift: open_with_lift! against a legacy catalog file
    # imports the history AND migrates the catalog forward (dropping the
    # now-moved tables) — run once by the first write-path command.
    def test_open_with_lift_imports_then_drops_the_legacy_tables
      Dir.mktmpdir("nabu-lift") do |root|
        catalog_path = File.join(root, "catalog.sqlite3")
        history_path = File.join(root, "history.sqlite3")
        catalog = legacy_catalog(catalog_path)
        sid = seed_legacy_source(catalog, slug: "src", upstream_url: "https://up", last_sync_sha: "sha")
        catalog[:runs].insert(source_id: sid, started_at: Time.now, status: "succeeded")
        catalog.disconnect

        ledger = Nabu::Store::Ledger.open_with_lift!(history_path: history_path, catalog_path: catalog_path)

        assert_equal 1, ledger[:runs].where(source_slug: "src").count
        assert_equal "sha", ledger[:pins].first(source_slug: "src")[:last_sync_sha]
        reopened = Nabu::Store.connect(catalog_path)
        refute reopened.table_exists?(:runs), "the catalog's legacy runs table is dropped after the lift"
        refute reopened.table_exists?(:source_repos)
        refute reopened[:sources].columns.include?(:license_baseline_sha256)
        reopened.disconnect
        ledger.disconnect
      end
    end

    def test_open_with_lift_with_no_catalog_is_a_clean_bootstrap
      Dir.mktmpdir("nabu-boot") do |root|
        ledger = Nabu::Store::Ledger.open_with_lift!(
          history_path: File.join(root, "history.sqlite3"),
          catalog_path: File.join(root, "catalog.sqlite3")
        )
        assert_equal 0, ledger[:runs].count
        refute File.exist?(File.join(root, "catalog.sqlite3")), "a missing catalog is not created by the ledger"
        ledger.disconnect
      end
    end

    # -- ledger migration 005 (P18-7: quarantine baselines) -------------------

    def test_migration_005_creates_the_quarantine_baselines_table
      assert @ledger.table_exists?(:quarantine_baselines)
      @ledger[:quarantine_baselines].insert(source_slug: "papyri-ddbdp", baseline: 9_312,
                                            anchor: 9_312, recorded_at: Time.now)
      assert_raises(Sequel::UniqueConstraintViolation, Sequel::ConstraintViolation) do
        @ledger[:quarantine_baselines].insert(source_slug: "papyri-ddbdp", baseline: 1,
                                              anchor: 1, recorded_at: Time.now)
      end
    end

    # Forward-only against a LIVE-shaped ledger: apply 001–004, fill every
    # pre-existing table as production would, migrate to 005 — nothing lost,
    # the new table present and empty.
    def test_migration_005_applies_to_a_live_shaped_ledger_without_loss
      db = Nabu::Store::Ledger.connect("sqlite::memory:")
      require "sequel/extensions/migration"
      Sequel::Migrator.run(db, Nabu::Store::Ledger::MIGRATIONS_DIR, target: 4)
      db[:runs].insert(source_slug: "perseus-greek", kind: "sync", started_at: Time.now,
                       finished_at: Time.now, added: 3, status: "succeeded")
      db[:pins].insert(source_slug: "perseus-greek", repo_url: "https://x", last_sync_sha: "abc")
      db[:revisions].insert(urn: "urn:x:1", event: "revised", at: Time.now)
      db[:source_probes].insert(source_slug: "perseus-greek", checked_at: Time.now,
                                drift: "current", license: "unchanged")
      db[:language_notes].insert(lang_code: "grc", kind: "name", body: "Ancient Greek",
                                 source: "seed", created_at: Time.now)

      Nabu::Store::Ledger.migrate!(db)

      assert_equal 6, db[:schema_info].get(:version) # 005 baselines + 006 drift widen (P19-1)
      assert db.table_exists?(:quarantine_baselines)
      assert_equal 0, db[:quarantine_baselines].count
      assert_equal 3, db[:runs].get(:added)
      assert_equal "abc", db[:pins].get(:last_sync_sha)
      assert_equal "urn:x:1", db[:revisions].get(:urn)
      assert_equal "current", db[:source_probes].get(:drift)
      assert_equal "Ancient Greek", db[:language_notes].get(:body)
    ensure
      db&.disconnect
    end

    # A catalog frozen at the pre-P7-1 shape: migrations 001–004 applied, so
    # runs/source_repos/sources.license_baseline_sha256 still live in it.
    LEGACY_TARGET = 4

    private

    def legacy_catalog(path = "sqlite::memory:")
      db = Nabu::Store.connect(path)
      require "sequel/extensions/migration"
      Sequel::Migrator.run(db, Nabu::Store::MIGRATIONS_DIR, target: LEGACY_TARGET,
                                                            allow_missing_migration_files: true)
      db
    end

    def seed_legacy_source(catalog, slug:, upstream_url:, last_sync_sha: nil, license_baseline_sha256: nil)
      catalog[:sources].insert(
        slug: slug, name: slug, adapter_class: "X", license_class: "open",
        upstream_url: upstream_url, last_sync_sha: last_sync_sha,
        license_baseline_sha256: license_baseline_sha256
      )
    end
  end
end
