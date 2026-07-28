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
          # P45-r3: the write-time freq shelf when it exists (the P42
          # doctrine — probes at read time), the live aggregate only on a
          # pre-P42-1 fulltext.
          if Store::LemmaFrequencies.available?(@fulltext)
            Store::LemmaFrequencies.gold_language_totals(@fulltext).each do |language, count|
              codes[language][:lemma_rows] = count
            end
          else
            gold_lemma_rows.group_and_count(:language).each do |row|
              codes[row.fetch(:language)][:lemma_rows] = row.fetch(:count)
            end
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

      public

      # The axis card's one-number probe (P45-r3): summed gold rows over a
      # language set in ONE grouped query — never a per-code Relevance
      # build (relevance also computes shelves/edges/breakdowns the card
      # discards).
      def gold_rows_for(codes)
        return 0 unless lemma_index?

        if Store::LemmaFrequencies.available?(@fulltext)
          totals = Store::LemmaFrequencies.gold_language_totals(@fulltext)
          return codes.sum { |code| totals[code.to_s].to_i }
        end
        gold_lemma_rows.where(language: codes.map(&:to_s)).count
      end

      # The axis card's languages line (P48-r3): [[code, count], …] over a
      # member slug set — live document counts per language (stats-backed,
      # the P42 doctrine: probes at read time, never a documents scan at
      # card time) plus dictionary entry counts for shelf languages, one
      # merged doc-or-entry count per code, holdings descending (ties by
      # code). The counts are the honesty mechanism: a multilingual pack's
      # three-document spillover reads as 3 beside a 40K holding.
      def language_holdings_for(slugs)
        slugs = slugs.map(&:to_s)
        counts = Hash.new(0)
        document_counts_for(slugs).each { |code, count| counts[code] += count }
        entry_counts_for(slugs).each { |code, count| counts[code] += count }
        counts.sort_by { |code, count| [-count, code] }
      end

      # The language card's axes seam (P48-r3): every source slug holding
      # +code+ — ≥1 live document (stats-backed) or a dictionary shelf in
      # it. The CLI maps these onto the research desks they serve.
      def holding_slugs(code)
        code = code.to_s
        (sources_breakdown(code).keys + shelf_source_slugs(code)).uniq
      end

      private

      def lemma_rows(code)
        return 0 unless lemma_index?
        # P45-r3 (the owner's 30 s `axis romance`: 18 member languages ×
        # a live COUNT over the 16M-row lemma index): probe the write-time
        # freq shelf; the live count survives only for a pre-P42-1 fulltext.
        if Store::LemmaFrequencies.available?(@fulltext)
          return Store::LemmaFrequencies.gold_language_total(@fulltext, code)
        end

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

      # {code => live document count} restricted to +slugs+ — the stats
      # shelf when it exists (P42-0), the live aggregate on a pre-019
      # catalog.
      def document_counts_for(slugs)
        if stats?
          @catalog[:source_stats_languages]
            .join(:sources, id: Sequel[:source_stats_languages][:source_id])
            .where(Sequel[:sources][:slug] => slugs)
            .where { documents >= 1 }
            .group(Sequel[:source_stats_languages][:language])
            .select(Sequel[:source_stats_languages][:language].as(:language),
                    Sequel.function(:sum, Sequel[:source_stats_languages][:documents]).as(:count))
            .to_h { |row| [row.fetch(:language), row.fetch(:count).to_i] }
        else
          live_documents
            .join(:sources, id: Sequel[:documents][:source_id])
            .where(Sequel[:sources][:slug] => slugs)
            .exclude(Sequel[:documents][:language] => nil)
            .group(Sequel[:documents][:language])
            .select(Sequel[:documents][:language].as(:language),
                    Sequel.function(:count).*.as(:count))
            .to_h { |row| [row.fetch(:language), row.fetch(:count)] }
        end
      end

      # {code => live dictionary entry count} restricted to +slugs+ — the
      # entry tables are shelf-bounded, so a live count is the P42-r2
      # posture, same as #shelves.
      def entry_counts_for(slugs)
        return {} unless @catalog.table_exists?(:dictionaries)

        @catalog[:dictionary_entries]
          .join(:dictionaries, id: Sequel[:dictionary_entries][:dictionary_id])
          .join(:sources, id: Sequel[:dictionaries][:source_id])
          .where(Sequel[:sources][:slug] => slugs, Sequel[:dictionary_entries][:withdrawn] => false)
          .group(Sequel[:dictionaries][:language])
          .select(Sequel[:dictionaries][:language].as(:language),
                  Sequel.function(:count).*.as(:count))
          .to_h { |row| [row.fetch(:language), row.fetch(:count)] }
      end

      # Source slugs with a dictionary shelf in +code+.
      def shelf_source_slugs(code)
        return [] unless @catalog.table_exists?(:dictionaries)

        @catalog[:dictionaries]
          .join(:sources, id: Sequel[:dictionaries][:source_id])
          .where(Sequel[:dictionaries][:language] => code)
          .distinct
          .select_map(Sequel[:sources][:slug])
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
