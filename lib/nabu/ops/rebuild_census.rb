# frozen_string_literal: true

require "fileutils"
require "json"
require "time"

require_relative "../errors"
require_relative "../store/rebuild_runs"
require_relative "../store/source_aggregates"

module Nabu
  module Ops
    # `rake rebuild:census` — the BEFORE picture a full rebuild is verified
    # against (`rake rebuild:verify`, Ops::RebuildVerify): per source the
    # live document/passage counts and the fulltext membership, the
    # library totals, every db/ file's size (main file + its -wal), the
    # quarantine baselines the ledger holds, and the code revision. O(1)
    # on the catalog: the counts are the source_aggregates rows (migration
    # 054 — maintained at write time; `rake aggregates:backfill` populates
    # a pre-054 catalog), never a walk.
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
        { "captured_at" => now.utc.iso8601, "git_sha" => git_sha,
          "totals" => Store::SourceAggregates.rollup(catalog).transform_keys(&:to_s),
          "sources" => sources.sort.to_h, "files" => file_sizes(db_dir), "quarantine" => baselines(ledger) }
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
