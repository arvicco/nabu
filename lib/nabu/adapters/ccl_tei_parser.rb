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
    # - citations: NOT from the TEI. +etymologies+ (C-id → Ccl::Etymology,
    #   the ORAEC crosswalk + KELLIA tab composed by Ccl.merge_etymologies
    #   since P89-2) mints one DictionaryCitation per ancestor id — urn_raw
    #   in the sibling shelves' urn space (urn:nabu:dict:aed:<id>;
    #   urn:nabu:dict:tla-demotic:<id>, ids in the ORAEC convention incl.
    #   the 220 negative demotic word numbers), the label crediting the
    #   attesting witness(es), cts_work/citation nil (these resolve through
    #   the links journal, never the CTS citation path). KELLIA's
    #   transcriptions and EN/DE glosses (owner ruling 2026-08-30, option c) ride as a `tla:` body
    #   line.
    # - crossrefs (P124-3): one headword-keyed DictionaryCrossref per
    #   <xr type><ref target="#<headword>"> anywhere in the entry (kind per
    #   XR_KINDS; the ref text — a German gloss — rides the label; the
    #   target folds through the shelf's own fold, so it meets
    #   headword_folded). Census 2026-10-13 over v1.2: 2,611 <xr> (cf
    #   2,489, syn 118, ant 4; 2,550 entry-level, 54 in a sense, 7 in an
    #   etym) carrying 2,614 refs, every target a "#headword" string — no
    #   C-id targets — on 2,070 entries. The CCL's homograph grain (ⲁ-
    #   names four entries) keeps most verbatim under the unique-match
    #   rule: 796 resolve, 1,716 meet several homographs, 102 name no
    #   headword.
    # - reflexes: the Coptic → Greek BORROWING edges. The DDGLC (Database
    #   and Dictionary of Greek Loanwords in Coptic) half of the lexicon
    #   states each loanword's Greek source lemma inside <etym> as
    #   <ref type="greek_lemma::grl_lemma"> (with grl_ID/meaning/pos/ref
    #   siblings) — 3,229 of 11,284 entries in v1.2, exactly one each. One
    #   DictionaryReflex per such ref: lang_code/language grc, the Greek
    #   lemma verbatim (NFC), folded as Greek, borrowed true, relation
    #   "borrowed" (the kaikki {{bor}} spelling — the donor is the entry's
    #   own etymon, an UP edge the descent walks skip), so `define ⲧⲟⲡⲟⲥ`
    #   states "borrowed grc τόπος" on its etymon line, resolved to the
    #   Greek shelf entry when exactly one holds it. These are the dictionary side of Coptic Scriptorium's
    #   language-of-origin tags: the corpus lemmatizes to these same
    #   CDO/CCL headwords. Census 2026-10-22 (held catalog, gold lemmas):
    #   2,034 Greek-tagged lemma types / 23,488 tokens — 944 types / 20,765
    #   tokens (88%) fold onto a DDGLC entry carrying its Greek donor; 1,043
    #   types / 2,515 tokens have no CCL entry at all (proper names —
    #   ⲡⲉⲧⲣⲟⲥ, ⲡⲁⲩⲗⲟⲥ, ⲡⲓⲗⲁⲧⲟⲥ — and spelling variants such as ϩⲁⲅⲓⲟⲥ);
    #   47 types / 208 tokens meet a native entry (tagging slips on ⲟⲩ,
    #   ϩⲁⲡ). Not donors, deliberately: prose etym <note>s ("persisches
    #   Lehnwort") name a language but no word, and the 587
    #   <ref type="Greek"> are Crum's Greek TRANSLATION equivalents for
    #   native words (κόραξ for the raven) — both stay in the body. The
    #   adapter stays OUT of reflex_bearing? (the JMdict precedent): these
    #   rows carry no upstream language NAME, so the language_names census
    #   that promise also checks could never fill.
    class CclTeiParser
      TEI_NS = { "tei" => "http://www.tei-c.org/ns/1.0" }.freeze

      LANGUAGE = "cop"
      AED_URN_PREFIX = "urn:nabu:dict:aed:"
      DEMOTIC_URN_PREFIX = "urn:nabu:dict:tla-demotic:"

      # Gloss preference: the define surface is English-first; de/fr stay
      # in the body verbatim.
      GLOSS_LANGS = %w[en de fr].freeze

      # The DDGLC Greek source-lemma ref (class note).
      GREEK_LEMMA_XPATH = %(./tei:etym/tei:ref[@type="greek_lemma::grl_lemma"])
      GREEK = "grc"

      # P124-3: xr @type => [kind, printed label prefix].
      XR_KINDS = { "cf" => ["cf.", "cf."], "syn" => ["synonym", "syn."], "ant" => ["antonym", "ant."] }.freeze

      # Parse +path+ and return its DictionaryEntry values in file order.
      # +etymologies+ maps C-id => Ccl::Etymology (either id may be nil —
      # 350 ORAEC rows are hieroglyphic-only, 482 demotic-only).
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
        etymology = etymologies[entry_id]
        Nabu::DictionaryEntry.new(
          entry_id: entry_id, key_raw: entry_id, language: LANGUAGE,
          headword: headword,
          headword_folded: fold(headword),
          gloss: gloss(elem),
          body: body(elem, etymology),
          citations: crosswalk_citations(etymology),
          crossrefs: crossrefs(elem),
          reflexes: greek_donors(elem)
        )
      end

      # The DDGLC borrowing edges (class note): one borrowed grc donor
      # reflex per Greek source-lemma ref, duplicates minted once.
      def greek_donors(elem)
        elem.xpath(GREEK_LEMMA_XPATH, TEI_NS).filter_map do |ref|
          word = Nabu::Normalize.nfc(collapse(ref.text))
          next if word.empty?

          folded = Nabu::Normalize.search_form(word, language: GREEK)
          Nabu::DictionaryReflex.new(lang_code: GREEK, language: GREEK, word: word,
                                     word_folded: folded.empty? ? nil : folded,
                                     borrowed: true, relation: "borrowed")
        end.uniq
      end

      # P124-3: the xr pointers (census in the class note).
      def crossrefs(elem)
        elem.xpath(".//tei:xr/tei:ref[@target]", TEI_NS).filter_map do |ref|
          target = Nabu::Normalize.nfc(collapse(ref["target"].delete_prefix("#")))
          next if target.empty?

          kind, prefix = XR_KINDS.fetch(ref.parent["type"].to_s, XR_KINDS.fetch("cf"))
          gloss = collapse(ref.text)
          label = gloss.empty? ? "#{prefix} #{target}" : "#{prefix} #{target} (#{gloss})"
          folded = fold(target)
          Nabu::DictionaryCrossref.new(kind: kind, label: Nabu::Normalize.nfc(label), target: target,
                                       target_folded: folded.strip.empty? ? nil : folded)
        end
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

      def body(elem, etymology = nil)
        lines = [forms_line(elem), gram_line(elem)]
        elem.xpath("./tei:sense", TEI_NS).each_with_index do |sense, index|
          lines << sense_line(sense, index + 1)
        end
        lines << etym_line(elem)
        lines << tla_line(etymology)
        elem.xpath("./tei:xr", TEI_NS).each { |xr| lines << xr_line(xr) }
        Nabu::Normalize.nfc(lines.compact.reject(&:empty?).join("\n"))
      end

      # "tla: egy ꜥ.t · dem ꜥrwe.t — en (lotus) stalk; stem | de Stängel
      # (Lotos, Schilf) [KELLIA etymologies]" — the transcriptions and
      # glosses only the KELLIA tab carries (owner ruling 2026-08-30, option c); nil when the tab
      # is absent or contributed nothing for this entry.
      def tla_line(etymology)
        return nil if etymology.nil?

        lemmas = []
        lemmas << "egy #{collapse(etymology.egy_lemma)}" if etymology.egy_lemma
        lemmas << "dem #{collapse(etymology.demo_lemma)}" if etymology.demo_lemma
        glosses = []
        glosses << "en #{collapse(etymology.gloss_en)}" if etymology.gloss_en
        glosses << "de #{collapse(etymology.gloss_de)}" if etymology.gloss_de
        return nil if lemmas.empty? && glosses.empty?

        line = [lemmas.join(" · "), glosses.join(" | ")].reject(&:empty?).join(" — ")
        "tla: #{line} [KELLIA etymologies]"
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

      def crosswalk_citations(etymology)
        return [] if etymology.nil?

        citations = []
        if etymology.hieroglyphic
          citations << Nabu::DictionaryCitation.new(
            urn_raw: "#{AED_URN_PREFIX}#{etymology.hieroglyphic}", cts_work: nil, citation: nil,
            label: "TLA #{etymology.hieroglyphic} (hieroglyphic; " \
                   "#{etymology.hieroglyphic_witnesses.join(' + ')})"
          )
        end
        if etymology.demotic
          citations << Nabu::DictionaryCitation.new(
            urn_raw: "#{DEMOTIC_URN_PREFIX}#{etymology.demotic}", cts_work: nil, citation: nil,
            label: "TLA demotic #{etymology.demotic} (#{etymology.demotic_witnesses.join(' + ')})"
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
