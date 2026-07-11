# frozen_string_literal: true

module Nabu
  module Adapters
    # Parser family "freising-tei" (P13-11): the eZISS TEI P4 electronic
    # critical edition layout (Brižinski spomeniki, ZRC SAZU/IJS 2007).
    #
    # == The layout
    #
    # The edition is composed of one MASTER file (bs.xml — TEI.2 header with
    # the license, langUsage and the ZRCola charDesc, plus a body of external
    # entity includes) and per-layer content files (bsCT/bsDT/bsPT/bsTR-*),
    # each an independently parseable <div> fragment sharing one skeleton:
    #
    #   div[@type=mon @n=1..3]  the monument (BS I, II, III)
    #     page[@n=folio]        the Clm 6426 folio (78r … 161v)
    #       line[@n]            the manuscript line — per-monument continuous
    #                           numbering across pages, IDENTICAL @n/@id keys
    #                           across every layer (the alignment anchor)
    #
    # The master's external entities are deliberately NOT resolved: each
    # layer file is read directly, so no DTD/entity machinery runs at all.
    #
    # == ZRCola glyphs
    #
    # Special characters appear only as <g corresp="zrcolaXXXX"/> refs (no
    # raw PUA codepoints in text); the master's <charDesc> maps each id to
    # standard Unicode (<mapping type="standard">). glyph_map reads that
    # table once; an unmapped ref in a layer file is damage → ParseError.
    #
    # == Flattening rules (the reading text per line)
    #
    # - <note> (editorial end-notes), <milestone>, <gap> leave no residue.
    # - <sic> immediately followed by <corr> yields the corr — the critical
    #   layer's emended reading (a standalone corr, an editorial insertion,
    #   is kept; a sic with no corr stays).
    # - <abbr> immediately followed by <expan> yields the expan.
    # - Scribal <del> (erased ink) is dropped, <add> kept — the diplomatic
    #   witness flattens to the scribe's FINAL state; keeping both would
    #   mint readings the parchment never carried. The erased matter stays
    #   recoverable in canonical (never "cleaned": the choice picks one of
    #   two upstream-encoded readings, it does not alter either).
    # - Whitespace collapses to single spaces; output is NFC; lines that
    #   flatten to nothing (the empty <line n="36"/> of BS I) are skipped.
    class FreisingTeiParser
      Monument = Data.define(:n, :lines)
      Line = Data.define(:n, :folio, :tei_id, :lang, :text)

      DROPPED = %w[note milestone gap del].freeze
      private_constant :DROPPED

      # id => standard-Unicode replacement, from the master's charDesc.
      # Nokogiri's #text skips comments, so the inline "<!--LATIN SMALL
      # LETTER…-->" annotations inside <mapping> cost nothing.
      def self.glyph_map(master_path)
        doc = parse_xml(master_path)
        doc.xpath("//charDesc/char").to_h do |char|
          mapping = char.at_xpath("./mapping[@type='standard']")
          raise ParseError, "#{master_path}: char #{char['id']} has no standard mapping" if mapping.nil?

          [char["id"], Normalize.nfc(mapping.text)]
        end
      end

      def self.parse_xml(path)
        document = Nokogiri::XML(File.read(path), &:strict)
        raise ParseError, "#{path}: malformed eZISS TEI: #{document.errors.first}" unless document.errors.empty?

        document
      rescue Nokogiri::XML::SyntaxError => e
        raise ParseError, "#{path}: malformed eZISS TEI: #{e.message}"
      end

      def initialize(glyph_map:)
        @glyph_map = glyph_map
      end

      # The monuments of one layer file, in document order.
      def monuments(layer_path)
        self.class.parse_xml(layer_path).xpath("//div[@type='mon']").map do |div|
          Monument.new(n: Integer(div["n"], 10), lines: monument_lines(div, layer_path))
        end
      end

      private

      def monument_lines(div, path)
        div.xpath("./page").flat_map do |page|
          page.xpath("./line").filter_map do |line|
            text = line_text(line, path)
            next if text.empty?

            Line.new(n: Integer(line["n"], 10), folio: page["n"], tei_id: line["id"],
                     lang: line["lang"], text: text)
          end
        end
      end

      def line_text(line, path)
        Normalize.nfc(flatten(line, path).gsub(/\s+/, " ").strip)
      end

      # Recursive flatten under the rules above. Elements not named keep
      # their text content (name, hi, emph, q, ref, add, expan, corr, …).
      def flatten(node, path)
        node.children.map { |child| flatten_child(child, path) }.join
      end

      def flatten_child(child, path)
        return child.text if child.is_a?(Nokogiri::XML::Text)
        return "" unless child.is_a?(Nokogiri::XML::Element)

        case child.name
        when *DROPPED then ""
        when "g" then glyph(child, path)
        when "sic" then followed_by?(child, "corr") ? "" : flatten(child, path)
        when "abbr" then followed_by?(child, "expan") ? "" : flatten(child, path)
        else flatten(child, path)
        end
      end

      # Is the next element sibling (whitespace/comments skipped) a <name>?
      def followed_by?(node, name)
        sibling = node.next_sibling
        sibling = sibling.next_sibling while sibling && !sibling.is_a?(Nokogiri::XML::Element) &&
                                             sibling.text.to_s.strip.empty?
        sibling.is_a?(Nokogiri::XML::Element) && sibling.name == name
      end

      def glyph(node, path)
        @glyph_map.fetch(node["corresp"]) do
          raise ParseError, "#{path}: unmapped ZRCola glyph #{node['corresp'].inspect} " \
                            "(not in the master charDesc)"
        end
      end
    end
  end
end
