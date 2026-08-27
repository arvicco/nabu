# frozen_string_literal: true

module Nabu
  module Store
    # P84-1 — the silver-lemma projection: streams the local-lemmas shelf
    # (Nabu::LemmaShelf — the enricher's non-derivable model output) into
    # passage_lemmas as tier-"silver" rows, riding the P26-0 tier machinery
    # unchanged (search --lemma labels silver hits and gold-scoped
    # consumers exclude them already).
    #
    # The pass is INSERT-IF-ABSENT at passage grain: a urn with ANY
    # existing lemma rows — gold annotation rows, an upstream-silver
    # source's rows, the equivalence tier, or an earlier run of this very
    # pass — is skipped whole. That one rule is simultaneously the
    # never-overwrite-gold guarantee, the idempotency proof, and the
    # ordering contract with the annotation pass (which always runs
    # first). Derived-of-derived like everything fulltext-side: a pure
    # function of shelf + catalog, so it survives `nabu rebuild` by
    # construction and re-applies after a source's incremental refresh
    # strips its slice.
    #
    # == The epigraphy mitigation (the P79-4 trial's 75% band)
    #
    # Stanza's worst error class on EDR/EDH is invented proper-name
    # nominatives. For sources declared `lemma_dictionary_filter: true`
    # in sources.yml, a silver lemma is kept only when the language's
    # reference dictionary attests it (folded headword match — Lewis-Short
    # for Latin) OR it folds identically to one of its own surface forms
    # (identity is harmless: surface search already reaches it). No
    # dictionary rows loaded = no filtering — dropping everything
    # unconfirmed would be dishonest, so the filter degrades to a no-op.
    # The filter is index-time POLICY over raw shelf tokens: re-indexing
    # with a different rule never costs model compute again.
    module SilverLemmaIndexer
      TIER = "silver"
      BATCH = 1_000

      # The confirmation dictionary per language lane (see class note).
      DICTIONARY_SLUGS = { "lat" => %w[lewis-short] }.freeze

      # What one apply did. passages_indexed counts passages that gained
      # rows; skipped_covered = already lemma-covered (any tier);
      # skipped_missing = urn absent or withdrawn (either level);
      # skipped_mismatch = passage language drifted from the shelf claim;
      # filtered_lemmas = distinct lemmas the dictionary filter dropped.
      Result = Data.define(:passages_indexed, :rows_inserted, :skipped_covered,
                           :skipped_missing, :skipped_mismatch, :filtered_lemmas)

      module_function

      # Apply the shelf to passage_lemmas. +urns+ (a Set, optional) scopes
      # the pass to one source's slice (the refresh_source! path);
      # +dictionary_filter_slugs+ names the sources under the epigraphy
      # filter; +update_frequencies+ folds the inserted rows into
      # lemma_frequencies (callers that rebuild or delta the table
      # themselves pass false).
      def apply!(catalog:, fulltext:, shelf:, urns: nil, dictionary_filter_slugs: [],
                 update_frequencies: false, progress: nil)
        counts = Hash.new(0)
        frequencies = Hash.new(0)
        shelf.languages.each do |language|
          dictionary = dictionary_folded(catalog, language, dictionary_filter_slugs)
          each_batch(shelf, language, urns) do |batch|
            apply_batch(catalog, fulltext, batch,
                        counts: counts, frequencies: frequencies,
                        dictionary: dictionary, filter_slugs: dictionary_filter_slugs)
            progress&.load_tick(counts[:passages_indexed], 0)
          end
        end
        upsert_frequencies(fulltext, frequencies) if update_frequencies
        Result.new(passages_indexed: counts[:passages_indexed], rows_inserted: counts[:rows_inserted],
                   skipped_covered: counts[:skipped_covered], skipped_missing: counts[:skipped_missing],
                   skipped_mismatch: counts[:skipped_mismatch], filtered_lemmas: counts[:filtered_lemmas])
      end

      def each_batch(shelf, language, urns)
        batch = []
        shelf.each_record(language: language) do |record|
          next if urns && !urns.include?(record.urn)

          batch << record
          if batch.size >= BATCH
            yield batch
            batch = []
          end
        end
        yield batch unless batch.empty?
      end

      def apply_batch(catalog, fulltext, batch, counts:, frequencies:, dictionary:, filter_slugs:)
        covered = covered_urns(fulltext, batch)
        live = live_passages_by_urn(catalog, batch)
        rows = []
        batch.each do |record|
          next counts[:skipped_covered] += 1 if covered.include?(record.urn)

          passage = live[record.urn]
          next counts[:skipped_missing] += 1 if passage.nil?
          next counts[:skipped_mismatch] += 1 if passage[:language] != record.language

          filter = dictionary if filter_slugs.include?(passage[:slug])
          record_rows = silver_rows(record, passage, dictionary: filter, counts: counts)
          next if record_rows.empty?

          counts[:passages_indexed] += 1
          counts[:rows_inserted] += record_rows.size
          record_rows.each { |row| frequencies[[row[:lemma_folded], row[:language]]] += 1 }
          rows.concat(record_rows)
        end
        fulltext.transaction { rows.each_slice(BATCH) { |slice| fulltext[Indexer::LEMMA_TABLE].multi_insert(slice) } }
      end

      # Urns of +batch+ that already hold ANY lemma rows (the
      # insert-if-absent guard; urn is B-tree indexed).
      def covered_urns(fulltext, batch)
        fulltext[Indexer::LEMMA_TABLE].where(urn: batch.map(&:urn)).distinct.select_map(:urn).to_set
      end

      # { urn => { passage_id:, language:, slug: } } for the LIVE passages
      # of +batch+ (the two-level visibility rule: passage AND document).
      def live_passages_by_urn(catalog, batch)
        catalog[:passages]
          .join(:documents, id: :document_id)
          .join(:sources, id: Sequel[:documents][:source_id])
          .where(Sequel[:passages][:urn] => batch.map(&:urn),
                 Sequel[:passages][:withdrawn] => false,
                 Sequel[:documents][:withdrawn] => false)
          .select(Sequel[:passages][:id].as(:passage_id), Sequel[:passages][:urn],
                  Sequel[:passages][:language], Sequel[:sources][:slug].as(:slug))
          .to_hash(:urn)
      end

      # One record's tier-silver rows: group tokens by FOLDED lemma
      # (Normalize.search_form — the same fold-both-sides contract as the
      # annotation pass), one row per (passage, folded lemma), distinct
      # surface forms in first-seen order. Lemma-less tokens contribute
      # nothing; the dictionary filter (when armed) drops unattested
      # non-identity lemmas.
      def silver_rows(record, passage, dictionary:, counts:)
        grouped = group_tokens(record)
        grouped.filter_map do |folded, entry|
          if dictionary && !dictionary.include?(folded) && !identity_lemma?(folded, entry, record.language)
            counts[:filtered_lemmas] += 1
            next
          end
          { lemma_folded: folded, lemma_raw: entry[:raw], passage_id: passage[:passage_id],
            urn: record.urn, language: record.language,
            surface_forms: entry[:forms].join(", "), tier: TIER }
        end
      end

      def group_tokens(record)
        record.tokens.each_with_object({}) do |(form, lemma, _upos), grouped|
          next if lemma.nil? || lemma.empty?

          folded = Normalize.search_form(lemma, language: record.language)
          entry = grouped[folded] ||= { raw: lemma, forms: [] }
          entry[:forms] << form if form && !form.empty? && !entry[:forms].include?(form)
        end
      end

      # A lemma that folds identically to one of its own surface forms:
      # surface search already reaches it, so keeping it risks nothing.
      def identity_lemma?(folded, entry, language)
        entry[:forms].any? { |form| Normalize.search_form(form, language: language) == folded }
      end

      # The folded headword set confirming lemmas for +language+, or nil
      # when the filter is unarmed (no flagged sources) or unconfirmable
      # (no dictionary rows — the honest no-op).
      def dictionary_folded(catalog, language, filter_slugs)
        return nil if filter_slugs.empty?

        slugs = DICTIONARY_SLUGS[language]
        return nil if slugs.nil? || !catalog.table_exists?(:dictionary_entries)

        set = catalog[:dictionary_entries]
              .join(:dictionaries, id: :dictionary_id)
              .where(Sequel[:dictionaries][:slug] => slugs,
                     Sequel[:dictionary_entries][:withdrawn] => false)
              .select_map(:headword_folded).to_set
        set.empty? ? nil : set
      end

      def upsert_frequencies(fulltext, frequencies)
        return if frequencies.empty?

        LemmaFrequencies.create_table!(fulltext) unless fulltext.table_exists?(LemmaFrequencies::TABLE)
        fulltext.transaction do
          frequencies.each do |(folded, language), count|
            LemmaFrequencies.upsert(fulltext, [folded, language, TIER], count)
          end
        end
      end
    end
  end
end
