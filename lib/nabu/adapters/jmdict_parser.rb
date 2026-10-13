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

      # P123-1: the sense-level pointer elements => crossref kind.
      CROSSREF_KINDS = { "xref" => "see", "ant" => "antonym" }.freeze

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
          body: Normalize.nfc(body_lines(element, kanji, readings).join("\n")),
          crossrefs: crossrefs(element)
        )
      end

      # P123-1: the sense-level <xref> ("see also") and <ant> (antonym)
      # pointers, document order. Upstream shape "keb・reb・sense" (any
      # part optional — "丸・まる・1", "天ぷら", "アガペー・1"): the
      # first part is the pointed-at headword (the form this parser keys
      # entries by), the whole text the verbatim label. Census 2026-10-13
      # over the held JMdict_e (218,214 entries): 36,647 <xref> + 1,112
      # <ant> on 32,770 entries; 32,828 resolve to a unique headword,
      # 1,891 are ambiguous homographs (left verbatim). Kinds:
      # CROSSREF_KINDS above.
      def crossrefs(element)
        element.xpath(".//sense/xref | .//sense/ant").filter_map do |node|
          text = Normalize.nfc(node.text.strip)
          target = text.split("・").first.to_s.strip
          next nil if target.empty?

          kind = CROSSREF_KINDS.fetch(node.name)
          folded = Normalize.search_form(target, language: LANGUAGE)
          Nabu::DictionaryCrossref.new(kind: kind, label: "#{kind} #{text}", target: target,
                                       target_folded: folded.strip.empty? ? nil : folded)
        end
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
