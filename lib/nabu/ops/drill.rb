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
    #   3. rebuild the derived db from the restored permanent folders,
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
    # +pure: true+ (P71-8, THE LAW'S PROOF) restores ONLY the three
    # permanent folders — canonical/, config/, local/ — never db/: the
    # rebuild must re-mint every derived store from scratch, the lect
    # journal and links counts must match the live instruments (the
    # derivation oracles), and the grant/creep gates must answer from
    # local/config alone (no ledger row ever consulted for a decision).
    class Drill
      Counts = Data.define(:documents, :passages)

      Report = Data.define(
        :target, :machine_root, :backup, :rebuild_quarantined,
        :verify_clean, :golden_found, :golden_lost, :golden_skipped,
        :source_counts, :restored_counts,
        :pure, :lects_match, :links_match, :grants_quiet, :creep_quiet
      ) do
        # Verify must be clean, no golden query may be lost, and — when the
        # live catalog was available to compare — the restored counts must
        # match it. Quarantines are NOT a failure when the counts oracle is
        # available: a faithful restore REPRODUCES the source's honest
        # quarantines (the live corpus carries thousands of text-less papyri
        # stubs), and a genuinely lost document surfaces as a count mismatch.
        # Without a source to compare (no live catalog), fall back to the
        # conservative zero-quarantine requirement.
        def counts_match? = source_counts.nil? || source_counts == restored_counts

        def ok?
          backup.ok? && verify_clean && golden_lost.zero? && counts_match? &&
            (source_counts ? true : rebuild_quarantined.zero?) && pure_ok?
        end

        # The pure-mode law assertions (vacuously true otherwise).
        def pure_ok? = !pure || (lects_match && links_match && grants_quiet && creep_quiet)
      end

      def initialize(config:, workspace:, now: Time.now, pure: false)
        @config = config
        @workspace = workspace
        @now = now
        @pure = pure
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
          restored_counts: read_counts(restored.catalog_path),
          pure: @pure,
          lects_match: !@pure || store_count(@config.lects_journal_path, :lect_assignments) ==
                                 store_count(restored.lects_journal_path, :lect_assignments),
          links_match: !@pure || store_count(@config.links_path, :links) ==
                                store_count(restored.links_path, :links),
          grants_quiet: !@pure || grants_quiet?(restored),
          creep_quiet: !@pure || creep_quiet?(restored)
        )
      end

      private

      def back_up(target)
        Backup.new(config: @config, target: target, allow_unmounted: true).run
      end

      # The restore side of the drill: rsync each backed-up section back into a
      # fresh machine root — exactly what an operator does on new hardware after
      # cloning the repo. Mirrors the backup layout; pure mode restores ONLY
      # the three permanent folders (db/ must re-derive, the law's claim).
      def restore(target, machine)
        subs = @pure ? %w[canonical config local] : %w[canonical config local db]
        subs.each do |sub|
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
          local_dir: File.join(machine, "local"),
          sources_path: File.join(machine, "config", "sources.yml"),
          config_path: File.join(machine, "config", "nabu.yml")
        )
      end

      # Every grant recorded in the restored local/config answers
      # acknowledged? with NO ledger handle at all — config is the truth.
      def grants_quiet?(restored)
        gate = GrantGate.new(ledger: nil, grants_path: restored.grants_path)
        gate.config_grants.all? { |g| gate.acknowledged?(g["source"]) }
      end

      # Every creep acceptance reads back config-first on a nil ledger.
      def creep_quiet?(restored)
        Health::QuarantineBaseline
          .send(:config_acceptances, restored.creep_acceptances_path)
          .all? do |row|
            Health::QuarantineBaseline.latest_acceptance(
              nil, row["source"], path: restored.creep_acceptances_path
            )&.fetch(:accepted_baseline, nil) == row["baseline"]
          end
      end

      # Row count of one table in a store file (nil-safe: absent file or
      # table counts 0 — both sides of each oracle use the same rule).
      def store_count(path, table)
        return 0 unless File.exist?(path)

        db = Store.connect(path, readonly: true)
        db.table_exists?(table) ? db[table].count : 0
      ensure
        db&.disconnect
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
