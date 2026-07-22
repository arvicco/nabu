# frozen_string_literal: true

require_relative "../normalize"

module Nabu
  module Query
    # Build a search-result snippet from a passage's STORED text (P39-r3).
    #
    # The FTS index folds text into a per-language search skeleton
    # (Normalize.search_form): accents stripped, kana voicing marks gone
    # (だ→た, のである→のてある), CJK variants collapsed onto a traditional or
    # even archaic skeleton (学→學, 一→弌, 明→朙). SQLite's snippet() draws its
    # highlight from that folded column, so it renders glyphs the passage never
    # contained — tolerable-by-luck for lightly-folded Greek/Latin, incoherent
    # for CJK and kana (every jpn hit showed pseudo-text). The snippet is
    # therefore rebuilt HERE from the pristine stored text: text_normalized is
    # never shown to a user.
    #
    # == Locating the match (the fold is not length-preserving)
    #
    # The folded offsets do not carry back to the stored glyphs (mark-stripping
    # and 1→n folds change lengths), so we fold the stored text the SAME way the
    # index did but WITH a char-index map back to the stored glyphs
    # (Normalize.fold_with_map, the KWIC mechanism), find the folded query term
    # in that folded string, and map the span back onto the stored glyphs. The
    # map is exact and O(passage length) — run only per DISPLAYED hit (≤ limit),
    # never over the candidate set.
    #
    # --exact instead locates the query LITERALLY in the NFC stored text: its
    # whole point is the stored glyph, and a fold-located span could bracket a
    # variant that merely folds to the same skeleton (辨 where the user typed
    # 弁). Either way the brackets wrap STORED glyphs; when nothing locates
    # (defensive — a real hit always contains a matched term), a leading stored
    # window renders, never the folded form.
    #
    # == --word (P40-w): whole-word highlighting
    #
    # +word:+ narrows the located span to the earliest occurrence that stands as
    # a WHOLE WORD in the stored text — bounded by start/end of text or a
    # non-word character (a combining mark is word-INTERNAL, never a boundary).
    # Search only ever asks for a word snippet on a passage the word FILTER
    # already verified, so the located span exists; the defensive nil branch
    # still falls back to a leading window, never the folded form.
    #
    # == NFC-exempt display (P40-w, item 3)
    #
    # hbo/arc are stored byte-verbatim, NOT NFC (Masoretic combining-mark order;
    # architecture §3, Normalize.NFC_EXEMPT_LANGUAGES). Their snippet must show
    # those stored bytes, so the display text is NOT NFC-folded for them. The
    # locators still reconcile a divergent mark order by comparing NFC-both: the
    # literal locator searches an NFC copy of the display (Hebrew NFC only
    # REORDERS combining marks — it neither composes nor changes length — so an
    # index found in the NFC copy is a valid index into the stored display), and
    # the folded locator rides fold_with_map, which NFC-folds internally and
    # returns a map onto base-letter positions that survive the reorder.
    module StoredSnippet
      # Stored characters of context per side, mirroring Fuzzy::SNIPPET_CONTEXT
      # (the house windowed-snippet convention). Truncation is marked with … .
      # const: a display window width (a UX choice, not a corpus measurement) —
      # the sibling of the DEFAULT-exempt snippet knobs, pinned to the fuzzy value.
      CONTEXT = 40
      ELLIPSIS = "…"
      # A trailing combining mark that a fold dropped sits just outside the
      # mapped span — extend over \p{M} ONLY (never word characters, which would
      # swallow a whole space-free CJK run into the highlight).
      COMBINING_MARK = /\p{M}/
      # A word constituent for --word boundary detection: a letter OR a combining
      # mark (marks are word-internal — a diacritic never opens or closes a
      # word). Everything else — whitespace, punctuation, symbols — is a boundary.
      WORD_CHAR = /[\p{L}\p{M}]/

      module_function

      # A windowed snippet of the STORED +text+ with the earliest matched term
      # in [brackets]. +terms+ are the pristine query tokens to locate; +exact+
      # switches to literal (NFC) location for the glyph-exact mode; +word+
      # narrows to the earliest whole-word occurrence.
      def build(text:, language:, terms:, exact: false, word: false)
        exempt = Nabu::Normalize.nfc_exempt?(language)
        display = normalized_display(text, exempt: exempt)
        span = if exact
                 locate_literal(display, terms, exempt: exempt, word: word)
               else
                 locate_folded(display, terms, language, word: word)
               end
        span ? window(display, span) : leading(display)
      end

      # Proximity (P40-w, item 2): a window of the STORED text with BOTH matched
      # terms in [brackets], the two-term contract carried onto the stored glyphs
      # (proximity used to ride the folded FTS snippet). +anchor_terms+ and
      # +near_terms+ are the two sides' locator forms (the anchor's query/surface
      # forms, the near term); each is folded and located exactly as a plain
      # snippet locates one. If a side can't be located (edge) the snippet falls
      # back to the located side, then to a leading window — never the folded form.
      def build_proximity(text:, language:, anchor_terms:, near_terms:)
        exempt = Nabu::Normalize.nfc_exempt?(language)
        display = normalized_display(text, exempt: exempt)
        anchor = locate_folded(display, anchor_terms, language)
        near = locate_folded(display, near_terms, language)
        render_pair(display, anchor, near)
      end

      # True when EVERY term has ≥1 whole-word occurrence in the stored text —
      # the --word FILTER predicate (P40-w). Mirrors the located-span logic, so a
      # snippet built with +word:+ on a passage this accepts always finds a span.
      def word_match?(text:, language:, terms:, exact:)
        exempt = Nabu::Normalize.nfc_exempt?(language)
        display = normalized_display(text, exempt: exempt)
        if exact
          haystack = exempt ? Nabu::Normalize.nfc(display) : display
          terms.all? do |term|
            needle = Nabu::Normalize.nfc(term.to_s)
            needle.empty? || earliest_literal_span(display, haystack, needle, word: true)
          end
        else
          folded, map = Nabu::Normalize.fold_with_map(display, language: language)
          terms.all? do |term|
            needle = Nabu::Normalize.search_form(term, language: language)
            needle.empty? || earliest_folded_span(display, folded, map, needle, word: true)
          end
        end
      end

      # The display text: byte-verbatim for the NFC-exempt languages (their
      # snippet must show the stored Masoretic bytes), NFC otherwise; whitespace
      # collapsed either way.
      def normalized_display(text, exempt:)
        base = exempt ? text.to_s : Nabu::Normalize.nfc(text.to_s)
        base.gsub(/\s+/, " ").strip
      end

      # [start, finish) char span of the earliest folded term in +display+,
      # mapped back through fold_with_map; nil when no term folds into the text
      # (or, under +word:+, when no occurrence stands as a whole word).
      def locate_folded(display, terms, language, word: false)
        folded, map = Nabu::Normalize.fold_with_map(display, language: language)
        best = nil
        terms.each do |term|
          needle = Nabu::Normalize.search_form(term, language: language)
          next if needle.empty?

          span = earliest_folded_span(display, folded, map, needle, word: word)
          best = span if span && (best.nil? || span.first < best.first)
        end
        best
      end

      # The earliest [start, finish) STORED span where +needle+ (a folded form)
      # occurs in +folded+, mapped back onto +display+; under +word:+ the
      # earliest such occurrence that stands as a whole word. nil when none.
      def earliest_folded_span(display, folded, map, needle, word:)
        from = 0
        while (index = folded.index(needle, from))
          start = map[index]
          finish = extend_over_marks(display, map[index + needle.length - 1] + 1)
          return [start, finish] if !word || word_bounded?(display, start, finish)

          from = index + 1
        end
        nil
      end

      # [start, finish) char span of the earliest literal (NFC) query token in
      # +display+ (or its whole-word occurrence under +word:+); nil when none is
      # present (the --exact post-filter guarantees one for a real hit — the nil
      # branch is defensive only). +exempt+ (hbo/arc) reconciles a divergent
      # Masoretic mark order by locating in an NFC copy of the display.
      def locate_literal(display, terms, exempt:, word: false)
        haystack = exempt ? Nabu::Normalize.nfc(display) : display
        best = nil
        terms.each do |term|
          needle = Nabu::Normalize.nfc(term.to_s)
          next if needle.empty?

          span = earliest_literal_span(display, haystack, needle, word: word)
          best = span if span && (best.nil? || span.first < best.first)
        end
        best
      end

      # The earliest [start, finish) span where +needle+ occurs literally in
      # +haystack+ (an index into +display+); under +word:+ the earliest whole-
      # word occurrence. haystack may be an NFC copy of a byte-verbatim display,
      # but Hebrew NFC preserves length, so the index is a valid display index.
      def earliest_literal_span(display, haystack, needle, word:)
        from = 0
        while (index = haystack.index(needle, from))
          finish = index + needle.length
          return [index, finish] if !word || word_bounded?(display, index, finish)

          from = index + 1
        end
        nil
      end

      # A [start, finish) span stands as a whole word when neither side abuts a
      # word constituent — start/end of text or a non-word char on each flank.
      def word_bounded?(display, start, finish)
        chars = display.chars
        left_ok = start.zero? || !word_char?(chars[start - 1])
        right_ok = finish >= chars.length || !word_char?(chars[finish])
        left_ok && right_ok
      end

      def word_char?(char)
        char&.match?(WORD_CHAR) || false
      end

      def extend_over_marks(display, finish)
        chars = display.chars
        finish += 1 while finish < chars.length && chars[finish].match?(COMBINING_MARK)
        finish
      end

      def window(display, (start, finish))
        chars = display.chars
        left = [start - CONTEXT, 0].max
        right = [finish + CONTEXT, chars.length].min
        "#{ELLIPSIS if left.positive?}#{chars[left...start].join}" \
          "[#{chars[start...finish].join}]" \
          "#{chars[finish...right].join}#{ELLIPSIS if right < chars.length}"
      end

      # Two brackets, one window: the earlier span opens the window, the later
      # closes it, with the between-context ellipsized when the terms sit far
      # apart. Overlapping spans (defensive) collapse to a single merged bracket.
      def render_pair(display, span_a, span_b)
        spans = [span_a, span_b].compact
        return leading(display) if spans.empty?
        return window(display, spans.first) if spans.one?

        first, second = spans.sort_by(&:first)
        return window(display, [first.first, [first.last, second.last].max]) if second.first < first.last

        window_two(display, first, second)
      end

      def window_two(display, (s1, f1), (s2, f2))
        chars = display.chars
        left = [s1 - CONTEXT, 0].max
        right = [f2 + CONTEXT, chars.length].min
        middle = if s2 - f1 <= 2 * CONTEXT
                   chars[f1...s2].join
                 else
                   "#{chars[f1, CONTEXT].join}#{ELLIPSIS}#{chars[(s2 - CONTEXT)...s2].join}"
                 end
        "#{ELLIPSIS if left.positive?}#{chars[left...s1].join}" \
          "[#{chars[s1...f1].join}]#{middle}[#{chars[s2...f2].join}]" \
          "#{chars[f2...right].join}#{ELLIPSIS if right < chars.length}"
      end

      # No term located: a leading stored window, no highlight (still stored
      # text — the fold form is never a fallback).
      def leading(display)
        chars = display.chars
        return display if chars.length <= 2 * CONTEXT

        "#{chars[0, 2 * CONTEXT].join}#{ELLIPSIS}"
      end
    end
  end
end
