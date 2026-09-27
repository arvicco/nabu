# frozen_string_literal: true

require "nokogiri"

module Nabu
  module Adapters
    # The 84000 glossary lane (P106-4 — the P48 follow-up executed): each
    # publication's back-matter <div type="glossary"> holds entity records
    # — <gloss type="term|person|place|…"> with the English rendering, the
    # attested Tibetan (script + Wylie), the Sanskrit, and a definition —
    # the desk's largest Tibetan–Sanskrit–English term bank, parsed AROUND
    # since P48. They ride the P104-4 secondary dictionary lane
    # (Adapter.dictionary_lane, the oracc pilot's seam) into ONE shared
    # shelf, slug "e84000-glossary", beside mvp.
    #
    # Headword ladder: the Tibetan-script term (trailing shad stripped so
    # the folded form meets EWTS-typed queries — the verbatim string keeps
    # its shad in key_raw), else the Wylie, else the English rendering.
    # Language is xct throughout (the derge shelves' code; the №R-69 v1
    # limit — one code per dictionary — is a ruled posture, and the
    # Sanskrit/English lanes ride the body). Two upstream gloss shapes are
    # both real and both parsed: bare <term> + <term type="definition">
    # and <term type="translationMain"> + <note type="definition">.
    #
    # Discovery DELEGATES to the primary adapter (same published cone,
    # same duplicate-pair winner rule, placeholders never discovered), so
    # the lane can never disagree with the passage shelf about which
    # edition of a renamed publication is live.
    class E84000GlossaryLane < Nabu::Adapter
      SLUG = "e84000-glossary"
      LANGUAGE = "xct"
      TITLE = "84000 glossary — Tibetan-Sanskrit-English entity records (back matter)"
      REF_PREFIX = "e84000-gloss:"
      XML_NS = "http://www.w3.org/XML/1998/namespace"
      # Tibetan shad/double-shad (and stray whitespace) trail most bo
      # terms; folding keeps them, so EWTS queries would never match.
      TRAILING_SHAD = /[\s་]*[།༎]+\s*\z/

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        E84000.new.discover(workdir)
              .select { |ref| gloss_bearing?(ref.path) }
              .map do |ref|
          Nabu::DocumentRef.new(
            source_id: ref.source_id,
            id: "#{REF_PREFIX}#{ref.id.delete_prefix(E84000::URN_PREFIX)}",
            path: ref.path, metadata: ref.metadata
          )
        end.each(&block)
      end

      # One DictionaryDocument per publication file (the loader upserts by
      # (dictionary, entry_id) across files — DictionaryDocument's LSJ
      # contract); a publication without a glossary yields it empty,
      # honestly. Reader-streamed to the glossary items so a long sutra
      # never DOM-parses whole (the >5 MB TEI rule).
      def parse(document_ref)
        document = Nabu::DictionaryDocument.new(
          slug: SLUG, language: LANGUAGE, title: TITLE,
          canonical_path: document_ref.path
        )
        each_gloss(document_ref.path) do |node|
          entry = self.class.build_entry(node)
          document << entry if entry
        end
        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "e84000 glossary #{document_ref.id}: #{e.message}"
      end

      # The unit seam for the headword ladder (bo → Wylie → English);
      # fields is the extracted record, nil values honest.
      def self.build_entry_from(fields)
        raw = fields[:bo] || fields[:wylie] || fields[:en]
        return nil if raw.nil? || fields[:id].nil?

        raw = Normalize.nfc(raw)
        headword = raw.sub(TRAILING_SHAD, "").strip
        return nil if headword.empty?

        folded = Normalize.search_form(headword, language: LANGUAGE)
        Nabu::DictionaryEntry.new(
          entry_id: fields[:id], key_raw: raw, language: LANGUAGE,
          headword: headword,
          headword_folded: folded.nil? || folded.empty? ? headword : folded,
          gloss: fields[:en] && Normalize.nfc(fields[:en]),
          body: entry_body(fields)
        )
      end

      # One <gloss> element → the extracted record. Terms without xml:lang
      # are the English rendering (the bare shape) or carry translation*
      # types (the translationMain shape); type="definition" is the old
      # inline definition, <note type="definition"> the new one.
      def self.build_entry(node)
        terms = node.xpath("./*[local-name()='term']")
        build_entry_from(
          id: xml_attr(node, "id"),
          type: node["type"],
          en: english_term(terms),
          bo: lang_terms(terms, "bo").first,
          wylie: lang_terms(terms, "Bo-Ltn").first,
          skt: lang_terms(terms, "Sa-Ltn").first,
          bo_all: lang_terms(terms, "bo"),
          wylie_all: lang_terms(terms, "Bo-Ltn"),
          skt_all: lang_terms(terms, "Sa-Ltn"),
          definition: definition_text(node, terms)
        )
      end

      def self.entry_body(fields)
        lines = []
        headline = [fields[:en], fields[:type] && "type: #{fields[:type]}"].compact
        lines << (headline.size == 2 ? "#{headline[0]} (#{headline[1]})" : headline.first) unless headline.empty?
        { "bo" => fields[:bo_all] || [fields[:bo]].compact,
          "wylie" => fields[:wylie_all] || [fields[:wylie]].compact,
          "skt" => fields[:skt_all] || [fields[:skt]].compact }.each do |label, values|
          values = Array(values).compact.reject(&:empty?)
          lines << "#{label}: #{values.join(' · ')}" unless values.empty?
        end
        lines << fields[:definition] unless fields[:definition].to_s.strip.empty?
        Normalize.nfc(lines.join("\n"))
      end

      def self.english_term(terms)
        candidate = terms.find do |term|
          xml_attr(term, "lang").nil? &&
            (term["type"].nil? || term["type"].start_with?("translation"))
        end
        text_of(candidate)
      end

      def self.lang_terms(terms, lang)
        terms.select { |term| xml_attr(term, "lang") == lang }
             .filter_map { |term| text_of(term) }
      end

      def self.definition_text(node, terms)
        inline = terms.find { |term| term["type"] == "definition" }
        return text_of(inline) if inline

        note = node.xpath("./*[local-name()='note'][@type='definition']").first
        text_of(note)
      end

      def self.text_of(node)
        return nil if node.nil?

        text = node.text.gsub(/\s+/, " ").strip
        text.empty? ? nil : text
      end

      def self.xml_attr(node, name)
        node.attribute_with_ns(name, XML_NS)&.value
      end

      # const: discovery-grain containment probe — a publication without a
      # single <gloss element (most placeholder-era and some early
      # translations) is never a lane ref, so every discovered ref parses
      # to a non-empty shelf document (the lane conformance contract).
      GLOSS_MARKER = "<gloss"
      PROBE_CHUNK = 1 << 20

      private

      def gloss_bearing?(path)
        File.open(path, "rb") do |io|
          carry = +""
          while (chunk = io.read(PROBE_CHUNK))
            return true if (carry + chunk).include?(GLOSS_MARKER)

            carry = chunk[-GLOSS_MARKER.length..] || chunk
          end
        end
        false
      end

      # Stream to each glossary <gloss> (any depth inside a glossary div);
      # only the gloss element itself is DOM-parsed (a few hundred bytes).
      def each_gloss(path)
        depth = 0
        reader = Nokogiri::XML::Reader(File.open(path, "rb"))
        reader.each do |node|
          case node.node_type
          when Nokogiri::XML::Reader::TYPE_ELEMENT
            if node.local_name == "div" && !node.self_closing?
              # Depth counts EVERY open div while inside the glossary
              # (its section sub-divs must not close it early).
              depth += 1 if depth.positive? || glossary_div?(node)
            elsif depth.positive? && node.local_name == "gloss"
              fragment = Nokogiri::XML(node.outer_xml, nil, "UTF-8", &:recover).root
              yield fragment if fragment
            end
          when Nokogiri::XML::Reader::TYPE_END_ELEMENT
            depth -= 1 if depth.positive? && node.local_name == "div"
          end
        end
      end

      # <div type="glossary"> — prefixed (tei:div) or not; nested plain
      # divs inside it are balanced by counting every div end while inside.
      def glossary_div?(node)
        node.local_name == "div" && node.attribute("type") == "glossary"
      end
    end
  end
end
