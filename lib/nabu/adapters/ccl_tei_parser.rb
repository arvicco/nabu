# frozen_string_literal: true

require "nokogiri"

require_relative "../normalize"

module Nabu
  module Adapters
    # The ccl-tei parser family (P28-3): the Comprehensive Coptic Lexicon
    # v1.2 TEI (Refubium fub188/27813) — namespaced TEI P5 against the
    # project's own Coptic_Lemma_Schema, NOT the P4/PersDict shape
    # LexiconTeiParser reads. Census (full artifact, 2026-07-18): 11,284
    # <entry> with unique xml:id="C<n>" (the CDO/CCL id space the ORAEC
    # crosswalk keys on), 5,417 at body level + 5,867 inside 1,181 id-less
    # <superEntry> homograph/compound groups (entries never nest in
    # entries — the Reader yields every entry exactly once, flat); dialect
    # sigla in usg[@type="geo"] (S/B/A/L/F/Ak…), senses as
    # <cit type="translation"> quote triples (en 15,889 / de 8,911 /
    # fr 8,911), print-dictionary <bibl> strings (CD/CED/KoptHWb/DELC —
    # no CTS urns anywhere, so the TEI itself mints no citation rows).
    # Streams with Nokogiri::XML::Reader (11.77 MB — the no-DOM-over-5MB
    # rule) and DOM-parses one entry at a time (entries are small).
    #
    # == What one entry yields (Nabu::DictionaryEntry)
    #
    # - entry_id/key_raw: the xml:id verbatim ("C1494") — there is no @key;
    #   the C-id is the stable upsert key AND the crosswalk join key.
    # - headword: the first form[@type="lemma"]/orth (exactly one entry in
    #   v1.2, C11273, lacks a lemma form → first orth anywhere, censused).
    # - headword_folded: the headword through Normalize.search_form
    #   language "cop" (the P17-1 fold the Coptic Scriptorium shelf already
    #   searches with: generic downcase + mark strip — supralinear-stroke
    #   FE24/FE25/FE26 marks fall here — plus the ⳿ U+2CFF delete), with
    #   the morph hyphen "-" and the status-pronominalis marker "⸗"
    #   (U+2E17, ×471) stripped first — the LexiconTeiParser fold-key
    #   contract, so a bare-form query lands on prefix/pronominal entries.
    #   Censused: no orth folds to empty.
    # - gloss: the first sense's English translation quote (fallback de,
    #   then fr; nil is honest for gloss-less entries).
    # - body: linearized entry — dialect-labeled forms, gramGrp, numbered
    #   senses with all three gloss languages and their print bibls, etym
    #   notes, cross-references.
    # - citations: NOT from the TEI. +etymologies+ (the ORAEC crosswalk,
    #   C-id → [hieroglyphic TLA lemma id, demotic TLA word id]) mints one
    #   DictionaryCitation per ancestor id — urn_raw in the sibling
    #   shelves' urn space (urn:nabu:dict:aed:<id>; urn:nabu:dict:
    #   tla-demotic:<id>, ids verbatim incl. the 220 negative demotic
    #   word numbers), cts_work/citation nil (these resolve through the
    #   links journal, never the CTS citation path).
    class CclTeiParser
      TEI_NS = { "tei" => "http://www.tei-c.org/ns/1.0" }.freeze

      LANGUAGE = "cop"
      AED_URN_PREFIX = "urn:nabu:dict:aed:"
      DEMOTIC_URN_PREFIX = "urn:nabu:dict:tla-demotic:"

      # Gloss preference: the define surface is English-first; de/fr stay
      # in the body verbatim.
      GLOSS_LANGS = %w[en de fr].freeze

      # Parse +path+ and return its DictionaryEntry values in file order.
      # +etymologies+ maps C-id => [hieroglyphic id, demotic id] (either
      # may be nil/empty — 350 rows are hieroglyphic-only, 482
      # demotic-only).
      def entries(path, etymologies: {})
        collected = []
        File.open(path) do |io|
          Nokogiri::XML::Reader(io, path).each do |node|
            next unless node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT
            next unless node.name == "entry"

            elem = Nokogiri::XML(node.outer_xml).root
            collected << build_entry(elem, etymologies)
          end
        end
        collected
      rescue Nokogiri::XML::SyntaxError => e
        raise Nabu::ParseError, "ccl-tei: malformed XML in #{path}: #{e.message}"
      end

      private

      def build_entry(elem, etymologies)
        entry_id = elem["xml:id"]
        raise Nabu::ParseError, "ccl-tei: entry without xml:id" if entry_id.nil?

        headword = headword(elem, entry_id)
        Nabu::DictionaryEntry.new(
          entry_id: entry_id, key_raw: entry_id, language: LANGUAGE,
          headword: headword,
          headword_folded: fold(headword),
          gloss: gloss(elem),
          body: body(elem),
          citations: crosswalk_citations(etymologies[entry_id])
        )
      end

      def headword(elem, entry_id)
        orth = elem.at_xpath(%(./tei:form[@type="lemma"]/tei:orth), TEI_NS) ||
               elem.at_xpath(".//tei:orth", TEI_NS)
        raise Nabu::ParseError, "ccl-tei: entry #{entry_id} has no orth" if orth.nil?

        Nabu::Normalize.nfc(collapse(orth.text))
      end

      # The lookup key (class note): morph hyphen and U+2E17 dropped, then
      # the cop search fold — the same both-sides contract lemma search
      # uses, which is what joins the Scriptorium's gold lemmas.
      def fold(headword)
        Nabu::Normalize.search_form(headword.delete("-⸗"), language: LANGUAGE)
      end

      def gloss(elem)
        sense = elem.at_xpath("./tei:sense", TEI_NS)
        return nil if sense.nil?

        GLOSS_LANGS.each do |lang|
          quote = sense.at_xpath(%(./tei:cit[@type="translation"]/tei:quote[@xml:lang="#{lang}"]), TEI_NS)
          text = quote && collapse(quote.text)
          return Nabu::Normalize.nfc(text) if text && !text.empty?
        end
        nil
      end

      # -- body linearization ---------------------------------------------------

      def body(elem)
        lines = [forms_line(elem), gram_line(elem)]
        elem.xpath("./tei:sense", TEI_NS).each_with_index do |sense, index|
          lines << sense_line(sense, index + 1)
        end
        lines << etym_line(elem)
        elem.xpath("./tei:xr", TEI_NS).each { |xr| lines << xr_line(xr) }
        Nabu::Normalize.nfc(lines.compact.reject(&:empty?).join("\n"))
      end

      # "S ⲕⲁϩ; B ⲁ⸗ (Status pronominalis)" — every form with its dialect
      # sigla and any form-level subcategory.
      def forms_line(elem)
        forms = elem.xpath("./tei:form", TEI_NS).map do |form|
          sigla = form.xpath("./tei:usg", TEI_NS).map { |usg| collapse(usg.text) }.reject(&:empty?)
          orth = form.at_xpath("./tei:orth", TEI_NS)
          subc = form.at_xpath("./tei:gramGrp/tei:subc", TEI_NS)
          parts = [sigla.join("/"), orth && collapse(orth.text)].reject { |part| part.nil? || part.empty? }
          next nil if parts.empty?

          "#{parts.join(' ')}#{" (#{collapse(subc.text)})" if subc}"
        end
        forms.compact.uniq.join("; ")
      end

      def gram_line(elem)
        gram = elem.at_xpath("./tei:gramGrp", TEI_NS)
        gram ? collapse(gram.text) : nil
      end

      # "1. de Erde, Boden | en earth, soil | fr terre — CD 131ab" (+ "ex."
      # example quotes and <def> prose when present).
      def sense_line(sense, number)
        parts = []
        sense.xpath("./tei:cit", TEI_NS).each do |cit|
          part = cit["type"] == "translation" ? translation_part(cit) : example_part(cit)
          parts << part unless part.nil? || part.empty?
        end
        sense.xpath("./tei:def", TEI_NS).each { |definition| parts << collapse(definition.text) }
        bibls = sense.xpath(".//tei:bibl", TEI_NS).map { |bibl| collapse(bibl.text) }.reject(&:empty?)
        line = parts.reject(&:empty?).join("; ")
        line = "#{line} — #{bibls.join(' · ')}" unless bibls.empty?
        "#{number}. #{line}"
      end

      def translation_part(cit)
        cit.xpath("./tei:quote", TEI_NS).filter_map do |quote|
          text = collapse(quote.text)
          next if text.empty?

          lang = quote["xml:lang"]
          lang ? "#{lang} #{text}" : text
        end.join(" | ")
      end

      def example_part(cit)
        quotes = cit.xpath("./tei:quote", TEI_NS).map { |quote| collapse(quote.text) }.reject(&:empty?)
        quotes.empty? ? nil : "ex. #{quotes.join(', ')}"
      end

      def etym_line(elem)
        etym = elem.at_xpath("./tei:etym", TEI_NS)
        return nil if etym.nil?

        text = collapse(etym.text)
        text.empty? ? nil : "etym: #{text}"
      end

      def xr_line(xref)
        refs = xref.xpath("./tei:ref", TEI_NS).map { |ref| collapse(ref.text) }.reject(&:empty?)
        return nil if refs.empty?

        "#{xref['type'] || 'cf'}: #{refs.join(', ')}"
      end

      # -- crosswalk citations --------------------------------------------------

      def crosswalk_citations(row)
        return [] if row.nil?

        hieroglyphic, demotic = row
        citations = []
        unless hieroglyphic.nil? || hieroglyphic.empty?
          citations << Nabu::DictionaryCitation.new(
            urn_raw: "#{AED_URN_PREFIX}#{hieroglyphic}", cts_work: nil, citation: nil,
            label: "TLA #{hieroglyphic} (hieroglyphic; ORAEC crosswalk)"
          )
        end
        unless demotic.nil? || demotic.empty?
          citations << Nabu::DictionaryCitation.new(
            urn_raw: "#{DEMOTIC_URN_PREFIX}#{demotic}", cts_work: nil, citation: nil,
            label: "TLA demotic #{demotic} (ORAEC crosswalk)"
          )
        end
        citations
      end

      def collapse(text)
        text.gsub(/\s+/, " ").strip
      end
    end
  end
end
