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

    # P78-r2: the indexer's six timed sub-stages — what the "fulltext index"
    # umbrella estimate sums over (see index_eta).
    INDEX_ETA_STAGES = %w[fts_lemma trigram passage_chars passage_signs alignment reflex].freeze

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
    Result = Data.define(:db_path, :db_existed, :outcomes, :skips, :indexed, :axes, :facets, :profile,
                         :analyzed, :link_failures) do
      # +axes+ (P15-2) is the TimelineBuilder::Summary of the timeline
      # regenerated from canonical after replay; +facets+ (P17-2) the
      # FacetBuilder::Summary of the genre-facet table projected from the
      # replayed documents' metadata. +profile+ (P36-0) is the always-on
      # RebuildProfile of per-source/per-stage wall times (nil only for the
      # pre-P36 construction paths). All default nil so every existing
      # construction stays valid.
      # +analyzed+ (P42-4) is the Store::AnalyzeReport of the post-rebuild
      # planner-stats refresh — a full rebuild re-derives the whole catalog and
      # index, so it ALWAYS analyzes both (the freshly-loaded db had no
      # sqlite_stat1 at all). nil only for the pre-P42-4 construction paths.
      # +link_failures+ (P70-3b) — the links stage's contained per-producer
      # failures ("slug: message" strings): the summary must name the gaps a
      # partial links re-mine left, never claim a clean rebuild over them.
      def initialize(db_path:, db_existed:, outcomes:, skips:, indexed:, axes: nil, facets: nil,
                     profile: nil, analyzed: nil, link_failures: [])
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
      # P70 fail-fast: a malformed hand edit to config/lect_rulings.yml must
      # refuse HERE — before the db drop and the hours of replay the late
      # lect-journal stage would otherwise waste.
      LectRulings.validate!(@config.lect_rulings_paths)
      db_existed = File.exist?(db_path)
      # P36-0: the always-on stage profiler. Cheap (a monotonic sample per stage
      # boundary; per document for parse/insert), so it runs on every rebuild.
      # Since P78-r1 its facts persist to the LEDGER at run end (stage_timings
      # — №R-21 territory, so still rebuild-safe: db/ stays f(canonical)).
      profile = RebuildProfile.new
      ledger = Store::Ledger.open_with_lift!(history_path: history_path, catalog_path: db_path)
      # Sidecars go WITH each db (Store.drop_database_files! — the 2026-08-02
      # incident: a held -shm surviving the drop poisons the fresh file).
      Store.drop_database_files!(db_path)
      Store.drop_database_files!(fulltext_path) # the index is derived-of-derived; drop it too
      db = fresh_db
      # P36-2: bulk-load with the non-unique secondary indexes DROPPED, then
      # build them in one pass at the end (Store.create_deferred_indexes!). A
      # crashed rebuild is simply re-run, so a transiently index-less db is safe.
      Store.drop_deferred_indexes!(db)
      fulltext = Store.connect_fulltext(fulltext_path, rebuild: true)
      outcomes = []
      skips = []
      # P89-1: pin every source's code identity BEFORE any replay — a stamp
      # minted hours into the run must describe the code the run loaded, not
      # whatever sits on disk by then (DerivationFingerprint#warm).
      @registry.each_source { |entry| fingerprints.warm(entry) }
      # Warming must COMPLETE before the first replay begins; folding it into
      # the replay loop would warm the last source hours after load time,
      # recreating the lying stamp.
      @registry.each_source do |entry| # rubocop:disable Style/CombinableLoops
        if replayable?(entry)
          progress&.stage(entry.slug, eta: load_eta(ledger, entry.slug))
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
      replay_place_index(db)
      # P36-2: the bulk insert is done — build the deferred secondary indexes in
      # one pass BEFORE the query-side stages (timeline/facets/indexer) that join
      # on passages.document_id.
      Store.create_deferred_indexes!(db)
      # The timeline (P15-2) is f(canonical): rebuild it from canonical
      # into the fresh catalog AFTER every source is back (it joins by urn), so
      # `nabu rebuild` regenerates document_axes and the invariant holds.
      progress&.stage("timeline", eta: corpus_eta(ledger, "timeline"))
      axes = profile.measure(scope: RebuildProfile::CORPUS, stage: :timeline) do
        Store::TimelineBuilder.rebuild!(catalog: db, canonical_dir: @config.canonical_dir)
      end
      # P63-7: the nabu-places registry projection re-runs AFTER the lanes
      # rebuilt document_axes (NULL-only, adapter-asserted wins) — db/ stays
      # a pure function of canonical/ incl. the registry under it. A missing
      # registry is the honest no-op.
      progress&.stage("place apply")
      Nabu::PlaceApply.run(catalog: db, canonical_dir: @config.canonical_dir)
      # The facet table (P17-2) projects from the documents just replayed
      # (their metadata_json is f(canonical)), so it regenerates here too.
      progress&.stage("facets", eta: corpus_eta(ledger, "facets"))
      facets = profile.measure(scope: RebuildProfile::CORPUS, stage: :facets) do
        Store::FacetBuilder.rebuild!(catalog: db)
      end
      # P89-1 (№R-54 (c)): the corpus builders just ran against the current
      # code — mint their sentinel so an incremental run can skip them
      # honestly until a builder file actually changes.
      Store::DerivationStamp.stamp_builders!(
        db, digest: DerivationFingerprint.builders_digest,
            migration_level: DerivationFingerprint.migration_level
      )
      # P70 (the derivability contract): the lect JOURNAL is derived — re-mint
      # it wholesale from the two-folder truth (config/lect_rulings.yml owner
      # rows + the compiled rules + infer-dates) BEFORE the facet reads it.
      # db/lects.sqlite3 thereby needs no backup: losing it loses nothing
      # this stage cannot restore.
      progress&.stage("lect journal", eta: corpus_eta(ledger, "lect_journal"))
      profile.measure(scope: RebuildProfile::CORPUS, stage: :lect_journal) do
        journal = Store::LectJournal.open!(@config.lects_journal_path)
        begin
          Store::LectJournal.rederive!(journal, catalog: db, config: @config)
        ensure
          journal.disconnect
        end
      end
      # The lect facet (P58-4) flattens the whole lect resolution — journal
      # rulings, source overrides, codemap defaults — into one indexed axis.
      # Feature-detected: no nabu-lects module -> zero rows, clean skip (the
      # registry carries the journal overlay via load_default's :auto).
      progress&.stage("lect facets", eta: corpus_eta(ledger, "lect_facets"))
      profile.measure(scope: RebuildProfile::CORPUS, stage: :lect_facets) do
        Store::LectFacets.rebuild!(catalog: db, registry: Nabu::Lects.load_default(config: @config))
      end
      # P61-3: the artifact-script lane — pure function of stored codes +
      # config/artifact_scripts.yml, re-derived wholesale like the stats.
      progress&.stage("artifact scripts", eta: corpus_eta(ledger, "artifact_scripts"))
      profile.measure(scope: RebuildProfile::CORPUS, stage: :artifact_scripts) do
        Store::ArtifactScripts.derive!(db, config_path: @config.artifact_scripts_path,
                                           registry: Nabu::Lects.load_default(config: @config))
      end
      # P42-0: the write-time census. The loader hooks maintained it through
      # the replay; the wholesale derivation here is the rebuildability
      # invariant made explicit — stats are exactly f(loaded catalog).
      progress&.stage("source stats", eta: corpus_eta(ledger, "stats"))
      profile.measure(scope: RebuildProfile::CORPUS, stage: :stats) do
        Store::SourceStats.derive!(db, note: "derived (rebuild)")
      end
      # Reindex ONCE after all sources are back — the index is corpus-wide.
      progress&.stage("fulltext index", eta: index_eta(ledger))
      # The alignment registry (config, not derived) rides in so alignment_refs
      # regenerates with the re-minted passage ids (architecture §10). The
      # profile threads in so the index's own sub-stages (fts+lemma / trigram /
      # alignment / reflex) are timed as corpus stages.
      indexed = Store::Indexer.rebuild!(catalog: db, fulltext: fulltext,
                                        alignments: AlignmentRegistry.load(@config.alignments_path),
                                        fuzzy_slugs: @registry.fuzzy_slugs,
                                        lemma_tiers: @registry.lemma_tiers,
                                        profile: profile,
                                        sign_list: Nabu::SignList.load_default(config: @config),
                                        progress: progress,
                                        lemma_shelf: lemma_shelf,
                                        lemma_filter_slugs: @registry.lemma_filter_slugs)
      # P70-3b (the derivability contract): the links instrument is DERIVED —
      # drop and re-mine it wholesale: every slug-scoped reference producer
      # (the sync-time lane replayed over the re-minted catalog) plus every
      # batch scope recorded in config/link_scopes.yml (parallels needs the
      # fulltext index, hence after it). db/links.sqlite3 thereby needs no
      # backup.
      progress&.stage("links", eta: corpus_eta(ledger, "links"))
      link_failures = profile.measure(scope: RebuildProfile::CORPUS, stage: :links) do
        rederive_links!(db, fulltext)
      end
      # P42-4: the fresh catalog+index have no planner statistics yet — ANALYZE
      # both so the very first query off a rebuilt db plans against real row
      # distributions (ops §10). A corpus stage in the always-on profile.
      progress&.stage("analyze", eta: corpus_eta(ledger, "analyze"))
      analyzed = profile.measure(scope: RebuildProfile::CORPUS, stage: :analyze) do
        Store::AnalyzeReport.new(scope: "catalog + index",
                                 seconds: Store.analyze!(db) + Store.analyze!(fulltext))
      end
      # P78-r1 (Q34): the profiler's facts now OUTLIVE the run — appended to
      # the ledger's stage_timings so the next rebuild can render ETAs. The
      # ledger is №R-21 territory (operational history, never dropped here),
      # so the derivability law holds: db/ stays f(canonical) and the
      # timings survive it by construction.
      persist_stage_timings!(ledger, profile, outcomes, indexed)
      Result.new(db_path: db_path, db_existed: db_existed, outcomes: outcomes,
                 skips: skips, indexed: indexed, axes: axes, facets: facets, profile: profile,
                 analyzed: analyzed, link_failures: link_failures)
    ensure
      db&.disconnect
      fulltext&.disconnect
      ledger&.disconnect
    end

    private

    # P84-1: the local-lemmas shelf when it exists on this box — an absent
    # shelf projects nothing, honestly (the silver-lemma pass is skipped).
    def lemma_shelf
      dir = LemmaShelf.dir(@config)
      return nil unless Dir.exist?(dir)

      LemmaShelf.new(dir: dir)
    end

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

    # P78-r2 (Q34): the estimates the stage announcements carry, read from
    # the P78-r1 history. "fulltext index" is an umbrella over the indexer's
    # six timed sub-stages, so its estimate sums them. No current-rows
    # denominator here — a rebuild doesn't know its document counts until it
    # parses, so the estimate is the last run verbatim (the CLI's in-stage
    # extrapolation takes over once ticks flow). "place apply" has no
    # profiler stage and stays bare.
    def load_eta(ledger, slug)
      Nabu::Eta.for(ledger, kind: "rebuild", scope: slug, stage: "load")
    end

    def corpus_eta(ledger, stage)
      Nabu::Eta.for(ledger, kind: "rebuild", scope: "corpus", stage: stage)
    end

    def index_eta(ledger)
      Nabu::Eta.for_stages(ledger, kind: "rebuild", scope: "corpus", stages: INDEX_ETA_STAGES)
    end

    # P78-r1 (Q34): append the profiler's facts to the ledger's stage_timings
    # (append-only; the latest row governs the next run's ETA). +rows+ is the
    # honest work-size denominator so the estimate can scale by drift: the
    # replayed document count for a source's :load, the indexed passage count
    # for corpus stages (they all scan the corpus). One timestamp for the
    # whole batch — the rows describe one run, not fourteen moments.
    def persist_stage_timings!(ledger, profile, outcomes, indexed)
      return if profile.nil? || profile.empty?

      at = Time.now
      docs = outcomes.to_h { |outcome| [outcome.slug, outcome.report.added + outcome.report.updated] }
      profile.source_scopes.each do |slug|
        Store::StageTimings.record!(ledger, kind: "rebuild", scope: slug, stage: "load",
                                            seconds: profile.seconds(scope: slug, stage: :load),
                                            rows: docs[slug], at: at)
      end
      profile.corpus_stages.each do |stage|
        Store::StageTimings.record!(ledger, kind: "rebuild", scope: "corpus", stage: stage.to_s,
                                            seconds: profile.corpus_total(stage), rows: indexed, at: at)
      end
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
                                    language_shelf_dir: @config.source_workdir(Nabu::LanguageShelf::SLUG),
                                    profile: profile)
      when :language
        Store::LanguageDossierLoader.new(db: db, source: source, ledger: ledger)
      when :notes
        Store::NoteLoader.new(db: db, source: source, ledger: ledger)
      when :lemmas
        Store::LemmaShelfLoader.new(db: db, source: source, ledger: ledger)
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
      fingerprint = fingerprints.for_source(entry, languages: languages)
      Store::DerivationStamp.stamp!(db, slug: entry.slug, fingerprint: fingerprint)
      record_ingest_identity(db, entry, fingerprint)
    end

    # P50-r1 (owner ruling D50-a): mirror the replay's canonical identity
    # onto the sources row — the last-INGEST record the `nabu data build`
    # stale-ingest guard compares against the cone's current state (sync
    # writes the same column; migration 022). A weak identity records nil:
    # "cannot prove", which the guard refuses. Shared with IncrementalRebuild.
    def record_ingest_identity(db, entry, fingerprint)
      db[:sources].where(slug: entry.slug).update(last_ingest_identity: fingerprint.canonical_identity)
    end

    # Shared with IncrementalRebuild (subclass): one computer per run so the
    # code/fold digests are hashed once, not per source.
    def fingerprints
      @fingerprints ||= DerivationFingerprint.new(config: @config)
    end

    # Re-derive every enrichment_producer? source's layer into the fresh
    # catalog (P44-7 — the first enricher to land here). The enrichments table
    # lives in catalog.sqlite3 (dropped by this rebuild) and keys on the
    # re-minted passage_id, so unlike the urn-keyed links journal it does NOT
    # survive passively — it is RE-DERIVED from canonical + the just-replayed
    # text tables, which is exactly the db = f(canonical) invariant. Each
    # producer supersedes its own rows (idempotent), so a re-run yields
    # byte-identical enrichments; a source with no local corpus is the honest
    # no-op. Runs AFTER replay (the passages the producer resolves against are
    # in place) and BEFORE the query-side index/facets stages.
    def replay_enrichments(db)
      @registry.each_source do |entry|
        next unless entry.adapter_class.enrichment_producer?
        next unless replayable?(entry)

        entry.adapter_class.enrichment_producer(catalog: db)
             .run(entry.slug, workdir: workdir_for(entry.slug))
      end
    end

    # Re-derive the place index from every place_index_producer? source's
    # canonical dump (P45-6 — pleiades). Like source_stats and the
    # enrichments replay, the index lives in the dropped catalog and is a
    # pure function of canonical bytes, so a full rebuild always re-derives
    # it. +dirty+ (IncrementalRebuild) restricts the re-derive to sources it
    # names — an incremental run whose dump is stamped clean AND whose index
    # is already populated skips the ~3 s / ~3.9 GB dump load; an EMPTY index
    # (the just-migrated catalog) still derives, the self-heal path.
    def replay_place_index(db, dirty: nil)
      @registry.each_source do |entry|
        next unless entry.adapter_class.place_index_producer?
        next unless replayable?(entry)
        next if dirty && !dirty.include?(entry.slug) && Store::PlaceIndex.populated?(db)

        entry.adapter_class.place_index_producer(catalog: db)
             .run(entry.slug, workdir: workdir_for(entry.slug))
      end
    end

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

    def workdir_for(slug) = @config.source_workdir(slug)

    # The links re-mine (P70-3b): wipe the journal, replay every
    # slug-scoped reference producer, then every recorded batch scope.
    # A producer's Nabu::Error-class failure is contained and returned (the
    # Result carries it into the summary — a partial links re-mine names
    # its gaps); infrastructure errors (I/O, Sequel) abort the rebuild
    # loudly, by design. Returns the failure strings.
    def rederive_links!(db, fulltext)
      journal = Store::LinksJournal.open!(@config.links_path)
      journal[:links].delete
      journal[:link_runs].delete
      failures = []
      @registry.each_source do |entry|
        next unless entry.adapter_class.reference_edges?

        entry.adapter_class.reference_producer(catalog: db, journal: journal)
             .run(entry.slug, workdir: workdir_for(entry.slug))
      rescue Nabu::Error => e
        failures << "#{entry.slug}: #{e.message}"
      end
      LinkScopes.load(@config.link_scopes_path).each do |scope|
        replay_batch_scope(scope, db, fulltext, journal)
      rescue Nabu::Error, ArgumentError => e
        failures << "#{scope['producer']} #{scope['scope']}: #{e.message}"
      end
      warn "links rederive: #{failures.size} producer(s) failed — #{failures.join(' · ')}" unless failures.empty?
      failures
    ensure
      journal&.disconnect
    end

    def replay_batch_scope(scope, db, fulltext, journal)
      params = scope["params"] || {}
      case scope["producer"]
      when "parallels"
        BatchParallels.new(catalog: db, fulltext: fulltext, journal: journal)
                      .run(scope["scope"],
                           **{ lang: params["lang"], license: params["license"],
                               min_score: params["min_score"], per_anchor: params["per_anchor"] }.compact)
      when "cognates"
        BatchCognates.new(catalog: db, fulltext: fulltext, journal: journal,
                          registry: AlignmentRegistry.load(@config.alignments_path))
                     .run(scope["scope"], langs: params["langs"], all: params.fetch("all", false))
      when "formulas"
        BatchFormulas.new(catalog: db, journal: journal)
                     .run(scope["scope"],
                          **{ gram_size: params["gram_size"], min_count: params["min_count"],
                              lang: params["lang"], max_formulas: params["max_formulas"] }.compact)
      else
        raise Nabu::Error, "unknown batch producer #{scope['producer'].inspect} in link_scopes.yml"
      end
    end

    def db_path = @config.catalog_path

    def fulltext_path = @config.fulltext_path

    def history_path = @config.history_path
  end
end
