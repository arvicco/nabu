# frozen_string_literal: true

require "json"
require_relative "../normalize"
require_relative "../display"
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
    # Left context is rendered to EXACTLY +width+ display CELLS (padded or
    # ellipsis-truncated), so the keyword's left edge sits in the same column
    # on every row. Padding and clipping go through Nabu::Display.width (P35-7),
    # which counts East-Asian wide (Han/kana/hangul/fullwidth) clusters as two
    # cells — a lzh KWIC line aligns exactly where a grc one does. For narrow
    # (grc/lat/chu) text width == String#length, so their output is unchanged.
    class Concord
      # One KWIC row. +left+ and +right+ are already trimmed to the requested
      # width (left right-justified, right left-justified, ellipsis where
      # clipped); +keyword+ is the pristine matched span. license_class and
      # language ride along for the MCP contract and the CLI tag. +tier+
      # (P26-4, the P26-0 journaled decision — concord is a FORMATTER over
      # LemmaSearch, so it inherits the label): the lemma-mode hit's lemma
      # tier ("gold" | "silver"), passed through so renderers tag silver
      # rows exactly as search --lemma does; nil in text mode (an FTS hit
      # makes no annotation claim).
      Row = Data.define(:urn, :language, :license_class, :left, :keyword, :right, :tier) do
        def initialize(tier: nil, **rest) = super
      end

      DEFAULT_WIDTH = 40
      ELLIPSIS = "…"
      # Keyword-completion stops at whitespace OR punctuation: letters, combining
      # marks (accents stay attached), and digits are word characters.
      WORD_CHAR = /[[:alpha:]\p{M}[:digit:]]/

      def initialize(catalog:, fulltext:)
        @catalog = catalog
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
        span = locate_hyphen_joined(display, terms, result) if span == [0, 0]
        left, keyword, right = split_on_span(display, span)
        Row.new(
          urn: result.urn, language: result.language, license_class: result.license_class,
          left: trim_left(left, width), keyword: keyword, right: trim_right(right, width),
          tier: (result.tier if result.respond_to?(:tier))
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
        span_from(folded, map, terms, language, display)
      end

      # The diplomatic line-break retry (P14-5, conventions §9): a ccmh-txt
      # hyphen line indexes the COMPLETED split word, so a term matched there
      # is absent from the folded pristine display. Rebuild the haystack the
      # way the index saw it — trailing hyphen dropped, the annotation's tail
      # appended with every tail character mapped to the hyphen/EOL display
      # position — and scan again. The keyword the span yields is exactly the
      # visible fragment + hyphen ("mOdrova-"): honest highlighting, no
      # fabricated display text. Passages without a hyphen_join tail (or a
      # display not ending in "-") keep the [0, 0] fallback.
      def locate_hyphen_joined(display, terms, result)
        return [0, 0] unless display.end_with?("-")

        tail = hyphen_tail(result.urn)
        return [0, 0] unless tail

        folded, map = Nabu::Normalize.fold_with_map(display, language: result.language)
        return [0, 0] unless folded.end_with?("-")

        folded = folded.delete_suffix("-")
        map = map[0, folded.length]
        eol = display.chars.length - 1
        Nabu::Normalize.search_form(tail, language: result.language).each_char do |char|
          folded += char
          map << eol
        end
        span_from(folded, map, terms, result.language, display)
      end

      # The hit's "hyphen_join" tail from the catalog row (the annotation the
      # ccmh-txt parser records; nil for everything else). One lookup per
      # retried row only — a formatter-grade cost.
      def hyphen_tail(urn)
        json = @catalog[:passages].where(urn: urn).get(:annotations_json)
        return nil unless json

        JSON.parse(json).dig("hyphen_join", "tail")
      rescue JSON::ParserError
        nil
      end

      def span_from(folded, map, terms, language, display)
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

      # Left context, right-justified to exactly +width+ display cells: pad
      # short lines on the left; clip long ones to the last (width-1) cells
      # behind a leading ellipsis (the near context is what matters for reading
      # the keyword). Cells, not chars, so wide (Han/kana) context clips and
      # pads to the same column a narrow line does.
      def trim_left(str, width)
        return Nabu::Display.rjust(str, width) if Nabu::Display.width(str) <= width

        ELLIPSIS + take_last_cells(str, width - 1)
      end

      # Right context, left-justified to exactly +width+ display cells: pad
      # short lines on the right; clip long ones to the first (width-1) cells
      # before a trailing ellipsis. Equal-width left AND right also aligns the
      # urn tag.
      def trim_right(str, width)
        return Nabu::Display.ljust(str, width) if Nabu::Display.width(str) <= width

        take_first_cells(str, width - 1) + ELLIPSIS
      end

      # The longest suffix / prefix of whole grapheme clusters whose display
      # width fits within +budget+ cells — never splitting a wide cluster, so
      # the clip lands on a cell boundary (a trailing gap of at most one cell
      # is closed by the caller's re-pad).
      def take_last_cells(str, budget)
        kept = []
        used = 0
        str.grapheme_clusters.reverse_each do |cluster|
          cell = Nabu::Display.width(cluster)
          break if used + cell > budget

          kept.unshift(cluster)
          used += cell
        end
        kept.join
      end

      def take_first_cells(str, budget)
        kept = []
        used = 0
        str.grapheme_clusters.each do |cluster|
          cell = Nabu::Display.width(cluster)
          break if used + cell > budget

          kept << cluster
          used += cell
        end
        kept.join
      end
    end
  end
end
