# frozen_string_literal: true

require "fileutils"

module Nabu
  module Store
    # The history ledger: db/history.sqlite3 (architecture §5). Everything the
    # derived catalog must NOT be trusted to keep — run history, per-repo sync
    # pins, license-drift baselines, the durable revision journal — lives
    # here, keyed by slug/url/urn so it survives the id re-minting a rebuild
    # performs. `nabu rebuild` never touches this file; backups must include
    # it. A fresh machine simply has no ledger yet: read paths treat that as
    # empty history, and the first write path creates it.
    #
    # Mechanics mirror Store: its own migration directory (db/ledger_migrate —
    # a separate forward-only track; each SQLite file carries its own
    # schema_info, so the catalog's and the ledger's version counters can
    # never collide) and the same define-once/rebind-per-setup! model pattern.
    module Ledger
      MIGRATIONS_DIR = File.expand_path("../../../db/ledger_migrate", __dir__)

      # Model constant (under Nabu::Store) => backing ledger table.
      MODELS = {
        Run: :runs,
        Pin: :pins,
        Revision: :revisions,
        Probe: :source_probes,
        LanguageNote: :language_notes
      }.freeze

      module_function

      # Same scheme-less-path handling as Store.connect, so callers can pass
      # config.history_path directly.
      def connect(url) = Store.connect(url)

      # Apply pending ledger migrations (db/ledger_migrate) to +db+.
      def migrate!(db)
        require "sequel/extensions/migration"
        Sequel::Migrator.run(db, MIGRATIONS_DIR)
        db
      end

      # Bind the ledger models to +db+. Idempotent, exactly like Store.setup!:
      # first call loads the model files, later calls rebind their datasets.
      def setup!(db)
        Sequel::Model.db = db
        # Tolerate a ledger whose schema predates a just-shipped table: the
        # read-only `nabu status` path binds the models without migrating (write
        # paths migrate first), so a pre-P14-12 ledger has no source_probes yet.
        # require_valid_table false makes that binding lazy — a missing table
        # errors only if actually queried, and every reader guards with
        # table_exists? (StatusReport's probe cache degrades to "never probed").
        with_lenient_table_binding do
          if @models_loaded
            MODELS.each_key { |const| Store.const_get(const).set_dataset(db[MODELS.fetch(const)]) }
          else
            require_relative "run"
            require_relative "pin"
            require_relative "revision"
            require_relative "probe"
            require_relative "language_note"
            @models_loaded = true
          end
        end
        db
      end

      def with_lenient_table_binding
        previous = Sequel::Model.require_valid_table
        Sequel::Model.require_valid_table = false
        yield
      ensure
        Sequel::Model.require_valid_table = previous
      end

      # The write-path opener: create the file if absent, migrate, bind models.
      def open!(path)
        FileUtils.mkdir_p(File.dirname(path))
        db = connect(path)
        migrate!(db)
        setup!(db)
        db
      end

      # open! plus the one-shot lift-and-shift: if a pre-P7-1 catalog sits at
      # +catalog_path+ (it still has the runs/source_repos tables), its history
      # is copied into the ledger and the catalog is migrated forward (dropping
      # the moved tables). Every production write path (sync, health --remote,
      # rebuild) opens the ledger through here, so the shift happens exactly
      # once, automatically, on the first run of the new code. A missing
      # catalog is a fresh bootstrap: nothing to lift, nothing created.
      def open_with_lift!(history_path:, catalog_path:)
        ledger = open!(history_path)
        lift_from_catalog_file!(ledger: ledger, catalog_path: catalog_path)
        ledger
      end

      # A catalog still carrying the pre-P7-1 history tables?
      def legacy_catalog?(catalog)
        catalog.table_exists?(:runs) || catalog.table_exists?(:source_repos)
      end

      # Copy runs / pins / license baselines out of a legacy catalog handle
      # into +ledger+, re-keying by slug (runs) and (slug, repo_url) (pins).
      # Guarded per table on "ledger already has rows": the lift is a one-time
      # import, never a merge — re-lifting (e.g. after restoring an old catalog
      # backup next to a live ledger) must not duplicate history.
      def lift!(catalog:, ledger:)
        slugs = catalog[:sources].select_hash(:id, :slug)
        lift_runs!(catalog, ledger, slugs)
        lift_pins!(catalog, ledger, slugs)
      end

      def lift_from_catalog_file!(ledger:, catalog_path:)
        return unless File.exist?(catalog_path)

        catalog = Store.connect(catalog_path)
        return unless legacy_catalog?(catalog)

        lift!(catalog: catalog, ledger: ledger)
        Store.migrate!(catalog) # applies 005: drops the now-moved tables
      ensure
        catalog&.disconnect
      end

      def lift_runs!(catalog, ledger, slugs)
        return unless catalog.table_exists?(:runs) && ledger[:runs].empty?

        catalog[:runs].order(:id).each do |row|
          ledger[:runs].insert(
            source_slug: slugs.fetch(row[:source_id]), kind: "sync",
            started_at: row[:started_at], finished_at: row[:finished_at],
            added: row[:added], updated: row[:updated],
            withdrawn_count: row[:withdrawn_count], errored: row[:errored],
            status: row[:status], notes: row[:notes]
          )
        end
      end

      # Multi-repo pins come from source_repos rows verbatim; single-repo
      # sources carried their pin/baseline as sources columns, keyed here by
      # sources.upstream_url (which is what Adapter.upstream_repo_urls yields
      # for every single-repo adapter — sync_source! writes the manifest url).
      # A multi-repo source's aggregate sources.last_sync_sha is NOT copied:
      # its org url is un-probeable and its real pins are the per-repo rows.
      def lift_pins!(catalog, ledger, slugs)
        return unless ledger[:pins].empty?

        multi_ids = lift_repo_pins!(catalog, ledger, slugs)
        has_baseline = catalog[:sources].columns.include?(:license_baseline_sha256)
        catalog[:sources].each do |row|
          next if multi_ids.include?(row[:id])

          baseline = has_baseline ? row[:license_baseline_sha256] : nil
          next if blank?(row[:last_sync_sha]) && blank?(baseline)
          next if blank?(row[:upstream_url])

          ledger[:pins].insert(source_slug: row[:slug], repo_url: row[:upstream_url],
                               last_sync_sha: row[:last_sync_sha], license_baseline_sha256: baseline)
        end
      end

      # Returns the source ids that had per-repo rows (the multi-repo set).
      def lift_repo_pins!(catalog, ledger, slugs)
        return [] unless catalog.table_exists?(:source_repos)

        catalog[:source_repos].order(:id).map do |row|
          ledger[:pins].insert(
            source_slug: slugs.fetch(row[:source_id]), repo_url: row[:repo_url],
            last_sync_sha: row[:last_sync_sha], license_baseline_sha256: row[:license_baseline_sha256]
          )
          row[:source_id]
        end
      end

      def blank?(value) = value.nil? || value.empty?
    end
  end
end
