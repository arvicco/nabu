# frozen_string_literal: true

require "nokogiri"

module Nabu
  module Adapters
    # Streaming parser for the CCMH gospel files (Corpus Cyrillo-Methodianum
    # Helsingiense, Kielipankki; P13-2) — the ccmh-ces family. The corpus's
    # own "very simple" CES XML (cesDoc version 4, NOT TEI):
    #
    #   <cesDoc version="4"><cesHeader>…</cesHeader><text>
    #     <div id="b.MAT" type="book">
    #       <div id="b.MAT.01" type="chapter">
    #         <seg id="b.MAT.01.01" type="verse">
    #           <ver id="1.01.01.0.0"> *k$nIg&amp;I !rodstva …</ver>
    #
    # A standalone, individually tested component the Ccmh adapter composes,
    # in the AsprParser one-file-many-documents shape: #books lists the
    # gospel-book inventory for discover, #parse re-streams and extracts
    # exactly one book div.
    #
    # == The two upstream sub-shapes (verified against the full files, Phase A)
    #
    # Assemanianus and Savvina (the lectionaries) wrap verse text in <ver>
    # children — several per seg where the verse is line-split or appears in
    # parallel lectionary renditions (the 7-digit ver-id's last digit).
    # Marianus and Zographensis put the text directly in the seg's mixed
    # content. One rule covers both: a passage's text is ALL character data
    # between <seg> and </seg>, whitespace-collapsed — <ver> boundaries read
    # as the space between lines, parallels concatenate in file order.
    #
    # == Citation: the seg id, zero-padding stripped
    #
    # seg id "b.MAT.01.01" (shape A, padded) and "b.MAT.5.23" (shape B,
    # bare) both mint <doc-urn>:<chapter>.<verse> with integer components
    # (…:1.1, …:5.23), so the two shapes cite uniformly. Chapter 0 exists
    # (marianus JOH — the ms's chapter-heading list) and is kept: canonical
    # means canonical. Duplicate (chapter, verse) seg ids occur with DISTINCT
    # text (lectionary parallels, repeated headings); the second occurrence
    # in document order gets a ":b2" suffix, the third ":b3" (the GRETIL
    # collision-tolerance precedent) — never merged, never quarantined.
    #
    # == Text policy (canonical means canonical)
    #
    # The corpus's 7-bit-ASCII transliteration is stored VERBATIM — including
    # the editorial marks (*=ms capital, !=titlo, [..]=interpolation) and the
    # %-marks the Helsinki editors left on unchecked spots. Cyrillic
    # back-transliteration would be an enrichment, never a parse step. NFC at
    # the boundary is trivially satisfied by ASCII but minted anyway (house
    # rule); the only non-ASCII byte upstream is the BOM (three of the four
    # files), which the Reader absorbs.
    #
    # == Streaming
    #
    # The only Nokogiri entry point is Nokogiri::XML::Reader (the house
    # rule). #parse stops reading at the requested book div's end.
    class CcmhCesParser
      # One gospel book of the inventory pass: the div id ("b.MAT") + the
      # bare book code ("MAT").
      Book = Data.define(:id, :code)

      BOOK_ID_PATTERN = /\Ab\.(?<code>[A-Z]+)\z/
      SEG_ID_PATTERN = /\Ab\.[A-Z]+\.(?<chapter>\d+)\.(?<verse>\d+)\z/

      # List the book divs of the file, in file order (canonical gospel
      # order upstream), without extracting text.
      def books(path)
        inventory = []
        each_node(path) do |node|
          next unless book_element?(node)

          id = node.attribute("id").to_s
          match = BOOK_ID_PATTERN.match(id) or
            raise ParseError, "#{path}: book div id #{id.inspect} does not match b.<CODE>"
          inventory << Book.new(id: id, code: match[:code])
        end
        inventory
      end

      # Extract one gospel book (by its div +book_id+) into a Nabu::Document.
      # Raises Nabu::ParseError when the book is absent, yields no verses, or
      # the XML is malformed.
      def parse(path, book_id:, urn:, language:, title:)
        document = Nabu::Document.new(urn: urn, language: language, title: title,
                                      canonical_path: File.expand_path(path))
        extract_book(path, book_id, urn, language, document)
        raise ParseError, "#{path}: book #{book_id.inspect} yielded no verses" if document.empty?

        document
      rescue Nabu::ValidationError => e
        raise ParseError, "#{path}: book #{book_id.inspect}: #{e.message}"
      end

      private

      # One streaming pass. Book divs never nest in each other but DO contain
      # chapter divs, so a depth counter (not a boolean) tracks the requested
      # book's subtree; reading stops at its END_ELEMENT.
      def extract_book(path, book_id, urn, language, document)
        walk = { in_book: false, seen: false, depth: 0, seg_id: nil, text: +"", citations: Hash.new(0) }
        each_node(path) do |node|
          break if book_boundary(node, book_id, walk) == :done

          track_seg(node, walk) do |seg_id, text|
            append_verse(document, urn, language, seg_id, text, walk[:citations], path)
          end
        end
        raise ParseError, "#{path}: book #{book_id.inspect} not found" unless walk[:seen]
      end

      # Track entry/exit of the requested book div; :done once its subtree is
      # fully read. Chapter divs inside it only move the depth counter.
      def book_boundary(node, book_id, walk)
        return nil unless node.name == "div"

        case node.node_type
        when Nokogiri::XML::Reader::TYPE_ELEMENT
          if walk[:in_book]
            walk[:depth] += 1 unless node.self_closing?
          elsif node.attribute("id") == book_id && node.attribute("type") == "book"
            walk[:in_book] = true
            walk[:seen] = true
          end
        when Nokogiri::XML::Reader::TYPE_END_ELEMENT
          return nil unless walk[:in_book]
          return :done if walk[:depth].zero?

          walk[:depth] -= 1
        end
        nil
      end

      # Capture character data only inside <seg> within the requested book —
      # ALL of it, whether wrapped in <ver> children (shape A) or direct
      # mixed content (shape B); the <ver> elements themselves are invisible
      # to the text accumulation. A seg closes at its END_ELEMENT.
      def track_seg(node, walk)
        return unless walk[:in_book]

        case [node.node_type, node.name]
        in [Nokogiri::XML::Reader::TYPE_ELEMENT, "seg"]
          walk[:seg_id] = node.attribute("id").to_s
        in [Nokogiri::XML::Reader::TYPE_END_ELEMENT, "seg"]
          text = walk[:text].split.join(" ")
          seg_id = walk[:seg_id]
          walk[:seg_id] = nil
          walk[:text] = +""
          yield seg_id, text unless text.empty?
        in [Nokogiri::XML::Reader::TYPE_TEXT | Nokogiri::XML::Reader::TYPE_CDATA |
            Nokogiri::XML::Reader::TYPE_SIGNIFICANT_WHITESPACE, _] if walk[:seg_id]
          walk[:text] << node.value
        else
          nil
        end
      end

      def append_verse(document, urn, language, seg_id, text, citations, path)
        match = SEG_ID_PATTERN.match(seg_id) or
          raise ParseError, "#{path}: seg id #{seg_id.inspect} does not match b.<CODE>.<ch>.<verse>"

        citation = "#{match[:chapter].to_i}.#{match[:verse].to_i}"
        citations[citation] += 1
        count = citations[citation]
        citation = "#{citation}:b#{count}" unless count == 1
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
        raise ParseError, "#{path}: malformed CCMH CES XML: #{e.message}"
      end

      def book_element?(node)
        node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT &&
          node.name == "div" && node.attribute("type") == "book"
      end
    end
  end
end
