# frozen_string_literal: true

require "nokogiri"

module Nabu
  module Adapters
    # Parser family "edrdg-xml", JMdict half (P32-4): one DictionaryEntry
    # per <entry> of JMdict_e (the English-gloss build; 217,951 entries at
    # the 2026-07-19 nightly), streamed with Nokogiri::XML::Reader over the
    # ~60 MB decompressed XML. JMdict's part-of-speech and misc tags are
    # internal-DTD entities (&n; → "noun (common) (futsuumeishi)"); the
    # Reader runs with NOENT so the expanded prose lands in the body, never
    # the raw entity name.
    #
    # entry_id is the upstream <ent_seq> (the EDRDG-stable sequence number);
    # the headword is the first kanji form (<keb>) or, for kana-only
    # entries, the first reading (<reb>).
    class JmdictParser
      LANGUAGE = "jpn"

      # +io+: any IO yielding the XML (File or Zlib::GzipReader).
      def entries(io)
        collected = []
        reader = Nokogiri::XML::Reader(io, nil, nil, Nokogiri::XML::ParseOptions::NOENT)
        reader.each do |node|
          next unless node.name == "entry" && node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT

          collected << entry(Nokogiri::XML(node.outer_xml).root)
        end
        collected
      end

      private

      def entry(element)
        seq = element.at("ent_seq")&.text.to_s
        raise Nabu::ParseError, "edrdg-xml: JMdict entry without ent_seq" if seq.empty?

        kanji = element.xpath(".//keb").map { |keb| Normalize.nfc(keb.text) }
        readings = element.xpath(".//reb").map { |reb| Normalize.nfc(reb.text) }
        headword = kanji.first || readings.first or
          raise Nabu::ParseError, "edrdg-xml: JMdict entry #{seq} has neither keb nor reb"
        Nabu::DictionaryEntry.new(
          entry_id: seq, key_raw: seq, language: LANGUAGE,
          headword: headword,
          headword_folded: Normalize.search_form(headword, language: LANGUAGE),
          gloss: element.at(".//sense/gloss")&.text&.then { |text| Normalize.nfc(text) },
          body: Normalize.nfc(body_lines(element, kanji, readings).join("\n"))
        )
      end

      def body_lines(element, kanji, readings)
        lines = []
        lines << "kanji: #{kanji.join('、')}" unless kanji.empty?
        lines << "readings: #{readings.join('、')}" unless readings.empty?
        element.xpath(".//sense").each_with_index do |sense, index|
          line = sense_line(sense, index)
          lines << line if line
        end
        lines
      end

      # "1. (pos) gloss; gloss" — the pos annotation rides in prose (the
      # NOENT-expanded entity text), omitted when the sense has none.
      def sense_line(sense, index)
        glosses = sense.xpath(".//gloss").map(&:text)
        return nil if glosses.empty?

        pos = sense.xpath(".//pos").map(&:text)
        label = pos.empty? ? "" : " (#{pos.join('; ')})"
        "#{index + 1}.#{label} #{glosses.join('; ')}"
      end
    end
  end
end
