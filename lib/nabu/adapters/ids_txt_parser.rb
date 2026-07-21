# frozen_string_literal: true

module Nabu
  module Adapters
    # Parser family "ids-txt" (P37-4): Andrew West's BabelStone IDS.TXT —
    # Ideographic Description Sequences, one line per CJK ideograph:
    #
    #   U+68C4<TAB>棄<TAB>^⿳亠厶⿻廿木$(GHTP)<TAB>^⿳亠厶⿱丗木$(JK)
    #
    # UTF-8 with a BOM and CR/LF, a `#`-comment header (metadata + the
    # public-domain dedication). One `DictionaryEntry` per codepoint keyed
    # "U+XXXX" (so it joins Unihan/KANJIDIC2 by codepoint verbatim); `body`
    # carries each source-tagged IDS sequence VERBATIM, one per line
    # (canonical means canonical — the `^…$(SOURCES)` form is kept whole so
    # the regional source forms and the operator run both survive).
    #
    # The Ideographic Description Characters (the U+2FF0..U+2FFF operators)
    # give the sequence its tree shape; every non-operator ideograph, CJK
    # stroke or radical in it is a DIRECT component. `.components` peels one
    # sequence field to that component list — the seam
    # `search --char-component` walks TRANSITIVELY (component-of-a-component)
    # across the whole 97,680-entry repertoire, the span KRADFILE's ~12k JIS
    # kanji cannot reach.
    class IdsTxtParser
      # Ideographic Description Characters: U+2FF0..U+2FFB (Unicode ≤15.1) and
      # U+2FFC..U+2FFF (added 16.0) — structural operators, never components.
      IDC_RANGE = 0x2FF0..0x2FFF
      # Fullwidth question mark: the file's marker for a component with no
      # Unicode representative (header §5) — structural, not a real component.
      UNREPRESENTABLE = "？"

      # One DictionaryEntry per data line, file order (numeric codepoint —
      # the file already sorts URO before the extensions).
      def entries(path, language: "zho")
        rows(path).map { |code, char, ids_fields| entry(code, char, ids_fields, language) }
      end

      # The direct components of ONE `^…$(SOURCES)` sequence field: the chars
      # between the ^ and $ anchors, minus the trailing region tag, the IDC
      # operators and the unrepresentable marker. Class method so the query
      # layer can rebuild the containment graph from stored `body`.
      def self.components(ids_field)
        sequence(ids_field).each_char.reject do |char|
          IDC_RANGE.cover?(char.ord) || char == UNREPRESENTABLE
        end
      end

      # The bare description sequence of one field (strip the ^..$ anchors and
      # the trailing "(GHTJKPV)"-style source tag). A field without anchors (a
      # trimmed shape) degrades to the whole field minus any source tag.
      def self.sequence(ids_field)
        ids_field[/\A\^(.*?)\$/m, 1] || ids_field.sub(/\([^)]*\)\z/, "")
      end

      private

      def rows(path)
        # "bom|utf-8" strips the leading BOM; chomp handles the CR/LF endings.
        File.foreach(path, encoding: "bom|utf-8").filter_map do |line|
          line = line.chomp
          next if line.empty? || line.start_with?("#")

          code, char, *ids_fields = line.split("\t")
          next if code.nil? || char.nil? || ids_fields.empty?

          [validate_code(code), char, ids_fields]
        end
      end

      def validate_code(code)
        return code if code.match?(/\AU\+\h{4,6}\z/)

        raise Nabu::ParseError, "ids-txt: malformed codepoint key #{code.inspect}"
      end

      def entry(code, char, ids_fields, language)
        character = Normalize.nfc(char)
        Nabu::DictionaryEntry.new(
          entry_id: code, key_raw: code, language: language,
          headword: character,
          headword_folded: Normalize.search_form(character, language: language),
          gloss: nil,
          body: Normalize.nfc(ids_fields.join("\n"))
        )
      end
    end
  end
end
