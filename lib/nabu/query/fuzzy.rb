# frozen_string_literal: true

require_relative "../normalize"
require_relative "catalog_join"

module Nabu
  module Query
    # Fragment search (P16-4, intertext design §4): infix/mid-word substring
    # matching over the trigram index — the papyrologist's `]μηνιν αει[` on a
    # damaged scrap, where FTS5's word/prefix tokens cannot reach into the
    # middle of a word. Documentary scope only (the Indexer's trigram pass;
    # config/sources.yml `fuzzy_index: true`).
    #
    # == The two-phase shape: trigram candidates, then verify
    #
    # Phase 1 asks the trigram table for passages containing ALL of the
    # query's trigrams (implicit-AND MATCH), bm25-ordered. That is a
    # CANDIDATE set, not an answer: trigram co-occurrence does not imply
    # contiguity ("abc … bcd" satisfies the trigrams of "abcd" without
    # containing it), and the trigram tokenizer applies its own case folding
    # on top of ours, which can only widen the net. Phase 2 verifies each
    # candidate by plain substring inclusion of a folded query variant in the
    # passage's stored folded text — the ground truth of our own folding
    # contract. The standard pg_trgm shape; verification is load-bearing,
    # not belt-and-braces.
    #
    # == Query folding — same union-of-folds contract as Search
    #
    # The query folds through Normalize.query_forms (generic + per-language
    # variants, conventions §9), because a fragment carries no language: a
    # passage in language L stores extra_L(generic(text)), and the variant
    # set always contains extra_L(generic(query)). A candidate verifies if
    # ANY variant is a substring. Before folding, editorial square brackets
    # are stripped from the query — the papyrological use case types the
    # lacuna edges (`]μηνιν αει[`) straight off the edition, and brackets in
    # the QUERY mark damage, not searchable characters. (Braces are NOT
    # stripped: {d} is a cuneiform determinative the akk/sux fold handles.)
    #
    # == The trigram floor
    #
    # A trigram index cannot see fragments shorter than 3 characters; a
    # sub-3-char query raises QueryTooShort so the surface can say WHY there
    # are no results instead of silently returning none.
    class Fuzzy
      include CatalogJoin

      # A fragment whose folded form is under 3 characters cannot be looked
      # up in a trigram index. Carries the folded remainder so the message
      # can show what the query became.
      class QueryTooShort < Nabu::Error
        attr_reader :folded

        def initialize(folded)
          @folded = folded
          super("fuzzy fragment too short: #{folded.inspect} is under 3 characters after folding (trigram floor)")
        end
      end

      # One fuzzy hit. `snippet` is a window of the FOLDED text with the
      # matched fragment in [brackets] (the search form, like Search's FTS
      # snippets); `folded_marked` is the same without the window — the whole
      # folded passage, match bracketed — for --long. `text` is the pristine
      # passage for anyone rendering the edition instead.
      Result = Data.define(:urn, :language, :text, :snippet, :folded_marked, :document_title, :license_class)

      MIN_QUERY_CHARS = 3
      # Editorial marks stripped from the QUERY before folding (class note):
      # square brackets (lacuna edges as typed off a papyrus edition) and the
      # underdot-carrying combining mark falls to the generic fold already.
      EDITORIAL_MARKS = /[\[\]]/
      # Folded-snippet context window, chars per side (DDbDP passages average
      # 34 chars — most render whole).
      SNIPPET_CONTEXT = 40

      # Same candidate over-fetch as Search: catalog-side filters (language/
      # license/date) and the verify phase both drop rows; fetch enough
      # candidates to still fill the page.
      INNER_LIMIT_FACTOR = 10

      def initialize(catalog:, fulltext:)
        @catalog = catalog
        @fulltext = fulltext
      end

      # The slugs the CURRENT trigram index was built over (the Indexer's
      # scope table) — what the CLI reports as honest coverage. Empty array
      # for an empty scope; nil when the fulltext db predates the trigram
      # index entirely (the caller should hint at a reindex).
      def scope
        return nil unless @fulltext.table_exists?(Store::Indexer::TRIGRAM_SCOPE_TABLE)

        @fulltext[Store::Indexer::TRIGRAM_SCOPE_TABLE].select_order_map(:slug)
      end

      # Substring-search +fragment+ and return up to +limit+ Results in bm25
      # candidate order. Filters compose exactly as Search: +lang+ on passage
      # language, +license+ on effective class, +from+/+to+/+place+ on the
      # document date/place axis, +facets+ (P17-2) on the document facet rows
      # — a fragmentary formula scoped `--type epitaph` is the designed use —
      # plus +source+ (P22-1) on the source slug and +loans+ (P34-2) on the
      # passage's stored loan-code counts. Raises QueryTooShort below the
      # trigram floor.
      def run(fragment, lang: nil, license: nil, limit: 20, from: nil, to: nil, place: nil, facets: nil,
              source: nil, loans: nil)
        @incomplete_hint = nil
        variants = query_variants(fragment)
        inner_limit = limit * INNER_LIMIT_FACTOR
        hits = candidates(variants, inner_limit: inner_limit)
        verified = hits.filter_map do |row|
          match = locate(row.fetch(:text_normalized), variants)
          [row.fetch(:passage_id), row.fetch(:text_normalized), match] if match
        end

        rows = catalog_rows(verified.map(&:first), lang: lang, license: license,
                                                   from: from, to: to, place: place, facets: facets,
                                                   source: source, loans: loans)
               .to_h { |row| [row.fetch(:passage_id), row] }
        page = verified.filter_map { |id, folded, match| [rows[id], folded, match] if rows[id] }
                       .first(limit)
        note_page_completeness(
          window_exhausted: hits.size >= inner_limit,
          filters_active: [lang, license, from, to, place, source, loans].compact.any? || (facets || {}).any?,
          page_size: page.size, limit: limit
        )
        page.map { |row, folded, match| build_result(row, folded, match) }
      end

      private

      # Fold the fragment into its variant set (class note): strip editorial
      # brackets, then the same generic + per-language union Search matches.
      # Variants that fall under the trigram floor are dropped; if the GENERIC
      # form is under it, the query is honestly too short (per-language rules
      # never lengthen a query except ang's æ/þ/ð expansions, which only help).
      def query_variants(fragment)
        stripped = fragment.to_s.gsub(EDITORIAL_MARKS, "")
        variants = Nabu::Normalize.query_forms(stripped).map(&:strip)
        raise QueryTooShort, variants.first if variants.first.length < MIN_QUERY_CHARS

        variants.uniq.select { |variant| variant.length >= MIN_QUERY_CHARS }
      end

      # Phase 1 (class note): passages containing all trigrams of any variant.
      # The MATCH expression is built from the variants' own characters, each
      # trigram a quoted FTS5 string (internal quotes doubled), trigrams
      # implicit-ANDed within a variant, variants ORed. User text reaches SQL
      # only as the bound MATCH parameter (the standing raw-SQL exception).
      def candidates(variants, inner_limit:)
        @fulltext[Store::Indexer::TRIGRAM_TABLE]
          .where(Sequel.lit("passages_trigram MATCH ?", match_expression(variants)))
          .select(:passage_id, :text_normalized)
          .order(Sequel.lit("bm25(passages_trigram)"))
          .limit(inner_limit)
          .all
      end

      def match_expression(variants)
        groups = variants.map do |variant|
          trigrams(variant).map { |tri| %("#{tri.gsub('"', '""')}") }.join(" ")
        end
        return groups.first if groups.one?

        groups.map { |group| "(#{group})" }.join(" OR ")
      end

      # Every distinct character trigram of +variant+, spaces included — the
      # trigram tokenizer indexes them too, so a multi-word fragment stays one
      # contiguous constraint.
      def trigrams(variant)
        variant.each_char.each_cons(3).map(&:join).uniq
      end

      # Phase 2 (class note): the first variant actually contained in the
      # folded text, with its position — [start, length] — or nil for a
      # trigram-collision false candidate.
      def locate(folded, variants)
        variants.each do |variant|
          index = folded.index(variant)
          return [index, variant.length] if index
        end
        nil
      end

      def build_result(row, folded, (start, length))
        marked = "#{folded[0...start]}[#{folded[start, length]}]#{folded[(start + length)..]}"
        Result.new(
          urn: row.fetch(:urn), language: row.fetch(:language), text: row.fetch(:text),
          snippet: snippet(folded, start, length), folded_marked: marked,
          document_title: row.fetch(:document_title), license_class: row.fetch(:license_class)
        )
      end

      # Windowed folded snippet: match bracketed, up to SNIPPET_CONTEXT chars
      # of context per side, truncation marked with … (the --long form is
      # Result#folded_marked, untruncated).
      def snippet(folded, start, length)
        left = [start - SNIPPET_CONTEXT, 0].max
        right = [start + length + SNIPPET_CONTEXT, folded.length].min
        "#{'…' if left.positive?}#{folded[left...start]}[#{folded[start, length]}]" \
          "#{folded[(start + length)...right]}#{'…' if right < folded.length}"
      end
    end
  end
end
