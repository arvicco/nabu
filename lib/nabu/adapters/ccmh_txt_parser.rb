# frozen_string_literal: true

module Nabu
  module Adapters
    # Parser for the CCMH txt-only texts (P14-5) — the ccmh-txt family:
    # Codex Suprasliensis + Vita Constantini + Vita Methodii, the three
    # corpus texts upstream ships without XML. Plain line-coded prose, every
    # line "<7-digit code> <7-bit-ASCII transliteration>"; the code is the
    # only structure, and each text's own description page documents it:
    #
    #   folio-line (suprasliensis): part(1) folium(3) side(1) line(2) —
    #     side 1=recto 2=verso; Severjanov's edition addressing. One passage
    #     per PHYSICAL LINE (owner-approved grain 2026-07-12), citation
    #     <part>.<folium>.<side>.<line>, zero-padding stripped. The side
    #     digit is kept RAW: upstream carries four side-3 slips (3014301…)
    #     and "not properly checked" means we carry, never validate.
    #   chapter-verse (the Vitae): chapter(2) verse-in-the-edition(3)
    #     line-in-this-file-ONLY(1) always-zero(1) — upstream's own words,
    #     so only chapter.verse is citable. Consecutive lines of one
    #     (chapter, verse) aggregate into one passage joined by a space
    #     (safe: the Vitae wrap at word boundaries, zero EOL hyphens);
    #     an adjacent duplicate code (VC 0600200, VM 1700100) is the same
    #     verse run and absorbs silently, a NON-adjacent recurrence
    #     (VC 1101010) is a separate run and takes the :b2 collision
    #     suffix (document order, the GRETIL/ccmh-ces precedent).
    #
    # == Diplomatic line-break rejoining (conventions.md §9; owner
    #    requirement 2026-07-12)
    #
    # 51% of Suprasliensis lines end mid-word with a hyphen. The pristine
    # passage text keeps the diplomatic line VERBATIM (hyphen included);
    # what changes is the derived search form: a line ending in "-" has its
    # split word COMPLETED (hyphen dropped, the next line's first token
    # appended), and a continuation line DROPS its orphan leading fragment
    # (index noise — it must not produce junk hits). The derivation is
    # carried per passage in the "hyphen_join" annotation ({"tail" => …} on
    # the hyphen line, {"orphan" => …} on the continuation; a line can hold
    # both) so it is RECOMPUTABLE from the stored row alone — .search_source
    # is the pure function, pinned by the adapter conformance suite — and so
    # tools can read it (Query::Concord uses the tail for honest KWIC
    # highlighting; `nabu show` displays it). text_normalized is still
    # minted through the ONE folding boundary: Normalize.search_form over
    # the derivation source. Joins follow file order across folio, side and
    # even code-collision seams (the word physically continues); a
    # document-final hyphen line has no tail and keeps its fragment; an
    # unmarked split (upstream sometimes wraps without a hyphen, e.g.
    # "(ot&ved / ^jO") is NOT detectable and is left alone, honestly.
    class CcmhTxtParser
      LINE_PATTERN = /\A(?<code>\d{7}) (?<text>.*\S)\s*\z/
      FOLIO_CODE = /\A(?<part>\d)(?<folium>\d{3})(?<side>\d)(?<line>\d{2})\z/
      VERSE_CODE = /\A(?<chapter>\d{2})(?<verse>\d{3})\d\d\z/

      # The rejoined search source: +text+ with the derivation the
      # "hyphen_join" annotation records applied — orphan fragment dropped,
      # trailing hyphen replaced by the completing tail. Pure and
      # deterministic, so text_normalized is always recomputable from the
      # stored passage (the conformance pin). Falls back to the raw line if
      # the derivation would empty it (an all-orphan line must stay
      # searchable and text_normalized must not be empty).
      def self.search_source(text, annotations)
        join = annotations["hyphen_join"] or return text
        source = text
        source = source.delete_prefix(join["orphan"]).lstrip if join["orphan"]
        source = "#{source.delete_suffix('-')}#{join['tail']}" if join["tail"]
        source.strip.empty? ? text : source
      end

      # Parse one txt file into a Nabu::Document. +scheme+ picks the
      # citation grain: "folio-line" (suprasliensis) or "chapter-verse"
      # (the Vitae). Raises Nabu::ParseError on malformed lines or an empty
      # document; ArgumentError on an unknown scheme (a wiring bug, not
      # upstream damage).
      def parse(path, scheme:, urn:, language:, title:)
        builder = passage_builder(scheme)
        document = Nabu::Document.new(urn: urn, language: language, title: title,
                                      canonical_path: File.expand_path(path))
        builder.call(read_lines(path), document, urn, language)
        raise ParseError, "#{path}: no passages parsed" if document.empty?

        document
      rescue Nabu::ValidationError => e
        raise ParseError, "#{path}: #{e.message}"
      end

      private

      def passage_builder(scheme)
        case scheme
        when "folio-line" then method(:build_folio_lines)
        when "chapter-verse" then method(:build_verses)
        else raise ArgumentError, "unknown ccmh-txt scheme #{scheme.inspect}"
        end
      end

      # [[code, text], ...] in file order. Handles both upstream line
      # endings (suprasliensis is LF, the Vitae are CRLF) via the \s* tail
      # of LINE_PATTERN + chomp.
      def read_lines(path)
        File.foreach(path).with_index(1).map do |raw, lineno|
          match = LINE_PATTERN.match(raw.chomp) or
            raise ParseError, "#{path}:#{lineno}: line does not match <7-digit code> <text>: #{raw.strip.inspect}"
          [match[:code], match[:text]]
        end
      end

      # folio-line: one passage per physical line, hyphen_join derivation
      # from the neighbours (previous line's hyphen makes this line's orphan;
      # this line's hyphen takes the next line's first token as tail).
      def build_folio_lines(lines, document, urn, language)
        citations = Hash.new(0)
        lines.each_with_index do |(code, text), index|
          match = FOLIO_CODE.match(code) # 7 digits always match; kept for named groups
          citation = [match[:part], match[:folium], match[:side], match[:line]].map(&:to_i).join(".")
          annotations = hyphen_join(text, before: index.positive? ? lines[index - 1][1] : nil,
                                          after: lines[index + 1]&.last)
          append(document, urn, language, citation, text, citations, annotations: annotations)
        end
      end

      def hyphen_join(text, before:, after:)
        join = {}
        join["orphan"] = first_token(text) if before&.end_with?("-")
        join["tail"] = first_token(after) if text.end_with?("-") && after
        join.empty? ? {} : { "hyphen_join" => join }
      end

      def first_token(text)
        text.split(/\s+/, 2).first
      end

      # chapter-verse: consecutive lines sharing (chapter, verse) are one
      # passage (the file's line digit is "in this file only" — upstream's
      # words — and never cited); runs join by a single space.
      def build_verses(lines, document, urn, language)
        citations = Hash.new(0)
        runs = lines.chunk_while { |(code_a, _), (code_b, _)| verse_key(code_a) == verse_key(code_b) }
        runs.each do |run|
          chapter, verse = verse_key(run.first.first)
          append(document, urn, language, "#{chapter}.#{verse}",
                 run.map(&:last).join(" "), citations)
        end
      end

      def verse_key(code)
        match = VERSE_CODE.match(code)
        [match[:chapter].to_i, match[:verse].to_i]
      end

      def append(document, urn, language, citation, text, citations, annotations: {})
        citations[citation] += 1
        count = citations[citation]
        citation = "#{citation}:b#{count}" unless count == 1
        document << Nabu::Passage.new(
          urn: "#{urn}:#{citation}",
          language: language,
          text: Normalize.nfc(text),
          text_normalized: Normalize.search_form(
            self.class.search_source(text, annotations), language: language
          ),
          annotations: annotations,
          sequence: document.size
        )
      end
    end
  end
end
