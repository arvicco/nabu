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
    # A source that was replayed, carrying its LoadReport. +quarantine+
    # (P18-7) is the DELTA-aware quarantine finding for this replay — nil when
    # the errored count matches the recorded ledger baseline, so a standing
    # (audited) quarantine population no longer shouts "parser regression?" at
    # every rebuild while a CHANGE still does, loudly, with the delta.
    Outcome = Data.define(:slug, :report, :quarantine) do
      def initialize(slug:, report:, quarantine: nil)
        super
      end

      def warning? = !quarantine.nil?
    end

    # A source left untouched because it has no local canonical data yet.
    Skip = Data.define(:slug, :reason)

    # What a rebuild did. +indexed+ is the passage count in the freshly rebuilt
    # fulltext index (architecture §2): a fresh index is part of "loaded".
    Result = Data.define(:db_path, :db_existed, :outcomes, :skips, :indexed, :axes, :facets) do
      # +axes+ (P15-2) is the AxisBuilder::Summary of the date/place axis
      # regenerated from canonical after replay; +facets+ (P17-2) the
      # FacetBuilder::Summary of the genre-facet table projected from the
      # replayed documents' metadata. Both default nil for callers/tests that
      # predate them, so every existing construction stays valid.
      def initialize(db_path:, db_existed:, outcomes:, skips:, indexed:, axes: nil, facets: nil)
        super
      end

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
    # canonical/ (one sanctioned exception, P19-1: a replayed dictionary
    # source's language-notes accretion writes the local-language dossier
    # shelf through Nabu::LanguageShelf — deterministic and idempotent, a
    # byte-level no-op when the sections already exist) — and NEVER touches
    # the history ledger (P7-1): the ledger is
    # opened (created on a fresh machine; a pre-P7-1 catalog's history is
    # lifted into it first, BEFORE the file is deleted) but only appended to,
    # via the per-source "rebuild"-kind run rows. Runs/pins/revisions recorded
    # before the rebuild survive it by construction. +progress+ (a
    # Nabu::ProgressReporter or nil) is threaded into each source's loader for
    # live per-document ticks; the runner stays print-free.
    def run(progress: nil)
      db_existed = File.exist?(db_path)
      ledger = Store::Ledger.open_with_lift!(history_path: history_path, catalog_path: db_path)
      FileUtils.rm_f(db_path)
      FileUtils.rm_f(fulltext_path) # the index is derived-of-derived; drop it too
      db = fresh_db
      fulltext = Store.connect_fulltext(fulltext_path)
      outcomes = []
      skips = []
      @registry.each_source do |entry|
        if replayable?(entry)
          outcomes << replay(db, ledger, entry, progress)
        else
          skips << Skip.new(slug: entry.slug, reason: :no_canonical)
        end
      end
      replay_enrichments(db)
      # The date/place axis (P15-2) is f(canonical): rebuild it from canonical
      # into the fresh catalog AFTER every source is back (it joins by urn), so
      # `nabu rebuild` regenerates document_axes and the invariant holds.
      axes = Store::AxisBuilder.rebuild!(catalog: db, canonical_dir: @config.canonical_dir)
      # The facet table (P17-2) projects from the documents just replayed
      # (their metadata_json is f(canonical)), so it regenerates here too.
      facets = Store::FacetBuilder.rebuild!(catalog: db)
      # Reindex ONCE after all sources are back — the index is corpus-wide.
      # The alignment registry (config, not derived) rides in so alignment_refs
      # regenerates with the re-minted passage ids (architecture §10).
      indexed = Store::Indexer.rebuild!(catalog: db, fulltext: fulltext,
                                        alignments: AlignmentRegistry.load(@config.alignments_path),
                                        fuzzy_slugs: @registry.fuzzy_slugs,
                                        lemma_tiers: @registry.lemma_tiers)
      Result.new(db_path: db_path, db_existed: db_existed, outcomes: outcomes,
                 skips: skips, indexed: indexed, axes: axes, facets: facets)
    ensure
      db&.disconnect
      fulltext&.disconnect
      ledger&.disconnect
    end

    private

    # Reconcile the source row from the manifest, then replay its canonical
    # snapshot under a "rebuild"-kind ledger run row (slug-keyed; health
    # trends read kind=sync only, so replay counts never poison them). The
    # RunRecorder block returns the LoadReport (feeding the run counts); we
    # keep it for the Outcome too. The loader gets the ledger for durable
    # revision journaling — a replay into a fresh catalog only INSERTS, so it
    # writes no revisions (tested), but the seam stays uniform.
    def replay(db, ledger, entry, progress)
      source = entry.sync_source!(db)
      adapter = entry.build_adapter
      report = nil
      Store::RunRecorder.record(source_slug: entry.slug, kind: "rebuild") do
        report = build_loader(adapter, db, ledger, source).load_from(
          adapter,
          workdir: workdir_for(entry.slug), full: true,
          on_document: progress&.method(:load_tick)
        )
      end
      # Quarantine delta vs the ledger baseline, then advance it (P18-7: the
      # baseline is recorded at every ok sync/rebuild; the finding compares
      # against the PREVIOUS level, so each change announces exactly once).
      finding = Health::QuarantineBaseline.delta_finding(ledger, entry.slug, errored: report.errored)
      Health::QuarantineBaseline.record!(ledger, entry.slug, errored: report.errored)
      Outcome.new(slug: entry.slug, report: report, quarantine: finding)
    end

    # Same content-kind routing as SyncRunner (P11-4/P19-1/P24-1,
    # architecture §11/§16): dictionary sources replay through the
    # DictionaryLoader (with the corpus root — its language-notes accretion
    # is idempotent, so a replay re-derives the same dossier sections and
    # touches nothing), language dossier shelves through the
    # LanguageDossierLoader, the owner-notes shelf through the NoteLoader.
    def build_loader(adapter, db, ledger, source)
      case adapter.class.content_kind
      when :dictionary
        Store::DictionaryLoader.new(db: db, source: source, ledger: ledger,
                                    canonical_dir: @config.canonical_dir)
      when :language
        Store::LanguageDossierLoader.new(db: db, source: source, ledger: ledger)
      when :notes
        Store::NoteLoader.new(db: db, source: source, ledger: ledger)
      when :source
        Store::SourceDossierLoader.new(db: db, source: source, ledger: ledger)
      else
        Store::Loader.new(db: db, source: source, ledger: ledger)
      end
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

    def fulltext_path = @config.fulltext_path

    def history_path = @config.history_path
  end
end
