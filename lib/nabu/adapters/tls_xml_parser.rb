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
    # - citations (P34-4 — the attestation crosswalk): one DictionaryCitation
    #   per distinct (sense uuid, seg id) attestation in notes/doc +
    #   notes/swl (one `<textid>-ann.xml` per attested TEXT; each tls:ann's
    #   <link target="#<seg> #<sense>"/> binds one word sense to one text
    #   segment). The seg-id grammar mirrors the mandoku pb-anchor grammar —
    #   `<text>_<edition>_<juan>-<leaf><side>[.line]` (99.7% censused
    #   2026-07-20) — so a KR-shaped text id claims cts_work
    #   urn:nabu:kanripo:<KR-id> and citation "<juan>:<page>", the kanripo
    #   PASSAGE key; Query::Define probes the page at query time and falls
    #   back to the held document when the held edition's pagination
    #   disagrees (TLS's juan/page division only sometimes matches). Non-KR
    #   text ids (TLS-side CH…, Taishō T…) mint display-only rows (nil
    #   cts_work) — no invented links. No reflexes: concept->member edges
    #   are onomasiological, not etymological — minting them as
    #   dictionary_reflexes would pollute the etym/cognates lanes
    #   (architecture §12); recorded in 02-sources row 106.
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

      # -- the attestation lane (P34-4) ---------------------------------------

      # The two notes/ subdirs of the sparse cone that carry tls:ann rows.
      NOTES_DIRS = %w[doc swl].freeze

      # The P33-3 Kanripo id grammar, and the passage-urn prefix frozen by
      # P33-0 — the crosswalk's target id space.
      KANRIPO_URN_PREFIX = "urn:nabu:kanripo:"
      KR_TEXT_ID = /\AKR\d[a-z]\d{4}\z/

      # The censused seg-id grammar: the mandoku pb-anchor shape with an
      # edition token and an optional line suffix. Strays (0.3%: CBETA-style
      # sentence ids, "-p0007a-s2-seg1a" subdivisions) keep text grain only.
      SEG_ANCHOR = /\A(?<text>[^_]+)_[^_]+_(?<juan>\d+)-(?<page>\d+[a-c])(?:\.(?<line>\d+))?\z/

      # One tls:ann occurrence: which seg, quoting what, from which titled
      # text (title/quote may be empty — honest absences).
      Attestation = Data.define(:seg, :title, :quote)

      # A seg id mapped to what it honestly supports: cts_work only for
      # KR-shaped text ids, citation (the kanripo passage key
      # "<juan>:<page>") only under the anchor grammar, ref as the
      # human-readable display form, sort_key for deterministic order.
      SegReference = Data.define(:text_id, :cts_work, :citation, :ref, :sort_key)

      # Concept files: one DictionaryEntry per concepts/*.xml (sorted by
      # basename), skipping percent-encoded strays. +members+ is the
      # inverted membership index from +member_index+ — nil renders an
      # honest entry without the words section (attic partials).
      # CONTENT-EMPTY concepts (the N-A.xml placeholder found at the
      # owner's first real sync 2026-07-20: head "N/A", empty definition
      # <p/>, no notes/pointers/members — an empty body would fail
      # validation and quarantine the whole shelf) skip by rule, censused
      # via +skipped_empty_concepts+.
      def concept_entries(concepts_dir, members: nil)
        @skipped_empty_concepts = 0
        concept_files(concepts_dir).filter_map { |path| build_concept_entry(path, members) }
      end

      # Content-empty concept files skipped by the last concept_entries
      # walk (1 upstream: N-A.xml).
      attr_reader :skipped_empty_concepts

      # Word files: one DictionaryEntry per words/<hex>/*.xml (sorted by
      # relative path), skipping the empty-orth aggregate. +attestations+ is
      # the attestation_index of a sibling notes/ dir — nil (no notes on
      # disk: pre-P34-4 checkouts, attic partials, the concepts-only case)
      # parses honestly citation-free.
      def word_entries(words_dir, attestations: nil)
        word_files(words_dir).filter_map { |path| build_word_entry(path, attestations) }
      end

      # sense uuid -> [Attestation…] across notes/doc + notes/swl (one
      # `<textid>-ann.xml` per attested text; both tls:ann shapes — the
      # doc-side prefixed and the swl-side default-namespace one — appear
      # upstream, so element lookups are namespace-agnostic). Files reach
      # 13 MB, so the reader STREAMS (the >5 MB SAX rule) and DOM-parses
      # each small ann subtree alone. (sense, seg) pairs dedupe on first
      # sight in sorted path order (the doc/swl overlap is real upstream:
      # 285 pairs censused 2026-07-20).
      def attestation_index(notes_dir)
        index = Hash.new { |hash, key| hash[key] = [] }
        seen = Set.new
        ann_files(notes_dir).each do |path|
          each_ann_fragment(path) do |ann|
            link = ann.at_xpath(%(.//*[local-name()="link"]))
            seg, sense = link&.[]("target").to_s.split.map { |token| token.delete_prefix("#") }
            next if seg.nil? || sense.nil? || !seen.add?([sense, seg])

            srcline = ann.at_xpath(%(.//*[local-name()="srcline"]))
            index[sense] << Attestation.new(seg: seg, title: squeeze(srcline&.[]("title").to_s),
                                            quote: squeeze(srcline&.text.to_s))
          end
        end
        index
      end

      # What one seg id honestly supports (class census note): text grain
      # whenever the id prefix is KR-shaped, page grain only under the
      # anchor grammar. Resolution happens at QUERY time (Query::Define);
      # nothing resolved is ever stored.
      def seg_reference(seg_id)
        text_id = seg_id[/\A[^_]+/].to_s
        cts_work = text_id.match?(KR_TEXT_ID) ? "#{KANRIPO_URN_PREFIX}#{text_id}" : nil
        match = SEG_ANCHOR.match(seg_id)
        unless match
          return SegReference.new(text_id: text_id, cts_work: cts_work, citation: nil,
                                  ref: seg_id, sort_key: [text_id, 0, 0, "", 0, seg_id])
        end

        ref = "#{match[:juan]}-#{match[:page]}#{match[:line] && ".#{match[:line]}"}"
        SegReference.new(
          text_id: text_id, cts_work: cts_work,
          citation: cts_work && "#{match[:juan]}:#{match[:page]}", ref: ref,
          sort_key: [text_id, match[:juan].to_i, match[:page].to_i, match[:page][-1], match[:line].to_i, seg_id]
        )
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

        if lines.empty?
          @skipped_empty_concepts += 1
          return nil
        end

        build_entry(entry_id: entry_id, key_raw: head, headword: head,
                    gloss: definition.first, lines: lines, path: path)
      end

      def build_word_entry(path, attestations = nil)
        doc = parse_xml(path)
        root = doc.root
        entry_id = xml_id!(root, path)
        orth = text_at(root, "./tei:form/tei:orth")
        return nil if orth.empty? # the aggregate record — censused skip

        lines = ["word: #{orth}"]
        sense_ids = []
        gloss = nil
        root.xpath("./tei:entry", "tei" => TEI_NS).each_with_index do |entry, index|
          gloss ||= first_present(entry.xpath("./tei:sense/tei:def", "tei" => TEI_NS).map { |node| squeeze(node.text) })
          entry_block_lines(entry, index, orth, lines, sense_ids)
        end

        build_entry(entry_id: entry_id, key_raw: orth, headword: orth, gloss: gloss, lines: lines, path: path,
                    citations: attestations ? citations_for(sense_ids, attestations) : [])
      end

      def entry_block_lines(entry, index, super_orth, lines, sense_ids = [])
        concept = entry.attribute_with_ns("concept", TLS_NS)&.value.to_s
        concept_id = entry.attribute_with_ns("concept-id", TLS_NS)&.value.to_s
        entry_orth = text_at(entry, "./tei:form/tei:orth")
        variant = entry_orth.empty? || entry_orth == super_orth ? "" : " (#{entry_orth})"
        concept_ref = concept_id.empty? ? concept : "#{concept} → #{CONCEPTS_URN_PREFIX}#{concept_id}"
        lines << "entry #{index + 1}#{variant} — concept: #{concept_ref}"

        pron_line(entry, lines)
        entry_note = squeeze(text_at(entry, "./tei:def"))
        lines << "note: #{entry_note}" unless entry_note.empty?
        entry.xpath("./tei:sense", "tei" => TEI_NS).each do |sense|
          sense_line(sense, lines)
          sense_id = sense["xml:id"].to_s
          sense_ids << sense_id unless sense_id.empty?
        end
      end

      # One DictionaryCitation per attestation of this word's senses, in
      # sense DOCUMENT order then (text, juan, page, line) — deterministic,
      # so content hashes never flap across parses (loader idempotency).
      def citations_for(sense_ids, attestations)
        sense_ids.flat_map do |sense_id|
          attestations.fetch(sense_id, [])
                      .map { |attestation| [attestation, seg_reference(attestation.seg)] }
                      .sort_by { |_, reference| reference.sort_key }
                      .map { |attestation, reference| attestation_citation(attestation, reference, sense_id) }
        end
      end

      # urn_raw is the upstream link target VERBATIM (canonical means
      # canonical); the label reads title + ref + quote and names its sense
      # uuid — the join key back to the body's sense lines.
      def attestation_citation(attestation, reference, sense_id)
        title = attestation.title.empty? ? reference.text_id : attestation.title
        label = "#{title} #{reference.ref}"
        label << " 「#{attestation.quote}」" unless attestation.quote.empty?
        label << " · sense #{sense_id}"
        Nabu::DictionaryCitation.new(urn_raw: "##{attestation.seg} ##{sense_id}",
                                     cts_work: reference.cts_work, citation: reference.citation,
                                     label: Nabu::Normalize.nfc(label))
      end

      def ann_files(notes_dir)
        NOTES_DIRS.flat_map { |sub| Dir.glob(File.join(notes_dir, sub, "*-ann.xml")) }.sort
      end

      # Stream one ann file (class note: 13 MB — never DOM whole), yielding
      # each ann element as its own small parsed fragment. outer_xml carries
      # the in-scope namespace declarations, so both upstream shapes parse.
      def each_ann_fragment(path)
        File.open(path) do |io|
          reader = Nokogiri::XML::Reader.from_io(io)
          reader.each do |node|
            next unless node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT
            next unless node.name.sub(/\A.*:/, "") == "ann"

            fragment = Nokogiri::XML(node.outer_xml)
            yield fragment.root if fragment.root
          end
        end
      rescue Nokogiri::XML::SyntaxError => e
        raise Nabu::ParseError, "tls: #{path}: #{e.message}"
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

      def build_entry(entry_id:, key_raw:, headword:, gloss:, lines:, path:, citations: [])
        Nabu::DictionaryEntry.new(
          entry_id: entry_id,
          key_raw: Nabu::Normalize.nfc(key_raw),
          language: LANGUAGE,
          headword: Nabu::Normalize.nfc(headword),
          headword_folded: Nabu::Normalize.search_form(headword, language: LANGUAGE),
          gloss: gloss.nil? || gloss.empty? ? nil : Nabu::Normalize.nfc(gloss),
          body: Nabu::Normalize.nfc(lines.join("\n")),
          citations: citations
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
