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
  # the unattended path and respects the registry strictly: only ENABLED
  # kind: source rows with sync_policy "auto" run — "manual" and "frozen"
  # sources, and every shelf/module, are excluded by design (P39-0,
  # docs/maintenance-and-extension.md §2), and one source's failure never stops
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

    # A grain whose content kind mints neither passages nor dictionary
    # entries cannot change any index — its sync performs NO index work
    # (P26-5 Part A; pinned by an every-entry-point spy test).
    INDEX_INERT_KINDS = %i[notes language source].freeze

    # Post-load ANALYZE fires only after a BULK load — a sync that
    # added/updated/withdrew strictly more than this many rows (P42-4). The
    # bounded ANALYZE is still seconds-scale on the live corpus (measured 148s),
    # so re-planning after a 0-row skip-run — the common re-sync — is pure
    # waste; a maintenance touch of a few rows leaves the planner's existing
    # distribution representative. This counts the LOAD's size, not a fraction
    # of the corpus: it asks "was this a bulk change worth re-planning for",
    # which no corpus growth can make stale (a bulk load is a bulk load at any
    # scale). `nabu rebuild` re-derives everything, so it always analyzes and
    # backstops sub-threshold syncs regardless.
    # const: changed-row floor that marks a load "bulk" (load-size, not corpus-fraction)
    ANALYZE_MIN_CHANGED_ROWS = 10_000

    # What one source's sync did. Mirrors Rebuild::Outcome. On a tripped breaker
    # load_report is nil and #aborted? is true, with +breaker+ carrying the
    # Nabu::SyncAborted (its counts + message) for reporting; otherwise breaker
    # is nil, fetch_report is present (nil under --parse-only) and load_report
    # holds the Loader's counts. +warnings+ carries any inline deviation Findings
    # (P5-5) computed from the fresh LoadReport against the source's history —
    # advisory only, never failing the sync (empty on an aborted run).
    # +discovery+ (P11-7) is the adapter's Nabu::Adapter::DiscoverySkips census
    # of content-pattern files that never became refs (0-byte skeletons,
    # non-editions, and loud nested-root/unpack gaps); combined with load_report
    # it drives the printed discovery accounting. nil on an aborted run.
    # +references+ (P19-4) is the Nabu::LibraryReferences::Result for a
    # reference_edges? source (the manifests' related: urns refreshed into
    # the links journal after the load); nil for every other source.
    # +enrichments+ (P44-7) is the enrichment producer's census Result for an
    # enrichment_producer? source (pedecerto's meter scansions re-derived into
    # the enrichments table after the load); nil for every other source.
    # +place_index+ (P45-6) is the Store::PlaceIndex::Producer::Census for a
    # place_index_producer? source (pleiades: the gazetteer dump re-derived
    # into the catalog place index after the load); nil for every other
    # source, and nil for a pleiades parse-only sync before the first fetch.
    # +analyzed+ (P42-4) is the Store::AnalyzeReport of the post-load
    # planner-stats refresh when the load was bulk (see ANALYZE_MIN_CHANGED_ROWS);
    # nil when the load was sub-threshold (the common re-sync) or on an aborted
    # run — the CLI's report line stays silent then.
    Outcome = Data.define(:slug, :fetch_report, :load_report, :breaker, :indexed, :warnings,
                          :discovery, :references, :enrichments, :place_index, :analyzed) do
      def initialize(slug:, fetch_report:, load_report:, breaker:, indexed:, warnings:,
                     discovery:, references: nil, enrichments: nil, place_index: nil, analyzed: nil)
        super
      end

      def aborted? = !breaker.nil?
    end

    # A `sync --all` result sentinel (P42-r1): a grant_required source with no
    # recorded acknowledgment was SKIPPED, never prompted mid-batch — the CLI
    # renders GrantGate.skip_line for it. Distinct from an Outcome (nothing was
    # fetched or loaded) and from a captured Error (nothing went wrong).
    GrantRequired = Data.define(:slug)

    # +db+ is the catalog; +ledger+ the history ledger (Store::Ledger, P7-1) —
    # runs, per-repo pins, and durable revisions are recorded there, keyed by
    # slug/url/urn so they survive `nabu rebuild`.
    # The loaded Nabu::Config (P44-i1: the CLI's --redownload wipe needs
    # the canonical dir without re-loading config).
    attr_reader :config

    def initialize(config:, registry:, db:, ledger:)
      @config = config
      @registry = registry
      @db = db
      @ledger = ledger
      @grant_gate = GrantGate.new(ledger: ledger, grants_path: config&.grants_path)
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

    # Sync every ENABLED kind: source with sync_policy "auto". Returns { slug => Outcome |
    # Nabu::Error }: a source that raises is captured in the hash so the batch
    # runs to completion (one failure never stops the others). +enabled+
    # (P44-r3b) is the box's enabled-slug set: when given, the live-enabled
    # sweep is intersected with it (sync --all = the enabled set only); nil
    # keeps the whole registry sweep (an unconfigured box, or a --parse-only
    # repair run — the CLI decides).
    def sync_all(parse_only: false, force: false, progress: nil, enabled: nil)
      sweep = live_enabled
      sweep = sweep.select { |entry| enabled.include?(entry.slug) } unless enabled.nil?
      sweep.to_h do |entry|
        result =
          if @grant_gate.blocked?(entry)
            # A permission-bound source with no acknowledgment is SKIPPED, never
            # prompted mid-batch (P42-r1) — the CLI renders the honest skip line.
            GrantRequired.new(slug: entry.slug)
          else
            begin
              sync_entry(entry, parse_only: parse_only, force: force, progress: progress)
            rescue Nabu::Error => e
              e
            end
          end
        [entry.slug, result]
      end
    end

    private

    def live_enabled
      # `sync --all` sweeps only kind: source rows on the `auto` cadence
      # (P39-0): shelves are local (no network) and modules mint no catalog
      # rows, so neither belongs in the unattended batch, and `manual`/`frozen`
      # sources are owner-fired by name.
      @registry.each_source.select { |entry| entry.source? && entry.wired && entry.sync_policy == "auto" }
    end

    def sync_entry(entry, parse_only:, force:, progress:)
      source = entry.sync_source!(@db)
      adapter = entry.build_adapter
      workdir = workdir_for(entry.slug)
      fetch_report = nil
      load_report = nil

      begin
        run = Store::RunRecorder.record(source_slug: entry.slug) do
          fetch_report = fetch(adapter, workdir, slug: entry.slug, force: force, progress: progress) unless parse_only
          guard_withdrawal!(adapter, source, workdir, force: force)
          load_report = load(source, adapter, workdir, progress)
        end
      rescue Nabu::SyncAborted => e
        # Recorded "aborted" by RunRecorder; nothing was loaded, source row
        # untouched. Report it rather than crashing the batch.
        return Outcome.new(slug: entry.slug, fetch_report: fetch_report, load_report: nil,
                           breaker: e, indexed: nil, warnings: [], discovery: nil)
      end

      discovery = adapter.discovery_skips(workdir)
      record_discovery_notes(run, discovery)
      update_source_state(source, entry, fetch_report)
      # Warnings compare against the PREVIOUS ok run's baseline, so compute
      # them before the baseline advances (P18-7: recorded at every ok run).
      warnings = deviation_warnings(source, load_report, adapter)
      Health::QuarantineBaseline.record!(@ledger, entry.slug, errored: load_report.errored)
      # Reindex AFTER the RunRecorder block: the index files have their own
      # lifecycle, so index work must not live inside a source's run row (an
      # indexing failure surfaces as its own error, never a falsified run).
      # Incremental since P26-5: an index-inert grain (notes/language/source —
      # neither passages nor dictionary entries) skips indexing entirely
      # (indexed nil; the CLI omits the fragment); everything else refreshes
      # only ITS slice via Indexer.refresh_source!, and +indexed+ is the
      # SOURCE's live passage count — never the corpus total. `nabu rebuild`
      # keeps the full Indexer.rebuild! as the from-scratch guarantee.
      indexed = index_inert?(adapter) ? nil : reindex!(entry, adapter, progress)
      refresh_catalog_lanes(entry, load_report)
      Outcome.new(slug: entry.slug, fetch_report: fetch_report, load_report: load_report,
                  breaker: nil, indexed: indexed,
                  warnings: warnings, discovery: discovery,
                  references: refresh_references(entry),
                  enrichments: refresh_enrichments(entry),
                  place_index: refresh_place_index(entry),
                  analyzed: analyze_after_load(load_report, adapter))
    end

    # P47-r3 (the lane-drift audit — owner: "generalize and find out what
    # else could've been impacted"): the catalog-projected lanes (facets;
    # metadata-shape timeline rows) refreshed ONLY at full rebuild, so
    # every sync since the last rebuild served stale facet/timeline lanes
    # (EDR, IIP, Elephantine, the Sefaria Rabbinic wave — all found dark
    # in the audit). Both projections are cheap catalog reads; refresh the
    # synced source's slice post-load, mirroring Indexer.refresh_source!.
    # Canonical-walking timeline extractors (HGV, EDH…) stay rebuild-scoped
    # — their sources' syncs are rare and their walks are not cheap.
    def refresh_catalog_lanes(entry, load_report)
      return if load_report.nil? || (load_report.added.zero? && load_report.updated.zero?)

      Store::FacetBuilder.refresh_source!(catalog: @db, slug: entry.slug)
      Store::TimelineBuilder::MetadataDates.refresh_source!(catalog: @db, slug: entry.slug)
    end

    # P42-4: after a BULK load, refresh the query-planner statistics — the
    # catalog always (it holds the passages the planner mis-estimated), and the
    # fulltext index too UNLESS the source is index-inert (its passage_lemmas
    # table carries three b-tree indexes the lemma/etym/vocab joins choose
    # between, so its stats plan too; ops §10). Returns a Store::AnalyzeReport,
    # or nil when the load was sub-threshold so the report line stays silent.
    def analyze_after_load(load_report, adapter)
      return nil unless bulk_load?(load_report)

      seconds = Store.analyze!(@db)
      scope = "catalog"
      unless index_inert?(adapter)
        seconds += analyze_fulltext!
        scope = "catalog + index"
      end
      Store::AnalyzeReport.new(seconds: seconds, scope: scope)
    end

    # A load counts as bulk when it changed strictly more than
    # ANALYZE_MIN_CHANGED_ROWS rows (added + updated + withdrawn). A skip-run
    # (nothing changed, only skipped) is never bulk — the waste case the
    # threshold exists to avoid.
    def bulk_load?(load_report)
      return false unless load_report

      (load_report.added + load_report.updated + load_report.withdrawn) > ANALYZE_MIN_CHANGED_ROWS
    end

    # Analyze the fulltext index through its own short-lived connection (the
    # reindex! handle has already closed), mirroring reindex!'s connect/ensure.
    def analyze_fulltext!
      fulltext = Store.connect_fulltext(@config.fulltext_path)
      Store.analyze!(fulltext)
    ensure
      fulltext&.disconnect
    end

    # P19-4/P25-0: after a reference_edges? source loads, re-derive its
    # reference edges via the adapter's declared producer (the manifests'
    # related: urns for the library shelf, the token DIL ids for corph —
    # a pure function of the loaded rows, superseding the prior run).
    # +workdir+ rides along for the producer whose input is a canonical
    # file rather than catalog rows (P32-6, the suttacentral parallels
    # graph — read-only on canonical, like the loader); the catalog-derived
    # producers ignore it. Outside the RunRecorder block like reindexing:
    # the journal is a third store with its own lifecycle, and a journal
    # failure must surface as its own error, never falsify the source's
    # run row.
    def refresh_references(entry)
      return nil unless entry.adapter_class.reference_edges?

      journal = Store::LinksJournal.open!(@config.links_path)
      begin
        entry.adapter_class.reference_producer(catalog: @db, journal: journal)
             .run(entry.slug, workdir: workdir_for(entry.slug))
      ensure
        journal.disconnect
      end
    end

    # P44-7: after an enrichment_producer? source loads, re-derive its meter
    # enrichment layer via the adapter's declared producer — a pure function of
    # (canonical corpus, catalog, code) that supersedes its prior rows in the
    # enrichments table. Writes the CATALOG (@db) directly (the enrichments
    # table lives there, unlike the links journal's separate file), so no extra
    # store handle. +workdir+ is the source's canonical dir (the producer reads
    # the unpacked corpus from it); a parse-only sync before the first fetch is
    # the honest no-op that supersedes nothing.
    def refresh_enrichments(entry)
      return nil unless entry.adapter_class.enrichment_producer?

      entry.adapter_class.enrichment_producer(catalog: @db)
           .run(entry.slug, workdir: workdir_for(entry.slug))
    end

    # P45-6: after a place_index_producer? source syncs, re-derive the catalog
    # place index from the dump it just landed — a pure function of canonical
    # bytes, superseded wholesale per run (Store::PlaceIndex.derive!), so
    # reads never pay the per-invocation dump load again. A parse-only sync
    # before the first fetch is the honest no-op (Census nil).
    def refresh_place_index(entry)
      return nil unless entry.adapter_class.place_index_producer?

      entry.adapter_class.place_index_producer(catalog: @db)
           .run(entry.slug, workdir: workdir_for(entry.slug))
    end

    # Persist the LOUD discovery notes (unrecognized ≥ 1 — a project tree with
    # no ingestible content) into the run row so a silent gap leaves a durable,
    # queryable trace, not just a console line. A clean census leaves runs.notes
    # untouched (nil on success, as before).
    def record_discovery_notes(run, discovery)
      return if run.nil? || discovery.clean?

      run.update(notes: discovery.notes.join("; "))
    end

    # P5-5/P18-7: after a successful sync, advisory deviation warnings against
    # this fresh LoadReport — returned in the Outcome for the CLI to print,
    # never failing the sync (the >20% breaker is the only thing that stops
    # one). The quarantine check is DELTA-aware (P18-7): this run's errored
    # count against the ledger's recorded baseline — silent when the standing
    # count is unchanged (papyri's audited 9,312 stops shouting), one loud
    # line carrying the delta when it moved (this replaced the P5-5
    # recent-max spike rule here: the baseline comparison is strictly more
    # sensitive, and the spike rule still guards run HISTORY in `nabu
    # health`'s trend layer).
    def deviation_warnings(source, load_report, adapter)
      return [] unless load_report

      delta = [Health::QuarantineBaseline.delta_finding(@ledger, source.slug, errored: load_report.errored)]
      # Dictionary and language sources (P11-4/P19-1): entry-/record-grained
      # counts against a document-count baseline would be apples-to-oranges —
      # the quarantine delta still applies (errored counts files either way),
      # the document-withdrawal sweep rule does not.
      return delta.compact if adapter.class.content_kind != :passages

      total = Store::Document.where(source_id: source.id).count
      (delta + [Health::TrendRules.sync_withdrawal(withdrawn: load_report.withdrawn, total: total)]).compact
    end

    def index_inert?(adapter)
      INDEX_INERT_KINDS.include?(adapter.class.content_kind)
    end

    # Incrementally refresh THIS source's slice of the fulltext index from
    # the (now-updated) catalog (Store::Indexer.refresh_source!: per-source
    # FTS/lemma/trigram delete + re-insert; alignment only when the source
    # holds a registry witness; reflex closure only when its lemma rows or —
    # for a dictionary sync — the crosswalk changed). Opens its own
    # short-lived connection to config.fulltext_path so callers need not
    # thread a handle through. Returns the source's live passage count.
    def reindex!(entry, adapter, progress = nil)
      require "fileutils"
      FileUtils.mkdir_p(File.dirname(@config.fulltext_path))
      fulltext = Store.connect_fulltext(@config.fulltext_path)
      Store::Indexer.refresh_source!(catalog: @db, fulltext: fulltext, slug: entry.slug,
                                     alignments: AlignmentRegistry.load(@config.alignments_path),
                                     fuzzy_slugs: @registry.fuzzy_slugs,
                                     lemma_tiers: @registry.lemma_tiers,
                                     reflexes_changed: adapter.class.content_kind == :dictionary,
                                     sign_list: Nabu::SignList.load_default(config: @config),
                                     progress: progress,
                                     ledger: @ledger)
    ensure
      fulltext&.disconnect
    end

    # The ONE seam every adapter's fetch flows through during a sync (the only
    # call site is gated `unless parse_only`, so this is already the fetch
    # phase and nothing else). P44-i1c: take the per-source acquisition lock
    # around it so two nabu processes fetching the SAME source fail fast
    # instead of racing on canonical/<slug> and its .partial staging (the glaux
    # incident). AlreadyHeld propagates like any other fetch failure — the run
    # is recorded failed for `sync <slug>`, captured per-source by `sync --all`.
    def fetch(adapter, workdir, slug:, force:, progress:)
      # P78-r3: the fetch announces with the last sync's fetch estimate and
      # records its own wall time — the downloads themselves narrate via
      # fetch_line, but the estimate says how long the whole phase ran last.
      timed_stage(slug, "fetch", "fetch: #{slug}", progress) do
        FetchLock.hold(canonical_dir: @config.canonical_dir, slug: slug) do
          adapter.fetch(workdir, progress: progress&.method(:fetch_line), force: force)
        end
      end
    end

    # Route by the adapter's declared content kind (P11-4, architecture §11):
    # passage corpora load through Store::Loader, dictionary sources through
    # Store::DictionaryLoader (P19-1: with the corpus root, so its language-
    # notes accretion can reach the local-language dossier shelf), language
    # dossier shelves through Store::LanguageDossierLoader, the owner-notes
    # shelf through Store::NoteLoader (P24-1) — same call shape, same
    # LoadReport.
    def load(source, adapter, workdir, progress)
      loader = build_loader(adapter, source)
      # P78-r3: the parse+load phase announces with its estimate (the tick
      # counter then carries the label AND — once the recorded document
      # total is known — the CLI's in-stage "~Nm left" extrapolation), and
      # records its wall time WITH the document count: the honest drift
      # denominator the next sync's estimate scales by.
      progress&.stage("parse+load: #{source.slug}",
                      eta: Nabu::Eta.for(@ledger, kind: "sync", scope: source.slug, stage: "load"))
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      report = loader.load_from(adapter, workdir: workdir, full: true,
                                         on_document: progress&.method(:load_tick))
      Store::StageTimings.record!(@ledger, kind: "sync", scope: source.slug, stage: "load",
                                           seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started,
                                           rows: report.added + report.updated + report.skipped)
      report
    end

    # P78-r3 mechanics: announce with the ledger's last estimate for this
    # (sync, scope, stage), run, record the wall time.
    def timed_stage(scope, stage, label, progress, &)
      progress&.stage(label, eta: Nabu::Eta.for(@ledger, kind: "sync", scope: scope, stage: stage))
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = yield
      Store::StageTimings.record!(@ledger, kind: "sync", scope: scope, stage: stage,
                                           seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
      result
    end

    def build_loader(adapter, source)
      case adapter.class.content_kind
      when :dictionary
        Store::DictionaryLoader.new(db: @db, source: source, ledger: @ledger,
                                    language_shelf_dir: @config.source_workdir(Nabu::LanguageShelf::SLUG))
      when :language
        Store::LanguageDossierLoader.new(db: @db, source: source, ledger: @ledger)
      when :notes
        Store::NoteLoader.new(db: @db, source: source, ledger: @ledger)
      when :source
        Store::SourceDossierLoader.new(db: @db, source: source, ledger: @ledger)
      else
        Store::Loader.new(db: @db, source: source, ledger: @ledger)
      end
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

    # On success, stamp the sync time (and mirror the fetched sha onto the
    # source row — display-only convenience; the AUTHORITATIVE pins live in
    # the ledger, below). A --parse-only run has no fetch_report, so both the
    # sources mirror and the ledger pins are preserved untouched.
    #
    # last_ingest_identity (P50-r1, owner ruling D50-a) is recorded on EVERY
    # successful sync, parse-only included: it names the canonical tree the
    # load just derived this source's rows from — the record the `nabu data
    # build` stale-ingest guard compares against the cone's current state.
    # The DERIVATION STAMP is deliberately not touched here: sync skips the
    # rebuild-scoped corpus builders, so stamping would let `rebuild
    # --incremental` under-rebuild them (the sin). A tree with no honest
    # identity (dirty embedded git) records nil — "cannot prove", which the
    # guard refuses; refusing beats misdescribing.
    def update_source_state(source, entry, fetch_report)
      attrs = { last_sync_at: Time.now,
                last_ingest_identity: DerivationFingerprint.canonical_identity(workdir_for(entry.slug)) }
      attrs[:last_sync_sha] = fetch_report.sha if fetch_report
      source.update(attrs)
      update_pins(entry, fetch_report) if fetch_report
    end

    # Upsert one ledger pin per upstream repo, keyed (source_slug, repo_url) —
    # P7-1: pins moved out of the rebuild-dropped catalog. Multi-repo fetches
    # report per-repo shas in FetchReport#repos; single-repo sources pin their
    # one declared repo (Adapter.upstream_repo_urls, the same url the remote
    # probe ls-remotes). Only last_sync_sha is touched, so a license baseline
    # the probe recorded on the pin survives the sync. Pins for repos no
    # longer in the reported set are deleted — a stale pin must never linger
    # and read as phantom drift.
    def update_pins(entry, fetch_report)
      repos = fetch_report.repos
      repos = single_repo_pin(entry, fetch_report) if repos.nil? || repos.empty?
      return if repos.empty?

      slug = entry.slug
      repos.each do |repo_url, sha|
        row = Store::Pin.first(source_slug: slug, repo_url: repo_url)
        if row
          row.update(last_sync_sha: sha)
        else
          Store::Pin.create(source_slug: slug, repo_url: repo_url, last_sync_sha: sha)
        end
      end
      Store::Pin.where(source_slug: slug).exclude(repo_url: repos.keys).delete
    end

    def single_repo_pin(entry, fetch_report)
      url = entry.adapter_class.upstream_repo_urls.first
      url ? { url => fetch_report.sha } : {}
    end

    def workdir_for(slug) = @config.source_workdir(slug)
  end
end
