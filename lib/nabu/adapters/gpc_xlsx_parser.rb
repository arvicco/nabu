# frozen_string_literal: true

require "nokogiri"

module Nabu
  module Adapters
    # The gpc-xlsx parser family (P97-3): the GPC open subset ships as
    # one xlsx — a ZIP whose sheet is 45 MB of XML with a 16 MB
    # shared-string table — so both members stream through
    # Nokogiri::XML::Reader (the >5 MB SAX rule) after in-process
    # extraction via Nabu::ZipReader (no unzip forks, no new gem).
    #
    # == The sheet's shape (fixture README)
    #
    # Header row + one row per entry. Columns: A headword · B "active
    # link" (a formula column, empty in data) · C plain URL carrying
    # the STABLE entry id (gpc.html?gpc000002 → gpc000002 — the id and
    # the link-users condition in one string) · D variants · E POS ·
    # F plural forms · G English first-sense opening · H XML POS.
    # D and G use "_" as an internal separator; split and rejoin
    # honestly. Cells are shared-string refs (t="s") or inline values.
    #
    # == Skips (censused, never silent)
    #
    # A row whose C cell yields no gpc id cannot mint a stable entry
    # (the real file holds a handful); such rows are counted on
    # +skipped+ and skipped. Duplicate ids would violate the document's
    # own contract and raise there — loudly, not here.
    class GpcXlsxParser
      SHEET = "xl/worksheets/sheet1.xml"
      STRINGS = "xl/sharedStrings.xml"

      ID_PATTERN = /gpc\.html\?(gpc\d+)/

      attr_reader :skipped

      def initialize(path)
        @path = path
        @skipped = 0
      end

      # Yield one DictionaryEntry per id-bearing row (header skipped).
      def entries
        return enum_for(:entries) unless block_given?

        zip = Nabu::ZipReader.new(File.binread(@path))
        strings = shared_strings(zip)
        each_row(zip, strings) do |cells|
          entry = build_entry(cells)
          if entry.nil?
            @skipped += 1
            next
          end
          yield entry
        end
      end

      private

      def member(zip, name)
        entry = zip.entries.find { |e| e.name == name.b }
        raise Nabu::ParseError, "gpc-xlsx: #{@path} has no #{name} member" if entry.nil?

        zip.extract(entry)
      end

      def shared_strings(zip)
        strings = []
        current = nil
        reader = Nokogiri::XML::Reader.from_memory(member(zip, STRINGS))
        reader.each do |node|
          case [node.name, node.node_type]
          in ["si", Nokogiri::XML::Reader::TYPE_ELEMENT] then current = +""
          in ["si", Nokogiri::XML::Reader::TYPE_END_ELEMENT]
            strings << current
            current = nil
          in ["t", Nokogiri::XML::Reader::TYPE_ELEMENT] unless current.nil?
            current << Nokogiri::XML.fragment(node.inner_xml).text
          else nil
          end
        end
        strings
      end

      # Stream rows; each yields { "A" => text, ... } with shared-string
      # cells resolved. The first (header) row is dropped.
      def each_row(zip, strings)
        header_seen = false
        reader = Nokogiri::XML::Reader.from_memory(member(zip, SHEET))
        reader.each do |node|
          next unless node.name == "row" && node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT

          unless header_seen
            header_seen = true
            next
          end
          yield row_cells(node.outer_xml, strings)
        end
      end

      def row_cells(row_xml, strings)
        cells = {}
        # outer_xml carries the sheet's default namespace into the row
        # snippet; strip it so the cell xpath stays plain.
        Nokogiri::XML(row_xml).remove_namespaces!.xpath("//c").each do |c|
          column = c["r"].to_s[/[A-Z]+/]
          value = c.at_xpath("./v")&.text
          text = c["t"] == "s" && value ? strings[Integer(value)] : value
          cells[column] = text
        end
        cells
      end

      def build_entry(cells)
        id = cells["C"].to_s[ID_PATTERN, 1]
        headword = cells["A"].to_s.strip
        return nil if id.nil? || headword.empty?

        Nabu::DictionaryEntry.new(
          entry_id: id, key_raw: headword, language: Gpc::LANGUAGE,
          headword: Nabu::Normalize.nfc(headword),
          headword_folded: Nabu::Normalize.search_form(headword, language: Gpc::LANGUAGE),
          gloss: gloss(cells["G"]),
          body: body(cells, id),
          citations: []
        )
      end

      def gloss(english)
        first = split_segments(english).first
        return nil if first.nil? || first.empty?

        # "@" separates near-synonym glosses inside one segment (the
        # aberth shape); the short gloss is the first of them.
        Nabu::Normalize.nfc(first.split("@").first.strip)
      end

      # The body as labelled plain lines, ending with the entry's GPC
      # Online URL — the grant's link-users condition made surface.
      def body(cells, id)
        lines = []
        lines << "pos: #{cells['E']}" unless blank?(cells["E"])
        variants = split_segments(cells["D"])
        lines << "variants: #{variants.join('; ')}" unless variants.empty?
        plurals = split_segments(cells["F"])
        lines << "plural: #{plurals.join('; ')}" unless plurals.empty?
        english = split_segments(cells["G"]).map { |seg| seg.split("@").map(&:strip).join(", ") }
        lines << "en: #{english.join('; ')}" unless english.empty?
        lines << "GPC Online: https://www.geiriadur.ac.uk/gpc/gpc.html?#{id}"
        Nabu::Normalize.nfc(lines.join("\n"))
      end

      def split_segments(value)
        value.to_s.split("_").map(&:strip).reject(&:empty?)
      end

      def blank?(value) = value.to_s.strip.empty?
    end
  end
end
