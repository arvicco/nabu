# frozen_string_literal: true

require "fileutils"
require "json"
require "time"

require_relative "../errors"
require_relative "../store/rebuild_runs"
require_relative "../store/source_aggregates"
require_relative "db_snapshot"

module Nabu
  module Ops
    # `rake rebuild:census` — the BEFORE picture a full rebuild is verified
    # against (`rake rebuild:verify`, Ops::RebuildVerify): per source the
    # live document/passage counts and the fulltext membership, the
    # library totals, every db/ file's size (main file + its -wal), the
    # quarantine baselines the ledger holds, and the code revision. O(1)
    # on the catalog for the passage sources: their counts are the
    # source_aggregates rows (migration 054 — maintained at write time;
    # `rake aggregates:backfill` populates a pre-054 catalog), never a
    # walk. Dictionary-kind sources (entries, no aggregates row) are
    # counted live per source under "dictionaries" — one grouped pass
    # over the entries, seconds at library scale (.dictionary_counts).
    #
    # THE GATEWAY: this module is the one writer of local/rebuild/ —
    # instance state outside db/ (a rebuild must never wipe the picture it
    # is checked against), created on first capture, one JSON file per
    # capture, never overwritten:
    #
    #   local/rebuild/census-<UTC yyyymmddThhmmssZ>.json
    #
    # The verify step reads the newest census captured BEFORE the rebuild
    # it checks (.latest_before), so a census taken after the rebuild can
    # never pass for the before picture.
    module RebuildCensus
      DIRNAME = "rebuild"
      PATTERN = "census-*.json"

      class Refused < Nabu::Error; end

      module_function

      def dir(local_dir) = File.join(local_dir, DIRNAME)

      # The census as a Hash (string keys — what lands in the file).
      def build(catalog:, db_dir:, ledger: nil, now: Time.now, git_sha: Store::RebuildRuns.code_revision)
        unless Store::SourceAggregates.available?(catalog)
          raise Refused, "the catalog has no source_aggregates table (pre-054) — run `rake aggregates:backfill` first"
        end

        slugs = catalog[:sources].select_hash(:id, :slug)
        sources = Store::SourceAggregates.all(catalog).values.filter_map do |row|
          slug = slugs[row.source_id] or next
          [slug, { "documents" => row.documents_count, "passages" => row.passages_count,
                   "fts_members" => row.fts_member_count, "fts_behind" => row.fts_behind }]
        end
        dictionaries = dictionary_counts(catalog)
        totals = Store::SourceAggregates.rollup(catalog).transform_keys(&:to_s)
                                        .merge("dictionary_entries" => dictionaries.values.sum { |row| row["entries"] })
        { "captured_at" => now.utc.iso8601, "git_sha" => git_sha, "totals" => totals,
          "sources" => sources.sort.to_h, "dictionaries" => dictionaries,
          "files" => file_sizes(db_dir), "quarantine" => baselines(ledger) }
      end

      # { slug => { "dictionaries" => n, "entries" => live entries } } for
      # every dictionary-kind source — they hold entries, not passages, and
      # have no source_aggregates row. Counted LIVE (one grouped pass over
      # dictionary_entries — seconds at library scale), not read from the
      # derived dictionary_stats rows the rebuild itself re-projects: the
      # census is what those are checked against. Empty on a catalog
      # without the dictionary tables.
      def dictionary_counts(catalog)
        return {} unless catalog.table_exists?(:dictionaries) && catalog.table_exists?(:dictionary_entries)

        slugs = catalog[:sources].select_hash(:id, :slug)
        owners = catalog[:dictionaries].select_hash(:id, :source_id)
        entries = catalog[:dictionary_entries].where(withdrawn: false).group_and_count(:dictionary_id)
                                              .as_hash(:dictionary_id, :count)
        counts = Hash.new { |hash, slug| hash[slug] = { "dictionaries" => 0, "entries" => 0 } }
        owners.each do |dictionary_id, source_id|
          slug = slugs[source_id] or next
          counts[slug]["dictionaries"] += 1
          counts[slug]["entries"] += entries.fetch(dictionary_id, 0)
        end
        counts.sort.to_h
      end

      # Write the census through the gateway; returns [path, census].
      def capture!(catalog:, db_dir:, local_dir:, ledger: nil, now: Time.now, **)
        census = build(catalog: catalog, db_dir: db_dir, ledger: ledger, now: now, **)
        FileUtils.mkdir_p(dir(local_dir))
        path = File.join(dir(local_dir), "census-#{now.utc.strftime('%Y%m%dT%H%M%SZ')}.json")
        raise Refused, "#{path} already exists — a census is never overwritten" if File.exist?(path)

        File.write(path, "#{JSON.pretty_generate(census)}\n")
        [path, census]
      end

      # [path, census] of the newest census captured strictly before
      # +time+, or nil.
      def latest_before(local_dir, time)
        Dir.glob(File.join(dir(local_dir), PATTERN)).filter_map do |path|
          census = JSON.parse(File.read(path))
          captured = Time.iso8601(census.fetch("captured_at"))
          [path, census, captured] if captured < time
        rescue JSON::ParserError, KeyError, ArgumentError
          nil
        end.max_by(&:last)&.first(2)
      end

      # The rake task's SUMMARY line. The behind figure is the count of
      # source_aggregates rows carrying the loaders' write-time fts_behind
      # FLAG (set when a load moves index-visible rows, cleared by an index
      # refresh or rebuild) — not a probe of real index membership, so it
      # is labelled as the flag it is, beside how many sources have a
      # recorded membership at all: an unknown membership (NULL — never
      # refreshed since the aggregates were backfilled) reads as neither
      # behind nor current.
      def summary(census, path)
        totals = census.fetch("totals")
        sources = census.fetch("sources")
        dictionaries = census.fetch("dictionaries", {})
        known = sources.values.count { |row| !row["fts_members"].nil? }
        files = census.fetch("files")
        "SUMMARY rebuild:census — #{sources.size} passage sources · #{totals['documents_count']} documents · " \
          "#{totals['passages_count']} passages · #{totals['dictionary_entries'].to_i} dictionary entries over " \
          "#{dictionaries.size} dictionary source(s) · #{totals['behind_sources']} flagged fulltext-behind (the " \
          "loaders' write-time flag, not an index probe; membership recorded for #{known} of #{sources.size} " \
          "passage sources) · #{files.size} db file(s), #{DbSnapshot.human(files.values.sum)} → #{path}"
      end

      # { "catalog.sqlite3" => bytes (main + -wal) } for every db/*.sqlite3.
      def file_sizes(db_dir)
        Dir.glob(File.join(db_dir, "*.sqlite3")).to_h do |path|
          wal = "#{path}-wal"
          [File.basename(path), File.size(path) + (File.file?(wal) ? File.size(wal) : 0)]
        end
      end

      def baselines(ledger)
        return {} if ledger.nil? || !ledger.table_exists?(:quarantine_baselines)

        ledger[:quarantine_baselines].select_hash(:source_slug, :baseline)
      end
    end
  end
end
