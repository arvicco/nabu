# frozen_string_literal: true

# Nabu::Store::Indexer — the heal's lemma census baseline.
# A partial of lib/nabu/store/indexer.rb, which loads it.
module Nabu
  module Store
    module Indexer
      module_function

      # -- the census baseline (CENSUS_BASELINES_TABLE note) -----------------

      def census_baseline?(fulltext, slug)
        fulltext.table_exists?(CENSUS_BASELINES_TABLE) &&
          !fulltext[CENSUS_BASELINES_TABLE].where(slug: slug).empty?
      end

      # The source's whole key set for a whole-contribution census: the
      # slice's own keys where the run already holds them, else one keyed
      # read (a bulk delta — test-scale only; a real delta never reaches
      # the bulk threshold under the delta cap).
      def census_whole_ids(catalog, source_id, ids, heal, use_delta)
        return heal.slice_ids if heal
        return ids unless use_delta

        source_passage_keys(catalog, source_id).first
      end

      def write_census_baseline!(fulltext, slug, ids)
        freq = LemmaFrequencies.snapshot(fulltext, ids: ids)
        stats = ReflexRootsIndexer.stats_snapshot(fulltext, ids: ids)
        fulltext.create_table?(CENSUS_BASELINES_TABLE) do
          String :slug, null: false
          String :kind, null: false
          String :lemma_folded
          String :language
          String :tier
          Integer :n, null: false
          index :slug
        end
        rows = freq.map do |(folded, language, tier), n|
          { slug: slug, kind: "freq", lemma_folded: folded, language: language, tier: tier, n: n }
        end
        rows += stats.map { |language, n| { slug: slug, kind: "stats", language: language, n: n } }
        fulltext.transaction do
          rows.each_slice(BATCH_SIZE) { |batch| fulltext[CENSUS_BASELINES_TABLE].multi_insert(batch) }
          # An empty contribution still needs its marker row, or a crash
          # would leave no baseline to find.
          fulltext[CENSUS_BASELINES_TABLE].insert(slug: slug, kind: "marker", n: 0) if rows.empty?
        end
      end

      # baseline → the source's whole current contribution, applied to
      # both aggregates and the baseline cleared in ONE transaction (so a
      # crash leaves either the standing baseline or a finished move —
      # never both). Returns the stats delta's gold-language moves.
      def apply_census_from_baseline!(fulltext, slug, ids)
        base = fulltext[CENSUS_BASELINES_TABLE].where(slug: slug)
        freq = base.where(kind: "freq").to_h { |row| [[row[:lemma_folded], row[:language], row[:tier]], row[:n]] }
        stats = base.where(kind: "stats").to_h { |row| [row[:language], row[:n]] }
        after = LemmaFrequencies.snapshot(fulltext, ids: ids)
        after_stats = ReflexRootsIndexer.stats_snapshot(fulltext, ids: ids)
        fulltext.transaction do
          LemmaFrequencies.apply_delta(fulltext, before: freq, after: after)
          moves = ReflexRootsIndexer.apply_stats_delta!(fulltext, before: stats, after: after_stats)
          base.delete
          moves
        end
      end
    end
  end
end
