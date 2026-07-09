# frozen_string_literal: true

require_relative "../normalize"

module Nabu
  module Query
    # Dictionary lookup (P11-4): `nabu define <lemma>` over the catalog's
    # dictionary shelf (architecture §11). Folded-headword equality with the
    # same both-sides contract as lemma search — the query folds through the
    # Normalize.query_forms union, the shelf stores
    # Normalize.search_form(headword, dictionary language) — so μηνις finds
    # μῆνις and λόγος (typed with its final sigma) finds the entry folded
    # λογοσ.
    #
    # == Citation resolution — query time, best effort
    #
    # Entry citations carry a work-level CTS prefix and a dot citation
    # (store shape); here each is resolved against whatever edition of that
    # WORK the catalog currently holds: documents matching
    # <cts_work>.<edition>, preferring the original-language edition over
    # translations (a lexicon cites the Greek, not Butler), then the passage
    # urn <document>:<citation> must actually exist. Resolution is at query
    # time deliberately — works sync after dictionaries and vice versa, and a
    # rebuild re-mints everything; nothing stale is ever stored. Unresolved
    # citations keep their display text and a nil resolved_urn: an honest
    # miss, never an invented link.
    #
    # Degradation: a catalog predating migration 006 (or none at all) simply
    # has no shelf — run returns [], the MCP layer words the state.
    class Define
      # One dictionary entry hit. +citations+ are CitationView values in
      # entry order; +license_class+/+license+ come from the owning source.
      Result = Data.define(:urn, :dictionary_slug, :dictionary_title, :language,
                           :headword, :key_raw, :gloss, :body,
                           :license, :license_class, :source_slug, :citations)

      # One citation of an entry: display label always; resolved_urn is the
      # in-catalog passage urn or nil.
      CitationView = Data.define(:label, :urn_raw, :resolved_urn)

      DEFAULT_LIMIT = 5

      def initialize(catalog:)
        @catalog = catalog
      end

      # Look up +lemma+; +lang+ filters by dictionary language (grc/lat).
      # Returns up to +limit+ Results ordered (dictionary, entry_id).
      def run(lemma, lang: nil, limit: DEFAULT_LIMIT)
        return [] unless shelf?

        variants = Nabu::Normalize.query_forms(lemma.to_s)
        return [] if variants.first.strip.empty?

        rows = entry_rows(variants, lang: lang, limit: limit)
        rows.map { |row| build_result(row) }
      end

      # Batch short-gloss lookup for lemma-search integration (P11-4):
      # +pairs+ is an array of [lemma, language]; returns
      # { [lemma, language] => gloss } for every pair a dictionary of that
      # language glosses. One query per distinct language.
      def glosses(pairs)
        return {} unless shelf?

        pairs.uniq.group_by(&:last).each_with_object({}) do |(language, group), out|
          folded = group.to_h { |lemma, _| [Nabu::Normalize.search_form(lemma, language: language), lemma] }
          gloss_rows(folded.keys, language).each do |row|
            lemma = folded[row.fetch(:headword_folded)]
            out[[lemma, language]] ||= row.fetch(:gloss)
          end
        end
      end

      private

      def shelf?
        @catalog.table_exists?(:dictionary_entries)
      end

      def entry_rows(variants, lang:, limit:)
        dataset = @catalog[:dictionary_entries]
                  .join(:dictionaries, id: Sequel[:dictionary_entries][:dictionary_id])
                  .join(:sources, id: Sequel[:dictionaries][:source_id])
                  .where(Sequel[:dictionary_entries][:headword_folded] => variants,
                         Sequel[:dictionary_entries][:withdrawn] => false)
        dataset = dataset.where(Sequel[:dictionaries][:language] => lang) if lang
        dataset.order(Sequel[:dictionaries][:slug], Sequel[:dictionary_entries][:entry_id])
               .limit(limit)
               .select(
                 Sequel[:dictionary_entries][:id].as(:entry_row_id),
                 Sequel[:dictionary_entries][:urn], Sequel[:dictionary_entries][:entry_id],
                 Sequel[:dictionary_entries][:key_raw], Sequel[:dictionary_entries][:headword],
                 Sequel[:dictionary_entries][:gloss], Sequel[:dictionary_entries][:body],
                 Sequel[:dictionaries][:slug].as(:dictionary_slug),
                 Sequel[:dictionaries][:title].as(:dictionary_title),
                 Sequel[:dictionaries][:language],
                 Sequel[:sources][:license], Sequel[:sources][:license_class],
                 Sequel[:sources][:slug].as(:source_slug)
               ).all
      end

      def gloss_rows(folded_keys, language)
        @catalog[:dictionary_entries]
          .join(:dictionaries, id: Sequel[:dictionary_entries][:dictionary_id])
          .where(Sequel[:dictionary_entries][:headword_folded] => folded_keys,
                 Sequel[:dictionary_entries][:withdrawn] => false,
                 Sequel[:dictionaries][:language] => language)
          .exclude(Sequel[:dictionary_entries][:gloss] => nil)
          .order(Sequel[:dictionaries][:slug], Sequel[:dictionary_entries][:entry_id])
          .select(Sequel[:dictionary_entries][:headword_folded], Sequel[:dictionary_entries][:gloss])
          .all
      end

      def build_result(row)
        Result.new(
          urn: row.fetch(:urn), dictionary_slug: row.fetch(:dictionary_slug),
          dictionary_title: row.fetch(:dictionary_title), language: row.fetch(:language),
          headword: row.fetch(:headword), key_raw: row.fetch(:key_raw),
          gloss: row.fetch(:gloss), body: row.fetch(:body),
          license: row.fetch(:license), license_class: row.fetch(:license_class),
          source_slug: row.fetch(:source_slug),
          citations: resolve_citations(row.fetch(:entry_row_id))
        )
      end

      # -- resolution --------------------------------------------------------------

      def resolve_citations(entry_row_id)
        rows = @catalog[:dictionary_citations]
               .where(dictionary_entry_id: entry_row_id)
               .order(:seq)
               .select(:urn_raw, :cts_work, :citation, :label)
               .all
        editions = {}
        rows.map do |row|
          CitationView.new(label: row.fetch(:label), urn_raw: row.fetch(:urn_raw),
                           resolved_urn: resolve(row, editions))
        end
      end

      def resolve(row, editions)
        work = row.fetch(:cts_work)
        citation = row.fetch(:citation)
        return nil if work.nil? || citation.nil?

        edition_urns = (editions[work] ||= editions_of(work))
        return nil if edition_urns.empty?

        candidates = citation_forms(citation).flat_map do |form|
          edition_urns.map { |urn| "#{urn}:#{form}" }
        end
        existing = @catalog[:passages]
                   .where(urn: candidates, withdrawn: false)
                   .select_map(:urn).to_set
        candidates.find { |urn| existing.include?(urn) }
      end

      # The citation as cited, then — for 3+-part citations — the classical
      # chapter/section double-citation fallback: "Cic. Off. 1, 2, 4" is
      # book 1, chapter 2, CONTINUOUS section 4, and Perseus editions cite
      # book.section, so 1.2.4 falls back to 1.4 (first, last). Tried only
      # when the full form matches nothing, so a genuinely 3-level edition
      # always wins with the exact citation.
      def citation_forms(citation)
        parts = citation.split(".")
        return [citation] if parts.length < 3

        [citation, "#{parts.first}.#{parts.last}"]
      end

      # Live editions of +work+, original language first (translations are a
      # last resort — a lexicon cites the source text), then urn order for
      # determinism.
      def editions_of(work)
        @catalog[:documents]
          .where(Sequel.like(:urn, "#{work.gsub(/[%_]/) { |ch| "\\#{ch}" }}.%"))
          .where(withdrawn: false)
          .select_map(%i[urn language])
          .sort_by { |urn, language| [language == "eng" ? 1 : 0, urn] }
          .map(&:first)
      end
    end
  end
end
