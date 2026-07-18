# frozen_string_literal: true

require "nokogiri"

require_relative "../normalize"

module Nabu
  module Adapters
    # The aed-tei parser family (P28-1): the TLA/BBAW Ägyptische Wortliste
    # (aed-tei files/dictionary.xml) — TEI P5 in the default TEI namespace,
    # NOT the PersDict shape the lexicon-tei family reads: entries are flat
    # <entry xml:id="tla…"> records with exactly one form/orth, one
    # gramGrp/term and one sense (censused over all 35,052 upstream
    # entries), no nested senses, no @key, no betacode. Streams with
    # Nokogiri::XML::Reader (the file is 18 MB — CLAUDE.md's no-DOM-over-5MB
    # rule) and DOM-parses one entry at a time (entries are tiny;
    # remove_namespaces! per entry keeps the xpaths plain).
    #
    # == What one entry yields (Nabu::DictionaryEntry)
    #
    # - entry_id: the @xml:id VERBATIM ("tla550034") — THE JOIN CONTRACT:
    #   the xml:id is the TLA lemmaID that the AES corpus (P28-0) mints as
    #   its gold lemma ids, so urn:nabu:dict:aed:<lemmaID> is exactly the
    #   urn an AES annotation predicts. Never renumbered, never prefixed.
    # - headword / key_raw: the orth text verbatim (NFC) — Egyptological
    #   transliteration (ꜣ ꜥ ḥ ḫ …); the folded form goes through the P28-1
    #   egy fold (conventions §9) so ASCII-ish lookups land (nfr, hap-r).
    # - gloss: the German translation quote — the COMPLETE lane (all 35,052
    #   entries carry de; en covers 16,972) and the TLA's own curated
    #   Bedeutung; English rides the body verbatim instead.
    # - body: one line per upstream element in document order — the
    #   gramGrp/term verbatim ("substantive/substantive_masc"), each
    #   translation as "<lang>: <quote>" (de/en and the two upstream
    #   fr/it oddballs), the whole <bibl> verbatim as "bibl: …" (omitted
    #   when upstream ships <bibl/> empty — the root entries), then each
    #   <xr> as "<type>: <target-ids>" (type verbatim: root, rootOf,
    #   partOf, contains, referencedBy, referencing, predecessor,
    #   successor). CENSUSED VERDICT (P28-1): xr refs carry NO surface
    #   form (an empty <ref target="tla…"/> — no word, no language), so
    #   reflex rows cannot be minted honestly; they land as body
    #   cross-reference lines whose ids resolve through the join contract
    #   (nabu show urn:nabu:dict:aed:<id>).
    # - citations: one DictionaryCitation per bibl SEGMENT (";"-split)
    #   matching /\AWb\s/ — the Wörterbuch der aegyptischen Sprache, a
    #   PRINT dictionary: label and urn_raw carry the segment verbatim,
    #   cts_work stays nil (the BDB-pages pattern — nothing resolves until
    #   a Wb local-library scan exists), citation carries "volume.page"
    #   when the segment parses ("Wb 1, 2.8" → "1.2"; the "Wb 3. 293…"
    #   dot-after-volume quirk included), the future deep-link key. Other
    #   print references (MedWb, KoptHWb, Meeks, GDG, LGG …) mint no row —
    #   they read verbatim in the body's bibl line.
    class AedTeiParser
      ENTRY_ELEMENT = "entry"
      LANGUAGE = "egy"

      # One Wb print-page segment: "Wb <volume>, <page>[.<line(s)>]" —
      # upstream also writes a dot after the volume (censused ×32).
      WB_PAGE = /\AWb (\d+)[,.] (\d+)/

      # Parse +path+ and return its DictionaryEntry values in file order.
      def entries(path)
        collected = []
        File.open(path) do |io|
          Nokogiri::XML::Reader(io, path).each do |node|
            next unless node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT
            next unless node.name == ENTRY_ELEMENT

            collected << build_entry(entry_element(node))
          end
        end
        collected
      rescue Nokogiri::XML::SyntaxError => e
        raise Nabu::ParseError, "aed-tei: malformed XML in #{path}: #{e.message}"
      end

      private

      # One entry's subtree as its own small namespace-free DOM (outer_xml
      # redeclares the TEI default namespace; entries never nest).
      def entry_element(node)
        doc = Nokogiri::XML(node.outer_xml, &:strict)
        doc.remove_namespaces!
        doc.root
      end

      def build_entry(elem)
        id = elem["id"]
        raise Nabu::ParseError, "aed-tei: entry without @xml:id" if id.nil? || id.empty?

        orth = elem.at_xpath("form/orth")&.text.to_s
        raise Nabu::ParseError, "aed-tei: entry #{id} without form/orth" if orth.strip.empty?

        headword = Nabu::Normalize.nfc(collapse(orth))
        Nabu::DictionaryEntry.new(
          entry_id: id, key_raw: headword, language: LANGUAGE,
          headword: headword,
          headword_folded: Nabu::Normalize.search_form(headword, language: LANGUAGE),
          gloss: gloss(elem),
          body: body(elem),
          citations: citations(elem)
        )
      end

      # The German quote — the complete lane (every upstream entry carries
      # one; nil would only be an upstream regression, kept honest).
      def gloss(elem)
        quote = elem.at_xpath(%(sense/cit[@type="translation"][@lang="de"]/quote))&.text
        return nil if quote.nil?

        text = collapse(quote)
        text.empty? ? nil : Nabu::Normalize.nfc(text)
      end

      def body(elem)
        lines = [collapse(elem.at_xpath("gramGrp/term")&.text.to_s)]
        elem.xpath("sense/cit").each do |cit|
          lines << cit_line(cit)
        end
        elem.xpath("xr").each do |xr|
          targets = xr.xpath("ref").map { |ref| ref["target"] }.compact
          lines << "#{xr['type']}: #{targets.join(', ')}" unless targets.empty?
        end
        Nabu::Normalize.nfc(lines.compact.reject(&:empty?).join("\n"))
      end

      # A translation cit → "<lang>: <quote>"; a bibliography cit → the
      # whole bibl verbatim as "bibl: …", nil when upstream ships it empty.
      def cit_line(cit)
        if cit["type"] == "translation"
          quote = collapse(cit.at_xpath("quote")&.text.to_s)
          quote.empty? ? nil : "#{cit['lang']}: #{quote}"
        else
          bibl = collapse(cit.at_xpath("bibl")&.text.to_s)
          bibl.empty? ? nil : "bibl: #{bibl}"
        end
      end

      def citations(elem)
        bibl = collapse(elem.at_xpath("sense/cit/bibl")&.text.to_s)
        bibl.split(";").map(&:strip).filter_map do |segment|
          next unless segment.match?(/\AWb\s/)

          label = Nabu::Normalize.nfc(segment)
          page = segment.match(WB_PAGE)
          Nabu::DictionaryCitation.new(
            urn_raw: label, cts_work: nil,
            citation: page && "#{page[1]}.#{page[2]}", label: label
          )
        end
      end

      def collapse(text)
        text.gsub(/\s+/, " ").strip
      end
    end
  end
end
