# frozen_string_literal: true

require_relative "../normalize"
require_relative "search"
require_relative "lemma_search"

module Nabu
  module Query
    # KWIC concordance (P8-3): a FORMATTER over Search and LemmaSearch, not a
    # new query path. One row per hit — left context, the matched keyword, and
    # right context — with the keyword located in the PRISTINE passage text so
    # the concordance reads like the edition, accents and all.
    #
    # == Locating the keyword (the honest hard part)
    #
    # An FTS hit carries the folded snippet (accents stripped); a lemma hit
    # carries surface forms. For KWIC we want the keyword's position in the
    # DISPLAY string. We fold the pristine passage text with the SAME
    # per-language rule the index used (Normalize.fold_with_map), find the
    # folded query/surface term in that folded string, and map the match index
    # back to the pristine text through the char-index map. The P6-4 folds are
    # not length-preserving (mark-stripping changes lengths), so the map — not
    # a naive index — is what makes ῆ line up under η. This is option (a) from
    # the packet: pristine display, a small reusable map helper, over option
    # (b) (show the folded line), because a concordance is for reading real
    # usage. Folding the query with the hit's own language means the term
    # always appears in the folded text exactly where it matched.
    #
    # == Occurrence policy
    #
    # FIRST occurrence per passage — one row per hit. Classic concordances emit
    # one row per occurrence; first-only keeps the row count equal to the hit
    # count, so the limit and the MCP bounded contract stay simple and honest.
    # A passage with the keyword twice shows its earliest hit; documented.
    #
    # == Order
    #
    # Corpus order, not rank order: a concordance is for scanning usage. The
    # underlying query selects the page (Search by rank, LemmaSearch by urn);
    # concord then re-sorts that page by urn — grouping a document's lines and
    # reading them in citation order. (urn-lexical, the only order a formatter
    # over the Result values can reach without a new query path.)
    #
    # == Alignment
    #
    # Left context is rendered to EXACTLY +width+ display characters (padded or
    # ellipsis-truncated), so the keyword's left edge sits in the same column
    # on every row. Padding is by String#length (character count) — deliberately
    # not East-Asian display width; grc/lat/chru fixed-width terminals are the
    # target, and over-engineering CJK width is out of scope.
    class Concord
      # One KWIC row. +left+ and +right+ are already trimmed to the requested
      # width (left right-justified, right left-justified, ellipsis where
      # clipped); +keyword+ is the pristine matched span. license_class and
      # language ride along for the MCP contract and the CLI tag.
      Row = Data.define(:urn, :language, :license_class, :left, :keyword, :right)

      DEFAULT_WIDTH = 40
      ELLIPSIS = "…"
      # Keyword-completion stops at whitespace OR punctuation: letters, combining
      # marks (accents stay attached), and digits are word characters.
      WORD_CHAR = /[[:alpha:]\p{M}[:digit:]]/

      def initialize(catalog:, fulltext:)
        @search = Search.new(catalog: catalog, fulltext: fulltext)
        @lemma_search = LemmaSearch.new(catalog: catalog, fulltext: fulltext)
      end

      # Concord +query+ (or +lemma+) and return Rows in corpus (urn) order.
      # +lang+/+license+/+limit+ pass straight through to the underlying query;
      # +width+ is the per-side context budget in display characters.
      def run(query = nil, lemma: nil, lang: nil, license: nil, limit: 20, width: DEFAULT_WIDTH)
        results, terms_for = search_results(query, lemma, lang: lang, license: license, limit: limit)
        results.map { |result| build_row(result, terms_for.call(result), width) }
               .sort_by(&:urn)
      end

      private

      # [results, term_extractor]. term_extractor.(result) yields the pristine
      # strings to locate in that hit: the query's words (text mode, shared
      # across hits) or the hit's own matched surface forms (lemma mode).
      def search_results(query, lemma, lang:, license:, limit:)
        if lemma
          results = @lemma_search.run(lemma, lang: lang, license: license, limit: limit)
          [results, ->(result) { surface_terms(result.surface_forms) }]
        else
          terms = query_terms(query)
          [@search.run(query, lang: lang, license: license, limit: limit), ->(_result) { terms }]
        end
      end

      # Query → locatable terms: drop FTS phrase quotes, split on whitespace,
      # strip a trailing prefix-* from each token. These are folded per-hit.
      def query_terms(query)
        query.to_s.tr('"', " ").split(/\s+/).filter_map do |token|
          stem = token.sub(/\*\z/, "")
          stem.empty? ? nil : stem
        end
      end

      # LemmaSearch's ", "-joined pristine surface forms → the terms to locate.
      def surface_terms(surface_forms)
        surface_forms.to_s.split(", ").reject(&:empty?)
      end

      def build_row(result, terms, width)
        display = flatten(result.text)
        span = locate(display, terms, result.language)
        left, keyword, right = split_on_span(display, span)
        Row.new(
          urn: result.urn, language: result.language, license_class: result.license_class,
          left: trim_left(left, width), keyword: keyword, right: trim_right(right, width)
        )
      end

      # Newlines and runs of whitespace collapse to one space so a KWIC line is
      # single-line; done BEFORE folding so char indices stay aligned with the
      # string we slice (fold_with_map re-nfc's this, idempotently).
      def flatten(text)
        Nabu::Normalize.nfc(text).gsub(/\s+/, " ").strip
      end

      # [start, end) character span in +display+ for the earliest-occurring
      # term, or [0, 0] when none is found (defensive — a real hit always
      # contains at least one folded term; an empty keyword still renders the
      # line, left-anchored).
      def locate(display, terms, language)
        folded, map = Nabu::Normalize.fold_with_map(display, language: language)
        best = nil
        terms.each do |term|
          needle = Nabu::Normalize.search_form(term, language: language)
          next if needle.empty?

          index = folded.index(needle)
          best = [index, needle.length] if index && (best.nil? || index < best.first)
        end
        return [0, 0] if best.nil?

        index, length = best
        start = map[index]
        finish = extend_to_word_end(display, map[index + length - 1] + 1)
        [start, finish]
      end

      # A folded term begins at a word boundary (FTS tokenizes on words) but a
      # prefix* match ends mid-word — extend the keyword rightward over the rest
      # of the word (letters/marks/digits, stopping at space OR punctuation) so
      # the concordance shows μῆνιν, not the μηνι stem, and never a trailing
      # comma or period. Extending only the END keeps the keyword's left edge
      # (the aligned column) fixed.
      def extend_to_word_end(display, finish)
        chars = display.chars
        finish += 1 while finish < chars.length && chars[finish].match?(WORD_CHAR)
        finish
      end

      def split_on_span(display, (start, finish))
        chars = display.chars
        [chars[0...start].join, chars[start...finish].join, chars[finish..].join]
      end

      # Left context, right-justified to exactly +width+ chars: pad short lines
      # on the left; clip long ones to the last width-1 chars behind a leading
      # ellipsis (the near context is what matters for reading the keyword).
      def trim_left(str, width)
        return str.rjust(width) if str.length <= width

        ELLIPSIS + str[(str.length - width + 1)..]
      end

      # Right context, left-justified to exactly +width+ chars: pad short lines
      # on the right; clip long ones to the first width-1 chars before a
      # trailing ellipsis. Equal-width left AND right also aligns the urn tag.
      def trim_right(str, width)
        return str.ljust(width) if str.length <= width

        str[0, width - 1] + ELLIPSIS
      end
    end
  end
end
