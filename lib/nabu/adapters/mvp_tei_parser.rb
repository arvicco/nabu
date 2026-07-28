# frozen_string_literal: true

require "nokogiri"

require_relative "../normalize"

module Nabu
  module Adapters
    # The mvp-tei parser family (P48-4): the DILA (Dharma Drum) Mahāvyutpatti
    # TEI P5 digital edition — one flat <body> of 308 <div> sections, each a
    # <head> (Chinese section title) and <entry key="…"> children. Every
    # entry (9,379 censused 2026-07-28) carries exactly one san-Latn + one
    # san-Deva <orth> pair and <cit type="translation"> quotes in zho-Hant /
    # bod-Latn / bod-Tibt. Streams with Nokogiri::XML::Reader (the 6.8 MB
    # member is over CLAUDE.md's no-DOM-over-5MB line) and DOM-parses one
    # ENTRY fragment at a time, the lexicon-tei pattern.
    #
    # == What one entry yields (Nabu::DictionaryEntry)
    #
    # - entry_id: the upstream @key, WHITESPACE-STRIPPED ("7752a " and
    #   "7752b " carry trailing spaces upstream — the only two), plus a
    #   positional ":<n>" suffix for the file's two duplicated keys
    #   (1055, 2347 — different words each time; the wiktionary-jsonl
    #   precedent: stable while upstream file order is stable).
    # - key_raw: the @key verbatim, spaces and all (canonical means
    #   canonical).
    # - headword: the san-Latn <orth> (IAST) — the glossary's own
    #   organization is Sanskrit-headed; language "san" so the shelf sits
    #   beside MW and the GRETIL/SARIT/DCS fold reaches it.
    # - gloss: the first bod-Latn quote (Wylie) — the Tibetan equivalent IS
    #   what this glossary exists to state.
    # - body: labeled lanes — "Sanskrit: <IAST> — <Devanāgarī>",
    #   "Tibetan: <Wylie> — <Tibetan script>", "Chinese: <quotes · joined>",
    #   "Section: <div head>". Empty sides degrade honestly (an empty
    #   bod-Tibt quote leaves the Wylie alone on its lane).
    # - citations: always empty — MVP quotes are unanchored (no CTS urns
    #   upstream), the Bosworth-Toller precedent.
    #
    # == Editorial markup (censused shapes, all of them in the fixture)
    #
    # - <add resp="ddbc">: DDBC's editorial additions are part of the
    #   current text — kept (×259).
    # - <del resp="ddbc">: editorially DELETED equivalents — dropped from
    #   lanes entirely, honoring upstream's own markup (×1,749, some
    #   self-closed/empty); a del-only quote contributes nothing.
    # - <choice><sic>…</sic><corr resp="ddbc">…</corr></choice>: rendered
    #   "sic (corr. corr)" so the transmitted text leads and the correction
    #   stays visible (×2,810).
    class MvpTeiParser
      ENTRY_ELEMENT = "entry"
      HEAD_ELEMENT = "head"
      LANGUAGE = "san"

      # Parse the TEI +xml+ string (streamed from disk or out of the
      # upstream zip by the adapter) and return DictionaryEntry values in
      # file order. +path+ names the origin in errors only.
      def entries(xml, path:)
        collected = []
        occurrences = Hash.new(0)
        section = nil
        Nokogiri::XML::Reader(xml, path).each do |node|
          next unless node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT

          case node.name
          when HEAD_ELEMENT
            section = squash(Nokogiri::XML(node.outer_xml).text)
          when ENTRY_ELEMENT
            collected << build_entry(entry_element(node), occurrences, section)
          end
        end
        collected
      rescue Nokogiri::XML::SyntaxError => e
        raise Nabu::ParseError, "mvp-tei: malformed XML in #{path}: #{e.message}"
      end

      private

      # One entry as a mini DOM. The Reader's outer_xml carries the
      # inherited TEI default namespace along, so parse it as a document
      # and strip namespaces once — plain css("orth") / css("cit") then
      # read naturally (the per-entry tree is tiny).
      def entry_element(node)
        document = Nokogiri::XML(node.outer_xml)
        document.remove_namespaces!
        document.root or raise Nabu::ParseError, "mvp-tei: unreadable <entry> fragment"
      end

      def build_entry(element, occurrences, section)
        apply_editorial_markup!(element)
        key = element["key"].to_s
        entry_id = positional_id(key.strip, occurrences)
        iast = orth_text(element, "san-Latn")
        wylie = quote_texts(element, "bod-Latn")

        Nabu::DictionaryEntry.new(
          entry_id: entry_id, key_raw: key, language: LANGUAGE,
          headword: Nabu::Normalize.nfc(iast),
          headword_folded: Nabu::Normalize.search_form(iast, language: LANGUAGE),
          gloss: wylie.first,
          body: body_text(element, iast: iast, wylie: wylie, section: section),
          citations: []
        )
      end

      def positional_id(id, occurrences)
        occurrences[id] += 1
        occurrences[id] > 1 ? "#{id}:#{occurrences[id]}" : id
      end

      # Deleted equivalents leave; sic/corr pairs render as
      # "sic (corr. corr)". Mutates the per-entry fragment once, before any
      # lane extraction.
      def apply_editorial_markup!(element)
        element.css("del").each(&:remove)
        element.css("choice").each do |choice|
          sic = squash(choice.at("sic")&.text.to_s)
          corr = squash(choice.at("corr")&.text.to_s)
          rendered = [sic, (corr.empty? ? nil : "(corr. #{corr})")].compact.reject(&:empty?).join(" ")
          choice.replace(Nokogiri::XML::Text.new(rendered, choice.document))
        end
      end

      def orth_text(element, lang)
        node = element.css("form > orth").find { |orth| orth["lang"] == lang }
        squash(node ? node.text : "")
      end

      def quote_texts(element, lang)
        element.css("cit").select { |cit| cit["lang"] == lang }
                          .map { |cit| squash(cit.text) }
                          .reject(&:empty?)
                          .map { |text| Nabu::Normalize.nfc(text) }
      end

      def body_text(element, iast:, wylie:, section:)
        lines = [
          lane("Sanskrit", [iast, orth_text(element, "san-Deva")]),
          lane("Tibetan", [wylie.join(" · "), quote_texts(element, "bod-Tibt").join(" · ")]),
          lane("Chinese", [quote_texts(element, "zho-Hant").join(" · ")]),
          section.to_s.empty? ? nil : "Section: #{section}"
        ]
        Nabu::Normalize.nfc(lines.compact.join("\n"))
      end

      # "Label: a — b" with empty sides dropped; nil when nothing remains.
      def lane(label, parts)
        kept = parts.reject { |part| part.to_s.empty? }
        kept.empty? ? nil : "#{label}: #{kept.join(' — ')}"
      end

      def squash(text)
        text.to_s.gsub(/\s+/, " ").strip
      end
    end
  end
end
