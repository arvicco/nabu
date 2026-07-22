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
  # re-minted rows and have no per-source seam. When nothing is dirty they do
  # not run at all. The enrichment replay hook mirrors Rebuild (no-op today).
  class IncrementalRebuild < Rebuild
    # A source skipped because its fingerprint matched its stamp.
    Clean = Data.define(:slug, :stamp_short)

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
    # preempts the verdicts.
    Plan = Data.define(:db_path, :db_exists, :refusal, :verdicts)

    # What an incremental rebuild did. +indexed+ is the passage count
    # re-indexed across dirty sources (nil when none needed index work);
    # +axes+/+facets+ are nil when the corpus-wide builders did not run.
    Result = Data.define(:db_path, :outcomes, :cleans, :skips, :indexed, :axes, :facets) do
      def warnings = outcomes.select(&:warning?)
    end

    # Describe the clean/dirty verdict per source without touching anything.
    def plan
      refusal = refusal_reason
      return Plan.new(db_path: db_path, db_exists: File.exist?(db_path), refusal: refusal, verdicts: []) if refusal

      with_readonly_catalog do |db|
        verdicts = @registry.each_source.map { |entry| verdict_for(db, entry) }
        Plan.new(db_path: db_path, db_exists: true, refusal: nil, verdicts: verdicts)
      end
    end

    # Re-derive the dirty sources into the LIVE catalog; skip the clean ones
    # entirely (one Clean per skip). Raises Nabu::Error on any refusal.
    def run(progress: nil)
      refusal = refusal_reason
      raise Nabu::Error, refusal if refusal

      db = Store.connect(db_path)
      Store.setup!(db)
      ledger = Store::Ledger.open!(history_path)
      fulltext = Store.connect_fulltext(fulltext_path)
      outcomes = []
      cleans = []
      skips = []
      indexed = nil
      @registry.each_source do |entry|
        unless replayable?(entry)
          skips << Skip.new(slug: entry.slug, reason: :no_canonical)
          next
        end
        fingerprint = fingerprint_for(db, entry)
        if fingerprint.drift_against(Store::DerivationStamp.fetch(db, entry.slug)).nil?
          cleans << Clean.new(slug: entry.slug, stamp_short: fingerprint.short)
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
        indexed = (indexed || 0) + refresh_index(db, fulltext, entry) unless index_inert?(entry)
      end
      replay_enrichments(db)
      axes, facets = corpus_builders(db, progress) if outcomes.any?
      indexed = heal_index(db, fulltext, progress) if outcomes.empty? && !Store::Indexer.incremental_ready?(fulltext)
      Result.new(db_path: db_path, outcomes: outcomes, cleans: cleans, skips: skips,
                 indexed: indexed, axes: axes, facets: facets)
    ensure
      db&.disconnect
      fulltext&.disconnect
      ledger&.disconnect
    end

    private

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
    def refresh_index(db, fulltext, entry)
      Store::Indexer.refresh_source!(
        catalog: db, fulltext: fulltext, slug: entry.slug,
        alignments: alignments, fuzzy_slugs: @registry.fuzzy_slugs,
        lemma_tiers: @registry.lemma_tiers,
        reflexes_changed: entry.adapter_class.content_kind == :dictionary
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
                              fuzzy_slugs: @registry.fuzzy_slugs, lemma_tiers: @registry.lemma_tiers)
    end

    def alignments
      @alignments ||= AlignmentRegistry.load(@config.alignments_path)
    end
  end
end
