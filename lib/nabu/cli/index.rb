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
    def doctor
      config = Nabu::Config.load
      unless File.exist?(config.fulltext_path)
        say "index doctor: no fulltext index at #{config.fulltext_path} (fresh clone, or awaiting rebuild)"
        return
      end

      fulltext = Nabu::Store.connect_fulltext(config.fulltext_path, readonly: !options[:consolidate])
      begin
        report_gauges(fulltext)
        report_stamps(fulltext, config)
        consolidate(fulltext) if options[:consolidate]
      ensure
        fulltext.disconnect
      end
    end

    no_commands do
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

      def consolidate(fulltext)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        chunks = [Nabu::Store::Indexer::TABLE, Nabu::Store::Indexer::CJK_TABLE].sum do |table|
          next 0 unless fulltext.table_exists?(table)

          say "consolidating #{table}…"
          Nabu::Store::Indexer.consolidate_merges!(fulltext, table)
        end
        seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        say "consolidated: #{chunks} merge chunks, WAL truncated (#{format_duration(seconds)})"
        report_gauges(fulltext)
      end
    end
  end
end
