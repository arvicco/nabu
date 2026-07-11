# frozen_string_literal: true

require "nokogiri"

module Nabu
  module Adapters
    # Streaming parser for the OTA 3009 TEI-P5 file holding the complete
    # Anglo-Saxon Poetic Records (Krapp & Dobbie; machine-readable version
    # Hidley/Macrae-Gibson, P12-2) — the seventh bespoke parser family
    # (architecture §3), and deliberately the smallest: ONE uniform file, no
    # Leiden, no marker archaeology. A standalone, individually tested
    # component the Aspr adapter composes, in the UsfxParser
    # single-file-many-documents shape: #texts lists the inventory for
    # discover, #parse re-streams and extracts exactly one poem.
    #
    # == The format (verified against the full upstream file, P12-2 Phase A)
    #
    #   <text><body>
    #     <div rend="linenumber" xml:id="A4.1">
    #       <head>Beowulf</head>
    #       <bibl>Dobbie, 1953 3-98; …</bibl>
    #       <l>Hwæt! We Gardena <caesura/> in geardagum, </l>
    #
    # 349 flat divs (never nested), one per poem; the @xml:id is the poem's
    # canonical Cameron/DOE record number (A1.1 Genesis … A4.1 Beowulf …),
    # unique across the file. `<head>` is always plain text (a poem may carry
    # a duplicate second <head> — Meters of Boethius, Psalm fragments — so
    # the FIRST wins); `<bibl>` is the ASPR volume citation (metadata, never
    # passage text). NOT EpiDoc/CTS: no refsDecl, no l/@n anywhere.
    #
    # == Citation: 1-based line ordinal — which IS the ASPR line number
    #
    # One <l> = one passage, cited by its 1-based ordinal within the div.
    # The div carries rend="linenumber" and its <l> count matches the printed
    # ASPR edition exactly (Beowulf 3182, Judith 349 — verified), so the
    # ordinal is the canonical line number, not a GRETIL-style synthetic.
    #
    # == Inline markup policy (canonical means canonical)
    #
    # Text is captured ONLY inside <l> within the requested div; head/bibl/
    # teiHeader text never leaks. Within a line everything keeps its text:
    # <unclear> spans (editorially uncertain readings ARE the reading text),
    # <foreign xml:lang="rune"> runic letters, and <g ref="ecaudata">ę</g>
    # glyphs (mid-word: text nodes are concatenated raw, THEN whitespace-
    # collapsed, so "dom<g>ę</g>ldit" never gains a space). <caesura/> — the
    # half-line boundary, always space-padded upstream — reads as the space
    # between the verses. <gap/> (lacuna) is empty and contributes nothing;
    # a div-level <gap/> BETWEEN lines (Riddles 82) is not a line and does
    # not shift ordinals. Final text gets the house whitespace collapse and
    # NFC at the boundary (the upstream file is already NFC throughout).
    #
    # == Streaming
    #
    # The only Nokogiri entry point is Nokogiri::XML::Reader (the house rule;
    # the real file is 2.2 MB and holds 30,550 lines). #parse stops reading
    # at the requested div's end.
    class AsprParser
      # One poem of the inventory pass: Cameron id (the div @xml:id) + the
      # first <head> title.
      Text = Data.define(:id, :title)

      # List the poems of the file, in file order, without extracting text.
      def texts(path)
        inventory = []
        capture = false
        each_node(path) do |node|
          case [node.node_type, node.name]
          in [Nokogiri::XML::Reader::TYPE_ELEMENT, "div"]
            inventory << { id: node.attribute("xml:id"), title: nil }
          in [Nokogiri::XML::Reader::TYPE_ELEMENT, "head"]
            capture = inventory.any? && inventory.last[:title].nil?
          in [Nokogiri::XML::Reader::TYPE_END_ELEMENT, "head"]
            capture = false
          in [Nokogiri::XML::Reader::TYPE_TEXT | Nokogiri::XML::Reader::TYPE_CDATA, _] if capture
            inventory.last[:title] = node.value.strip
          else
            nil
          end
        end
        inventory.map { |text| Text.new(id: text[:id], title: text[:title]) }
      end

      # Extract one poem (by its Cameron +div_id+) into a Nabu::Document.
      # Raises Nabu::ParseError when the div is absent, yields no lines, or
      # the XML is malformed.
      def parse(path, div_id:, urn:, language:, title:)
        document = Nabu::Document.new(urn: urn, language: language, title: title,
                                      canonical_path: File.expand_path(path))
        extract_div(path, div_id, urn, language, document)
        raise ParseError, "#{path}: div #{div_id.inspect} yielded no lines" if document.empty?

        document
      rescue Nabu::ValidationError => e
        raise ParseError, "#{path}: div #{div_id.inspect}: #{e.message}"
      end

      private

      # One streaming pass; divs never nest, so a boolean suffices. Reading
      # stops at the requested div's END_ELEMENT.
      def extract_div(path, div_id, urn, language, document)
        state = { in_div: false, seen: false, in_line: false, text: +"" }
        each_node(path) do |node|
          if div_boundary(node, div_id, state) == :done
            break
          elsif state[:in_div]
            track_line(node, state) { |text| append_line(document, urn, language, text) }
          end
        end
        raise ParseError, "#{path}: div #{div_id.inspect} not found" unless state[:seen]
      end

      # Track entry/exit of the requested div; :done once its subtree is read.
      def div_boundary(node, div_id, state)
        return nil unless node.name == "div"

        case node.node_type
        when Nokogiri::XML::Reader::TYPE_ELEMENT
          state[:in_div] = node.attribute("xml:id") == div_id
          state[:seen] ||= state[:in_div]
        when Nokogiri::XML::Reader::TYPE_END_ELEMENT
          return :done if state[:in_div]
        end
        nil
      end

      # Capture character data only inside <l>; a line closes at its
      # END_ELEMENT. <caesura/>/<gap/> are empty elements and contribute
      # nothing; <unclear>/<foreign>/<g> keep their text (see header).
      def track_line(node, state)
        case [node.node_type, node.name]
        in [Nokogiri::XML::Reader::TYPE_ELEMENT, "l"]
          state[:in_line] = true
        in [Nokogiri::XML::Reader::TYPE_END_ELEMENT, "l"]
          state[:in_line] = false
          text = state[:text].split.join(" ")
          state[:text] = +""
          yield text unless text.empty?
        in [Nokogiri::XML::Reader::TYPE_TEXT | Nokogiri::XML::Reader::TYPE_CDATA |
            Nokogiri::XML::Reader::TYPE_SIGNIFICANT_WHITESPACE, _] if state[:in_line]
          # Whitespace-only nodes (Reader reports them as a distinct type)
          # matter: they separate sibling <foreign> runes — "D N L H.", not
          # "DNLH." — while the collapse keeps glyph-in-word joins tight.
          state[:text] << node.value
        else
          nil
        end
      end

      def append_line(document, urn, language, text)
        ordinal = document.size + 1
        document << Nabu::Passage.new(
          urn: "#{urn}:#{ordinal}",
          language: language,
          text: Normalize.nfc(text),
          sequence: document.size
        )
      end

      # The streaming spine: yield every reader node; malformed XML surfaces
      # as ParseError naming the file.
      def each_node(path, &)
        reader = Nokogiri::XML::Reader(File.open(path))
        reader.each(&)
      rescue Nokogiri::XML::SyntaxError => e
        raise ParseError, "#{path}: malformed ASPR TEI: #{e.message}"
      end
    end
  end
end
