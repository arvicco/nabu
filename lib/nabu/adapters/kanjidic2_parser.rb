# frozen_string_literal: true

require "nokogiri"

module Nabu
  module Adapters
    # Parser family "edrdg-xml", KANJIDIC2 half (P32-4): one DictionaryEntry
    # per <character> of the EDRDG kanjidic2.xml (13,108 kanji: JIS X 0208 +
    # 0212 + 0213), streamed with Nokogiri::XML::Reader (the >5 MB house
    # rule — the decompressed file is ~15 MB). Entry ids are "U+XXXX" from
    # the ucs <cp_value> so the shelf joins Unihan by codepoint verbatim.
    #
    # Verified upstream quirk (2026-07-19 build): BMP ucs values are
    # lowercase hex ("4e9c") but the 754 plane-2 kanji carry UPPERCASE hex
    # ("2000B") — ids are minted through one upcase so the join key never
    # forks on case.
    class Kanjidic2Parser
      LANGUAGE = "jpn"

      # +io+: any IO yielding the XML (File or Zlib::GzipReader).
      def entries(io)
        collected = []
        Nokogiri::XML::Reader(io).each do |node|
          next unless node.name == "character" && node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT

          collected << entry(Nokogiri::XML(node.outer_xml).root)
        end
        collected
      end

      private

      def entry(character)
        literal = Normalize.nfc(character.at("literal").text)
        ucs = character.at('cp_value[cp_type="ucs"]')&.text or
          raise Nabu::ParseError, "edrdg-xml: character #{literal.inspect} has no ucs codepoint"
        Nabu::DictionaryEntry.new(
          entry_id: "U+#{ucs.upcase}", key_raw: literal, language: LANGUAGE,
          headword: literal,
          headword_folded: Normalize.search_form(literal, language: LANGUAGE),
          gloss: meanings(character).first,
          body: Normalize.nfc(body_lines(character).join("\n"))
        )
      end

      # English meanings only — <meaning m_lang="fr|es|pt"> stay upstream.
      def meanings(character)
        character.xpath(".//meaning").reject { |meaning| meaning["m_lang"] }
                                     .map { |meaning| Normalize.nfc(meaning.text) }
      end

      def body_lines(character)
        [
          reading_line(character, "ja_on", "on"),
          reading_line(character, "ja_kun", "kun"),
          list_line("nanori", character.xpath(".//nanori").map(&:text)),
          list_line("meaning", meanings(character)),
          misc_line(character)
        ].compact
      end

      def reading_line(character, r_type, label)
        list_line(label, character.xpath(%(.//reading[@r_type="#{r_type}"])).map(&:text))
      end

      def list_line(label, values)
        values.empty? ? nil : "#{label}: #{values.join('、')}"
      end

      # The misc facts every character carries at least one of
      # (stroke_count is required by the DTD, so the body is never empty).
      def misc_line(character)
        facts = %w[grade stroke_count freq jlpt].filter_map do |field|
          value = character.at(".//misc/#{field}")&.text
          "#{field} #{value}" if value
        end
        facts.empty? ? nil : facts.join(" · ")
      end
    end
  end
end
