# frozen_string_literal: true

require_relative "../normalize"
require_relative "reflex_views"

module Nabu
  module Query
    # The comparativist's walk (P14-1, architecture §12): `nabu etym богъ`
    # takes an ATTESTED lemma, finds every reconstruction entry naming it as
    # a descendant reflex (folded match on the crosswalk's word_folded OR
    # roman_folded — the script bridge that lets got guþ reach *gudą through
    # 𐌲𐌿𐌸), and returns each proto entry with its full cognate list (corpus
    # attestation counts resolved at query time via ReflexViews) plus the
    # proto-to-proto ASCENT: entries of the OTHER reconstruction shelves
    # whose descendants name this reconstruction (PIE *bʰeh₂g- names sla-pro
    # *bogъ), each with its own cognates. The ascent is deliberately bounded
    # to ONE hop up — attested → proto → proto — so the walk stays a report,
    # not a graph crawl.
    #
    # A leading asterisk skips the attested side: `etym *bogъ` looks the
    # reconstruction headword up directly (same strip-the-asterisk
    # convention as `define *bogъ`; upstream stores headwords bare).
    #
    # Degradation is graceful everywhere: a catalog predating migration 007
    # (or with no shelves) returns []; without a fulltext handle the walk
    # works and every attestation count is an honest nil.
    class Etym
      # How the walk entered this entry: the reflex that matched the query
      # (nil for direct asterisk lookups).
      MatchedVia = Data.define(:language, :word, :roman)

      # One reconstruction entry on the walk. +headword+ carries the display
      # asterisk; +cognates+ are ReflexViews::View values in stored order;
      # +ancestors+ are Results one hop up (empty at the depth bound).
      Result = Data.define(:urn, :dictionary_slug, :dictionary_title, :language,
                           :headword, :gloss, :license, :license_class, :source_slug,
                           :matched_reflex, :cognates, :ancestors)

      DEFAULT_LIMIT = 5

      def initialize(catalog:, fulltext: nil)
        @catalog = catalog
        @views = ReflexViews.new(catalog: catalog, fulltext: fulltext)
      end

      def run(lemma, lang: nil, limit: DEFAULT_LIMIT)
        return [] unless shelf?

        term = lemma.to_s.strip
        direct = term.delete_prefix("*")
        return [] if direct.strip.empty?

        return headword_results(direct, limit: limit) if term.start_with?("*")

        reflex = proto_rows_by_reflex(term, lang: lang, limit: limit)
                 .map { |row, matched| build_result(row, matched: matched, ascend: true) }
        # Bare-form fallback (P14-10): the reflex path missed, so the user most
        # likely typed the RECONSTRUCTION form itself (bʰewgʰ, or ASCII bhewgh)
        # rather than an attested descendant. Try the -pro shelves' own
        # headwords — asterisk optional (zsh globs a bare *), trailing-hyphen
        # tolerant (root entries store *bʰewgʰ-), folded through §9.
        reflex.empty? ? headword_results(direct, limit: limit) : reflex
      end

      private

      def headword_results(headword, limit:)
        proto_rows_by_headword(headword, limit: limit)
          .map { |row| build_result(row, matched: nil, ascend: true) }
      end

      def shelf?
        @catalog.table_exists?(:dictionary_entries) && @views.available?
      end

      # -- entry finders -----------------------------------------------------------

      # Attested → proto: reflex rows whose word_folded/roman_folded hits the
      # query_forms union, deduplicated to entries (first matching reflex in
      # stored order wins as the MatchedVia).
      def proto_rows_by_reflex(term, lang:, limit:)
        variants = Nabu::Normalize.query_forms(term)
        dataset = entry_dataset
                  .join(:dictionary_reflexes, dictionary_entry_id: Sequel[:dictionary_entries][:id])
                  .where(
                    Sequel.|({ Sequel[:dictionary_reflexes][:word_folded] => variants },
                             { Sequel[:dictionary_reflexes][:roman_folded] => variants })
                  )
        dataset = dataset.where(Sequel[:dictionary_reflexes][:language] => lang) if lang
        rows = dataset.order(Sequel[:dictionaries][:slug], Sequel[:dictionary_entries][:entry_id],
                             Sequel[:dictionary_reflexes][:seq])
                      .select(*entry_columns,
                              Sequel[:dictionary_reflexes][:language].as(:reflex_language),
                              Sequel[:dictionary_reflexes][:word].as(:reflex_word),
                              Sequel[:dictionary_reflexes][:roman].as(:reflex_roman))
                      .all
        rows.uniq { |row| row.fetch(:entry_row_id) }.first(limit).map do |row|
          [row, MatchedVia.new(language: row.fetch(:reflex_language),
                               word: row.fetch(:reflex_word), roman: row.fetch(:reflex_roman))]
        end
      end

      # Direct `*headword` lookup — reconstruction shelves only (they are the
      # ones whose entries carry reflexes; the -pro language scope matches
      # Define's asterisk convention).
      def proto_rows_by_headword(headword, limit:)
        entry_dataset
          .where(Sequel[:dictionary_entries][:headword_folded] => headword_variants(headword))
          .where(Sequel.like(Sequel[:dictionaries][:language], "%-pro"))
          .order(Sequel[:dictionaries][:slug], Sequel[:dictionary_entries][:entry_id])
          .limit(limit)
          .select(*entry_columns)
          .all
      end

      # Folded lookup variants, trailing-hyphen tolerant (P14-10): a
      # reconstruction ROOT stores its headword with a trailing hyphen
      # (*bʰewgʰ-), so a query typed without it (bʰewgʰ, bhewgh) must still
      # reach the entry — and vice versa. Try each §9 fold variant as-is, with
      # a trailing hyphen appended, and with one stripped.
      def headword_variants(headword)
        Nabu::Normalize.query_forms(headword)
                       .flat_map { |form| [form, "#{form}-", form.chomp("-")] }
                       .uniq
      end

      # Proto → proto, one hop: reflex rows of OTHER reconstruction shelves
      # that name this entry's language + folded headword as a descendant.
      def ancestors_of(row)
        entry_dataset
          .join(:dictionary_reflexes, dictionary_entry_id: Sequel[:dictionary_entries][:id])
          .where(Sequel[:dictionary_reflexes][:language] => row.fetch(:language),
                 Sequel[:dictionary_reflexes][:word_folded] => row.fetch(:headword_folded))
          .exclude(Sequel[:dictionaries][:language] => row.fetch(:language))
          .order(Sequel[:dictionaries][:slug], Sequel[:dictionary_entries][:entry_id])
          .select(*entry_columns)
          .all
          .uniq { |ancestor| ancestor.fetch(:entry_row_id) }
          .map { |ancestor| build_result(ancestor, matched: nil, ascend: false) }
      end

      def entry_dataset
        @catalog[:dictionary_entries]
          .join(:dictionaries, id: Sequel[:dictionary_entries][:dictionary_id])
          .join(:sources, id: Sequel[:dictionaries][:source_id])
          .where(Sequel[:dictionary_entries][:withdrawn] => false)
      end

      def entry_columns
        [Sequel[:dictionary_entries][:id].as(:entry_row_id),
         Sequel[:dictionary_entries][:urn], Sequel[:dictionary_entries][:entry_id],
         Sequel[:dictionary_entries][:headword], Sequel[:dictionary_entries][:headword_folded],
         Sequel[:dictionary_entries][:gloss],
         Sequel[:dictionaries][:slug].as(:dictionary_slug),
         Sequel[:dictionaries][:title].as(:dictionary_title),
         Sequel[:dictionaries][:language],
         Sequel[:sources][:license], Sequel[:sources][:license_class],
         Sequel[:sources][:slug].as(:source_slug)]
      end

      # -- result assembly ----------------------------------------------------------

      def build_result(row, matched:, ascend:)
        Result.new(
          urn: row.fetch(:urn), dictionary_slug: row.fetch(:dictionary_slug),
          dictionary_title: row.fetch(:dictionary_title), language: row.fetch(:language),
          headword: "*#{row.fetch(:headword)}", gloss: row.fetch(:gloss),
          license: row.fetch(:license), license_class: row.fetch(:license_class),
          source_slug: row.fetch(:source_slug),
          matched_reflex: matched,
          cognates: @views.for_entry(row.fetch(:entry_row_id)),
          ancestors: ascend ? ancestors_of(row) : []
        )
      end
    end
  end
end
