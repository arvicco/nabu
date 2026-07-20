# frozen_string_literal: true

require "nokogiri"

require_relative "../normalize"

module Nabu
  module Adapters
    # The tls-xml parser family (P33-4): the eXist-db XML of the Thesaurus
    # Linguae Sericae (tls-kr/tls-data) — TEI-shaped, one small file per
    # record, two record shapes feeding the source's TWO dictionaries
    # (architecture §11; the hebrew-lexicon one-source/two-shelves grain):
    #
    #   concepts/<NAME>.xml — a TEI <div type="concept"> per onomasiological
    #     concept (3,018 distinct uuids censused 2026-07-20): <head> is the
    #     English concept name, then definition / altnames / translations /
    #     notes (old-chinese-criteria — Harbsmeier's synonym-group
    #     discussions — modern-chinese-criteria, huang-jingui,
    #     old-chinese-contrasts) / pointer lists (hypernymy 3,017, see 985,
    #     taxonymy 870, antonymy 594, mereonymy 90, wordnet 80 — <ref>
    #     targets are concept uuids) / source-references. The upstream
    #     <div type="words"> membership slot is EMPTY on 3,018 of 3,019
    #     files — membership lives on the words side, so the parser inverts
    #     it here (see +words+ index below).
    #
    #   words/<hex>/<uuid>.xml — a TEI <superEntry> per word (20,163 files,
    #     uuids unique; orths distinct on 20,159 — homographs are separate
    #     files): top-level <form><orth> is the headword, then one <entry>
    #     per word-x-concept assignment (34,808; every one carries
    #     tls:concept + tls:concept-id), each with pinyin/OC/MC <pron> rows
    #     and <sense> blocks (60,232: pos, tls:syn-func, tls:sem-feat,
    #     <usg> currency/valuation marks, <def>).
    #
    # == What one record yields (Nabu::DictionaryEntry)
    #
    # - entry_id: the record's xml:id uuid VERBATIM ("uuid-…") — the upsert
    #   key, and exactly what upstream pointer targets name, so hypernymy
    #   refs render as resolvable urn:nabu:dict:tls-concepts:<uuid> lines.
    #   The 30 duplicated <entry> uuids in the wild sit BELOW this grain
    #   (superEntry files are the entries here), so ids stay unique.
    # - key_raw: the concept <head> / superEntry <orth> verbatim.
    # - headword: same, NFC (censused: 0 non-NFC orths upstream).
    # - gloss: concepts — the first definition <p>; words — the first
    #   sense <def> of the first entry. nil is honest.
    # - body: structured plain text (house rule): definition, altnames,
    #   translations, the notes divs by type, pointer lines with target
    #   urns, source references, and the inverted member-word list
    #   (concepts) / per-entry concept + pron + sense lines (words). Sense
    #   uuids ride their lines verbatim — they are the join keys the
    #   111,484 upstream tls:ann attestations point at (notes/doc +
    #   notes/swl, NOT in the fetch cone; the deferred crosswalk needs
    #   them here).
    # - citations, reflexes: none. TLS attestations target seg ids of texts
    #   the catalog does not hold (and DictionaryCitation is CTS-shaped);
    #   concept->member edges are onomasiological, not etymological, so
    #   minting them as dictionary_reflexes would pollute the etym/cognates
    #   lanes (architecture §12) — both deliberately deferred, recorded in
    #   02-sources row 106.
    #
    # == Skip rules (censused by Tls#discovery_skips)
    #
    # - concepts: the ONE file with a percent-encoded Chinese basename
    #   ("%E5%AC%96…xml") duplicates CRONY.xml's uuid with different
    #   content — loading both would flap the revision on every sync, so
    #   any "%"-bearing basename is skipped by rule (no other concept file
    #   has one).
    # - words: the ONE superEntry with an EMPTY top orth
    #   (uuid-ea74382d-…, 477 orth-less entries — an upstream aggregate
    #   record) mints no headword and is skipped by rule.
    #
    # Files are small (largest concept 82 KB); DOM per file is the right
    # tool (the >5 MB SAX rule does not bite).
    class TlsXmlParser
      LANGUAGE = "och"

      TEI_NS = "http://www.tei-c.org/ns/1.0"
      TLS_NS = "http://hxwd.org/ns/1.0"

      CONCEPTS_URN_PREFIX = "urn:nabu:dict:tls-concepts:"

      # The pointer-list kinds censused upstream, rendered in this order.
      POINTER_KINDS = %w[hypernymy taxonymy antonymy mereonymy see wordnet].freeze

      # Concept files: one DictionaryEntry per concepts/*.xml (sorted by
      # basename), skipping percent-encoded strays. +members+ is the
      # inverted membership index from +member_index+ — nil renders an
      # honest entry without the words section (attic partials).
      def concept_entries(concepts_dir, members: nil)
        concept_files(concepts_dir).map { |path| build_concept_entry(path, members) }
      end

      # Word files: one DictionaryEntry per words/<hex>/*.xml (sorted by
      # relative path), skipping the empty-orth aggregate.
      def word_entries(words_dir)
        word_files(words_dir).filter_map { |path| build_word_entry(path) }
      end

      # concept uuid -> [[orth, pinyin, first sense def], …] in (orth, file)
      # order: the inversion of the words-side tls:concept-id assignments,
      # which is what puts member words back into concept bodies.
      def member_index(words_dir)
        index = Hash.new { |hash, key| hash[key] = [] }
        word_files(words_dir).each do |path|
          doc = parse_xml(path)
          orth = text_at(doc.root, "./tei:form/tei:orth")
          next if orth.empty?

          doc.root.xpath("./tei:entry", "tei" => TEI_NS).each do |entry|
            concept_id = entry.attribute_with_ns("concept-id", TLS_NS)&.value.to_s
            next if concept_id.empty?

            pinyin = text_at(entry, %(./tei:form/tei:pron[@xml:lang="zh-Latn-x-pinyin"]))
            first_def = text_at(entry, "./tei:sense/tei:def")
            index[concept_id] << [orth, pinyin, first_def]
          end
        end
        index.each_value(&:sort!)
        index
      end

      def concept_files(concepts_dir)
        Dir.glob(File.join(concepts_dir, "*.xml"))
           .reject { |path| skipped_concept_basename?(File.basename(path)) }
      end

      def word_files(words_dir)
        Dir.glob(File.join(words_dir, "*", "*.xml"))
      end

      # The stray detector shared with the discovery census: percent-encoded
      # basenames are the one known upstream defect class.
      def skipped_concept_basename?(basename)
        basename.include?("%")
      end

      # The words-side skip detector (shared with the census): a superEntry
      # whose top orth is empty cannot mint a headword.
      def skipped_word_file?(path)
        doc = parse_xml(path)
        text_at(doc.root, "./tei:form/tei:orth").empty?
      end

      private

      def build_concept_entry(path, members)
        doc = parse_xml(path)
        root = doc.root
        entry_id = xml_id!(root, path)
        head = text_at(root, "./tei:head")
        raise Nabu::ParseError, "tls: concept without <head>: #{path}" if head.empty?

        definition = root.xpath(%(./tei:div[@type="definition"]//tei:p), "tei" => TEI_NS)
                         .map { |node| squeeze(node.text) }.reject(&:empty?)

        lines = definition.map { |text| "definition: #{text}" }
        list_items(root, "altnames").then { |items| lines << "altnames: #{items.join('; ')}" unless items.empty? }
        translation_lines(root, lines)
        note_lines(root, lines)
        pointer_lines(root, lines)
        source_reference_lines(root, lines)
        member_lines(members ? members.fetch(entry_id, []) : [], lines)

        build_entry(entry_id: entry_id, key_raw: head, headword: head,
                    gloss: definition.first, lines: lines, path: path)
      end

      def build_word_entry(path)
        doc = parse_xml(path)
        root = doc.root
        entry_id = xml_id!(root, path)
        orth = text_at(root, "./tei:form/tei:orth")
        return nil if orth.empty? # the aggregate record — censused skip

        lines = ["word: #{orth}"]
        gloss = nil
        root.xpath("./tei:entry", "tei" => TEI_NS).each_with_index do |entry, index|
          gloss ||= first_present(entry.xpath("./tei:sense/tei:def", "tei" => TEI_NS).map { |node| squeeze(node.text) })
          entry_block_lines(entry, index, orth, lines)
        end

        build_entry(entry_id: entry_id, key_raw: orth, headword: orth,
                    gloss: gloss, lines: lines, path: path)
      end

      def entry_block_lines(entry, index, super_orth, lines)
        concept = entry.attribute_with_ns("concept", TLS_NS)&.value.to_s
        concept_id = entry.attribute_with_ns("concept-id", TLS_NS)&.value.to_s
        entry_orth = text_at(entry, "./tei:form/tei:orth")
        variant = entry_orth.empty? || entry_orth == super_orth ? "" : " (#{entry_orth})"
        concept_ref = concept_id.empty? ? concept : "#{concept} → #{CONCEPTS_URN_PREFIX}#{concept_id}"
        lines << "entry #{index + 1}#{variant} — concept: #{concept_ref}"

        pron_line(entry, lines)
        entry_note = squeeze(text_at(entry, "./tei:def"))
        lines << "note: #{entry_note}" unless entry_note.empty?
        entry.xpath("./tei:sense", "tei" => TEI_NS).each { |sense| sense_line(sense, lines) }
      end

      def pron_line(entry, lines)
        prons = { "pinyin" => "zh-Latn-x-pinyin", "oc" => "zh-x-oc", "mc" => "zh-x-mc" }
                .filter_map do |label, lang|
                  value = text_at(entry, %(./tei:form/tei:pron[@xml:lang="#{lang}"]))
                  "#{label}: #{value}" unless value.empty?
                end
        lines << prons.join(" | ") unless prons.empty?
      end

      def sense_line(sense, lines)
        sense_id = sense["xml:id"].to_s
        pos = text_at(sense, "./tei:gramGrp/tei:pos")
        syn_func = text_at(sense, "./tei:gramGrp/tls:syn-func")
        sem_feats = sense.xpath("./tei:gramGrp/tls:sem-feat", "tei" => TEI_NS, "tls" => TLS_NS)
                         .map { |node| squeeze(node.text) }.reject(&:empty?)
        usgs = sense.xpath("./tei:gramGrp/tei:usg", "tei" => TEI_NS)
                    .filter_map { |node| "#{node['type']}:#{squeeze(node.text)}" unless squeeze(node.text).empty? }
        definition = squeeze(text_at(sense, "./tei:def"))

        grammar = [pos, syn_func].reject(&:empty?).join(" ")
        grammar += " [#{sem_feats.join(', ')}]" unless sem_feats.empty?
        grammar += " (#{usgs.join(', ')})" unless usgs.empty?
        head = ["sense #{sense_id}".strip, grammar].reject(&:empty?).join(": ")
        lines << (definition.empty? ? head : "#{head} — #{definition}")
      end

      def translation_lines(root, lines)
        items = root.xpath(%(./tei:list[@type="translations"]/tei:item), "tei" => TEI_NS)
                    .filter_map do |item|
                      value = squeeze(item.text)
                      lang = item["xml:lang"].to_s
                      next if value.empty?

                      lang.empty? ? value : "#{lang} #{value}"
                    end
        lines << "translations: #{items.join('; ')}" unless items.empty?
      end

      # The notes divs, generically by @type — the censused kinds are
      # old-chinese-criteria / modern-chinese-criteria / huang-jingui /
      # old-chinese-contrasts, and a new kind must surface, not vanish.
      def note_lines(root, lines)
        root.xpath(%(./tei:div[@type="notes"]/tei:div[@type]), "tei" => TEI_NS).each do |div|
          paragraphs = div.xpath(".//tei:p", "tei" => TEI_NS).map { |node| squeeze(node.text) }.reject(&:empty?)
          next if paragraphs.empty?

          lines << "#{div['type']}:"
          lines.concat(paragraphs)
        end
      end

      def pointer_lines(root, lines)
        pointers = root.xpath(%(./tei:div[@type="pointers"]/tei:list[@type]), "tei" => TEI_NS)
                       .group_by { |list| list["type"].to_s }
        POINTER_KINDS.each do |kind|
          refs = Array(pointers[kind]).flat_map { |list| pointer_refs(list) }
          lines << "#{kind}: #{refs.join('; ')}" unless refs.empty?
        end
        (pointers.keys - POINTER_KINDS).sort.each do |kind|
          refs = pointers.fetch(kind).flat_map { |list| pointer_refs(list) }
          lines << "#{kind}: #{refs.join('; ')}" unless refs.empty?
        end
      end

      def pointer_refs(list)
        list.xpath("./tei:item/tei:ref", "tei" => TEI_NS).filter_map do |ref|
          label = squeeze(ref.text)
          target = ref["target"].to_s.delete_prefix("#")
          next if label.empty? && target.empty?

          target.empty? ? label : "#{label} → #{CONCEPTS_URN_PREFIX}#{target}"
        end
      end

      def source_reference_lines(root, lines)
        root.xpath(%(./tei:div[@type="source-references"]//tei:bibl), "tei" => TEI_NS).each do |bibl|
          parts = [text_at(bibl, "./tei:ref"), text_at(bibl, "./tei:title")].reject(&:empty?)
          scope = text_at(bibl, "./tei:biblScope")
          unit = bibl.at_xpath("./tei:biblScope", "tei" => TEI_NS)&.[]("unit").to_s
          parts << (unit.empty? ? scope : "#{unit} #{scope}") unless scope.empty?
          lines << "source: #{parts.join(' — ')}" unless parts.empty?
        end
      end

      def member_lines(members, lines)
        return if members.empty?

        lines << "words:"
        members.each do |orth, pinyin, definition|
          line = orth.dup
          line << " (#{pinyin})" unless pinyin.empty?
          line << " — #{definition}" unless definition.empty?
          lines << line
        end
      end

      def build_entry(entry_id:, key_raw:, headword:, gloss:, lines:, path:)
        Nabu::DictionaryEntry.new(
          entry_id: entry_id,
          key_raw: Nabu::Normalize.nfc(key_raw),
          language: LANGUAGE,
          headword: Nabu::Normalize.nfc(headword),
          headword_folded: Nabu::Normalize.search_form(headword, language: LANGUAGE),
          gloss: gloss.nil? || gloss.empty? ? nil : Nabu::Normalize.nfc(gloss),
          body: Nabu::Normalize.nfc(lines.join("\n"))
        )
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "tls: #{path}: #{e.message}"
      end

      def list_items(root, type)
        root.xpath(%(./tei:list[@type="#{type}"]/tei:item), "tei" => TEI_NS)
            .map { |item| squeeze(item.text) }.reject(&:empty?)
      end

      def xml_id!(root, path)
        id = root["xml:id"].to_s
        raise Nabu::ParseError, "tls: record without xml:id: #{path}" if id.empty?

        id
      end

      def parse_xml(path)
        doc = Nokogiri::XML(File.read(path), &:noblanks)
        raise Nabu::ParseError, "tls: unparseable XML: #{path}" if doc.root.nil?

        doc
      rescue Nokogiri::XML::SyntaxError => e
        raise Nabu::ParseError, "tls: #{path}: #{e.message}"
      end

      def text_at(node, xpath)
        squeeze(node.at_xpath(xpath, "tei" => TEI_NS, "tls" => TLS_NS)&.text.to_s)
      end

      def first_present(values)
        values.find { |value| !value.empty? }
      end

      def squeeze(text)
        text.gsub(/\s+/, " ").strip
      end
    end
  end
end
