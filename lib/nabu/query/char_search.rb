# frozen_string_literal: true

require_relative "catalog_join"
require_relative "char_filter"
require_relative "search"

module Nabu
  module Query
    # Character-structure search (P37-4): the passage half of
    # `search --radical N | --strokes A-B | --char-component C`. CharFilter
    # resolves the active options to one glyph set (AND of the options, the
    # containment union inside --char-component); this class then finds the
    # Han-language passages that CARRY at least one of those characters,
    # composing with a text query and the ordinary --lang/--license/--source
    # passage filters. The char filters are NEVER folded into the FTS MATCH
    # (the survey ruling): a structural property is a different question than a
    # word, so it rides as a post-filter over the candidate passages, and the
    # footer names it distinctly.
    #
    # Two candidate sources, both honest about scale:
    #   * with a text query — the FTS hit page (already the right passages by
    #     word), thinned to those that also carry a matching character;
    #   * without one — a bounded scan of the visible Han-language passages
    #     (SCAN_CAP), thinned the same way. A character-posting index is the
    #     production path for the char-only case; v1 scans and says so when the
    #     cap is reached (the CatalogJoin incompleteness posture).
    class CharSearch
      include CatalogJoin

      # One structural hit: the passage + the matching characters (for the
      # footer's "why").
      Result = Data.define(:urn, :language, :text, :document_title, :license_class, :matched)

      # The whole run: hits + the human filter labels + the resolved character
      # count + honesty flags.
      Outcome = Data.define(:results, :labels, :char_count, :incomplete, :resolved_empty)

      # const: the char-only passage-scan bound — a fixture/research-scale UX
      # cap (the char-posting index is the production path), not a corpus count.
      SCAN_CAP = 5000
      # const: FTS hits pulled before the containment thin, so a page can still
      # fill after most are dropped — a fetch-window bound, not a corpus count.
      FTS_FETCH = 500

      def initialize(catalog:, fulltext:)
        @catalog = catalog
        @fulltext = fulltext
      end

      def run(query, radical: nil, strokes: nil, component: nil,
              lang: nil, license: nil, source: nil, limit: 20)
        resolved = CharFilter.new(catalog: @catalog).resolve(radical: radical, strokes: strokes, component: component)
        chars = resolved.chars
        if chars.nil? || chars.empty?
          return Outcome.new(results: [], labels: resolved.labels, char_count: 0,
                             incomplete: false, resolved_empty: true)
        end

        candidates, window_exhausted =
          if query.to_s.strip.empty?
            han_candidates(lang: lang, license: license, source: source)
          else
            fts_candidates(query, lang: lang, license: license, source: source)
          end

        matched = candidates.select { |row| contains_any?(row, chars) }
        page = matched.first(limit).map { |row| build(row, chars) }
        Outcome.new(results: page, labels: resolved.labels, char_count: chars.size,
                    incomplete: window_exhausted && page.size < limit, resolved_empty: false)
      end

      private

      def contains_any?(row, chars)
        row.fetch(:text).each_char.any? { |char| chars.include?(char) }
      end

      def build(row, chars)
        matched = row.fetch(:text).each_char.select { |char| chars.include?(char) }.uniq
        Result.new(urn: row.fetch(:urn), language: row.fetch(:language), text: row.fetch(:text),
                   document_title: row.fetch(:document_title), license_class: row.fetch(:license_class),
                   matched: matched)
      end

      # The visible Han-bearing passages (any language — a non-Han passage
      # simply never carries a Han character, so it self-excludes at the
      # containment test), bounded by SCAN_CAP; the flag says whether more
      # exist beyond the bound.
      def han_candidates(lang:, license:, source:)
        rows = visible_passages(lang: lang, license: license, source: source)
               .select(*catalog_columns)
               .limit(SCAN_CAP + 1)
               .all
        [rows.first(SCAN_CAP), rows.size > SCAN_CAP]
      end

      # FTS hits for the text query (the right passages by word), mapped to the
      # catalog-row shape the containment test reads.
      def fts_candidates(query, lang:, license:, source:)
        results = Search.new(catalog: @catalog, fulltext: @fulltext)
                        .run(query, lang: lang, license: license, source: source, limit: FTS_FETCH)
        rows = results.map do |r|
          { urn: r.urn, language: r.language, text: r.text,
            document_title: r.document_title, license_class: r.license_class }
        end
        [rows, results.size >= FTS_FETCH]
      end
    end
  end
end
