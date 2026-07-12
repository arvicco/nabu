# frozen_string_literal: true

module Nabu
  module Store
    # The cognate root-closure table (P15-3, intertext design §6, fable
    # closure review 2026-07-12): one row per (gold language, folded lemma,
    # reconstruction-entry urn) asserting the lemma descends — within the
    # bounded two-level walk below — from that reconstruction entry. The
    # P7-5 pattern again: derived from the catalog's stored crosswalk, living
    # in fulltext.sqlite3 beside passage_lemmas/alignment_refs with the same
    # drop-and-rebuild lifecycle, created here imperatively, never migrated.
    # Indexer.rebuild! is the single choke point (sync's reindex + rebuild),
    # so a recon re-sync and a treebank sync both regenerate it — the
    # review's staleness rider.
    #
    # == The walk (and why it is exactly two levels)
    #
    # DIRECT (depth 1): every dictionary_reflexes row of a live entry maps
    # (language, word_folded) and (language, roman_folded) to its OWNING
    # entry — the roman fold is the script bridge (got 𐍃𐌰𐌻𐍄 joins the gold
    # lemma "salt"). ASCENT (depth 2): a direct target that is itself a
    # reconstruction ("-pro" dictionary) adds every OTHER-shelf entry whose
    # reflexes name its (language, headword_folded) — the same proto-to-proto
    # edge Query::Etym#ancestors_of walks, same same-language exclusion (the
    # live PIE extract holds ~6k intra-shelf derivational edges that are
    # sub-tree structure, not ancestry). The ascent step is not re-expanded,
    # so a malformed proto-to-proto cycle terminates trivially, and — with
    # exactly three reconstruction shelves, every reflex row owned by one of
    # them — one hop up provably reaches everything an unbounded walk would
    # (a depth-3 chain needs an intermediate shelf, e.g. Proto-Balto-Slavic,
    # that does not exist in the catalog; revisit the bound if one lands).
    #
    # == Roots are URNs, not row ids (the review's determinism finding)
    #
    # dictionary_entries ids re-mint whenever the shelf reloads, and a recon
    # re-sync does NOT drop this table — only the next reindex does. Stored
    # ids would go silently stale (or worse, point at since-withdrawn rows);
    # stored URNs are the project's cross-parse stability contract, and the
    # query resolves them against the CURRENT catalog with the withdrawn
    # filter applied, so a root withdrawn since the build drops out honestly.
    #
    # == Gold scoping
    #
    # Final rows are emitted only for languages present in passage_lemmas:
    # the table exists solely to join gold lemmas, and the ~250k modern-
    # language descendant keys (en, de, ru …) can never join. Proto shelves
    # still participate as build-time intermediates. Measured live:
    # ~51k rows, < 5 MB, ~1.4 s.
    #
    # The companion STATS_TABLE holds per-language gold passage counts —
    # what Query::Cognates' common-word suppression divides by (a fixed
    # absolute df threshold is percentile-incoherent across corpora spanning
    # 125 to 113k gold passages; the review's calibration finding).
    module ReflexRootsIndexer
      TABLE = :reflex_roots
      STATS_TABLE = :reflex_root_stats

      BATCH_SIZE = 2_000

      module_function

      # Drop and rebuild the closure + stats tables from +catalog+ into
      # +fulltext+. A catalog without the crosswalk (pre-007, or no recon
      # sync yet) and a fulltext without gold lemmas both leave the tables
      # EMPTY, never missing — queries degrade to "no rows". Returns the
      # closure row count.
      def rebuild!(catalog:, fulltext:)
        fulltext.drop_table?(TABLE)
        fulltext.drop_table?(STATS_TABLE)
        create_tables(fulltext)
        write_stats(fulltext)
        return 0 unless catalog.table_exists?(:dictionary_reflexes)

        gold = gold_languages(fulltext)
        return 0 if gold.empty?

        rows = closure_rows(entry_meta(catalog), reflex_edges(catalog), gold)
        count = 0
        fulltext.transaction do
          rows.each_slice(BATCH_SIZE) do |batch|
            fulltext[TABLE].multi_insert(batch)
            count += batch.size
          end
        end
        count
      end

      def create_tables(fulltext)
        fulltext.create_table(TABLE) do
          String :language, null: false
          String :lemma_folded, null: false
          String :root_urn, null: false
          index %i[language lemma_folded]
        end
        fulltext.create_table(STATS_TABLE) do
          String :language, null: false
          Integer :gold_passages, null: false
          index :language, unique: true
        end
      end

      # Per-language DISTINCT gold passage counts — the suppression
      # denominator, snapshotted from the passage_lemmas built in the same
      # rebuild pass (so the two can never drift).
      def write_stats(fulltext)
        return unless fulltext.table_exists?(Indexer::LEMMA_TABLE)

        rows = fulltext[Indexer::LEMMA_TABLE]
               .group(:language)
               .select { [language, count(:passage_id).distinct.as(:gold_passages)] }
               .map { |row| { language: row.fetch(:language), gold_passages: row.fetch(:gold_passages) } }
        fulltext[STATS_TABLE].multi_insert(rows)
      end

      def gold_languages(fulltext)
        return [] unless fulltext.table_exists?(Indexer::LEMMA_TABLE)

        fulltext[Indexer::LEMMA_TABLE].distinct.select_map(:language).compact
      end

      # Live entries only (the withdrawn filter mirrors Etym#entry_dataset):
      # id => { language:, headword_folded:, urn: }.
      def entry_meta(catalog)
        catalog[:dictionary_entries]
          .join(:dictionaries, id: Sequel[:dictionary_entries][:dictionary_id])
          .where(Sequel[:dictionary_entries][:withdrawn] => false)
          .select(Sequel[:dictionary_entries][:id].as(:entry_id),
                  Sequel[:dictionaries][:language].as(:dict_language),
                  Sequel[:dictionary_entries][:headword_folded],
                  Sequel[:dictionary_entries][:urn])
          .to_h do |row|
            [row.fetch(:entry_id), { language: row.fetch(:dict_language),
                                     headword_folded: row.fetch(:headword_folded),
                                     urn: row.fetch(:urn) }]
          end
      end

      # (reflex language, folded form) => Set of owning entry ids, over both
      # the word and roman folds. Rows with a nil catalog-side language are
      # display-only, never join candidates (§12); rows of withdrawn entries
      # are filtered by the caller's entry_meta lookup.
      def reflex_edges(catalog)
        edges = Hash.new { |hash, key| hash[key] = Set.new }
        catalog[:dictionary_reflexes]
          .exclude(language: nil)
          .select(:language, :word_folded, :roman_folded, :dictionary_entry_id)
          .each do |row|
            [row.fetch(:word_folded), row.fetch(:roman_folded)].compact.uniq.each do |folded|
              next if folded.empty?

              edges[[row.fetch(:language), folded]].add(row.fetch(:dictionary_entry_id))
            end
          end
        edges
      end

      # The closure over the two-level walk, gold-scoped, deduplicated, and
      # sorted (deterministic across identical inputs — rebuild determinism
      # is a review requirement, not a nicety).
      def closure_rows(meta, edges, gold)
        gold_set = gold.to_set
        rows = Set.new
        edges.each do |(language, folded), entry_ids|
          next unless gold_set.include?(language)

          root_urns(entry_ids, meta, edges).each do |urn|
            rows.add([language, folded, urn])
          end
        end
        rows.sort.map { |language, folded, urn| { language: language, lemma_folded: folded, root_urn: urn } }
      end

      # Direct targets plus one ascent hop each — never re-expanded (the
      # depth bound), never into the same shelf (the derivational-edge
      # exclusion). Withdrawn or unknown entry ids resolve to nothing.
      def root_urns(entry_ids, meta, edges)
        entry_ids.each_with_object(Set.new) do |entry_id, urns|
          entry = meta[entry_id] or next
          urns.add(entry.fetch(:urn))
          next unless entry.fetch(:language).to_s.end_with?("-pro") && entry[:headword_folded]

          edges.fetch([entry.fetch(:language), entry.fetch(:headword_folded)], []).each do |ancestor_id|
            ancestor = meta[ancestor_id] or next
            urns.add(ancestor.fetch(:urn)) unless ancestor.fetch(:language) == entry.fetch(:language)
          end
        end
      end
    end
  end
end
