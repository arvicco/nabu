# frozen_string_literal: true

require "nokogiri"

require_relative "../betacode"
require_relative "../normalize"

module Nabu
  module Adapters
    # The lexicon-tei parser family (P11-4): Perseus dictionary TEI — P4
    # (<TEI.2> + PersDict DTD, unfetchable offline; the Reader streams past
    # it, the P9-2 experience) with entryFree entries under
    # div0[@type="alphabetic letter"]. Streams with Nokogiri::XML::Reader
    # (LSJ letter files run to 43 MB, Lewis & Short to 77 MB — CLAUDE.md's
    # no-DOM-over-5MB rule) and DOM-parses one ENTRY at a time, which is the
    # natural unit and never large (the ~300 KB λόγος entry is the known
    # maximum).
    #
    # == What one entry yields (Nabu::DictionaryEntry)
    #
    # - headword: the first <orth> (fallback: the @key), betacode-decoded for
    #   LSJ (+betacode: true+ — its keys, orths and Greek quotes are all
    #   betacode; Lewis & Short eng2 is already Unicode).
    # - headword_folded: minted from the @key — decoded, stem hyphens and
    #   trailing homograph digits stripped ("mh=nis" → μηνισ, "a2" → a) —
    #   through Normalize.search_form with the dictionary language, the same
    #   both-sides fold contract as lemma search (conventions §9).
    # - gloss: the first <tr>; when a lexicon glosses in italics instead
    #   (Lewis & Short), the first non-abbreviation <hi rend="ital"> of the
    #   FIRST sense (an italic run ending in "." is a grammatical
    #   abbreviation — "gen. plur." — not a gloss). Best-effort: nil is
    #   honest for cross-reference stubs.
    # - body: the whole entry as plain text, whitespace collapsed, each
    #   <sense> starting a new line prefixed with its @n label, Greek decoded.
    # - citations: one DictionaryCitation per <bibl> whose @n is a urn:cts:
    #   value (the 2014 upstream revision put CTS urns there); the @n is kept
    #   verbatim, the work-level prefix and dot-joined citation are derived
    #   for query-time resolution. URN-less and non-CTS bibls ("Dig. 33.6.9")
    #   mint no row — their display text still reads in the body.
    class LexiconTeiParser
      ENTRY_ELEMENT = "entryFree"

      # First <tr> or italic run of the FIRST sense, in document order,
      # skipping quote translations (anything inside <cit>) and grammatical
      # abbreviations (italic runs ending in "." — "gen. plur."). Best-effort:
      # nil is honest (see #gloss).
      GLOSS_XPATH = %(.//tr[not(ancestor::cit)] | .//hi[@rend="ital"][not(ancestor::cit)])

      # Parse +path+ and return its DictionaryEntry values in file order.
      def entries(path, language:, betacode: false)
        collected = []
        File.open(path) do |io|
          Nokogiri::XML::Reader(io, path).each do |node|
            next unless node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT
            next unless node.name == ENTRY_ELEMENT

            collected << build_entry(entry_element(node), language: language, betacode: betacode)
          end
        end
        collected
      rescue Nokogiri::XML::SyntaxError => e
        raise Nabu::ParseError, "lexicon-tei: malformed XML in #{path}: #{e.message}"
      end

      private

      # One entry's subtree as its own small DOM (entries never nest).
      def entry_element(node)
        fragment = Nokogiri::XML.fragment(node.outer_xml)
        fragment.children.find(&:element?)
      end

      def build_entry(elem, language:, betacode:)
        key = elem["key"]
        raise Nabu::ParseError, "lexicon-tei: entryFree without @key (id #{elem['id'].inspect})" if key.nil?

        entry_id = elem["id"] || key
        Nabu::DictionaryEntry.new(
          entry_id: entry_id, key_raw: key, language: language,
          headword: headword(elem, key, betacode: betacode),
          headword_folded: fold_key(key, language: language, betacode: betacode),
          gloss: gloss(elem),
          body: body(elem, betacode: betacode),
          citations: citations(elem)
        )
      end

      def headword(elem, key, betacode:)
        orth = elem.at_xpath(".//orth")
        raw = orth ? collapse(orth.text) : key
        raw = Betacode.decode(raw) if betacode
        Nabu::Normalize.nfc(raw)
      end

      # The lookup key: decoded @key, stem hyphens and trailing homograph
      # digits dropped, folded per the language rule table.
      def fold_key(key, language:, betacode:)
        source = betacode ? Betacode.decode(key) : key
        source = source.delete("-").sub(/\d+\z/, "")
        Nabu::Normalize.search_form(source, language: language)
      end

      def gloss(elem)
        scope = elem.at_xpath(".//sense") || elem
        scope.xpath(GLOSS_XPATH)
             .map { |node| collapse(node.text) }
             .find { |text| !text.empty? && !text.end_with?(".") }
      end

      # Linearize the entry: text in document order, whitespace collapsed,
      # sense boundaries as labeled line breaks, Greek decoded when the
      # lexicon is betacode-encoded.
      def body(elem, betacode:)
        buffer = +""
        walk(elem, buffer, greek: false, betacode: betacode)
        text = buffer.gsub(/[ \t]+/, " ").gsub(/ *\n */, "\n").strip
        Nabu::Normalize.nfc(text)
      end

      def walk(node, buffer, greek:, betacode:)
        node.children.each do |child|
          if child.text?
            text = child.text
            text = Betacode.decode(text) if betacode && greek
            buffer << text.gsub(/\s+/, " ")
          elsif child.element?
            buffer << sense_break(child) if child.name == "sense"
            walk(child, buffer, greek: greek || child["lang"] == "greek", betacode: betacode)
          end
        end
      end

      def sense_break(sense)
        label = sense["n"]
        label ? "\n#{label}. " : "\n"
      end

      def citations(elem)
        elem.xpath(".//bibl[@n]").filter_map do |bibl|
          urn_raw = bibl["n"]
          next unless urn_raw.start_with?("urn:cts:")

          label = collapse(bibl.text)
          next if label.empty?

          cts_work, citation = cite_parts(urn_raw)
          Nabu::DictionaryCitation.new(urn_raw: urn_raw, cts_work: cts_work,
                                       citation: citation, label: Nabu::Normalize.nfc(label))
        end
      end

      # "urn:cts:latinLit:phi0474.phi055.perseus-lat1:1:2:4" →
      # ["urn:cts:latinLit:phi0474.phi055", "1.2.4"]. Edition tokens are
      # dropped from the work prefix (see class note); colon-separated
      # citation parts join with dots (the catalog's citation-suffix shape).
      # Malformed urns still split honestly — they resolve to nothing later.
      def cite_parts(urn_raw)
        parts = urn_raw.split(":", -1)
        return [nil, nil] if parts.length < 4

        work = "urn:cts:#{parts[2]}:#{parts[3].split('.').first(2).join('.')}"
        citation = parts.length > 4 ? parts[4..].join(".") : nil
        [work, citation]
      end

      def collapse(text)
        text.gsub(/\s+/, " ").strip
      end
    end
  end
end
