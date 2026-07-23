# frozen_string_literal: true

require_relative "../store/indexer"

module Nabu
  module Query
    # Live relevance for `nabu language` (P18-4): what this library actually
    # HOLDS in a language. Every count is over the code as stored: corpus
    # documents/passages (documents.language, passages.language), gold lemma
    # rows (passage_lemmas.language), dictionary shelves
    # (dictionaries.language), and reconstruction-crosswalk edges — where a
    # code appears verbatim as the upstream lang_code AND where it appears
    # as the catalog-side mapped tag (chu collects the cu-coded edges; both
    # reported, never double-counted).
    #
    # P42-0: the corpus grain (documents/passages/per-source split) reads
    # the source_stats derived table when it exists — the measured 131s
    # language card was this class scanning 60M+ passages per code. Lemma
    # rows, shelves, and reflex edges stay live: each is an indexed count
    # over a table orders of magnitude smaller (passage_lemmas rides its
    # language index; shelves/reflexes are reference-shelf-sized). A
    # catalog predating migration 019 falls back to the live aggregates.
    # One deliberate alignment: stats count LIVE passages (neither the
    # passage nor its document withdrawn — the census rule), where the old
    # inline count included withdrawn passages under live documents.
    class LanguageInfo
      Shelf = Data.define(:slug, :title, :entries)
      Relevance = Data.define(:documents, :passages, :lemma_rows, :shelves,
                              :reflex_edges, :edge_codes, :sources) do
        def empty?
          documents.zero? && lemma_rows.zero? && shelves.empty? && reflex_edges.zero?
        end
      end
      Held = Data.define(:code, :documents, :lemma_rows, :shelves)

      def initialize(catalog:, fulltext: nil)
        @catalog = catalog
        @fulltext = fulltext
      end

      def relevance(code)
        code = code.to_s
        Relevance.new(
          documents: documents_count(code), passages: passages_count(code),
          lemma_rows: lemma_rows(code), shelves: shelves(code),
          reflex_edges: reflex_edges(code), edge_codes: edge_codes(code),
          sources: sources_breakdown(code)
        )
      end

      # The --list scope: every code with live corpus documents, gold lemma
      # rows, or a dictionary shelf — the held languages, NOT the 800-code
      # etymology tail (that is what `language CODE` is for).
      def held
        codes = Hash.new { |hash, key| hash[key] = { documents: 0, lemma_rows: 0, shelves: [] } }
        held_document_counts.each do |language, count|
          codes[language][:documents] = count
        end
        if lemma_index?
          gold_lemma_rows.group_and_count(:language).each do |row|
            codes[row.fetch(:language)][:lemma_rows] = row.fetch(:count)
          end
        end
        shelf_rows.each { |shelf| codes[shelf[:language]][:shelves] << shelf[:title] }
        codes.sort.map do |code, held|
          Held.new(code: code, documents: held[:documents],
                   lemma_rows: held[:lemma_rows], shelves: held[:shelves])
        end
      end

      private

      # The source_stats feature gate (P42-0, migration 019).
      def stats?
        return @stats if defined?(@stats)

        @stats = @catalog.table_exists?(:source_stats)
      end

      def documents_count(code)
        return live_documents.where(language: code).count unless stats?

        @catalog[:source_stats_languages].where(language: code).sum(:documents).to_i
      end

      def passages_count(code)
        return @catalog[:source_stats_languages].where(language: code).sum(:passages).to_i if stats?
        return 0 unless @catalog.table_exists?(:passages)

        @catalog[:passages]
          .join(:documents, id: :document_id)
          .where(Sequel[:passages][:language] => code, Sequel[:documents][:withdrawn] => false)
          .count
      end

      def lemma_rows(code)
        return 0 unless lemma_index?

        gold_lemma_rows.where(language: code).count
      end

      # The card's lemma line SAYS gold (P26-0): silver (automatic) rows are
      # excluded so the label stays honest. A pre-tier index has no tier
      # column — and no silver rows — so the unfiltered dataset is the same
      # gold-only count.
      def gold_lemma_rows
        dataset = @fulltext[Store::Indexer::LEMMA_TABLE]
        return dataset unless dataset.columns.include?(:tier)

        dataset.where(tier: Store::Indexer::GOLD_TIER)
      end

      def shelves(code)
        return [] unless @catalog.table_exists?(:dictionaries)

        @catalog[:dictionaries].where(language: code).order(:slug).map do |row|
          Shelf.new(slug: row.fetch(:slug), title: row.fetch(:title),
                    entries: @catalog[:dictionary_entries]
                             .where(dictionary_id: row.fetch(:id), withdrawn: false).count)
        end
      end

      # Verbatim upstream code OR catalog-side mapped tag, one count (never
      # doubled: the OR is over rows).
      def reflex_edges(code)
        return 0 unless reflexes?

        @catalog[:dictionary_reflexes]
          .where(Sequel.|({ lang_code: code }, { language: code }))
          .count
      end

      # The per-upstream-code breakdown of the mapped side: `language chu`
      # reports its edges arrive as "cu" (LANG_CODE_MAP) — shown under
      # --long so the join is honest.
      def edge_codes(code)
        return {} unless reflexes?

        @catalog[:dictionary_reflexes]
          .where(Sequel.|({ lang_code: code }, { language: code }))
          .group_and_count(:lang_code)
          .to_h { |row| [row.fetch(:lang_code), row.fetch(:count)] }
      end

      def sources_breakdown(code)
        unless stats?
          return live_documents
                 .join(:sources, id: :source_id)
                 .where(Sequel[:documents][:language] => code)
                 .group_and_count(Sequel[:sources][:slug])
                 .order(Sequel.desc(:count))
                 .to_h { |row| [row.fetch(:slug), row.fetch(:count)] }
        end

        @catalog[:source_stats_languages]
          .join(:sources, id: Sequel[:source_stats_languages][:source_id])
          .where(Sequel[:source_stats_languages][:language] => code)
          .where { documents >= 1 }
          .order(Sequel.desc(:documents))
          .select_hash(Sequel[:sources][:slug], Sequel[:source_stats_languages][:documents])
      end

      def live_documents
        @catalog[:documents].where(withdrawn: false)
      end

      # {code => live document count} across the corpus, for #held.
      def held_document_counts
        if stats?
          @catalog[:source_stats_languages]
            .where { documents >= 1 }
            .group(:language)
            .select(:language, Sequel.function(:sum, :documents).as(:count))
            .to_h { |row| [row.fetch(:language), row.fetch(:count).to_i] }
        else
          live_documents.exclude(language: nil).group_and_count(:language)
                        .to_h { |row| [row.fetch(:language), row.fetch(:count)] }
        end
      end

      def shelf_rows
        return [] unless @catalog.table_exists?(:dictionaries)

        @catalog[:dictionaries].order(:slug).map { |row| { language: row.fetch(:language), title: row.fetch(:title) } }
      end

      def lemma_index?
        !@fulltext.nil? && @fulltext.table_exists?(Store::Indexer::LEMMA_TABLE)
      end

      def reflexes?
        @catalog.table_exists?(:dictionary_reflexes)
      end
    end
  end
end
