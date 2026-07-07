# frozen_string_literal: true

require_relative "../normalize"
require_relative "catalog_join"

module Nabu
  module Query
    # Lemma search (P7-5): exact-lemma lookup over the gold-treebank lemma
    # index (Store::Indexer::LEMMA_TABLE in fulltext.sqlite3), then the shared
    # catalog join for the pristine text, language, and license filtering.
    # `bin/nabu search --lemma λέγω` finds every inflected attestation —
    # λέγουσι, εἶπας, εἰπεῖν — because the match is on the annotation's
    # dictionary form, not the surface text.
    #
    # == Folding: the same both-sides contract as full-text search
    #
    # The index carries lemma_folded = Normalize.search_form(lemma, language)
    # — a lemma is a dictionary form in its passage's language, so it folds
    # exactly like text (grc final-sigma λόγος → λογοσ, lat v→u/j→i). The
    # query carries NO language, so it matches the Normalize.query_forms
    # UNION, the P6-4 argument verbatim: the variant set always contains
    # extra_L(generic(query)), so a lemma spelled the way the treebank spells
    # it folds, on that variant, exactly the way the index folded it; and the
    # variants are a plain IN-list, so the generic variant still matches
    # languages with no extra rule.
    #
    # == Ranking
    #
    # There is none: an exact-lemma hit has no bm25-style relevance. Hits come
    # back in urn order — deterministic, and it groups a document's passages
    # together.
    class LemmaSearch
      include CatalogJoin

      # One hit. `lemma` is the index's raw upstream spelling (the dictionary
      # form as the treebank wrote it); `surface_forms` the distinct pristine
      # inflected forms attesting it in this passage (", "-joined); `text` the
      # pristine passage text for display.
      Result = Data.define(:urn, :language, :lemma, :surface_forms, :text,
                           :document_title, :license_class)

      # Pull more index hits than the caller's limit so that catalog-side
      # filtering (language/license/withdrawn) can drop rows and still fill
      # the page (same factor as Search).
      INNER_LIMIT_FACTOR = 10

      def initialize(catalog:, fulltext:)
        @catalog = catalog
        @fulltext = fulltext
      end

      # Search +lemma+ and return up to +limit+ Result values in urn order.
      # +lang+ / +license+ filter catalog-side exactly as in Search. +urn+
      # restricts the match to one passage — the ranking-independent golden
      # replay probe (health), not a pagination knob.
      def run(lemma, lang: nil, license: nil, limit: 20, urn: nil)
        variants = Nabu::Normalize.query_forms(lemma.to_s)
        return [] if variants.first.strip.empty? # generic form first; extras never add characters

        hits = lemma_hits(variants, inner_limit: limit * INNER_LIMIT_FACTOR, urn: urn)
        return [] if hits.empty?

        ordered_ids = hits.map { |row| row.fetch(:passage_id) }
        rows = catalog_rows(ordered_ids, lang: lang, license: license)
               .to_h { |row| [row.fetch(:passage_id), row] }
        by_id = hits.to_h { |row| [row.fetch(:passage_id), row] }

        ordered_ids.filter_map { |id| rows[id] }
                   .first(limit)
                   .map { |row| build_result(row, by_id.fetch(row.fetch(:passage_id))) }
      end

      private

      # Exact folded-lemma lookup: a plain indexed equality/IN dataset — no
      # FTS, no raw SQL. Distinct on passage_id: a passage row per folded
      # lemma means one passage could match twice only if two distinct folded
      # lemmas both sit in the variant set (contrived, but dedup is one line).
      def lemma_hits(variants, inner_limit:, urn: nil)
        dataset = @fulltext[Store::Indexer::LEMMA_TABLE].where(lemma_folded: variants)
        dataset = dataset.where(urn: urn) if urn
        dataset.order(:urn)
               .limit(inner_limit)
               .select(:passage_id, :lemma_raw, :surface_forms)
               .all
               .uniq { |row| row.fetch(:passage_id) }
      end

      def build_result(row, hit)
        Result.new(
          urn: row.fetch(:urn),
          language: row.fetch(:language),
          lemma: hit.fetch(:lemma_raw),
          surface_forms: hit.fetch(:surface_forms),
          text: row.fetch(:text),
          document_title: row.fetch(:document_title),
          license_class: row.fetch(:license_class)
        )
      end
    end
  end
end
