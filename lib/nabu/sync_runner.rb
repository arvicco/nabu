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
    Outcome = Data.define(:slug, :fetch_report, :load_report, :breaker, :indexed, :warnings,
                          :discovery, :references) do
      def initialize(slug:, fetch_report:, load_report:, breaker:, indexed:, warnings:,
                     discovery:, references: nil)
        super
      end

      def aborted? = !breaker.nil?
    end

    # +db+ is the catalog; +ledger+ the history ledger (Store::Ledger, P7-1) —
    # runs, per-repo pins, and durable revisions are recorded there, keyed by
    # slug/url/urn so they survive `nabu rebuild`.
    def initialize(config:, registry:, db:, ledger:)
      @config = config
      @registry = registry
      @db = db
      @ledger = ledger
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
      # `sync --all` sweeps only kind: source rows on the `auto` cadence
      # (P39-0): shelves are local (no network) and modules mint no catalog
      # rows, so neither belongs in the unattended batch, and `manual`/`frozen`
      # sources are owner-fired by name.
      @registry.each_source.select { |entry| entry.source? && entry.enabled && entry.sync_policy == "auto" }
    end

    def sync_entry(entry, parse_only:, force:, progress:)
      source = entry.sync_source!(@db)
      adapter = entry.build_adapter
      workdir = workdir_for(entry.slug)
      fetch_report = nil
      load_report = nil

      begin
        run = Store::RunRecorder.record(source_slug: entry.slug) do
          fetch_report = fetch(adapter, workdir, force: force, progress: progress) unless parse_only
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
      indexed = index_inert?(adapter) ? nil : reindex!(entry, adapter)
      Outcome.new(slug: entry.slug, fetch_report: fetch_report, load_report: load_report,
                  breaker: nil, indexed: indexed,
                  warnings: warnings, discovery: discovery,
                  references: refresh_references(entry))
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
    def reindex!(entry, adapter)
      require "fileutils"
      FileUtils.mkdir_p(File.dirname(@config.fulltext_path))
      fulltext = Store.connect_fulltext(@config.fulltext_path)
      Store::Indexer.refresh_source!(catalog: @db, fulltext: fulltext, slug: entry.slug,
                                     alignments: AlignmentRegistry.load(@config.alignments_path),
                                     fuzzy_slugs: @registry.fuzzy_slugs,
                                     lemma_tiers: @registry.lemma_tiers,
                                     reflexes_changed: adapter.class.content_kind == :dictionary)
    ensure
      fulltext&.disconnect
    end

    def fetch(adapter, workdir, force:, progress:)
      adapter.fetch(workdir, progress: progress&.method(:fetch_line), force: force)
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
      loader.load_from(adapter, workdir: workdir, full: true, on_document: progress&.method(:load_tick))
    end

    def build_loader(adapter, source)
      case adapter.class.content_kind
      when :dictionary
        Store::DictionaryLoader.new(db: @db, source: source, ledger: @ledger,
                                    canonical_dir: @config.canonical_dir)
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
    def update_source_state(source, entry, fetch_report)
      attrs = { last_sync_at: Time.now }
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

    def workdir_for(slug) = File.join(@config.canonical_dir, slug)
  end
end
