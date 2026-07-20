# frozen_string_literal: true

module Nabu
  module Adapters
    # Parser family "radkfile" (P37-4): the EDRDG KRADFILE — one line per
    # kanji giving its visible components (the decomposition Jisho's
    # multi-radical search runs in reverse):
    #
    #   棄 : 一 木 亠 凵 厶
    #
    # `#`-comment header, `kanji : comp comp …` body, historically
    # distributed EUC-JP (the adapter transcodes to UTF-8 NFC at the
    # boundary; BMP CJK, NFC-stable, no exemption). One `DictionaryEntry`
    # per kanji keyed on the glyph; `body` lists the components. The
    # companion RADKFILE (component → kanji, `$`-header groups carrying the
    # element + its stroke count) is the transpose of this same bipartite
    # graph — `search --char-component X` recovers the component→kanji
    # direction by scanning these per-kanji component lists, so the base
    # KRADFILE alone backs both the card's component index and the flat
    # containment filter over its ~6,355-kanji (JIS X 0208) span.
    #
    # Some components have no clean Unicode ideograph and appear as their
    # nearest kana/stroke stand-in (材's ノ, 世's ｜) — kept VERBATIM
    # (canonical means canonical); they are honest members of the index.
    class KradfileParser
      LANGUAGE = "jpn"
      # "kanji : comp comp …" — space-colon-space splits the head from the
      # component run; components are whitespace-separated.
      SEPARATOR = " : "

      # +lines+: an enumerable of UTF-8 strings (the adapter owns the EUC-JP
      # decode + any gunzip, and hands decoded lines here). One entry per
      # non-comment line, file order.
      def entries(lines, language: LANGUAGE)
        lines.filter_map { |line| parse_line(line.chomp, language) }
      end

      # The component list of one raw KRADFILE line, or nil for a comment /
      # blank / malformed line. Class method so callers can reuse the split.
      def self.components(line)
        return nil if line.empty? || line.start_with?("#")

        _kanji, rest = line.split(SEPARATOR, 2)
        return nil if rest.nil?

        rest.strip.split(/\s+/)
      end

      private

      def parse_line(line, language)
        return nil if line.empty? || line.start_with?("#")

        kanji, rest = line.split(SEPARATOR, 2)
        return nil if kanji.nil? || rest.nil?

        components = rest.strip.split(/\s+/)
        return nil if kanji.strip.empty? || components.empty?

        entry(kanji.strip, components, language)
      end

      def entry(kanji, components, language)
        character = Normalize.nfc(kanji)
        Nabu::DictionaryEntry.new(
          entry_id: character, key_raw: kanji, language: language,
          headword: character,
          headword_folded: Normalize.search_form(character, language: language),
          gloss: nil,
          body: Normalize.nfc("components: #{components.join(' ')}")
        )
      end
    end
  end
end
