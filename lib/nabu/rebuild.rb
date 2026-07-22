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
  # - sync_policy (auto/manual/frozen) is irrelevant to rebuild: policies gate
  #   network syncs, and rebuild does no network. We replay whatever is local.
  # - Disabled sources ARE replayed when their canonical dir exists: the data is
  #   already local and licensed, and `enabled` gates *future* syncs, not replay
  #   of data on disk.
  # - A fresh rebuild should quarantine nothing; LoadReport.errored > 0 means a
  #   parser regression (P1-4), so it is surfaced as a warning (collected, never
  #   aborting the rebuild).
  class Rebuild
    # How many parsed documents the plain Loader batches into one transaction
    # during rebuild (P36-2). Rebuild replays each source as pure inserts, so
    # ~one commit per document is wasteful; batching collapses them while a
    # per-document savepoint keeps a bad document from rolling back its batch.
    # A FIXED batch (not one transaction per whole source) bounds the
    # uncommitted WAL frames a 353k-document source (cdli) would otherwise pile
    # up — the memory/disk ceiling the single-mega-transaction alternative
    # lacked (measured: the fixed batch matches its speed without the ceiling).
    # The loader additionally caps a batch at Loader::TX_BATCH_ROWS buffered
    # passages (P37-7): a document count alone let mega-document sources
    # (kanripo/cbeta shape) turn one batch into a multi-GB transaction whose
    # savepoint statement journal — in RAM under the rebuild pragmas'
    # temp_store=MEMORY — caused the measured ×1.6–3.4 load regression.
    LOAD_TX_BATCH = 1_000

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
    Result = Data.define(:db_path, :db_existed, :outcomes, :skips, :indexed, :axes, :facets, :profile) do
      # +axes+ (P15-2) is the TimelineBuilder::Summary of the timeline
      # regenerated from canonical after replay; +facets+ (P17-2) the
      # FacetBuilder::Summary of the genre-facet table projected from the
      # replayed documents' metadata. +profile+ (P36-0) is the always-on
      # RebuildProfile of per-source/per-stage wall times (nil only for the
      # pre-P36 construction paths). All default nil so every existing
      # construction stays valid.
      def initialize(db_path:, db_existed:, outcomes:, skips:, indexed:, axes: nil, facets: nil, profile: nil)
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
      # P36-0: the always-on stage profiler. Cheap (a monotonic sample per stage
      # boundary; per document for parse/insert), so it runs on every rebuild —
      # observability only, never persisted, so rebuild-safe by construction.
      profile = RebuildProfile.new
      ledger = Store::Ledger.open_with_lift!(history_path: history_path, catalog_path: db_path)
      FileUtils.rm_f(db_path)
      FileUtils.rm_f(fulltext_path) # the index is derived-of-derived; drop it too
      db = fresh_db
      # P36-2: bulk-load with the non-unique secondary indexes DROPPED, then
      # build them in one pass at the end (Store.create_deferred_indexes!). A
      # crashed rebuild is simply re-run, so a transiently index-less db is safe.
      Store.drop_deferred_indexes!(db)
      fulltext = Store.connect_fulltext(fulltext_path, rebuild: true)
      outcomes = []
      skips = []
      @registry.each_source do |entry|
        if replayable?(entry)
          progress&.stage(entry.slug)
          # The :load roll-up is the authoritative per-source number (parse +
          # insert + adapter build + run-recorder); parse/insert split rides
          # inside it via the loader's component timers.
          outcomes << profile.measure(scope: entry.slug, stage: :load) do
            replay(db, ledger, entry, progress, profile)
          end
          stamp!(db, entry)
        else
          skips << Skip.new(slug: entry.slug, reason: :no_canonical)
        end
      end
      replay_enrichments(db)
      # P36-2: the bulk insert is done — build the deferred secondary indexes in
      # one pass BEFORE the query-side stages (timeline/facets/indexer) that join
      # on passages.document_id.
      Store.create_deferred_indexes!(db)
      # The timeline (P15-2) is f(canonical): rebuild it from canonical
      # into the fresh catalog AFTER every source is back (it joins by urn), so
      # `nabu rebuild` regenerates document_axes and the invariant holds.
      progress&.stage("timeline")
      axes = profile.measure(scope: RebuildProfile::CORPUS, stage: :timeline) do
        Store::TimelineBuilder.rebuild!(catalog: db, canonical_dir: @config.canonical_dir)
      end
      # The facet table (P17-2) projects from the documents just replayed
      # (their metadata_json is f(canonical)), so it regenerates here too.
      progress&.stage("facets")
      facets = profile.measure(scope: RebuildProfile::CORPUS, stage: :facets) do
        Store::FacetBuilder.rebuild!(catalog: db)
      end
      # Reindex ONCE after all sources are back — the index is corpus-wide.
      progress&.stage("fulltext index")
      # The alignment registry (config, not derived) rides in so alignment_refs
      # regenerates with the re-minted passage ids (architecture §10). The
      # profile threads in so the index's own sub-stages (fts+lemma / trigram /
      # alignment / reflex) are timed as corpus stages.
      indexed = Store::Indexer.rebuild!(catalog: db, fulltext: fulltext,
                                        alignments: AlignmentRegistry.load(@config.alignments_path),
                                        fuzzy_slugs: @registry.fuzzy_slugs,
                                        lemma_tiers: @registry.lemma_tiers,
                                        profile: profile)
      Result.new(db_path: db_path, db_existed: db_existed, outcomes: outcomes,
                 skips: skips, indexed: indexed, axes: axes, facets: facets, profile: profile)
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
    def replay(db, ledger, entry, progress, profile = nil)
      source = entry.sync_source!(db)
      adapter = entry.build_adapter
      report = nil
      Store::RunRecorder.record(source_slug: entry.slug, kind: "rebuild") do
        report = build_loader(adapter, db, ledger, source, profile).load_from(
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
    # +profile+ (P36-0) is threaded into the two loaders that carry the corpus
    # mass — the plain text Loader and the DictionaryLoader — so their parse /
    # insert split is captured. The three dossier/note shelf loaders handle a
    # handful of tiny administrative documents; they take no profile, so those
    # sources show only their :load roll-up (measured by the caller), no split.
    def build_loader(adapter, db, ledger, source, profile = nil)
      case adapter.class.content_kind
      when :dictionary
        Store::DictionaryLoader.new(db: db, source: source, ledger: ledger,
                                    canonical_dir: @config.canonical_dir, profile: profile)
      when :language
        Store::LanguageDossierLoader.new(db: db, source: source, ledger: ledger)
      when :notes
        Store::NoteLoader.new(db: db, source: source, ledger: ledger)
      when :source
        Store::SourceDossierLoader.new(db: db, source: source, ledger: ledger)
      else
        Store::Loader.new(db: db, source: source, ledger: ledger, profile: profile,
                          tx_batch: LOAD_TX_BATCH)
      end
    end

    # P36-1: record the derivation fingerprint this replay just satisfied —
    # the identity `rebuild --incremental` compares to skip clean sources. A
    # full rebuild re-derives everything, so stamping here is correct by
    # construction; a weak fingerprint writes no stamp (absent = dirty).
    # P39-1: the fold digest is scoped by the source's language census, read
    # AFTER the replay (this call site runs post-replay) so it describes
    # exactly the derived rows the stamp vouches for.
    def stamp!(db, entry)
      languages = Store::DerivationStamp.derived_languages(db, entry.slug)
      Store::DerivationStamp.stamp!(db, slug: entry.slug,
                                        fingerprint: fingerprints.for_source(entry, languages: languages))
    end

    # Shared with IncrementalRebuild (subclass): one computer per run so the
    # code/fold digests are hashed once, not per source.
    def fingerprints
      @fingerprints ||= DerivationFingerprint.new(config: @config)
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
      # rebuild: true — the fast-and-unsafe rebuild-mode connection profile
      # (Store.rebuild_pragmas!): synchronous=OFF + big cache, sound only
      # because this db is regenerated from canonical/ (a crashed rebuild is
      # re-run, never recovered).
      db = Store.connect(db_path, rebuild: true)
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
