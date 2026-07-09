# frozen_string_literal: true

require "nokogiri"

module Nabu
  module Adapters
    # Streaming parser for one USFX bible file (P11-5) — the eBible.org
    # milestone dialect the Clementine Vulgate ships in. A standalone,
    # individually tested parser family that the Vulgate adapter composes.
    #
    # == The format
    #
    # USFX is MILESTONE markup, not container markup:
    #
    #   <book id="GEN"><h>Genesis</h>
    #     <c id="1"/>
    #     <v id="1"/>In principio creavit Deus cælum et terram.<ve/>
    #
    # `<book id>` carries the OSIS/Paratext 3-letter code, `<h>` the display
    # heading (Genesis, Marcus…); `<c id>` is a chapter milestone; verse text
    # is the character data between `<v id>` and its closing `<ve/>`. The one
    # Nokogiri entry point is XML::Reader (the house streaming contract — the
    # real file is 4.65 MB, whole-bible).
    #
    # == What the caller chooses
    #
    # One physical file holds the whole bible, but the Vulgate adapter mints
    # ONE DOCUMENT PER BOOK (per-book titles, per-book quarantine, and the
    # alignment hub's cts-verse extractor rides the per-book passage-urn
    # tails). So #books lists the inventory for discover, and #parse extracts
    # exactly one book into a Nabu::Document: one passage per verse, urn
    # <doc-urn>:<chapter>.<verse>, upstream orthography kept verbatim
    # (ligatures, spaced punctuation — canonical means canonical), NFC at the
    # boundary.
    class UsfxParser
      # One book of the inventory pass: OSIS/Paratext code + display heading.
      Book = Data.define(:id, :heading)

      # List the books of the file, in file order, without extracting text.
      def books(path)
        inventory = []
        each_node(path) do |node|
          case [node.node_type, node.name]
          in [Nokogiri::XML::Reader::TYPE_ELEMENT, "book"]
            inventory << { id: node.attribute("id"), heading: nil }
          in [Nokogiri::XML::Reader::TYPE_ELEMENT, "h"]
            inventory.last[:heading] = node.inner_xml.strip if inventory.any?
          else
            nil
          end
        end
        inventory.map { |book| Book.new(id: book[:id], heading: book[:heading]) }
      end

      # Extract one +book+ (by its id) into a Nabu::Document. Raises
      # Nabu::ParseError when the book is absent or the XML is malformed.
      def parse(path, book:, urn:, language:, title:)
        document = Nabu::Document.new(urn: urn, language: language, title: title,
                                      canonical_path: File.expand_path(path))
        extract_book(path, book, urn, language, document)
        raise ParseError, "#{path}: book #{book.inspect} yielded no verses" if document.empty?

        document
      rescue Nabu::ValidationError => e
        raise ParseError, "#{path}: book #{book.inspect}: #{e.message}"
      end

      private

      # One streaming pass; verse state lives in these locals. A verse closes
      # at its <ve/> — and defensively at the next <v>/<c>/book boundary, so a
      # missing close never bleeds one verse's text into the next.
      def extract_book(path, book, urn, language, document)
        state = { in_book: false, seen: false, chapter: nil, verse: nil, text: +"" }
        each_node(path) do |node|
          track_book(node, book, state)
          next unless state[:in_book]

          track_verse(node, state) { |citation, text| append_verse(document, urn, language, citation, text) }
        end
        raise ParseError, "#{path}: book #{book.inspect} not found" unless state[:seen]
      end

      def track_book(node, book, state)
        return unless node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT && node.name == "book"

        state[:in_book] = node.attribute("id") == book
        state[:seen] ||= state[:in_book]
      end

      def track_verse(node, state, &)
        case [node.node_type, node.name]
        in [Nokogiri::XML::Reader::TYPE_ELEMENT, "c"]
          close_verse(state, &)
          state[:chapter] = node.attribute("id")
        in [Nokogiri::XML::Reader::TYPE_ELEMENT, "v"]
          close_verse(state, &)
          state[:verse] = node.attribute("id")
        in [Nokogiri::XML::Reader::TYPE_ELEMENT, "ve"] | [Nokogiri::XML::Reader::TYPE_END_ELEMENT, "book"]
          close_verse(state, &)
        in [Nokogiri::XML::Reader::TYPE_TEXT | Nokogiri::XML::Reader::TYPE_CDATA, _]
          state[:text] << node.value if state[:verse]
        else
          nil
        end
      end

      def close_verse(state)
        verse, chapter = state.values_at(:verse, :chapter)
        text = state[:text].split.join(" ")
        state[:verse] = nil
        state[:text] = +""
        yield("#{chapter}.#{verse}", text) if verse && chapter && !text.empty?
      end

      def append_verse(document, urn, language, citation, text)
        document << Nabu::Passage.new(
          urn: "#{urn}:#{citation}",
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
        raise ParseError, "#{path}: malformed USFX XML: #{e.message}"
      end
    end
  end
end
