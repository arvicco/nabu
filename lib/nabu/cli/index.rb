# frozen_string_literal: true

# Nabu::CLI — the `nabu index` subcommand family (IndexCLI). Carved out of
# lib/nabu/cli.rb, the registry that loads it.
module Nabu
  # `nabu index` (P112-3): the fulltext-index operations surface.
  class IndexCLI < Thor
    include DurationFormat

    namespace "index"

    # The doctor's report tables, in display order.
    DOCTOR_TABLES = [
      Nabu::Store::Indexer::TABLE,
      Nabu::Store::Indexer::CJK_TABLE,
      Nabu::Store::Indexer::TRIGRAM_TABLE
    ].freeze

    desc "doctor", "Index health: fts5 segment/tombstone gauges + per-source freshness stamps"
    long_desc <<~HELP, wrap: false
      Reads each fts5 table's structure record (segment count against the
      hard cap of 2000 — the count that, reached, wedges all writes with a
      misleading "database or disk is full" — plus pages and the tombstone
      share deletemerge pressure builds) and the per-source freshness
      stamps (which catalog state each slice serves). --consolidate then
      runs the bounded incremental-merge loop on the passage tables and
      truncates the WAL — the same announced loop bulk slices run, callable
      standalone when the gauges warn.
    HELP
    option :consolidate, type: :boolean, default: false,
                         desc: "run the bounded merge loop on the fts tables, then checkpoint"
    option :deadline, type: :numeric, banner: "MINUTES",
                      desc: "--consolidate only: index-watcher kill deadline (0 = never kill)"
    def doctor
      config = Nabu::Config.load
      unless File.exist?(config.fulltext_path)
        say "index doctor: no fulltext index at #{config.fulltext_path} (fresh clone, or awaiting rebuild)"
        return
      end

      fulltext = Nabu::Store.connect_fulltext(config.fulltext_path, readonly: !options[:consolidate])
      begin
        report_runs(config)
        report_gauges(fulltext)
        report_lanes(fulltext, config)
        report_stamps(fulltext, config)
        report_stale(fulltext)
        report_deferred(fulltext, config)
        if options[:consolidate]
          supervise(config, label: "index doctor --consolidate", estimate: nil) do |tee|
            consolidate(fulltext, progress: tee.call(nil))
          end
        end
      ensure
        fulltext.disconnect
      end
    end

    desc "refresh SLUG", "Refresh one source's fulltext slice (the index step a deferred sync skipped)"
    long_desc <<~HELP, wrap: false
      Runs the full slice refresh for one registered source — the same
      index step a sync runs inline, with the same announced stages and
      recorded stage timings. A source declared `index_policy: deferred`
      in config/sources.yml (the paced-crawl citizens) loads its documents
      at sync time and skips the index; this command pays it, once per
      wave. Any source may be refreshed: a pending (crashed) or behind
      slice heals here too. `index doctor` lists the deferred sources and
      whether their slice is behind the catalog.

      Examples:
        nabu index refresh ndl-kotenseki
        nabu index refresh wellcome
    HELP
    option :deadline, type: :numeric, banner: "MINUTES",
                      desc: "Index-watcher kill deadline (default 2x the ledger estimate; 0 = never kill)"
    option :accept_long, type: :boolean, default: false,
                         desc: "Run even when the preflight predicts more than the inline budget (~15m)"
    def refresh(slug)
      config = Nabu::Config.load
      registry = Nabu::SourceRegistry.load(config.sources_path)
      unless registry[slug]
        raise Thor::Error, "index refresh: unknown source #{slug.inspect} — " \
                           "known sources: #{registry.slugs.join(', ')}"
      end
      unless File.exist?(config.catalog_path)
        raise Thor::Error, "index refresh: no catalog at #{config.catalog_path} — run bin/nabu sync #{slug} first"
      end

      # The proportionality law's preflight (Nabu::IndexPreflight): the
      # plan prints and a long one refuses BEFORE any db is opened.
      Nabu::IndexPreflight.gate!(history_path: config.history_path, slugs: [slug],
                                 accept_long: options[:accept_long])
      run_refresh(config, registry, slug)
    rescue Nabu::Error => e
      raise Thor::Error, "index refresh: #{e.message}"
    end

    desc "maintain", "The maintenance rail: stale-aggregate recomputes, merge consolidation, WAL truncation"
    long_desc <<~HELP, wrap: false
      Runs ALL corpus-scale index work the sync path no longer pays inline
      (the proportionality law, docs/architecture.md §1), in one
      announced, ledgered run under the index watcher:

        1. every stale aggregate `index doctor` lists is recomputed and its
           flag cleared (char postings per source, the reflex closure, the
           corpus lemma census);
        2. every fts5 table's merge debt is consolidated in bounded chunks
           until the engine reports no work (the debt a sync only probes
           and reports as "run nabu index maintain");
        3. the WAL is truncated;
        4. the structure gauges are reported before and after.

      Resumable: a killed run leaves exactly its unfinished flags and the
      merge state it reached — the next run continues there. Fire it
      between phases (or from cron); the kill deadline defaults to 2x the
      ledger's estimate of the last run.

      Examples:
        nabu index maintain
        nabu index maintain --deadline 0
    HELP
    option :deadline, type: :numeric, banner: "MINUTES",
                      desc: "Index-watcher kill deadline (default 2x the ledger estimate; 0 = never kill)"
    def maintain
      config = Nabu::Config.load
      unless File.exist?(config.fulltext_path)
        say "index maintain: no fulltext index at #{config.fulltext_path} — nothing to maintain"
        return
      end
      unless File.exist?(config.catalog_path)
        raise Thor::Error, "index maintain: no catalog at #{config.catalog_path} — recomputes read it"
      end

      run_maintain(config)
    rescue Nabu::Error => e
      raise Thor::Error, "index maintain: #{e.message.delete_prefix('index maintain: ')}"
    end

    no_commands do
      def run_maintain(config)
        ledger = Nabu::Store::Ledger.open!(config.history_path)
        catalog = Nabu::Store.connect(config.catalog_path, readonly: true)
        fulltext = Nabu::Store.connect_fulltext(config.fulltext_path)
        narrator = Nabu::CLI.new
        estimate = Nabu::IndexWatcher.ledger_estimate(ledger, kind: Nabu::Store::IndexMaintenance::KIND)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        report = supervise(config, label: "index maintain", estimate: estimate) do |tee|
          Nabu::Store::IndexMaintenance.run!(catalog: catalog, fulltext: fulltext, ledger: ledger,
                                             progress: tee.call(narrator.progress_reporter))
        end
        narrator.finish_progress
        print_maintain(report, Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
      ensure
        fulltext&.disconnect
        catalog&.disconnect
        ledger&.disconnect
      end

      def print_maintain(report, seconds)
        recomputed = report.recomputed.empty? ? "no stale aggregates" : "recomputed #{report.recomputed.join(', ')}"
        say "index maintain: #{recomputed}; #{report.merge_chunks} merge chunks; WAL truncated " \
            "(#{format_duration(seconds)})"
        report.gauges_after.each do |table, gauges|
          was = report.gauges_before[table]
          say "  #{table}: #{"#{was[:segments]} → " if was}#{gauges[:segments]} segments · " \
              "tombstones #{gauges[:tombstone_pages]} (#{format('%.1f%%', gauges[:tombstone_share] * 100)})"
        end
      end

      # The stale-aggregate flags (Store::StaleAggregates): what the
      # maintenance rail owes, oldest first.
      def report_stale(fulltext)
        flags = Nabu::Store::StaleAggregates.all(fulltext)
        return say "stale aggregates: none" if flags.empty?

        say "stale aggregates (nabu index maintain recomputes):"
        flags.each do |flag|
          say "  ⚠ #{flag[:aggregate]} (#{flag[:scope]}) since #{flag[:marked_at]} — #{flag[:reason]}"
        end
      end

      # The refresh rides SyncRunner#index_entry (the sync path's own
      # reindex! wiring) and the main CLI's progress reporter, so the
      # stages read exactly as they do inside a sync.
      def run_refresh(config, registry, slug)
        Nabu::Store.assert_writable!(config.catalog_path)
        ledger = Nabu::Store::Ledger.open!(config.history_path)
        catalog = Nabu::Store.connect(config.catalog_path)
        Nabu::Store.setup!(catalog)
        runner = Nabu::SyncRunner.new(config: config, registry: registry, db: catalog, ledger: ledger)
        narrator = Nabu::CLI.new
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        estimate = Nabu::IndexWatcher.ledger_estimate(ledger, kind: "sync", scopes: [slug, "corpus"],
                                                              stages: Nabu::IndexWatcher::REFRESH_STAGES)
        covered = Nabu::IndexWatcher.evidence_covers?(ledger, kind: "sync", scopes: [slug, "corpus"],
                                                              stages: Nabu::IndexWatcher::REFRESH_STAGES)
        indexed = supervise(config, label: "index refresh #{slug}", estimate: estimate, slug: slug,
                                    arm_kill: covered) do |tee|
          runner.index_entry(slug, progress: tee.call(narrator.progress_reporter))
        end
        narrator.finish_progress
        seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        say "index refresh: #{slug} — indexed #{indexed} passages (#{format_duration(seconds)})"
      ensure
        catalog&.disconnect
        ledger&.disconnect
      end

      # The index watcher over this command's writes (Nabu::IndexWatcher —
      # the CLI class's supervised_index_write, for this Thor class).
      def supervise(config, label:, estimate:, slug: nil, arm_kill: true, &)
        deadline = Nabu::IndexWatcher.deadline_for(estimate: estimate, override_minutes: options[:deadline],
                                                   arm_default: arm_kill)
        if deadline || $stderr.tty?
          warn Nabu::IndexWatcher.arming_line(deadline: deadline, estimate: estimate, kill_default: arm_kill)
        end
        Nabu::IndexWatcher.supervise(label: label, fulltext_path: config.fulltext_path, deadline: deadline,
                                     slug: slug, &)
      end

      # P168: the index_policy: deferred sources and whether each slice
      # is behind the catalog (the P111-1b probe) — a deferred wave with
      # no freshness stamp (the first wave after a full rebuild) would
      # otherwise read as "everything fresh". Silent when none declared.
      def report_deferred(fulltext, config)
        deferred = Nabu::SourceRegistry.load(config.sources_path).each_source.select(&:index_deferred?)
        return if deferred.empty? || !File.exist?(config.catalog_path)

        say "deferred-index sources (index_policy: deferred):"
        catalog = Nabu::Store.connect(config.catalog_path, readonly: true)
        begin
          deferred.map(&:slug).sort.each do |slug|
            behind = Nabu::Store::Indexer.slice_behind?(fulltext, catalog, slug)
            say(behind ? "  #{slug}: BEHIND the catalog — run bin/nabu index refresh #{slug}" : "  #{slug}: current")
          end
        ensure
          catalog.disconnect
        end
      end

      def report_gauges(fulltext)
        say "fts5 structure (segment hard cap 2000):"
        DOCTOR_TABLES.each do |table|
          gauges = Nabu::Store::FtsStructure.gauges(fulltext, table)
          next say "  #{table}: absent" if gauges.nil?

          share = format("%.1f%%", gauges[:tombstone_share] * 100)
          say "  #{table}: #{gauges[:segments]} segments / #{gauges[:levels]} levels · " \
              "#{gauges[:pages]} pages · tombstones #{gauges[:tombstone_pages]} (#{share})" \
              "#{segment_flag(gauges[:segments])}"
        end
      end

      # The run-health lines (the dead-row sweep + an unfinished rebuild —
      # RebuildRuns.health_lines, shared with `nabu status`). The
      # doctor is the place a partial index gets diagnosed, so it opens
      # the ledger for writing (migrating it forward) when one exists.
      def report_runs(config)
        return unless File.exist?(config.history_path)

        ledger = Nabu::Store::Ledger.open!(config.history_path)
        Nabu::Store::RebuildRuns.health_lines(ledger).each { |line| say line }
      ensure
        ledger&.disconnect
      end

      # The lane-coverage check (Store::LaneCoverage — the Nov 2026
      # crash-loss incident): config flags vs built scope vs rows, every
      # disagreement a ⚠ line. Needs the catalog for the row probes; a
      # box without one says so instead of guessing.
      def report_lanes(fulltext, config)
        say "lane coverage (config flags vs built scope vs rows):"
        unless File.exist?(config.catalog_path)
          return say "  (no catalog at #{config.catalog_path} — row probes skipped)"
        end

        registry = Nabu::SourceRegistry.load(config.sources_path)
        catalog = Nabu::Store.connect(config.catalog_path, readonly: true)
        begin
          lanes = { cjk: [Nabu::Store::Indexer::CJK_SCOPE_TABLE, registry.cjk_slugs],
                    trigram: [Nabu::Store::Indexer::TRIGRAM_SCOPE_TABLE, registry.fuzzy_slugs] }
          lanes.each do |lane, (scope_table, flags)|
            summary = Nabu::Store::LaneCoverage.summary(fulltext, scope_table, flags)
            say "  #{lane}: #{summary || 'absent'}"
          end
          findings = Nabu::Store::LaneCoverage.findings(catalog: catalog, fulltext: fulltext,
                                                        cjk_slugs: registry.cjk_slugs,
                                                        fuzzy_slugs: registry.fuzzy_slugs)
          findings.each { |finding| say "  ⚠ #{finding.lane}: #{finding.message}" }
          say "  every flagged source is built and has rows" if findings.empty?
        ensure
          catalog.disconnect
        end
      end

      def segment_flag(segments)
        return "  ⚠ ANOMALY (≥#{Nabu::Store::FtsStructure::SEGMENT_ANOMALY})" if
          segments >= Nabu::Store::FtsStructure::SEGMENT_ANOMALY
        return "  ⚠ warn (≥#{Nabu::Store::FtsStructure::SEGMENT_WARN})" if
          segments >= Nabu::Store::FtsStructure::SEGMENT_WARN

        ""
      end

      def report_stamps(fulltext, config)
        stamps = Nabu::Store::Indexer.slice_stamps(fulltext)
        return say "freshness stamps: none (everything fresh from the last full rebuild)" if stamps.empty?

        say "freshness stamps (catalog state each slice serves):"
        catalog = File.exist?(config.catalog_path) ? Nabu::Store.connect(config.catalog_path, readonly: true) : nil
        begin
          stamps.sort.each { |slug, stamp| say "  #{stamp_line(slug, stamp, catalog)}" }
        ensure
          catalog&.disconnect
        end
      end

      def stamp_line(slug, stamp, catalog)
        return "#{slug}: PENDING since #{stamp[:started_at]} (crashed refresh — next sync heals)" if
          stamp[:finished_at].nil?
        return "#{slug}: finished #{stamp[:finished_at]} (pre-stamp row, no state claim)" if
          stamp[:live_rows].nil?

        line = "#{slug}: #{stamp[:live_rows]} rows @ #{stamp[:finished_at]}"
        return line unless catalog

        live, max_id = Nabu::Store::Indexer.source_live_stats(catalog, slug)
        fresh = live == stamp[:live_rows] && max_id == stamp[:max_passage_id]
        "#{line}#{fresh ? ' · fresh' : "  ⚠ STALE (catalog holds #{live})"}"
      end

      def consolidate(fulltext, progress: nil)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        chunks = [Nabu::Store::Indexer::TABLE, Nabu::Store::Indexer::CJK_TABLE].sum do |table|
          next 0 unless fulltext.table_exists?(table)

          say "consolidating #{table}…"
          Nabu::Store::Indexer.consolidate_merges!(fulltext, table, progress: progress)
        end
        seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        say "consolidated: #{chunks} merge chunks, WAL truncated (#{format_duration(seconds)})"
        report_gauges(fulltext)
      end
    end
  end
end
