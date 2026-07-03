# frozen_string_literal: true

require "fileutils"

module Nabu
  # `nabu rebuild` — the proof of the one-way data-flow invariant (architecture
  # §1): drop the derived catalog db and regenerate it from canonical/ alone.
  #
  # PARSE-ONLY. Rebuild NEVER calls Adapter#fetch — there is no network here. It
  # replays the canonical snapshot each source already fetched, so `db/` is a
  # pure function of `canonical/` (plus, eventually, the enrichment journal).
  # Consequences of that stance:
  #
  # - A source whose canonical dir is missing or empty was never synced, so
  #   there is nothing local to replay: it is SKIPPED (a note, not an error, and
  #   no run row) rather than fetched.
  # - sync_policy (live/manual/frozen) is irrelevant to rebuild: policies gate
  #   network syncs, and rebuild does no network. We replay whatever is local.
  # - Disabled sources ARE replayed when their canonical dir exists: the data is
  #   already local and licensed, and `enabled` gates *future* syncs, not replay
  #   of data on disk.
  # - A fresh rebuild should quarantine nothing; LoadReport.errored > 0 means a
  #   parser regression (P1-4), so it is surfaced as a warning (collected, never
  #   aborting the rebuild).
  class Rebuild
    # A source that was replayed, carrying its LoadReport.
    Outcome = Data.define(:slug, :report) do
      def warning? = report.errored.positive?
    end

    # A source left untouched because it has no local canonical data yet.
    Skip = Data.define(:slug, :reason)

    # What a rebuild did.
    Result = Data.define(:db_path, :db_existed, :outcomes, :skips) do
      # Outcomes that quarantined at least one document (parser regressions).
      def warnings = outcomes.select(&:warning?)
    end

    # What a rebuild WOULD do, for --dry-run. +items+ is a list of
    # [slug, :replay | :skip_no_canonical] pairs in registration order.
    Plan = Data.define(:db_path, :db_exists, :items)

    def initialize(config:, registry:)
      @config = config
      @registry = registry
    end

    # Describe a would-be rebuild without changing anything on disk.
    def plan
      Plan.new(
        db_path: db_path,
        db_exists: File.exist?(db_path),
        items: @registry.each_source.map do |entry|
          [entry.slug, replayable?(entry) ? :replay : :skip_no_canonical]
        end
      )
    end

    # Delete the catalog db file, re-migrate a fresh one, and replay every
    # source that has local canonical data. Returns a Result. Never touches
    # canonical/. +progress+ (a Nabu::ProgressReporter or nil) is threaded into
    # each source's loader for live per-document ticks; the runner stays
    # print-free.
    def run(progress: nil)
      db_existed = File.exist?(db_path)
      FileUtils.rm_f(db_path)
      db = fresh_db
      outcomes = []
      skips = []
      @registry.each_source do |entry|
        if replayable?(entry)
          outcomes << replay(db, entry, progress)
        else
          skips << Skip.new(slug: entry.slug, reason: :no_canonical)
        end
      end
      replay_enrichments(db)
      Result.new(db_path: db_path, db_existed: db_existed, outcomes: outcomes, skips: skips)
    ensure
      db&.disconnect
    end

    private

    # Reconcile the source row from the manifest, then replay its canonical
    # snapshot under a runs row. The RunRecorder block returns the LoadReport
    # (feeding the run counts); we keep it for the Outcome too.
    def replay(db, entry, progress)
      source = entry.sync_source!(db)
      report = nil
      Store::RunRecorder.record(db: db, source: source) do
        report = Store::Loader.new(db: db, source: source).load_from(
          entry.adapter_class.new,
          workdir: workdir_for(entry.slug), full: true,
          on_document: progress&.method(:load_tick)
        )
      end
      Outcome.new(slug: entry.slug, report: report)
    end

    # Enrichment replay is OUT OF SCOPE for rebuild-of-text (architecture §6):
    # once enrichers land, this is where rebuild will re-apply them from the
    # provenance/enrichment journal after the text tables are back. No-op hook.
    def replay_enrichments(_db) = nil

    # Replayable iff there is local canonical data to parse. Deliberately
    # ignores `enabled` and `sync_policy` (see class comment).
    def replayable?(entry)
      dir = workdir_for(entry.slug)
      Dir.exist?(dir) && !Dir.empty?(dir)
    end

    def fresh_db
      FileUtils.mkdir_p(File.dirname(db_path))
      db = Store.connect(db_path)
      Store.migrate!(db)
      Store.setup!(db)
      db
    end

    def workdir_for(slug) = File.join(@config.canonical_dir, slug)

    def db_path = @config.catalog_path
  end
end
