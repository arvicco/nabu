# frozen_string_literal: true

module Nabu
  # `nabu sync` — the network-facing counterpart to Rebuild (architecture §3,
  # §8). One source at a time: reconcile its row from the manifest, fetch the
  # upstream snapshot into canonical/<slug>/, guard against a mass-withdrawal,
  # then load via the shared Loader — all under a RunRecorder `runs` row.
  #
  # == sync_policy and --all
  #
  # `sync <slug>` is EXPLICIT and unconditional: an operator asking for a source
  # by name gets it, disabled or not (explicit beats config). `sync --all` is
  # the unattended path and respects the registry strictly: only ENABLED sources
  # with sync_policy "live" run — "manual" and "frozen" are excluded by design
  # (docs/maintenance-and-extension.md §2), and one source's failure never stops
  # the others.
  #
  # == The circuit breakers (architecture §8, relocated in P5-2)
  #
  # The PRIMARY mass-deletion breaker now lives in the fetch path
  # (Adapter#guard_mass_deletion!, driven by Nabu::GitFetch): it predicts from
  # the HEAD..FETCH_HEAD deletion diff and trips BEFORE the merge, so an
  # aborted sync leaves the canonical working tree byte-unchanged — a plain
  # `--force` then attics the deleted files and retires (never loses) their
  # documents.
  #
  # The load-side guard here remains as the second line of defense: before
  # loading anything it predicts the withdrawal sweep as the set-difference of
  # this source's existing non-withdrawn document urns and the ids
  # discover_with_attic() yields (cheap directory walking — no parse; attic
  # documents count as PRESENT, so retained corpora never false-trip). It
  # covers what the fetch breaker cannot see: --parse-only over a damaged
  # snapshot, discover regressions, and future non-git adapters. If it would
  # withdraw more than WITHDRAWAL_THRESHOLD of the source, we raise
  # Nabu::SyncAborted and write NOTHING. `--force` overrides both breakers.
  # The prediction is exact for adapters whose DocumentRef#id IS the document
  # urn (Perseus, the reference case); that identity is why discover can stand
  # in for a parse here.
  #
  # == parse-only
  #
  # `--parse-only` skips fetch entirely (Adapter#fetch is never called) and
  # re-parses whatever snapshot is already on disk — the same "no network" stance
  # as Rebuild, but scoped to one source and still under the load-side breaker.
  # The prior last_sync_sha is preserved (there was no new fetch to pin).
  class SyncRunner
    # Trip the load-side breaker when a sync would withdraw strictly more than
    # this fraction of a source's live documents. Shares the fetch-side value.
    WITHDRAWAL_THRESHOLD = Nabu::Adapter::MASS_DELETION_THRESHOLD

    # What one source's sync did. Mirrors Rebuild::Outcome. On a tripped breaker
    # load_report is nil and #aborted? is true, with +breaker+ carrying the
    # Nabu::SyncAborted (its counts + message) for reporting; otherwise breaker
    # is nil, fetch_report is present (nil under --parse-only) and load_report
    # holds the Loader's counts.
    Outcome = Data.define(:slug, :fetch_report, :load_report, :breaker, :indexed) do
      def aborted? = !breaker.nil?
    end

    def initialize(config:, registry:, db:)
      @config = config
      @registry = registry
      @db = db
    end

    # Sync exactly the named source, disabled or not (explicit request). An
    # unknown slug is a ValidationError. Returns an Outcome; a tripped breaker
    # returns Outcome#aborted? (the `runs` row is recorded "aborted"). Any other
    # Nabu::Error (fetch failure, ...) propagates after its failure is recorded.
    def sync(slug, parse_only: false, force: false, progress: nil)
      entry = @registry[slug]
      raise ValidationError, "unknown source #{slug.inspect}" if entry.nil?

      sync_entry(entry, parse_only: parse_only, force: force, progress: progress)
    end

    # Sync every ENABLED, sync_policy "live" source. Returns { slug => Outcome |
    # Nabu::Error }: a source that raises is captured in the hash so the batch
    # runs to completion (one failure never stops the others).
    def sync_all(parse_only: false, force: false, progress: nil)
      live_enabled.to_h do |entry|
        result =
          begin
            sync_entry(entry, parse_only: parse_only, force: force, progress: progress)
          rescue Nabu::Error => e
            e
          end
        [entry.slug, result]
      end
    end

    private

    def live_enabled
      @registry.each_source.select { |entry| entry.enabled && entry.sync_policy == "live" }
    end

    def sync_entry(entry, parse_only:, force:, progress:)
      source = entry.sync_source!(@db)
      adapter = entry.adapter_class.new
      workdir = workdir_for(entry.slug)
      fetch_report = nil
      load_report = nil

      begin
        Store::RunRecorder.record(db: @db, source: source) do
          fetch_report = fetch(adapter, workdir, force: force, progress: progress) unless parse_only
          guard_withdrawal!(adapter, source, workdir, force: force)
          load_report = load(source, adapter, workdir, progress)
        end
      rescue Nabu::SyncAborted => e
        # Recorded "aborted" by RunRecorder; nothing was loaded, source row
        # untouched. Report it rather than crashing the batch.
        return Outcome.new(slug: entry.slug, fetch_report: fetch_report, load_report: nil,
                           breaker: e, indexed: nil)
      end

      update_source_state(source, fetch_report)
      # Reindex the fulltext AFTER the RunRecorder block: the index is
      # corpus-wide, not per-source, so it must not live inside a source's run
      # row (an indexing failure surfaces as its own error, never a falsified
      # run). A full rebuild per successful source is simple and correct;
      # incremental per-source indexing is the future optimization.
      indexed = reindex!
      Outcome.new(slug: entry.slug, fetch_report: fetch_report, load_report: load_report,
                  breaker: nil, indexed: indexed)
    end

    # Rebuild the whole FTS5 index from the (now-updated) catalog into the
    # fulltext db. Opens its own short-lived connection to config.fulltext_path
    # so callers need not thread a handle through. Returns the passage count.
    def reindex!
      require "fileutils"
      FileUtils.mkdir_p(File.dirname(@config.fulltext_path))
      fulltext = Store.connect_fulltext(@config.fulltext_path)
      Store::Indexer.rebuild!(catalog: @db, fulltext: fulltext)
    ensure
      fulltext&.disconnect
    end

    def fetch(adapter, workdir, force:, progress:)
      adapter.fetch(workdir, progress: progress&.method(:fetch_line), force: force)
    end

    def load(source, adapter, workdir, progress)
      Store::Loader.new(db: @db, source: source)
                   .load_from(adapter, workdir: workdir, full: true, on_document: progress&.method(:load_tick))
    end

    # Predict the withdrawal sweep and refuse if it exceeds the threshold. Runs
    # before any load, so a tripped breaker loads nothing (the canonical tree
    # was already protected by the fetch-side breaker). Attic documents are
    # discovered too, so retained corpora count as present, never withdrawn.
    def guard_withdrawal!(adapter, source, workdir, force:)
      return if force

      existing = Store::Document.where(source_id: source.id, withdrawn: false).select_map(:urn)
      return if existing.empty?

      discovered = adapter.discover_with_attic(workdir).to_set(&:id)
      would_withdraw = existing.count { |urn| !discovered.include?(urn) }
      return unless would_withdraw > WITHDRAWAL_THRESHOLD * existing.size

      raise SyncAborted.new(
        existing_count: existing.size, would_withdraw_count: would_withdraw, threshold: WITHDRAWAL_THRESHOLD
      )
    end

    # On success, stamp the sync time and pin the fetched sha. A --parse-only
    # run has no fetch_report, so its prior last_sync_sha is preserved.
    def update_source_state(source, fetch_report)
      attrs = { last_sync_at: Time.now }
      attrs[:last_sync_sha] = fetch_report.sha if fetch_report
      source.update(attrs)
    end

    def workdir_for(slug) = File.join(@config.canonical_dir, slug)
  end
end
