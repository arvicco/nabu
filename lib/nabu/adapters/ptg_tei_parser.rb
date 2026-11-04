# frozen_string_literal: true

require "nokogiri"

require_relative "../normalize"

module Nabu
  module Adapters
    # The ptg-tei parser family: the DILA (Dharma Drum) Pentaglot TEI P5
    # digital edition — <body> holds two volume <div xml:id="han1|han2">,
    # each a run of <div type="topic"> (one nested level in the
    # bodhipakṣika block), each topic a run of <entry xml:id="pNNN.n">.
    # Every real entry carries five <sense xml:lang> columns in file order
    # san-Latn / bod-Tibt / mnc-Latn / mon-Latn / zho-Hant — the Tibetan
    # one always empty (upstream: "We have not digitized the Tibetan terms
    # as yet"). The member is 465 KB, under CLAUDE.md's 5 MB DOM line, but
    # the mvp-tei Reader + per-entry fragment shape is kept for symmetry.
    #
    # == What one entry yields, per headword language
    #
    # The Pentaglot is a mirror dictionary — no column is THE headword —
    # so #entries(xml, language:) emits the shelf for ONE column: only the
    # entries whose own column is non-empty, headed by it.
    # - entry_id / key_raw: the upstream @xml:id verbatim ("p005.2" = page
    #   5, item 2 of Raghu Vira's 1961 reprint — the citable address; the
    #   irregular "p192A." / "p209" shapes kept as-is, all unique).
    # - headword: the column's text, whitespace-squashed, NFC (upstream's
    #   Mongolian column writes a combining U+0308 415× (ö/ü as base +
    #   diaeresis, mixed with precomposed ü) — composed here, at
    #   the adapter boundary). Rubric rows (the bracketed Sanskrit topic
    #   heads, "[buddha paryāya - nāmāni]") stay verbatim, brackets too.
    # - headword_folded: Normalize.search_form of the headword — for
    #   Manchu with upstream's inline editorial parentheses removed
    #   ("ufuku(sic？for ufuhu)" → "ufuku"; "(BN …)" variant notes; ×12),
    #   so the lookup key is the word, while the display keeps the note.
    # - gloss: the Sanskrit (IAST) for the mnc/cmg/lzh shelves, the
    #   Chinese for the san shelf.
    # - body: labeled lanes in upstream column order — "Sanskrit:",
    #   "Manchu:", "Mongolian:", "Chinese:"; empty columns drop.
    #
    # An entry with no filled column at all (the file's lone p341A.1 —
    # only an XML comment on an untraceable index reference) skips by rule.
    class PtgTeiParser
      ENTRY_ELEMENT = "entry"

      # House language → [upstream xml:lang, lane label], upstream order.
      COLUMNS = {
        "san" => %w[san-Latn Sanskrit],
        "mnc" => %w[mnc-Latn Manchu],
        "cmg" => %w[mon-Latn Mongolian],
        "lzh" => %w[zho-Hant Chinese]
      }.freeze

      EDITORIAL_PARENS = /\s*\([^)]*\)\s*/

      # Parse the TEI +xml+ string and return the +language+ shelf's
      # DictionaryEntry values in file order. +path+ names the origin in
      # errors only.
      def entries(xml, language:, path:)
        COLUMNS.key?(language) or raise ArgumentError, "ptg-tei: unknown shelf language #{language.inspect}"

        collected = []
        Nokogiri::XML::Reader(xml, path).each do |node|
          next unless node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT && node.name == ENTRY_ELEMENT

          entry = build_entry(entry_element(node), language)
          collected << entry if entry
        end
        collected
      rescue Nokogiri::XML::SyntaxError => e
        raise Nabu::ParseError, "ptg-tei: malformed XML in #{path}: #{e.message}"
      end

      private

      def entry_element(node)
        document = Nokogiri::XML(node.outer_xml)
        document.remove_namespaces!
        document.root or raise Nabu::ParseError, "ptg-tei: unreadable <entry> fragment"
      end

      def build_entry(element, language)
        columns = COLUMNS.transform_values { |(lang, _label)| column_text(element, lang) }
        headword = columns.fetch(language)
        return nil if headword.empty?

        id = element["id"].to_s
        Nabu::DictionaryEntry.new(
          entry_id: id, key_raw: id, language: language,
          headword: headword,
          headword_folded: Nabu::Normalize.search_form(lookup_text(headword, language), language: language),
          gloss: gloss(columns, language),
          body: body_text(columns),
          citations: []
        )
      end

      def column_text(element, lang)
        node = element.css("sense").find { |sense| sense["lang"] == lang }
        Nabu::Normalize.nfc(node ? node.text.gsub(/\s+/, " ").strip : "")
      end

      def lookup_text(headword, language)
        return headword unless language == "mnc"

        headword.gsub(EDITORIAL_PARENS, " ").gsub(/\s+/, " ").strip
      end

      def gloss(columns, language)
        other = language == "san" ? columns.fetch("lzh") : columns.fetch("san")
        other.empty? ? nil : other
      end

      def body_text(columns)
        COLUMNS.filter_map do |language, (_lang, label)|
          text = columns.fetch(language)
          "#{label}: #{text}" unless text.empty?
        end.join("\n")
      end
    end
  end
end
