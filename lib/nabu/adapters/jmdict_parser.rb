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

      # The sense-level label elements mined into entry annotations (the
      # entry-facet seam; config/facet_map.yml rules them as domain /
      # usage / dialect). Each value is the entity TEXT the internal DTD
      # expands the tag to ("&comp;" → "computing") — what the NOENT reader
      # yields, and upstream's own one-to-one gloss of the code. Census
      # over the held JMdict_e (2026-07-29 build, 218k entries): <field>
      # 34,235 (comp 10,750 · med 2,688 · food 1,872 · Buddh 1,524 · law
      # 933 …), <misc> all of it (uk 11,763 · abbr 4,644 · arch 3,781 ·
      # hist 2,908 · col · sl · hon … — register and word-type marks
      # together, kept whole: the split is the facet reader's call, never
      # a silent drop here), <dial> 610.
      LABEL_ELEMENTS = %w[field misc dial].freeze

      # <lsource> (6,313 censused): the loanword source language as an
      # ISO 639-2 code, DTD default "eng" when xml:lang is absent (every
      # wasei element but a handful omits it); ls_wasei="y" (2,048) marks
      # wasei-eigo — a word Japan MADE from the donor's elements, so it
      # annotates its own key and never mints a borrowing edge;
      # ls_type="part" says the source word covers only part of the
      # Japanese word (still a genuine loan edge; the flag rides the body).
      LSOURCE_DEFAULT_LANG = "eng"

      # ISO 639-2/B bibliographic codes in the census → the ISO 639-3 tag
      # the catalog speaks (the terminology code; scr is the retired 639-2
      # Croatian code). Every other censused code is already a 639-3 (or
      # 639-5 collective: alg, bnt) tag and passes through.
      DONOR_LANGUAGES = {
        "fre" => "fra", "ger" => "deu", "chi" => "zho", "dut" => "nld", "gre" => "ell",
        "may" => "msa", "tib" => "bod", "per" => "fas", "geo" => "kat", "cze" => "ces",
        "rum" => "ron", "mao" => "mri", "ice" => "isl", "bur" => "mya", "arm" => "hye",
        "alb" => "sqi", "scr" => "hrv"
      }.freeze

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
          crossrefs: crossrefs(element),
          reflexes: donor_reflexes(element),
          annotations: annotations(element)
        )
      end

      # The entry's sense labels and loan-source codes (constant notes),
      # deduped across senses in document order; absent kinds omitted.
      def annotations(element)
        out = {}
        LABEL_ELEMENTS.each do |name|
          values = element.xpath(".//sense/#{name}").map { |node| Normalize.nfc(node.text.strip) }
                                                    .reject(&:empty?).uniq
          out[name] = values unless values.empty?
        end
        lsources = element.xpath(".//sense/lsource")
        { "lsource" => lsources.reject { |node| wasei?(node) },
          "wasei" => lsources.select { |node| wasei?(node) } }.each do |key, nodes|
          codes = nodes.map { |node| donor_code(node) }.uniq
          out[key] = codes unless codes.empty?
        end
        out
      end

      # One borrowed: true reflex per genuine loan source naming a donor
      # word (the WOLD donor-edge shape): lang_code the upstream code
      # verbatim, language its catalog tag, folded in that language.
      # Wasei sources and word-less <lsource/> mint none.
      def donor_reflexes(element)
        element.xpath(".//sense/lsource").filter_map do |node|
          word = Normalize.nfc(node.text.strip)
          next if word.empty? || wasei?(node)

          code = donor_code(node)
          language = DONOR_LANGUAGES.fetch(code, code)
          language = nil unless language.match?(Nabu::Model::Validation::LANGUAGE_SHAPE)
          Nabu::DictionaryReflex.new(lang_code: code, language: language, word: word,
                                     word_folded: language && donor_fold(word, language), borrowed: true)
        end.uniq
      end

      def donor_fold(word, language)
        folded = Normalize.search_form(word, language: language)
        folded.strip.empty? ? nil : folded
      end

      def donor_code(node)
        code = node["xml:lang"].to_s.strip
        code.empty? ? LSOURCE_DEFAULT_LANG : code
      end

      def wasei?(node) = node["ls_wasei"] == "y"

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

      # "1. (pos) [labels] gloss; gloss ← donor" — the pos annotation rides
      # in prose (the NOENT-expanded entity text), then the field/misc/dial
      # labels, then the loan sources; each part omitted when absent.
      def sense_line(sense, index)
        glosses = sense.xpath(".//gloss").map(&:text)
        return nil if glosses.empty?

        pos = sense.xpath(".//pos").map(&:text)
        label = pos.empty? ? "" : " (#{pos.join('; ')})"
        marks = LABEL_ELEMENTS.flat_map { |name| sense.xpath(name).map { |node| node.text.strip } }.reject(&:empty?)
        label += " [#{marks.join('; ')}]" unless marks.empty?
        "#{index + 1}.#{label} #{glosses.join('; ')}#{loan_suffix(sense)}"
      end

      # " ← eng pie (part); fre choux (part)" / " ← wasei eng calc" / " ← rus".
      def loan_suffix(sense)
        parts = sense.xpath("lsource").map do |node|
          word = node.text.strip
          bits = [wasei?(node) ? "wasei" : nil, donor_code(node), word.empty? ? nil : word]
          bits << "(part)" if node["ls_type"] == "part"
          bits.compact.join(" ")
        end
        parts.empty? ? "" : " ← #{parts.join('; ')}"
      end
    end
  end
end
