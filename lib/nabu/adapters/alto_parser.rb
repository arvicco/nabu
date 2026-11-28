# frozen_string_literal: true

require "nokogiri"

module Nabu
  module Adapters
    # ALTO v4 page XML as eScriptorium exports it (the `alto-escriptorium`
    # family; first consumer OpenITI MAKHZAN): one Page of TextBlocks of
    # TextLines, each line's text in its String CONTENT attributes (one
    # String per line in eScriptorium's export; several are joined with a
    # space, word-space <SP/> carries no text). Block and line types are
    # TAGREFS into the OtherTag list, whose labelled entries also carry the
    # export's document metadata (Call No, Genre, Script, Language …).
    #
    # Lines come in document order, each with its 1-based ordinal among ALL
    # TextLines of the page — empty (segmented but untranscribed) lines keep
    # their ordinal so a citation never shifts when one is transcribed later;
    # the caller decides what an empty line mints (nothing, for MAKHZAN).
    # Text is returned as upstream wrote it (outer whitespace stripped);
    # normalization is the caller's adapter-boundary duty.
    class AltoParser
      NS = { "a" => "http://www.loc.gov/standards/alto/ns-v4#" }.freeze

      Line = Data.define(:ordinal, :id, :text, :block_id, :block_type, :line_type)
      Page = Data.define(:language, :image_number, :file_name, :tags, :lines)

      # +bytes+ (UTF-8 XML) → Page; +label+ names it in errors.
      def self.parse(bytes, label:)
        doc = Nokogiri::XML(bytes) { |config| config.strict.nonet }
        new(doc, label).page
      rescue Nokogiri::XML::SyntaxError => e
        raise Nabu::ParseError, "#{label}: not well-formed ALTO (#{e.message})"
      end

      def initialize(doc, label)
        @doc = doc
        @label = label
      end

      def page
        page = @doc.at_xpath("/a:alto/a:Layout/a:Page", NS) or raise Nabu::ParseError, "#{@label}: no ALTO v4 Page"
        tag_labels = @doc.xpath("//a:Tags/a:OtherTag", NS).to_h { |tag| [tag["ID"], tag["LABEL"]] }
        Page.new(language: page["LANG"], image_number: page["PHYSICAL_IMG_NR"],
                 file_name: @doc.at_xpath("//a:sourceImageInformation/a:fileName", NS)&.text,
                 tags: metadata_tags, lines: lines(page, tag_labels))
      end

      private

      # The labelled OtherTags that carry a value (the export's metadata);
      # type tags (empty elements) are the TAGREFS vocabulary, not metadata.
      def metadata_tags
        @doc.xpath("//a:Tags/a:OtherTag", NS).each_with_object({}) do |tag, out|
          value = tag.text.strip
          out[tag["LABEL"]] = value unless value.empty?
        end
      end

      def lines(page, tag_labels)
        page.xpath(".//a:TextLine", NS).each_with_index.map do |line, index|
          block = line.at_xpath("ancestor::a:TextBlock[1]", NS)
          text = line.xpath("a:String", NS).map { |string| string["CONTENT"].to_s.strip }.reject(&:empty?).join(" ")
          Line.new(ordinal: index + 1, id: line["ID"], text: text, block_id: block&.[]("ID"),
                   block_type: type_label(block, tag_labels), line_type: type_label(line, tag_labels))
        end
      end

      # TAGREFS is an IDREFS list; the first id the tag list names labels it.
      def type_label(node, tag_labels)
        return nil if node.nil?

        node["TAGREFS"].to_s.split.filter_map { |ref| tag_labels[ref] }.first
      end
    end
  end
end
