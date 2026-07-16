# frozen_string_literal: true

require "nokogiri"

require_relative "../normalize"

module Nabu
  module Adapters
    # The zrc-xml parser family (P23-2): the flat ZRC SAZU dictionary XML of
    # the CLARIN.SI Slovenian historical dictionary shelf — NOT TEI. One
    # shared file shape (a single root element; one entry element per line
    # with a required zero-padded `geslo-id` attribute; XSD shipped in the
    # deposit zip), three element vocabularies:
    #
    #   pletersnik  <P>/<rc>   — <ge> unaccented headword, <zi><oi> accented
    #               toneme form, <ei> homograph number, <pr>/<vi> inflection
    #               and variants, <or> POS, <ra> explanation with <po>
    #               GERMAN glosses, <pi> etymology.
    #   jsv         <JSV>/<ge> — <iz> modernized headword, <ho> homograph,
    #               <za> grammar, <pz> sense blocks (<sp> sense numbers,
    #               <po> modern-Slovenian gloss, <zg> verbatim Baroque
    #               quotes with <ct> volume/page citations), <op> notes.
    #   besedje16   <besedje16>/<Ges> — <besed> headword, <bv>/<bvo> POS,
    #               <razl> bracketed explanation, <sku>/<skupk> attestation
    #               sigla of the 1550–1603 editions.
    #
    # == What one entry yields (Nabu::DictionaryEntry)
    #
    # - entry_id: the geslo-id verbatim (zero-padded — "000005"); the upsert
    #   key. Unique per file (censused: 103,185 / 8,461 / 27,759, no dupes).
    # - key_raw: the plain headword element verbatim (Pleteršnik <ge>, JSV
    #   <iz>, besedje16 <besed>) — the modernized-orthography form that
    #   matches the goo300k/IMP gold lemmas.
    # - headword: the DISPLAY form, NFC — Pleteršnik's accented <oi>
    #   (abecę̑da, ábəł) when present, otherwise the plain headword.
    # - headword_folded: Normalize.search_form of the PLAIN headword with
    #   "sl" (conventions §9: generic mark strip folds the tonemes; ſ→s) —
    #   folding the accented form instead would strand ə/ł spellings
    #   (ábəł folds to "abəł", never typed; its ge "abel" is the real key).
    # - gloss: best-effort first gloss — Pleteršnik: first <po> of <ra>
    #   (German); JSV: first <po> of the sense block (modern Slovenian);
    #   besedje16: the bracket-stripped <razl> explanation. nil is honest.
    # - body: the entry as structured plain text, whitespace collapsed, NFC:
    #   headline zones on the first line, then per-vocabulary lines (ra/pi;
    #   pz blocks split at <sp> sense numbers, op; besedje16 entries are
    #   born one-liners). Quotes keep their Bohorič orthography verbatim —
    #   canonical means canonical.
    # - citations: JSV only — every <ct> mints one UNRESOLVED
    #   DictionaryCitation: urn_raw/label the verbatim "(I/1, 207)",
    #   cts_work nil (no urn is invented; resolution against an IMP
    #   Sacrum promptuarium crosswalk is future work), citation the parsed
    #   "I/1.207" volume/page pair when the shape parses ("s." and-following
    #   suffix tolerated), nil otherwise.
    #
    # Files reach 25 MB (Pleteršnik), so entries stream through
    # Nokogiri::XML::Reader (the >5 MB house rule); each entry element is
    # DOM-parsed alone.
    class ZrcXmlParser
      LANGUAGE = "sl"

      ENTRY_ELEMENTS = {
        "pletersnik" => "rc",
        "jsv" => "ge",
        "besedje16" => "Ges"
      }.freeze

      # "(I/1, 207)" / "(II, 194 s.)" → ["I/1", "207"] / ["II", "194"].
      # Roman volume, optional /part, page number, optional "s." (and
      # following). Anything else (upstream typos like "I1") parses to nil —
      # the verbatim label is never lost.
      CITATION_SHAPE = %r{\A\(([IVX]+(?:/\d+)?),\s*(\d+)(?:\s*s\.)?\)\z}

      # Parse +path+ and return its DictionaryEntry values in file order.
      def entries(path, dictionary:)
        element = ENTRY_ELEMENTS.fetch(dictionary)
        result = []
        each_element(path, element) do |node|
          result << build_entry(node, dictionary, path)
        end
        result
      end

      private

      def each_element(path, name)
        reader = Nokogiri::XML::Reader(File.open(path))
        reader.each do |node|
          next unless node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT && node.name == name

          yield Nokogiri::XML.fragment(node.outer_xml).children.first
        end
      rescue Nokogiri::XML::SyntaxError => e
        raise Nabu::ParseError, "zrc-xml: malformed XML in #{path}: #{e.message}"
      end

      # Pleteršnik and JSV carry geslo-id on the entry element itself;
      # besedje16 carries it on the nested <besed> headword element.
      def build_entry(node, dictionary, path)
        id = node["geslo-id"] || node.at_xpath("besed")&.[]("geslo-id")
        case dictionary
        when "pletersnik" then pletersnik_entry(node, id)
        when "jsv" then jsv_entry(node, id)
        else besedje16_entry(node, id)
        end
      rescue Nabu::ValidationError, Nabu::Normalize::EncodingError => e
        raise Nabu::ParseError, "zrc-xml: entry geslo-id=#{id.inspect} in #{path}: #{e.message}"
      end

      def entry(id:, plain:, display:, gloss:, lines:, citations: [])
        Nabu::DictionaryEntry.new(
          entry_id: id, key_raw: plain, language: LANGUAGE,
          headword: Nabu::Normalize.nfc(display),
          headword_folded: Nabu::Normalize.search_form(plain, language: LANGUAGE),
          gloss: gloss,
          body: Nabu::Normalize.nfc(lines.reject(&:empty?).join("\n")),
          citations: citations
        )
      end

      # -- pletersnik --------------------------------------------------------------

      # Headline = the headword-adjacent zones in document order (<ei>
      # homograph, <zi> accented form, <pr>/<vi> inflection and variants,
      # <or> POS) — their text carries its own punctuation. <ge> is skipped
      # there: it duplicates key_raw. Then <ra>, then <pi>, one line each.
      def pletersnik_entry(node, id)
        plain = node.at_xpath("ge").text
        entry(
          id: id, plain: plain,
          display: node.at_xpath("zi/oi")&.text || plain,
          gloss: first_gloss(node, "ra//po"),
          lines: [collapse(node.xpath("ei | zi | pr | vi | or").map(&:text).join),
                  *node.xpath("ra | pi").map { |zone| collapse(zone.text) }]
        )
      end

      # -- jsv ---------------------------------------------------------------------

      def jsv_entry(node, id)
        iz = node.at_xpath("iz").dup
        iz.xpath("ho").each(&:remove) # the XSD allows a nested homograph number
        plain = iz.text
        headline = [plain, node.at_xpath("ho | iz/ho")&.text, node.at_xpath("za")&.text]
                   .compact.map { |part| collapse(part) }.reject(&:empty?).join(" ")
        entry(
          id: id, plain: plain, display: plain,
          gloss: first_gloss(node, "pz//po"),
          lines: [headline,
                  *node.xpath("pz").flat_map { |pz| sense_lines(pz) },
                  *node.xpath("op").map { |op| collapse(op.text) }],
          citations: node.xpath(".//ct").map { |ct| citation(ct) }
        )
      end

      # A <pz> sense block: <sp> sense numbers start new lines, everything
      # else flows in document order.
      def sense_lines(sense_block)
        lines = [+""]
        sense_block.children.each do |child|
          lines << +"" if child.name == "sp" && !lines.last.strip.empty?
          lines.last << child.text
        end
        lines.map { |line| collapse(line) }.reject(&:empty?)
      end

      def citation(node)
        label = Nabu::Normalize.nfc(collapse(node.text))
        volume, page = label.match(CITATION_SHAPE)&.captures
        Nabu::DictionaryCitation.new(
          urn_raw: label, cts_work: nil,
          citation: volume && "#{volume}.#{page}", label: label
        )
      end

      # -- besedje16 ----------------------------------------------------------------

      # Entries are born one-liners: the whole element text, collapsed. The
      # <razl> bracketed explanation is the only gloss-shaped field.
      def besedje16_entry(node, id)
        plain = node.at_xpath("besed").text
        razl = node.at_xpath("razl")
        gloss = razl && present(collapse(razl.text).sub(/\A\[/, "").sub(/\]\z/, "").strip)
        entry(
          id: id, plain: plain, display: plain,
          gloss: gloss && Nabu::Normalize.nfc(gloss),
          lines: [collapse(node.text)]
        )
      end

      # -- shared -------------------------------------------------------------------

      def first_gloss(node, xpath)
        text = node.at_xpath(xpath)&.text
        return nil unless text

        gloss = present(collapse(text).sub(/[\s,;:]+\z/, ""))
        gloss && Nabu::Normalize.nfc(gloss)
      end

      def collapse(text)
        text.gsub(/\s+/, " ").strip
      end

      def present(text)
        text.empty? ? nil : text
      end
    end
  end
end
