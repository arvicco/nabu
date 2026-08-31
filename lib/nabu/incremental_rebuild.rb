# frozen_string_literal: true

module Nabu
  # `nabu rebuild --incremental` (P36-1): keep the existing catalog, compare
  # each source's DerivationFingerprint against its stored stamp, skip the
  # clean ones and re-derive only the dirty ones — through the SAME replay
  # seam the full rebuild uses (Rebuild#replay: sync_source! + content-kind
  # loader with full: true, whose upsert/withdraw logic is exactly what
  # `sync --parse-only` runs against a live db) plus the Indexer's per-source
  # FTS/lemma/trigram delete+reinsert (Store::Indexer.refresh_source!, whose
  # row-identity-with-rebuild! contract is already test-pinned, P26-5).
  #
  # THE INVARIANT IS SACRED: the full rebuild remains the reference. An
  # incremental run must land content-equivalent to a fresh full rebuild of
  # the same canonical tree (counts + content shas; test-pinned). What
  # legitimately differs is bookkeeping the full rebuild re-mints: row ids,
  # revision counters (an incremental re-derive REVISES changed rows and
  # journals the change — strictly more history than a fresh insert), the
  # sources rows' last_sync_* mirrors, and withdrawn tombstones for documents
  # a dirtied source no longer yields (full rebuild has no row at all; the
  # catalog's never-hard-delete rule keeps the tombstone here).
  #
  # Refusals (loud, full rebuild required — never a silent divergence):
  # - no catalog on disk;
  # - the catalog's applied migration level differs from the code's (a
  #   migration landed: derived shapes may have changed corpus-wide);
  # - rows/stamps exist for a source with no replayable canonical tree (a
  #   full rebuild would drop them; skipping would strand them).
  #
  # Corpus-wide (non-source-scoped) builders re-run whole whenever ANY source
  # was dirty: the timeline (document_axes) and facet projections join across
  # re-minted rows and have no per-source seam — and since P70 the two
  # derived sibling dbs likewise: the lect journal re-derives (config
  # rulings + rules + infer-dates read the re-minted facets) and the links
  # instrument re-mines (producers read the changed canonical). When
  # nothing is dirty they do not run at all — the write-through CLIs keep
  # both journals live, so only a hand-edited config file awaits the next
  # full rebuild or dirty incremental. The enrichment replay hook mirrors
  # Rebuild (no-op today).
  class IncrementalRebuild < Rebuild
    # A source skipped because its fingerprint matched its stamp.
    Clean = Data.define(:slug, :stamp_short)

    # A source RE-STAMPED without replay under --trust-derivations (P89-1,
    # №R-54 (b)): parser-only drift + the code voucher's yes.
    Trusted = Data.define(:slug, :stamp_short)

    # One source's dry-run verdict: state :clean | :dirty | :skip, +reason+
    # the drift component for :dirty (:canonical/:parser/:config/:migration/
    # :unstamped/:weak_identity, or — P39-1, a String because it names files —
    # "fold(<module>, ...)") or :no_canonical for :skip.
    Verdict = Data.define(:slug, :state, :reason, :stamp_short) do
      def initialize(slug:, state:, reason: nil, stamp_short: nil)
        super
      end
    end

    # What `--dry-run --incremental` reports. +refusal+ (a message or nil)
    # preempts the verdicts. +builders_dirty+ (P89-1) announces a pending
    # corpus-builders re-run — it is not a source verdict.
    Plan = Data.define(:db_path, :db_exists, :refusal, :verdicts, :builders_dirty) do
      def initialize(db_path:, db_exists:, refusal:, verdicts:, builders_dirty: false)
        super
      end
    end

    # What an incremental rebuild did. +indexed+ is the passage count
    # re-indexed across dirty sources (nil when none needed index work);
    # +axes+/+facets+ are nil when the corpus-wide builders did not run.
    # +analyzed+ (P42-4) is the Store::AnalyzeReport of the post-run planner-
    # stats refresh — present when any source re-derived (the dirty replays
    # shifted the catalog/index distribution), nil when everything was clean.
    # +trusted+ (P89-1) lists the sources re-stamped without replay.
    Result = Data.define(:db_path, :outcomes, :cleans, :skips, :indexed, :axes, :facets, :analyzed,
                         :link_failures, :trusted) do
      def initialize(db_path:, outcomes:, cleans:, skips:, indexed:, axes:, facets:, analyzed: nil,
                     link_failures: [], trusted: [])
        super
      end

      def warnings = outcomes.select(&:warning?)
    end

    # Describe the clean/dirty verdict per source without touching anything.
    def plan
      refusal = refusal_reason
      return Plan.new(db_path: db_path, db_exists: File.exist?(db_path), refusal: refusal, verdicts: []) if refusal

      with_readonly_catalog do |db|
        verdicts = @registry.each_source.map { |entry| verdict_for(db, entry) }
        Plan.new(db_path: db_path, db_exists: true, refusal: nil, verdicts: verdicts,
                 builders_dirty: builders_dirty?(db))
      end
    end

    # Re-derive the dirty sources into the LIVE catalog; skip the clean ones
    # entirely (one Clean per skip). Raises Nabu::Error on any refusal.
    # +trust_stages+ (P87-3): mint the fulltext stage stamps at current
    # versions WITHOUT re-deriving — the documented bridge for an index
    # known to have been built by the current code (e.g. the full rebuild
    # that shipped just before the stamps machinery landed).
    # +trust_derivations+ (P89-1, №R-54 (b)): the derivation-stamp
    # counterpart — a source whose ONLY drift is the parser digest, and
    # whose own parser closure +code_voucher+ can vouch predates its stamp,
    # is re-stamped at its current fingerprint WITHOUT replay (the drift
    # was shared-core code the owner attests is content-neutral). Anything
    # the voucher cannot vouch for replays honestly — never a run refusal.
    def initialize(config:, registry:, trust_stages: false, trust_derivations: false,
                   code_voucher: nil)
      super(config: config, registry: registry)
      @trust_stages = trust_stages
      @trust_derivations = trust_derivations
      @code_voucher = code_voucher || CodeVoucher.new
    end

    def run(progress: nil)
      refusal = refusal_reason
      raise Nabu::Error, refusal if refusal

      # P70 fail-fast, mirroring the full rebuild: a malformed hand edit to
      # config/lect_rulings.yml refuses before any replay work.
      LectRulings.validate!(@config.lect_rulings_paths)

      db = Store.connect(db_path)
      Store.setup!(db)
      ledger = Store::Ledger.open!(history_path)
      fulltext = Store.connect_fulltext(fulltext_path)
      outcomes = []
      cleans = []
      skips = []
      trusted = []
      indexed = nil
      # P89-1: pin code identities before any replay (see Rebuild#run) —
      # the last verdict of a long dirty run happens hours after load time.
      @registry.each_source { |entry| fingerprints.warm(entry) }
      # The trust horizon (№R-54 (b)): the ELDEST per-source stamp, not each
      # stamp's own time. A long run stamps late from disk bytes while its
      # rows come from code loaded at start — a closure file committed
      # mid-run beats the source's own stamped_at and would be wrongly
      # vouched (the 2026-08-29 tshet-uinh stamp is the type specimen). The
      # eldest stamp ≈ the oldest run start any surviving stamp could
      # depend on; sources whose closure moved after it simply replay
      # (over-rebuild-safe).
      trust_horizon = @trust_derivations ? Store::DerivationStamp.oldest_stamped_at(db) : nil
      @registry.each_source do |entry|
        unless replayable?(entry)
          skips << Skip.new(slug: entry.slug, reason: :no_canonical)
          next
        end
        fingerprint = fingerprint_for(db, entry)
        stamp = Store::DerivationStamp.fetch(db, entry.slug)
        if fingerprint.drift_against(stamp).nil?
          cleans << Clean.new(slug: entry.slug, stamp_short: fingerprint.short)
          next
        end
        if @trust_derivations && trustable?(entry, stamp, fingerprint, trust_horizon)
          # A one-time event the owner reads in the TRANSCRIPT (2026-08-30
          # feedback): each trusted source leaves a durable stage line as
          # it happens, not only the end-of-run summary.
          progress&.stage("#{entry.slug} — trusted (re-stamped, no replay)")
          Store::DerivationStamp.stamp!(db, slug: entry.slug, fingerprint: fingerprint)
          record_ingest_identity(db, entry, fingerprint)
          trusted << Trusted.new(slug: entry.slug, stamp_short: fingerprint.short)
          next
        end
        progress&.stage(entry.slug)
        outcomes << replay(db, ledger, entry, progress)
        # P39-1: re-scope the fold digest AGAINST THE POST-REPLAY CENSUS
        # before stamping. The pre-replay fingerprint's fold set describes
        # the rows a dirty canonical/parser just replaced — stamping it could
        # miss a language the replay introduced (silent under-rebuild).
        fingerprint = fingerprint.with(
          fold_digest: DerivationFingerprint.fold_digest(Store::DerivationStamp.derived_languages(db, entry.slug))
        )
        Store::DerivationStamp.stamp!(db, slug: entry.slug, fingerprint: fingerprint)
        record_ingest_identity(db, entry, fingerprint)
        indexed = (indexed || 0) + refresh_index(db, fulltext, entry, progress) unless index_inert?(entry)
      end
      replay_enrichments(db)
      # P45-6: re-derive the place index only when its source was dirty (the
      # dump changed) or the index is still unpopulated (self-heal after
      # migration 021) — a clean stamped dump with a populated index skips
      # the ~3 s / ~3.9 GB dump load, keeping clean incremental runs cheap
      # while staying content-equivalent to a full rebuild (derive! is a
      # pure function of the unchanged canonical bytes).
      replay_place_index(db, dirty: outcomes.map(&:slug))
      # P42-0: the loader hooks maintained source_stats through each dirty
      # replay; re-deriving wholesale keeps the incremental run's stats
      # content-equivalent to a full rebuild's (the sacred invariant). A
      # skipped-everything run touched no rows, so stats need nothing.
      if outcomes.any?
        progress&.stage("source stats")
        Store::SourceStats.derive!(db, note: "derived (incremental rebuild)")
      end
      # P89-1 (№R-54 (c)): the builders' own covering mechanism — a drifted
      # builders digest re-runs the corpus builders even when every source
      # is clean; the sentinel then records the code they just ran as.
      builders_ran = outcomes.any? || builders_dirty?(db)
      axes, facets = corpus_builders(db, progress) if builders_ran
      if builders_ran
        Store::DerivationStamp.stamp_builders!(
          db, digest: DerivationFingerprint.builders_digest,
              migration_level: DerivationFingerprint.migration_level
        )
      end
      # P70/P71-6 (the derivability law): the lect journal re-derives on
      # EVERY incremental run — it is seconds-scale, and always-running
      # closes the hand-edit gap (an edited rulings file, facet rule, or
      # local/config overlay propagates immediately, dirty or clean).
      # Facet re-materialization rides only when something could have
      # changed (dirty replay or a journal delta). The links re-mine
      # stays DIRTY-ONLY: it is minutes-scale against the cheap-clean-run
      # design goal, and its config lane (link_scopes.yml) is written by
      # the batch CLIs live — only a hand edit diverges, and that waits
      # for the next full rebuild or dirty incremental (stated in §1 and
      # restore.md).
      progress&.stage("lect journal")
      journal = Store::LectJournal.open!(@config.lects_journal_path)
      begin
        before = journal_digest(journal)
        Store::LectJournal.rederive!(journal, catalog: db, config: @config)
        journal_changed = journal_digest(journal) != before
      ensure
        journal.disconnect
      end
      link_failures = []
      if outcomes.any? || journal_changed
        progress&.stage("lect facets")
        Store::LectFacets.rebuild!(catalog: db, registry: Nabu::Lects.load_default(config: @config))
      end
      if outcomes.any?
        progress&.stage("links")
        link_failures = rederive_links!(db, fulltext)
      end
      indexed = heal_index(db, fulltext, progress) if outcomes.empty? && !Store::Indexer.incremental_ready?(fulltext)
      # P87-3 (Q52a): reconcile the fulltext STAGE stamps — a derivation
      # version bump (the P86-3 postings widening is the type specimen)
      # surgically re-derives exactly its own stage against the kept
      # catalog; unreconcilable stages refuse loudly; a pre-P87 index
      # no-ops with the honest note.
      redone_stages, stage_refusal, stage_note = Store::Indexer.reconcile_stages!(
        catalog: db, fulltext: fulltext,
        sign_list: Nabu::SignList.load_default(config: @config),
        alignments: AlignmentRegistry.load(@config.alignments_path),
        trust: @trust_stages, progress: progress
      )
      raise Nabu::Error, stage_refusal if stage_refusal

      progress&.stage(stage_note) if stage_note
      indexed = (indexed || 0) + 1 if redone_stages.any? && indexed.nil?
      # P42-4: refresh the planner stats when dirty sources re-derived — their
      # replays revised the catalog and (per source) the index, so the
      # sqlite_stat1 both carry may no longer match (ops §10). A clean-swept run
      # touched no rows, so the existing stats still describe them.
      analyzed = analyze_after_incremental(db, fulltext) if builders_ran
      Result.new(db_path: db_path, outcomes: outcomes, cleans: cleans, skips: skips,
                 indexed: indexed, axes: axes, facets: facets, analyzed: analyzed,
                 link_failures: link_failures, trusted: trusted)
    ensure
      db&.disconnect
      fulltext&.disconnect
      ledger&.disconnect
    end

    private

    # A content digest of the journal's resolution-relevant columns —
    # the facet re-materialization trigger (order-independent via sum of
    # per-row hashes; a full scan, ~seconds on a 500k-row journal).
    def journal_digest(journal)
      journal[:lect_assignments].select_map(%i[urn code lect_id basis]).sum(&:hash)
    end

    # nil when incremental may proceed; otherwise the loud reason it may not.
    def refusal_reason
      return "no catalog at #{db_path} — full rebuild required (`nabu rebuild`)" unless File.exist?(db_path)

      with_readonly_catalog do |db|
        applied = applied_migration_level(db)
        latest = DerivationFingerprint.migration_level
        if applied != latest
          next "catalog schema v#{applied} != code v#{latest} — a migration landed; full rebuild required"
        end

        orphans = orphan_slugs(db)
        next nil if orphans.empty?

        "catalog rows/stamps exist for #{orphans.join(', ')} but no replayable canonical tree does — " \
          "a full rebuild would drop them; full rebuild required"
      end
    end

    def verdict_for(db, entry)
      return Verdict.new(slug: entry.slug, state: :skip, reason: :no_canonical) unless replayable?(entry)

      fingerprint = fingerprint_for(db, entry)
      stamp = Store::DerivationStamp.fetch(db, entry.slug)
      drift = fingerprint.drift_against(stamp)
      return Verdict.new(slug: entry.slug, state: :clean, stamp_short: fingerprint.short) if drift.nil?

      # A fold drift names the changed file(s) — the owner reads these lines.
      drift = "fold(#{fingerprint.fold_blame(stamp).join(', ')})" if drift == :fold
      Verdict.new(slug: entry.slug, state: :dirty, reason: drift)
    end

    # The current fingerprint, its fold digest scoped by the catalog's own
    # language census for the source (P39-1). Honest at verdict time because
    # a clean canonical+parser implies re-derivation would mint the same
    # language set the census reads; when they are NOT clean the source is
    # dirty through those components regardless of the fold set.
    def fingerprint_for(db, entry)
      fingerprints.for_source(entry, languages: Store::DerivationStamp.derived_languages(db, entry.slug))
    end

    def builders_dirty?(db)
      Store::DerivationStamp.builders_digest(db) != DerivationFingerprint.builders_digest
    end

    # May +entry+ be re-stamped without replay (P89-1, №R-54 (b))? Only
    # when every NON-parser component matches its stamp DIRECTLY (the
    # drift_against blame order reports the first drift only — a parser
    # drift could mask a fold or config one) AND the code voucher confirms
    # the source's own parser closure predates the trust +horizon+ (the
    # eldest stamp — see #run for why never the source's own stamped_at).
    # Then the drift can only live in shared-core code, which the owner's
    # flag attests is content-neutral for existing rows.
    def trustable?(entry, stamp, fingerprint, horizon)
      return false if stamp.nil? || fingerprint.weak? || horizon.nil?
      return false unless stamp[:migration_level] == fingerprint.migration_level &&
                          stamp[:canonical_identity] == fingerprint.canonical_identity &&
                          stamp[:fold_digest] == fingerprint.fold_digest &&
                          stamp[:config_json] == fingerprint.config_json

      @code_voucher.vouches?(files: fingerprints.parser_files(entry), since: horizon)
    end

    def with_readonly_catalog
      db = Store.connect(db_path, readonly: true)
      yield db
    ensure
      db&.disconnect
    end

    def applied_migration_level(db)
      return 0 unless db.table_exists?(:schema_info)

      db[:schema_info].get(:version).to_i
    end

    # Catalog slugs (source rows or stamps) with no replayable canonical
    # tree behind them: a full rebuild would drop their rows; incremental
    # must refuse rather than strand them (class doc).
    def orphan_slugs(db)
      replayable = @registry.each_source.select { |entry| replayable?(entry) }.map(&:slug)
      known = db.table_exists?(:sources) ? db[:sources].select_map(:slug) : []
      (known | Store::DerivationStamp.slugs(db)).sort - replayable
    end

    # Notes/language/source grains mint neither passages nor dictionary
    # entries — no index work (the SyncRunner rule, P26-5).
    def index_inert?(entry)
      SyncRunner::INDEX_INERT_KINDS.include?(entry.adapter_class.content_kind)
    end

    # The per-source FTS/lemma/trigram delete+reinsert (P26-5). Falls back to
    # the full Indexer.rebuild! internally if the index file predates the
    # incremental tables (self-healing, still ≡ full).
    def refresh_index(db, fulltext, entry, progress = nil)
      Store::Indexer.refresh_source!(
        catalog: db, fulltext: fulltext, slug: entry.slug,
        alignments: alignments, fuzzy_slugs: @registry.fuzzy_slugs,
        lemma_tiers: @registry.lemma_tiers,
        reflexes_changed: entry.adapter_class.content_kind == :dictionary,
        sign_list: Nabu::SignList.load_default(config: @config),
        progress: progress
      )
    end

    # Timeline + facets have no per-source seam (class doc): whole-table
    # projections, re-run whenever anything re-derived.
    def corpus_builders(db, progress)
      progress&.stage("timeline")
      axes = Store::TimelineBuilder.rebuild!(catalog: db, canonical_dir: @config.canonical_dir)
      progress&.stage("facets")
      facets = Store::FacetBuilder.rebuild!(catalog: db)
      [axes, facets]
    end

    # Nothing was dirty but the index file is missing/pre-incremental: a
    # skipped-everything run must still leave the state ≡ full rebuild.
    def heal_index(db, fulltext, progress)
      progress&.stage("fulltext index")
      Store::Indexer.rebuild!(catalog: db, fulltext: fulltext, alignments: alignments,
                              fuzzy_slugs: @registry.fuzzy_slugs, lemma_tiers: @registry.lemma_tiers,
                              sign_list: Nabu::SignList.load_default(config: @config),
                              progress: progress)
    end

    def alignments
      @alignments ||= AlignmentRegistry.load(@config.alignments_path)
    end

    # P42-4: bounded ANALYZE of the catalog and the fulltext index after the
    # dirty replays, mirroring the full rebuild's post-index refresh.
    def analyze_after_incremental(db, fulltext)
      Store::AnalyzeReport.new(scope: "catalog + index",
                               seconds: Store.analyze!(db) + Store.analyze!(fulltext))
    end
  end
end
