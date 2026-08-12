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

      # Named forensic entries per section beyond this cap render as an
      # announced "… and N more" — never a silent cut.
      RENDER_CAP = 10

      Report = Data.define(
        :target, :machine_root, :backup, :rebuild_quarantined,
        :verify_clean, :golden_found, :golden_lost, :golden_skipped,
        :source_counts, :restored_counts,
        :pure, :lects_match, :links_match, :grants_quiet, :creep_quiet,
        :verify_issues, :source_deltas
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

        # The printable report (Q21/P74: rendering lives ON the report so
        # the forensic sections are testable; the Rakefile just prints).
        def render
          lines = ["Restore drill"]
          lines << "  backup     → #{backup.target}  " \
                   "(#{backup.sections.count(&:ran?)}/#{backup.sections.size} sections, " \
                   "#{backup.files} files, #{backup.ok? ? 'OK' : 'FAILED'})"
          lines << "  restore    → #{machine_root}"
          lines << "  rebuild    quarantined #{rebuild_quarantined} document(s)"
          lines << "  verify     #{verify_clean ? 'clean' : 'FAILED'}"
          lines.concat(verify_issue_lines)
          lines << "  golden     #{golden_found} found, #{golden_lost} lost, #{golden_skipped} skipped"
          lines << "  counts     source=#{self.class.count_str(source_counts)}  " \
                   "restored=#{self.class.count_str(restored_counts)}  " \
                   "#{counts_match? ? 'MATCH' : 'MISMATCH'}"
          lines.concat(source_delta_lines)
          if pure
            lines << "  law        lects #{lects_match ? 'MATCH' : 'MISMATCH'} · " \
                     "links #{links_match ? 'MATCH' : 'MISMATCH'} · " \
                     "grants #{grants_quiet ? 'quiet' : 'RE-BLOCKED'} · " \
                     "creep #{creep_quiet ? 'quiet' : 'RE-ALARMED'}  (pure three-folder restore)"
          end
          lines << "  => #{ok? ? 'RESTORABLE' : 'NOT RESTORABLE'}"
          lines.join("\n")
        end

        def self.count_str(counts)
          counts.nil? ? "n/a" : "#{counts.documents} docs / #{counts.passages} passages"
        end

        private

        # The Q21 evidence sections: each failing document named with its
        # kind and detail; each differing source named with both counts.
        def verify_issue_lines
          return [] if verify_issues.empty?

          capped(["  verify failures (#{verify_issues.size}):"] +
                 verify_issues.first(RENDER_CAP).map do |issue|
                   "    #{issue.urn} (#{issue.kind}: #{issue.detail})"
                 end, verify_issues.size)
        end

        def source_delta_lines
          return [] if source_deltas.empty?

          capped(["  count deltas (#{source_deltas.size} source#{'s' unless source_deltas.size == 1}):"] +
                 source_deltas.first(RENDER_CAP).map do |slug, live, restored|
                   "    #{slug}: live #{self.class.count_str(live)} → " \
                     "restored #{self.class.count_str(restored)}"
                 end, source_deltas.size)
        end

        def capped(lines, total)
          lines << "    … and #{total - RENDER_CAP} more" if total > RENDER_CAP
          lines
        end
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
        restored_counts = read_counts(restored.catalog_path)

        Report.new(
          target: target, machine_root: machine, backup: backup,
          rebuild_quarantined: rebuild.outcomes.sum { |o| o.report.errored },
          verify_clean: verify.clean?,
          golden_found: golden.count { |g| g.status == :found },
          golden_lost: golden.count(&:lost?),
          golden_skipped: golden.count { |g| g.status == :skipped },
          source_counts: source_counts,
          restored_counts: restored_counts,
          pure: @pure,
          lects_match: !@pure || store_count(@config.lects_journal_path, :lect_assignments) ==
                                 store_count(restored.lects_journal_path, :lect_assignments),
          links_match: !@pure || store_count(@config.links_path, :links) ==
                                store_count(restored.links_path, :links),
          grants_quiet: !@pure || grants_quiet?(restored),
          creep_quiet: !@pure || creep_quiet?(restored),
          # Q21 (P74) — the evidence a failing drill hands over:
          verify_issues: verify.issues,
          source_deltas: source_deltas(source_counts, restored_counts, restored)
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

      # Q21: when the counts oracle mismatches, name the differing
      # source(s) — [slug, live Counts, restored Counts] per divergence,
      # union of both catalogs' slugs (a source absent on one side counts
      # 0/0 there, so a wholly lost source is named too).
      def source_deltas(source_counts, restored_counts, restored)
        return [] if source_counts.nil? || source_counts == restored_counts

        live = per_source_counts(@config.catalog_path)
        rest = per_source_counts(restored.catalog_path)
        (live.keys | rest.keys).sort.filter_map do |slug|
          zero = Counts.new(documents: 0, passages: 0)
          a = live.fetch(slug, zero)
          b = rest.fetch(slug, zero)
          [slug, a, b] unless a == b
        end
      end

      # {slug => Counts} for one catalog file.
      def per_source_counts(path)
        db = Store.connect(path, readonly: true)
        slugs = db[:sources].select_hash(:id, :slug)
        docs = db[:documents].group_and_count(:source_id).as_hash(:source_id, :count)
        passages = db[:passages].join(:documents, id: :document_id)
                                .group_and_count(Sequel[:documents][:source_id])
                                .as_hash(:source_id, :count)
        slugs.to_h do |source_id, slug|
          [slug, Counts.new(documents: docs.fetch(source_id, 0),
                            passages: passages.fetch(source_id, 0))]
        end
      ensure
        db&.disconnect
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
