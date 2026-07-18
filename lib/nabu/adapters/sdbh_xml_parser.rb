# frozen_string_literal: true

require "nokogiri"

require_relative "../normalize"

module Nabu
  module Adapters
    # The sdbh-xml parser family (P30-2): the UBS Semantic Dictionary of
    # Biblical Hebrew's own XML — one <Lexicon> root, one <Lexicon_Entry>
    # per lemma (v0.9.2: 7,932 entries / 16,220 definitions / 23,879
    # glosses / 260,813 verse-word scripture references, all counts
    # measured 2026-07-18). The file is 37 MB, so this streams with
    # Nokogiri::XML::Reader (the lexicon-tei precedent) and DOM-parses one
    # ENTRY at a time — entries are small (the שׁוב outlier is ~142 KB).
    #
    # == What one entry yields (Nabu::DictionaryEntry)
    #
    # - entry_id: @Id verbatim ("000001000000000") — the stable upsert key.
    # - key_raw / headword: @Lemma BYTE-VERBATIM — 3,217 of the 7,932
    #   lemmas are not NFC-stable (Masoretic dagesh-before-vowel order),
    #   the P26-3 hbo/arc exemption; never normalized.
    # - language: "arc" when the entry's <StrongCodes> are non-empty and
    #   every code sits in the A (Aramaic) number space; "hbo" otherwise
    #   (H-codes present, mixed H+A, no codes at all, or the measured
    #   upstream quirks — an author name and bare digits inside <Strong>).
    #   The @HasAramaic attribute is deliberately NOT the signal: אֵב
    #   carries HasAramaic="true" with H+A codes and is a Hebrew lemma.
    # - headword_folded: Normalize.search_form over the lemma — NFC + mark
    #   strip leaves the consonantal skeleton, so a bare-consonant query
    #   (or an OSHB lemma) finds the pointed headword.
    # - gloss: the first non-empty <Gloss> of the first sense; nil for
    #   Notes-only entries (empty <LEXMeanings/>) — an honest absence.
    # - body: structured plain text (see #body) — Strong codes, semantic
    #   domains with their hierarchy codes, definitions, glosses,
    #   collocations/synonyms/antonyms, notes with {A:…}/{L:…} encodings
    #   verbatim. Reference COUNTS ride the body; the reference LISTS are
    #   citation rows.
    # - citations: one DictionaryCitation per <LEXReference>, verse-keyed
    #   against the oshb shelf (the MW→GRETIL document-urn shape):
    #   cts_work "urn:nabu:oshb:<book>", citation "<chapter>.<verse>".
    #   Note <Reference>s are footnote anchors, rendered in the body only.
    #
    # == The scripture-reference encoding (upstream README, verified)
    #
    # BBBCCCVVVSSWWW: Book 001–039 in Protestant OT order, Chapter, Verse,
    # Segment (always 00 for Hebrew — measured), Word ("counted using even
    # numbers only" — word element = WWW/2). Versification is MASORETIC
    # (measured: אֵב cites Dan 4:9/11/18 MT, not the English 4:12/14/21),
    # i.e. exactly the OSHB/WLC osisID versification — which is what makes
    # the verse-keyed join honest. 2,697 references carry a trailing
    # footnote marker ("…{N:001}"): the 14 digits parse, the raw string
    # rides urn_raw verbatim and the marker stays visible in the label.
    class SdbhXmlParser
      ENTRY_ELEMENT = "Lexicon_Entry"

      # SDBH book number (BBB, 1-indexed) → OSHB wlc file stem. Protestant
      # OT order; downcased stems are the oshb document urn tails
      # (urn:nabu:oshb:gen — the P26-3 minting).
      BOOKS = %w[
        Gen Exod Lev Num Deut Josh Judg Ruth 1Sam 2Sam
        1Kgs 2Kgs 1Chr 2Chr Ezra Neh Esth Job Ps Prov
        Eccl Song Isa Jer Lam Ezek Dan Hos Joel Amos
        Obad Jonah Mic Nah Hab Zeph Hag Zech Mal
      ].freeze

      REFERENCE_SHAPE = /\A(\d{3})(\d{3})(\d{3})\d{2}(\d{3})(.*)\z/m

      # Parse +path+ (or any IO-able file) and return DictionaryEntry
      # values in file order.
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
        raise Nabu::ParseError, "sdbh-xml: malformed XML in #{path}: #{e.message}"
      end

      private

      # One entry's subtree as its own small DOM (entries never nest).
      def entry_element(node)
        fragment = Nokogiri::XML.fragment(node.outer_xml)
        fragment.children.find(&:element?)
      end

      def build_entry(elem)
        entry_id = elem["Id"]
        lemma = elem["Lemma"]
        raise Nabu::ParseError, "sdbh-xml: Lexicon_Entry without @Id/@Lemma" if entry_id.nil? || lemma.nil?

        strongs = texts(elem, "./StrongCodes/Strong")
        language = entry_language(strongs)
        Nabu::DictionaryEntry.new(
          entry_id: entry_id, key_raw: lemma, language: language,
          headword: lemma,
          headword_folded: Nabu::Normalize.search_form(lemma, language: language),
          gloss: texts(elem, ".//Gloss").first,
          body: body(elem, strongs: strongs, language: language),
          citations: citations(elem)
        )
      end

      # arc iff every Strong code is in the Aramaic number space; anything
      # else — H codes, mixtures, no codes, the measured quirks — is hbo.
      def entry_language(strongs)
        strongs.any? && strongs.all? { |code| code.match?(/\AA\d/) } ? "arc" : "hbo"
      end

      # == Body composition (upstream element order)
      #
      #   strong: H0003 A0004
      #   language: arc                     (arc entries only)
      #   alternate: …                      (AlternateLemma, when any)
      #   note 1 (Jer 48:21 w15): {A:MT-K} | {A:MT-Q} מֵיפַעַת
      #   noun m                            (per BaseForm)
      #   related: חמץ                      (RelatedLemma words)
      #   related names: …                  (RelatedName words)
      #   1. (Vegetation 001002004) = part of a plant …
      #   synonyms: … / antonyms: … / collocations: …
      #   glosses: blossom; flower
      #   refs: 3
      def body(elem, strongs:, language:)
        lines = []
        lines << "strong: #{strongs.join(' ')}" if strongs.any?
        lines << "language: arc" if language == "arc"
        push_list(lines, "alternate", texts(elem, "./AlternateLemmas/AlternateLemma"))
        note_lines(elem, lines)
        meaning_no = 0
        elem.xpath("./BaseForms/BaseForm").each do |base|
          base_form_lines(base, lines)
          base.xpath("./LEXMeanings/LEXMeaning").each do |meaning|
            meaning_no += 1
            meaning_lines(meaning, meaning_no, lines)
          end
        end
        lines.join("\n")
      end

      def base_form_lines(base, lines)
        pos = texts(base, "./PartsOfSpeech/PartOfSpeech")
        lines << pos.join("; ") if pos.any?
        push_list(lines, "related", texts(base, "./RelatedLemmas/RelatedLemma/Word"))
        push_list(lines, "related names", texts(base, "./RelatedNames/RelatedName/Word"))
      end

      def meaning_lines(meaning, number, lines)
        head = "#{number}. #{domains(meaning)}"
        definition = text_of(meaning, ".//DefinitionShort")
        head = "#{head} #{definition}" if definition
        lines << head.rstrip
        long = text_of(meaning, ".//DefinitionLong")
        lines << "long: #{long}" if long
        push_list(lines, "synonyms", texts(meaning, "./LEXSynonyms/LEXSynonym"))
        push_list(lines, "antonyms", texts(meaning, "./LEXAntonyms/LEXAntonym"))
        push_list(lines, "coordinates", texts(meaning, "./LEXCoordinates/LEXCoordinate"))
        push_list(lines, "collocations", texts(meaning, "./LEXCollocations/LEXCollocation"))
        push_list(lines, "forms", texts(meaning, "./LEXForms/LEXForm"))
        push_list(lines, "valency", texts(meaning, "./LEXValencies/LEXValency"))
        push_list(lines, "glosses", texts(meaning, ".//Glosses/Gloss"))
        comments = text_of(meaning, ".//Comments")
        lines << "comments: #{comments}" if comments
        refs = meaning.xpath("./LEXReferences/LEXReference").size
        lines << "refs: #{refs}" if refs.positive?
      end

      # "(Vegetation 001002004)" — label + hierarchy code per domain,
      # "·"-joined; empty-label domains keep their code (208 measured).
      def domains(meaning)
        rendered = meaning.xpath("./LEXDomains/LEXDomain").map do |domain|
          [collapse(domain.text), domain["Code"]].reject { |part| part.nil? || part.empty? }.join(" ")
        end.reject(&:empty?)
        rendered.any? ? "(#{rendered.join(' · ')})" : nil
      end

      # Entry-level Notes: the footnote texts entries reference as {N:001}.
      # Their <Reference>s render as verse labels here and mint NO citation
      # rows (footnote anchors, not lexical attestations).
      def note_lines(elem, lines)
        elem.xpath("./Notes/Note").each_with_index do |note, index|
          content = text_of(note, "./Content") or next
          refs = texts(note, "./References/Reference").filter_map { |raw| reference_label(raw) }
          anchor = refs.any? ? "note #{index + 1} (#{refs.join('; ')})" : "note #{index + 1}"
          lines << "#{anchor}: #{content}"
        end
      end

      def citations(elem)
        elem.xpath(".//LEXReferences/LEXReference").filter_map do |ref|
          raw = ref.text
          next if raw.strip.empty?

          parts = reference_parts(raw)
          Nabu::DictionaryCitation.new(
            urn_raw: raw,
            cts_work: parts && "urn:nabu:oshb:#{parts.fetch(:stem).downcase}",
            citation: parts && "#{parts.fetch(:chapter)}.#{parts.fetch(:verse)}",
            label: parts ? parts.fetch(:label) : raw
          )
        end
      end

      # BBBCCCVVVSSWWW(+optional footnote marker) → stem/chapter/verse and
      # the display label ("Isa 1:17 w6 {N:001}"). nil for a code outside
      # the 39-book space (none measured — defensive; the raw rides the
      # label so nothing is lost).
      def reference_parts(raw)
        match = REFERENCE_SHAPE.match(raw) or return nil
        stem = BOOKS[match[1].to_i - 1] or return nil

        chapter = match[2].to_i
        verse = match[3].to_i
        word = match[4].to_i / 2
        label = "#{stem} #{chapter}:#{verse} w#{word}"
        rest = match[5].strip
        label = "#{label} #{rest}" unless rest.empty?
        { stem: stem, chapter: chapter, verse: verse, label: label }
      end

      def reference_label(raw)
        parts = reference_parts(raw)
        parts ? parts.fetch(:label) : collapse(raw)
      end

      def push_list(lines, label, values)
        lines << "#{label}: #{values.join('; ')}" if values.any?
      end

      # Non-empty collapsed text values of +xpath+ under +node+.
      def texts(node, xpath)
        node.xpath(xpath).map { |child| collapse(child.text) }.reject(&:empty?)
      end

      def text_of(node, xpath)
        found = node.at_xpath(xpath) or return nil
        text = collapse(found.text)
        text.empty? ? nil : text
      end

      # Whitespace collapse only — never NFC: Hebrew rides these strings and
      # the Masoretic mark order is byte-canonical (see class note).
      def collapse(text)
        text.gsub(/\s+/, " ").strip
      end
    end
  end
end
