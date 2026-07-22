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

      module_function

      # A windowed snippet of the STORED +text+ with the earliest matched term
      # in [brackets]. +terms+ are the pristine query tokens to locate; +exact+
      # switches to literal (NFC) location for the glyph-exact mode.
      def build(text:, language:, terms:, exact: false)
        display = Nabu::Normalize.nfc(text.to_s).gsub(/\s+/, " ").strip
        span = exact ? locate_literal(display, terms) : locate_folded(display, terms, language)
        span ? window(display, span) : leading(display)
      end

      # [start, finish) char span of the earliest folded term in +display+,
      # mapped back through fold_with_map; nil when no term folds into the text.
      def locate_folded(display, terms, language)
        folded, map = Nabu::Normalize.fold_with_map(display, language: language)
        best = nil
        terms.each do |term|
          needle = Nabu::Normalize.search_form(term, language: language)
          next if needle.empty?

          index = folded.index(needle)
          best = [index, needle.length] if index && (best.nil? || index < best.first)
        end
        return nil unless best

        index, length = best
        [map[index], extend_over_marks(display, map[index + length - 1] + 1)]
      end

      # [start, finish) char span of the earliest literal (NFC) query token in
      # +display+; nil when none is present (the --exact post-filter guarantees
      # one for a real hit — the nil branch is defensive only).
      def locate_literal(display, terms)
        best = nil
        terms.each do |term|
          needle = Nabu::Normalize.nfc(term.to_s)
          next if needle.empty?

          index = display.index(needle)
          best = [index, needle.length] if index && (best.nil? || index < best.first)
        end
        best && [best.first, best.first + best.last]
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
