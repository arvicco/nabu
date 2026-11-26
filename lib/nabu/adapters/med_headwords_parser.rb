# frozen_string_literal: true

require "nokogiri"

require_relative "source_read"

module Nabu
  module Adapters
    # The `med-headwords-xml` parser family: the Middle English
    # Dictionary's entry list as its editors publish it on medictionary.info
    # ("Headwords, variant spellings, and IDs" — the 2021-12 / 2022-10 /
    # 2023-10 format): "straightforward excerpts from the raw XML of the MED
    # files themselves with only minimal alteration". FORMAT only — which
    # file, the dictionary slug and the license live in the adapter.
    #
    # == The upstream shape (censused over the whole 2023-10 list)
    #
    #   <!-- SORT>00004</SORT --><ENTRY ID="MED3" SEQ="4" [RESP=…] [DUB="Y"] [DEL="Y"]>
    #     <FORM><HDORTH><REG>a</REG><ORIG>a</ORIG></HDORTH> <POS><PS EXPAN="indefinite
    #     article">indef. art.</PS></POS> Also <ORTH><REG>an</REG><ORIG>an</ORIG></ORTH>. …
    #   </FORM></ENTRY>
    #
    # - ENTRY@ID: the MED entry id (unique; decimal ids are post-print
    #   entries) — the entry_id; the online entry is
    #   https://quod.lib.umich.edu/m/middle-english-dictionary/dictionary/<ID>.
    # - ENTRY@SEQ: alphabetical sequence (the SORT comment repeats it
    #   zero-padded — censused identical on every entry, so not mined twice);
    #   @RESP the revising editor's id; @DUB / @DEL the editors' "queried
    #   (dubious)" and "flagged for deletion" marks (always "Y").
    # - HDORTH (headword spellings, 1–n) and ORTH (the "Also …" variant
    #   spellings): each holds ORIG — the display form as printed, diacritics
    #   and abbreviated parentheticals ("on(e", "-ǒunen") kept — and one or
    #   more REG, the editors' search forms (diacritics dropped,
    #   parentheticals expanded). Upstream quirks rendered without loss: one
    #   ORTH carries two ORIGs (MED5005.5, both shown), one has no ORIG
    #   (MED20283 "hai-reve", its first REG shown), and 721 REGs carry a
    #   preceding <!-- maybe --> comment (an editor's doubtful expansion).
    # - POS: the part-of-speech text as printed ("n.(1)", "Latin abbrev.",
    #   "adv. & prep."); each PS@EXPAN spells one class out. Eight POS are
    #   empty.
    # - HI@REND (B/I) runs inside the prose of the form section: their
    #   text reads in place.
    #
    # == The entry
    #
    # - headword: the first HDORTH's ORIG (NFC); key_raw: its first REG
    #   verbatim; headword_folded: that REG's search form.
    # - body: the form section rendered as the dictionary prints it (ORIG
    #   spellings, the POS, the "Also …" prose), then the editorial flag
    #   lines, then the MED entry URL.
    # - gloss: nil — the list carries no definitions.
    # - citations: one row per entry, its online MED entry URL.
    # - annotations: pos (EXPAN values), pos_label, headword_forms,
    #   variants (ORTH ORIGs), search_forms (every REG, deduped in order),
    #   doubtful_search_forms, seq, resp, dubious, deprecated, url — absent
    #   keys are absences upstream.
    class MedHeadwordsParser
      LANGUAGE = "enm"
      ENTRY_URL = "https://quod.lib.umich.edu/m/middle-english-dictionary/dictionary/%s"
      READER_OPTIONS = Nokogiri::XML::ParseOptions::NONET | Nokogiri::XML::ParseOptions::NOWARNING |
                       Nokogiri::XML::ParseOptions::NOERROR
      DOUBT_MARK = "maybe"
      private_constant :READER_OPTIONS, :DOUBT_MARK

      def self.entry_url(id) = format(ENTRY_URL, id)

      def entries(path)
        xml = SourceRead.utf8_file(path, label: "med-headwords-xml")
        collected = []
        Nokogiri::XML::Reader(xml, path, nil, READER_OPTIONS).each do |node|
          next unless node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT && node.name == "ENTRY"

          collected << build(Nokogiri::XML(node.outer_xml, &:strict).root, path)
        end
        collected
      rescue Nokogiri::XML::SyntaxError => e
        raise Nabu::ParseError, "med-headwords-xml: malformed XML in #{path}: #{e.message}"
      end

      private

      def build(elem, path)
        id = elem["ID"].to_s.strip
        raise Nabu::ParseError, "med-headwords-xml: an ENTRY with no ID in #{path}" if id.empty?

        form = elem.at_xpath("FORM")
        heads = form ? form.xpath("HDORTH") : []
        raise Nabu::ParseError, "med-headwords-xml: #{id} has no HDORTH in #{path}" if heads.empty?

        url = self.class.entry_url(id)
        key = heads.first.at_xpath("REG")&.text.to_s
        key = display(heads.first) if key.empty?
        Nabu::DictionaryEntry.new(
          entry_id: id, key_raw: Normalize.nfc(key), language: LANGUAGE,
          headword: display(heads.first),
          headword_folded: Normalize.search_form(Normalize.nfc(key), language: LANGUAGE),
          body: body(elem, form, url),
          citations: [Nabu::DictionaryCitation.new(urn_raw: url, cts_work: nil, citation: id,
                                                   label: "Middle English Dictionary, #{id}")],
          annotations: annotations(elem, form, heads, url)
        )
      end

      # One spelling element as printed: its ORIG(s), else its first REG.
      def display(spelling)
        origs = spelling.xpath("ORIG").map(&:text)
        origs = [spelling.at_xpath("REG")&.text.to_s] if origs.empty?
        Normalize.nfc(origs.join(", "))
      end

      def body(elem, form, url)
        lines = [Normalize.nfc(render(form).gsub(/\s+/, " ").strip)]
        lines << "[queried (dubious) entry]" if elem["DUB"]
        lines << "[flagged for deletion in the editors' working copy]" if elem["DEL"]
        lines << "MED entry: #{url}"
        lines.join("\n")
      end

      # The form section's text with every spelling shown by its display
      # form (the REG search forms are not reading text — upstream's own
      # stylesheet hides them); comments never render.
      def render(node)
        node.children.map do |child|
          if child.text?
            child.text
          elsif child.element? && %w[HDORTH ORTH].include?(child.name)
            display(child)
          elsif child.element?
            render(child)
          else
            ""
          end
        end.join
      end

      def annotations(elem, form, heads, url)
        pos = form.at_xpath("POS")
        regs = form.xpath("HDORTH/REG|ORTH/REG")
        {
          "pos" => pos&.xpath("PS")&.map { |ps| Normalize.nfc(ps["EXPAN"].to_s) }&.reject(&:empty?),
          "pos_label" => pos && Normalize.nfc(pos.text.gsub(/\s+/, " ").strip),
          "headword_forms" => heads.map { |head| display(head) },
          "variants" => form.xpath("ORTH").map { |orth| display(orth) },
          "search_forms" => regs.map { |reg| Normalize.nfc(reg.text) }.uniq,
          "doubtful_search_forms" => regs.select { |reg| doubtful?(reg) }.map { |reg| Normalize.nfc(reg.text) },
          "seq" => elem["SEQ"]&.to_i,
          "resp" => elem["RESP"],
          "dubious" => elem["DUB"] ? true : nil,
          "deprecated" => elem["DEL"] ? true : nil,
          "url" => url
        }.reject { |_, value| value.nil? || value == "" || value == [] }
      end

      def doubtful?(reg)
        reg.children.any? { |child| child.comment? && child.text.strip == DOUBT_MARK }
      end
    end
  end
end
