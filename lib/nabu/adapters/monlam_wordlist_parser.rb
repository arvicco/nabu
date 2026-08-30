# frozen_string_literal: true

require_relative "../normalize"

module Nabu
  module Adapters
    # Parser for the MonlamIT headword lists (the `monlam-wordlist` family,
    # P88-A3) — one headword per line, NOTHING else: upstream publishes no
    # definitions, POS, or glosses under a license. Two physical shapes,
    # censused 2026-08-29 and declared per lane by the adapter:
    #
    #   monlam-lexicon-1.txt  UTF-16LE + BOM, CRLF, "word" header line
    #   monlam-lexicon-2.txt  UTF-8, LF, headerless
    #
    # == The censused dirt (handled, never fatal)
    #
    # Trailing tabs/spaces strip (70 lines); truly empty lines skip —
    # including the upstream 24,295-line BLANK HOLE in lexicon-2 (one
    # contiguous run: the late-འ…ཡ alphabetical band is absent upstream;
    # .docs/upstream-reports.md). Everything else is a headword VERBATIM
    # (the ~10 stray Tai Tham codepoints are upstream typos we keep —
    # canonical means canonical), NFC at the boundary: bod is not
    # NFC-exempt, so the 520 composition-excluded-vowel lines (U+0F75 →
    # U+0F71+U+0F74 etc.) normalize here, and headword_folded follows the
    # house search fold.
    #
    # == Identity
    #
    # entry_id = "<lane>:<headword>" — the lane prefix keeps the two
    # dictionaries' lists distinct under one shelf slug; an in-file
    # duplicate headword (7 in lex-1, 377 in lex-2, max ×2) takes the
    # occurrence suffix (":2", the tibetan-verbs idiom).
    class MonlamWordlistParser
      BOM = "\u{FEFF}"

      # +source+ is a path (String — opened with +encoding+) or an IO-like
      # (StringIO in tests, already decoded).
      def parse(source, lane:, lane_title:, header:, slug:, language:, title:,
                canonical_path:, encoding: "UTF-8")
        document = Nabu::DictionaryDocument.new(
          slug: slug, language: language, title: title, canonical_path: canonical_path
        )
        occurrences = Hash.new(0)
        each_headword(source, encoding: encoding, header: header) do |headword|
          document << build_entry(headword, lane: lane, lane_title: lane_title,
                                            language: language, occurrences: occurrences)
        end
        raise Nabu::ParseError, "#{canonical_path}: no headwords found" if document.empty?

        document
      end

      private

      def each_headword(source, encoding:, header:)
        first = true
        read_lines(source, encoding) do |raw|
          line = raw.sub(/\r?\n?\z/, "")
          line = line.delete_prefix(BOM) if first
          skip_header = first && header
          first = false
          next if skip_header

          headword = line.sub(/[\s ]+\z/, "")
          next if headword.empty?

          yield headword
        end
      end

      def read_lines(source, encoding, &block)
        if source.is_a?(String)
          File.open(source, "r", encoding: "#{encoding}:UTF-8") { |io| io.each_line(&block) }
        else
          source.each_line(&block)
        end
      end

      def build_entry(headword, lane:, lane_title:, language:, occurrences:)
        base = "#{lane}:#{headword}"
        occurrences[base] += 1
        entry_id = occurrences[base] > 1 ? "#{base}:#{occurrences[base]}" : base
        Nabu::DictionaryEntry.new(
          entry_id: entry_id, key_raw: headword, language: language,
          headword: Normalize.nfc(headword),
          headword_folded: Normalize.search_form(headword, language: language),
          gloss: nil,
          body: "Listed in the #{lane_title} (MonlamIT/Tibetan-Lexicon headword list — " \
                "upstream publishes headwords only; no definition is licensed)",
          citations: []
        )
      end
    end
  end
end
