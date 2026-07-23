# frozen_string_literal: true

require_relative "indexer"

module Nabu
  module Store
    # The corpus lemma-frequency DERIVED table (P42-1): passage-frequency per
    # (lemma_folded, language, tier), the write-time census behind vocab's
    # log-odds denominator and etym's per-reflex attestation counts. Measured
    # 2026-07-23 at 62.8M passages / 16.2M gold rows: `vocab` spent 17.9s
    # recomputing the corpus total from the whole passage_lemmas table, and
    # `etym` 9.0s because each reflex's per-language count query planned onto
    # the single-column `language` index — a full scan of that language's
    # millions of passage_lemmas rows + a temp-b-tree GROUP BY, repeated across
    # every reflex language and every ancestor on the walk. This is the same
    # doctrine as SourceStats (architecture §5): anything O(corpus) runs at
    # write time; read time is for probes.
    #
    # == Placement: fulltext, not the catalog (the SourceStats mirror)
    #
    # SourceStats lives in the catalog because it aggregates catalog tables
    # (documents/passages). This table aggregates passage_lemmas, which lives
    # in fulltext.sqlite3 — derived-of-derived, disposable, never migrated
    # (Indexer class note). So it lives BESIDE its source data, is built by the
    # Indexer in the same pass that builds passage_lemmas (no drift possible),
    # and shares the drop-and-rebuild lifecycle of reflex_roots / alignment_refs.
    # There is NO numbered migration and NO catalog schema_info bump: the
    # "migration backfill" concern of a catalog table becomes an INDEXER-backfill
    # concern — a fulltext file predating this table simply lacks it until the
    # next reindex, and readers feature-detect (#available?) and fall back to
    # today's live aggregate so behaviour is byte-identical pre-build. The
    # Indexer's incremental_ready? lists this table, so an old fulltext triggers
    # one full rebuild on the next sync and self-heals (the tier-column precedent).
    #
    # == Two lifecycles, one truth (the SourceStats contract)
    #
    # - WHOLESALE (#rebuild!): Indexer.rebuild! drops and re-derives the whole
    #   table from the freshly-built passage_lemmas in one grouped INSERT-SELECT
    #   — the rebuildability invariant, and the reference the incremental path is
    #   test-pinned against.
    # - INCREMENTAL (#refresh_source_delta): Indexer.refresh_source! rewrites one
    #   source's passage_lemmas rows, then applies that source's before/after
    #   contribution delta to this table IN THE SAME transaction. Per-source
    #   before/after aggregation (both urn-scoped and B-tree bounded) is chosen
    #   over per-row maintenance: passage_lemmas is bulk-written in slices, so a
    #   single grouped snapshot of the source's rows is far cheaper than tallying
    #   millions of individual inserts, and it is exactly as exact — the
    #   equivalence test pins refresh-vs-wholesale to byte identity.
    #
    # == Counting semantics
    #
    # One row per (lemma_folded, language, tier) carrying the PASSAGE count (one
    # per distinct folded lemma per passage, exactly as passage_lemmas is
    # grained — never token frequency). tier is always present here: this table
    # only ever exists alongside the tier-column Indexer that builds it, so
    # readers never meet a pre-tier freq table (a pre-tier fulltext has no freq
    # table at all, and the reader falls back). vocab's corpus reads collapse
    # across languages (#gold_total, #gold_frequencies); etym reads per language
    # split by tier (#language_tier_counts). No stored global roll-up — the
    # gold total is a SUM over the (tiny, ~1-2M-row-max) table.
    module LemmaFrequencies
      TABLE = :lemma_frequencies

      # The insert/scan slice — matches the Indexer's so a source's urn-scoped
      # snapshot batches identically.
      BATCH_SIZE = 2_000

      module_function

      # Feature detection: a fulltext file predating this table has none — every
      # caller (Indexer maintenance, vocab, reflex_views) degrades to the
      # pre-P42-1 live aggregate when this is false.
      def available?(fulltext)
        !fulltext.nil? && fulltext.table_exists?(TABLE)
      end

      # -- wholesale (Indexer.rebuild!) ---------------------------------------

      # Drop and re-derive the whole table from the current passage_lemmas.
      # Returns the row count. A fulltext without passage_lemmas (never, from
      # rebuild!, but defensive) leaves an empty table — readers see zeros, not
      # a missing table.
      def rebuild!(fulltext)
        fulltext.drop_table?(TABLE)
        create_table!(fulltext)
        derive!(fulltext)
      end

      def create_table!(fulltext)
        fulltext.create_table(TABLE) do
          String :lemma_folded, null: false
          String :language, null: false
          String :tier, null: false
          Integer :passage_count, null: false
          # The natural key AND the read index. lemma_folded is leftmost so the
          # vocab/etym `lemma_folded IN (…)` reads plan onto it as point lookups
          # (with language/tier as contiguous residual columns) — never onto the
          # low-selectivity language scan that made etym 9s on passage_lemmas.
          index %i[lemma_folded language tier], unique: true
        end
      end

      # Populate an empty table from passage_lemmas in one grouped INSERT-SELECT
      # (Sequel dataset import — no raw SQL). Returns the row count.
      def derive!(fulltext)
        return 0 unless fulltext.table_exists?(Indexer::LEMMA_TABLE)

        source = fulltext[Indexer::LEMMA_TABLE]
                 .group(:lemma_folded, :language, :tier)
                 .select(:lemma_folded, :language, :tier, Sequel.function(:count).*.as(:passage_count))
        fulltext[TABLE].import(%i[lemma_folded language tier passage_count], source)
        fulltext[TABLE].count
      end

      # -- incremental (Indexer.refresh_source!) ------------------------------

      # One source's contribution to the table: { [folded, language, tier] =>
      # passage_count } over its urns (B-tree indexed, sliced). Summed across
      # slices so a urn split over two batches still totals correctly.
      def snapshot(fulltext, urns)
        counts = Hash.new(0)
        urns.each_slice(BATCH_SIZE) do |batch|
          fulltext[Indexer::LEMMA_TABLE].where(urn: batch)
                                        .group(:lemma_folded, :language, :tier)
                                        .select(:lemma_folded, :language, :tier,
                                                Sequel.function(:count).*.as(:n))
                                        .each do |row|
            counts[[row[:lemma_folded], row[:language], row[:tier]]] += row[:n]
          end
        end
        counts
      end

      # Apply a source's before→after delta to the corpus table. Rows that reach
      # zero are pruned, so the incremental table stays row-identical to a
      # wholesale derivation (the equivalence contract). Caller runs this inside
      # the same transaction as the passage_lemmas rewrite.
      def apply_delta(fulltext, before:, after:)
        (before.keys | after.keys).each do |key|
          delta = after.fetch(key, 0) - before.fetch(key, 0)
          next if delta.zero?

          upsert(fulltext, key, delta)
        end
      end

      def upsert(fulltext, key, delta)
        folded, language, tier = key
        scope = fulltext[TABLE].where(lemma_folded: folded, language: language, tier: tier)
        current = scope.get(:passage_count)
        total = (current || 0) + delta
        if total <= 0
          scope.delete
        elsif current
          scope.update(passage_count: total)
        else
          fulltext[TABLE].insert(lemma_folded: folded, language: language, tier: tier, passage_count: total)
        end
      end

      # -- readers ------------------------------------------------------------

      # vocab's log-odds denominator: total GOLD passage-lemma rows across the
      # whole corpus (== gold_corpus_rows.count on passage_lemmas, exactly).
      def gold_total(fulltext)
        fulltext[TABLE].where(tier: Indexer::GOLD_TIER).sum(:passage_count) || 0
      end

      # vocab's corpus_frequencies: GOLD passage-frequency per folded lemma,
      # SUMMED across languages (vocab folds per the passage's language and
      # groups by lemma_folded alone). { folded => count }; batched under
      # SQLite's bound-variable limit.
      def gold_frequencies(fulltext, folded_lemmas)
        out = {}
        folded_lemmas.each_slice(500) do |slice|
          fulltext[TABLE].where(tier: Indexer::GOLD_TIER, lemma_folded: slice)
                         .group(:lemma_folded)
                         .select(:lemma_folded, Sequel.function(:sum, :passage_count).as(:count))
                         .each { |row| out[row[:lemma_folded]] = row[:count].to_i }
        end
        out
      end

      # etym's per-reflex counts for ONE language: { folded => { tier => count } }
      # over the folded list — the composite index makes each folded value a
      # point lookup with language as the contiguous next column.
      def language_tier_counts(fulltext, language:, folded:)
        out = {}
        folded.each_slice(500) do |slice|
          fulltext[TABLE].where(language: language, lemma_folded: slice)
                         .select(:lemma_folded, :tier, :passage_count)
                         .each { |row| (out[row[:lemma_folded]] ||= {})[row[:tier]] = row[:passage_count] }
        end
        out
      end

      # vocab's no-gold path: [[language, gold count], …] descending — the
      # gold-bearing languages, summed from the table (== the old
      # group_and_count(:language) over gold passage_lemmas, exactly). Removes
      # vocab's last O(corpus) scan.
      def gold_languages(fulltext)
        fulltext[TABLE].where(tier: Indexer::GOLD_TIER)
                       .group(:language)
                       .select(:language, Sequel.function(:sum, :passage_count).as(:count))
                       .order(Sequel.desc(:count))
                       .map { |row| [row[:language], row[:count].to_i] }
      end
    end
  end
end
