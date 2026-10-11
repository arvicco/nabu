# frozen_string_literal: true

require "nokogiri"

module Nabu
  module Adapters
    # The `page-xml` parser family (P116-1): PAGE 2013 (PcGts) pages as
    # Transkribus exports them — the HTR ground-truth exchange format
    # (htr-united's `format: Page-XML`). First occupant: the Prague Bible
    # 1488 GT (prague-bible-1488). Deliberately thin: the family owns the
    # XML reading, the reading order and the `custom` tag grammar; what a
    # page or a line MEANS (urns, language, metadata) stays in the adapter.
    #
    # - Regions come in the page's ReadingOrder (RegionRefIndexed @index);
    #   a region the ReadingOrder does not name follows in document order
    #   (none censused — the rule keeps a stray region from vanishing).
    # - Lines come in their own `readingOrder {index:N;}` order (document
    #   order when absent). The text is the LINE-level TextEquiv/Unicode,
    #   verbatim — never the region-level TextEquiv (a derived join) and
    #   never NFC'd here (the adapter boundary's job). An empty TextEquiv
    #   yields a line with empty text, its index kept, so the adapter can
    #   skip it without re-flowing any following citation.
    # - The Transkribus `custom` attribute is a sequence of
    #   `tag {key:value; key:value;}` groups. readingOrder and structure
    #   are consumed here; every other tag carrying offset/length (abbrev
    #   with its expansion, unclear, textStyle) becomes a Span over the
    #   line's VERBATIM text — `form` is that substring, cut before any
    #   normalization so offsets stay upstream's. Offsets are Java string
    #   indices (UTF-16 units); the censused GT is all-BMP, where they
    #   equal Ruby character indices.
    class PageXmlParser
      Span = Data.define(:tag, :offset, :length, :form, :attributes)
      Line = Data.define(:id, :index, :text, :spans)
      Region = Data.define(:id, :index, :type, :lines)
      Page = Data.define(:page_nr, :status, :image_filename, :doc_id, :regions)

      TAG_PATTERN = /([A-Za-z_][\w-]*)\s*\{([^}]*)\}/

      # "readingOrder {index:0;} abbrev {offset:3; length:2;expansion:geſt;}"
      # → [["readingOrder", {"index" => "0"}], ["abbrev", {...}]]
      def self.custom_tags(custom)
        custom.to_s.scan(TAG_PATTERN).map do |tag, body|
          pairs = body.split(";").filter_map do |pair|
            key, value = pair.split(":", 2)
            next if key.nil? || value.nil?

            [key.strip, value.strip]
          end
          [tag, pairs.to_h]
        end
      end

      def parse(path)
        doc = Nokogiri::XML(File.read(path, encoding: Encoding::UTF_8), &:strict)
        doc.remove_namespaces!
        page = doc.at_xpath("/PcGts/Page") or
          raise Nabu::ParseError, "#{path}: no PcGts/Page element (not a PAGE file)"

        build_page(doc, page)
      rescue Nokogiri::XML::SyntaxError => e
        raise Nabu::ParseError, "#{path}: malformed XML: #{e.message}"
      end

      private

      def build_page(doc, page)
        meta = doc.at_xpath("/PcGts/Metadata/TranskribusMetadata")
        Page.new(
          page_nr: meta&.[]("pageNr")&.to_i,
          status: meta&.[]("status"),
          image_filename: page["imageFilename"],
          doc_id: meta&.[]("docId"),
          regions: ordered_regions(page)
        )
      end

      def ordered_regions(page)
        order = page.xpath("ReadingOrder//RegionRefIndexed").to_h do |ref|
          [ref["regionRef"], ref["index"].to_i]
        end
        regions = page.xpath(".//TextRegion")
        fallback = order.empty? ? 0 : order.values.max + 1
        regions.each_with_index.map do |node, position|
          index = order.fetch(node["id"]) { fallback + position }
          Region.new(id: node["id"], index: index, type: region_type(node),
                     lines: ordered_lines(node))
        end.sort_by(&:index)
      end

      def region_type(node)
        return node["type"] if node["type"]

        structure = self.class.custom_tags(node["custom"]).find { |tag, _| tag == "structure" }
        structure&.last&.[]("type")
      end

      def ordered_lines(region)
        region.xpath("TextLine").each_with_index.map do |node, position|
          tags = self.class.custom_tags(node["custom"])
          order = tags.find { |tag, _| tag == "readingOrder" }&.last&.[]("index")
          text = node.at_xpath("TextEquiv/Unicode")&.text.to_s
          Line.new(id: node["id"], index: order ? order.to_i : position, text: text,
                   spans: spans(tags, text))
        end.sort_by(&:index)
      end

      def spans(tags, text)
        tags.filter_map do |tag, attrs|
          next unless attrs.key?("offset") && attrs.key?("length")

          offset = attrs["offset"].to_i
          length = attrs["length"].to_i
          Span.new(tag: tag, offset: offset, length: length,
                   form: text[offset, length].to_s,
                   attributes: attrs.except("offset", "length"))
        end
      end
    end
  end
end
