# frozen_string_literal: true

require "fileutils"

module Nabu
  module Ops
    # `rake ops:drill` — the fresh-machine restore drill (P7-2), fully local. It
    # proves the concept's own criterion — "restorable from an rsync backup with
    # zero services" — WITHOUT touching the live setup:
    #
    #   1. back up the live tree to a tmp target (--allow-unmounted: the tmp
    #      target is same-disk on purpose),
    #   2. "restore" onto a fresh tmp machine (rsync the target back into an
    #      empty root — the clone-the-repo-and-rsync-your-data step),
    #   3. rebuild the derived db from the restored canonical/ alone,
    #   4. verify (re-hash canonical against the rebuilt catalog),
    #   5. replay the golden queries against the restored corpus,
    #   6. report — and cross-check the restored corpus's document/passage
    #      counts against the source of truth (the live catalog, read-only).
    #
    # It READS the live corpus (backup is read-only on its sources) and WRITES
    # exclusively under the caller-supplied tmp workspace, so the orchestrator
    # can point it at the LIVE config at acceptance. The whole run is in-process
    # (the same Backup / Rebuild / Verify / Health code the CLI drives), so it is
    # fast and unit-testable; the restored root gets its OWN Config, honest to
    # the fresh-machine layout.
    class Drill
      Counts = Data.define(:documents, :passages)

      Report = Data.define(
        :target, :machine_root, :backup, :rebuild_quarantined,
        :verify_clean, :golden_found, :golden_lost, :golden_skipped,
        :source_counts, :restored_counts
      ) do
        # A rebuild off restored canonical must quarantine nothing new, verify
        # must be clean, no golden query may be lost, and — when the live
        # catalog was available to compare — the restored counts must match it.
        def counts_match? = source_counts.nil? || source_counts == restored_counts

        def ok?
          backup.ok? && rebuild_quarantined.zero? && verify_clean &&
            golden_lost.zero? && counts_match?
        end
      end

      def initialize(config:, workspace:, now: Time.now)
        @config = config
        @workspace = workspace
        @now = now
      end

      def run
        target = File.join(@workspace, "target")
        machine = File.join(@workspace, "machine")
        source_counts = read_counts(@config.catalog_path)

        backup = back_up(target)
        restore(target, machine)
        restored = restored_config(machine)

        rebuild = rebuild_restored(restored)
        verify = verify_restored(restored)
        golden = replay_golden(restored)

        Report.new(
          target: target, machine_root: machine, backup: backup,
          rebuild_quarantined: rebuild.outcomes.sum { |o| o.report.errored },
          verify_clean: verify.clean?,
          golden_found: golden.count { |g| g.status == :found },
          golden_lost: golden.count(&:lost?),
          golden_skipped: golden.count { |g| g.status == :skipped },
          source_counts: source_counts,
          restored_counts: read_counts(restored.catalog_path)
        )
      end

      private

      def back_up(target)
        Backup.new(config: @config, target: target, allow_unmounted: true).run
      end

      # The restore side of the drill: rsync each backed-up section back into a
      # fresh machine root — exactly what an operator does on new hardware after
      # cloning the repo. Mirrors the backup layout (canonical/, config/, db/).
      def restore(target, machine)
        %w[canonical config db].each do |sub|
          src = File.join(target, sub)
          next unless Dir.exist?(src)

          dest = File.join(machine, sub)
          FileUtils.mkdir_p(dest)
          Shell.run("rsync", "-a", File.join(src, ""), dest)
        end
      end

      # The restored tree's OWN config, pointed at the machine root — not the
      # live config. Built directly (rather than loading the restored nabu.yml)
      # so the drill never depends on how the live config resolves its paths.
      def restored_config(machine)
        Config.new(
          canonical_dir: File.join(machine, "canonical"),
          db_dir: File.join(machine, "db"),
          sources_path: File.join(machine, "config", "sources.yml"),
          config_path: File.join(machine, "config", "nabu.yml")
        )
      end

      def rebuild_restored(restored)
        Rebuild.new(config: restored, registry: SourceRegistry.load(restored.sources_path)).run
      end

      def verify_restored(restored)
        catalog = open_catalog(restored.catalog_path)
        Verify.new(config: restored, registry: SourceRegistry.load(restored.sources_path), db: catalog).run
      ensure
        catalog&.disconnect
      end

      def replay_golden(restored)
        catalog = open_catalog(restored.catalog_path)
        fulltext = open_fulltext(restored.fulltext_path)
        ledger = open_ledger(restored.history_path)
        Health::LocalCheck.new(
          registry: SourceRegistry.load(restored.sources_path),
          catalog: catalog, fulltext: fulltext, ledger: ledger,
          golden_queries: Health::LocalCheck.golden_queries, now: @now
        ).run.golden
      ensure
        catalog&.disconnect
        fulltext&.disconnect
        ledger&.disconnect
      end

      # Document/passage counts from a catalog file, or nil when it is absent
      # (the live drill may run with derived dbs never built — the drill then
      # self-validates through verify + golden rather than a count match).
      def read_counts(path)
        return nil unless File.exist?(path)

        db = Store.connect(path)
        return nil unless db.table_exists?(:documents)

        Counts.new(documents: db[:documents].count, passages: db[:passages].count)
      ensure
        db&.disconnect
      end

      def open_catalog(path)
        return nil unless File.exist?(path)

        db = Store.connect(path)
        Store.setup!(db)
        db
      end

      def open_fulltext(path)
        return nil unless File.exist?(path)

        db = Store.connect_fulltext(path)
        return db if db.table_exists?(Store::Indexer::TABLE)

        db.disconnect
        nil
      end

      def open_ledger(path)
        return nil unless File.exist?(path)

        db = Store::Ledger.connect(path)
        return Store::Ledger.setup!(db) if db.table_exists?(:runs)

        db.disconnect
        nil
      end
    end
  end
end
