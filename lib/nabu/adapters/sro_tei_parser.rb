# frozen_string_literal: true

require "nokogiri"
require "stringio"
require_relative "source_read"

module Nabu
  module Adapters
    # The sro-tei parser family: the Stationers' Register Online's
    # up-converted TEI P5 (Bergel & Gadd; schema and up-conversion James
    # Cummings) — one file per surviving Register (A–D), each holding
    # thousands of flat <div type="entry" xml:id="SRO<n>"> copy entries
    # under <body>, every entry closing on its <ab type="metadata"> block.
    # A family of its own because the GRAIN is the entry inside a 4–10 MB
    # file and the entry carries its own typed metadata; no held TEI family
    # reads that shape.
    #
    # == Streaming
    #
    # The files run 3.9–10.4 MB, so they are walked with
    # Nokogiri::XML::Reader (the house >5 MB rule): the teiHeader and each
    # entry div are lifted out as their own small DOM (Reader#outer_xml)
    # and read there — the whole file is never a DOM. #entry_ids is the
    # cheap pass discover needs (attributes only); #parse_file reads every
    # entry once.
    #
    # == The reading (per block)
    #
    # Block = each element child of the entry div except the metadata
    # block, in document order: <head> (the marginal enterer name, or a
    # whole head-only entry), <p>, <desc> (the marginal name before a
    # sub-item), <list>, and a top-level register <note>. Inside a block:
    #
    #   register text  — everything, including the register's OWN notes
    #                    (type="register"/"#register", resp="#register":
    #                    the Clerk's sum lines and marginalia) and Arber's
    #                    bracketed <supplied> letters (SRO keeps them).
    #   aside          — the apparatus notes (resp="#arber" — Arber's
    #                    1875–94 notes, prefixed "Arber:" upstream — and the
    #                    SRO editors' type="editorial" notes) ride the block's
    #                    "notes"; <del> (struck words) rides "deletions";
    #                    <choice> reads its <sic>/<orig> and records the
    #                    correction; <space> (with its editorial <desc>, "no
    #                    sum stated") is a gap, never text; the processing
    #                    comments (<!--orig: iiijd-->) are not text.
    #   mentions       — <persName> (n = SRO's own name key, role =
    #                    stationer / non-stationer / enterer / unknown),
    #                    <placeName>, <title> (the copy-titles) and <foreign>
    #                    readings are collected as they read.
    #
    # Whitespace runs collapse to one space (the files are pretty-printed:
    # inter-element whitespace is layout, and a few words are split by
    # element boundaries upstream — "discoue [r] y" — kept as encoded). A
    # block that reads empty (a paragraph holding only Arber's note) mints
    # no block; its notes move to the entry.
    class SroTeiParser
      Header = Data.define(:title, :licence, :liber)
      Entry = Data.define(:id, :liber, :sro_number, :sort_date, :register_date, :fee_pence, :register_ref,
                          :arber_ref, :register_id, :works, :statuses, :officers, :persons, :places, :titles,
                          :notes, :blocks)
      Block = Data.define(:kind, :rend, :text, :notes, :deletions, :foreign, :corrections)
      Result = Data.define(:header, :entries)

      ELEMENT = Nokogiri::XML::Reader::TYPE_ELEMENT
      REGISTER_MARKS = %w[register #register].freeze
      SILENT = %w[space anchor pb fw].freeze
      ORIGINAL = %w[sic orig].freeze
      CORRECTED = %w[corr reg expan].freeze

      # The entry ids in file order — attributes only, no entry DOM.
      def entry_ids(path)
        ids = []
        stream(path) do |node|
          next unless entry?(node)

          ids << (node.attribute("xml:id") || node.attribute("id") or
                    raise Nabu::ParseError, "#{path}: an entry div carries no xml:id")
        end
        ids
      end

      def parse_file(path)
        header = nil
        entries = []
        stream(path) do |node|
          if node.local_name == "teiHeader"
            header ||= read_header(fragment(node.outer_xml, path))
          elsif entry?(node)
            entries << read_entry(fragment(node.outer_xml, path), path)
          end
        end
        raise Nabu::ParseError, "#{path}: no teiHeader" if header.nil?

        Result.new(header: header, entries: entries)
      end

      private

      # The bytes come through the encoding belt (invalid UTF-8 → ParseError,
      # never a deep encoding crash); the 4–10 MB string is then STREAMED —
      # the Reader builds no DOM (the calfa-etymology pattern).
      def stream(path)
        text = SourceRead.utf8_file(path, label: "sro-tei")
        Nokogiri::XML::Reader(StringIO.new(text), path).each do |node|
          yield node if node.node_type == ELEMENT
        end
      rescue Nokogiri::XML::SyntaxError => e
        raise Nabu::ParseError, "#{path}: malformed XML: #{e.message}"
      end

      def entry?(node) = node.local_name == "div" && node.attribute("type") == "entry"

      def fragment(xml, path)
        doc = Nokogiri::XML(xml, &:strict)
        doc.remove_namespaces!
        doc.root
      rescue Nokogiri::XML::SyntaxError => e
        raise Nabu::ParseError, "#{path}: malformed XML: #{e.message}"
      end

      # -- the header ----------------------------------------------------------

      def read_header(node)
        Header.new(
          title: presence(squash(node.at_xpath("fileDesc/titleStmt/title")&.text.to_s)),
          licence: node.at_xpath(".//availability/licence")&.[]("target"),
          liber: presence(squash(node.at_xpath(".//publicationStmt/idno[@type='Liber']")&.text.to_s))
        )
      end

      # -- one entry -----------------------------------------------------------

      def read_entry(div, path)
        id = div["id"] or raise Nabu::ParseError, "#{path}: an entry div carries no xml:id"
        meta = div.at_xpath("ab[@type='metadata']") or raise Nabu::ParseError, "#{path}: #{id} has no metadata block"

        notes = []
        mentions = { persons: [], places: [], titles: [] }
        blocks = div.element_children.filter_map do |child|
          next if child == meta || child.name == "lb"

          if child.name == "note" && !register_note?(child)
            notes << apparatus(child)
            next
          end
          read_block(child, notes: notes, mentions: mentions)
        end
        notes.concat(meta_notes(meta))

        idno = ->(type) { presence(squash(meta.at_xpath("idno[@type='#{type}']")&.text.to_s)) }
        Entry.new(
          id: id, liber: idno.call("Liber"), sro_number: integer(idno.call("SRONumber")),
          sort_date: meta.at_xpath("date[@type='SortDate']")&.[]("when"),
          register_date: register_date(meta.at_xpath("date[@type='Register']")),
          fee_pence: number(meta.at_xpath("num[@type='totalEntryPence']")&.[]("value")),
          register_ref: idno.call("RegisterRef"), arber_ref: idno.call("ArberRef"),
          register_id: idno.call("RegisterID"),
          works: integer(meta.at_xpath("num[@type='works']")&.[]("value")),
          statuses: meta.xpath("note[@type='status']").filter_map { |n| presence(n["subtype"].to_s) },
          officers: meta.xpath("persName").map { |p| person(p, squash(p.text)) },
          persons: mentions[:persons].uniq, places: mentions[:places].uniq, titles: mentions[:titles],
          notes: notes, blocks: blocks
        )
      end

      def read_block(node, notes:, mentions:)
        reading = Reading.new
        walk(node, reading)
        text = squash(reading.buffer)
        if text.empty?
          notes.concat(reading.notes)
          return nil
        end

        mentions[:persons].concat(reading.persons)
        mentions[:places].concat(reading.places)
        mentions[:titles].concat(reading.titles)
        Block.new(kind: node.name, rend: node["rend"], text: text, notes: reading.notes,
                  deletions: reading.deletions, foreign: reading.foreign, corrections: reading.corrections)
      end

      # The metadata block's own apparatus: Arber's notes and the editors'
      # (never the status flags, which are the entry's statuses).
      def meta_notes(meta)
        meta.xpath("note[not(@type='status')]").map { |n| apparatus(n) }
      end

      def register_date(node)
        return nil if node.nil?

        { "when" => node["when"], "not_before" => node["notBefore"], "not_after" => node["notAfter"],
          "text" => presence(squash(node.text)) }.compact
      end

      # -- the walk ------------------------------------------------------------

      # The per-block accumulator: the register text buffer plus everything
      # read aside or collected on the way.
      class Reading
        attr_reader :buffer, :notes, :deletions, :foreign, :corrections, :persons, :places, :titles

        def initialize
          @buffer = +""
          @notes = []
          @deletions = []
          @foreign = []
          @corrections = []
          @persons = []
          @places = []
          @titles = []
        end
      end

      def walk(node, reading)
        node.children.each do |child|
          if child.text? || child.cdata?
            reading.buffer << child.text
          elsif child.element?
            element(child, reading)
          end
        end
      end

      def element(node, reading)
        case node.name
        when "note" then register_note?(node) ? walk(node, reading) : reading.notes << apparatus(node)
        when "del" then deletion(node, reading)
        when "choice" then choice(node, reading)
        when "lb" then reading.buffer << " "
        when *SILENT then nil
        when "persName" then collect(node, reading) { |value| reading.persons << person(node, value) }
        when "placeName" then collect(node, reading) { |value| reading.places << value }
        when "title" then collect(node, reading) { |value| reading.titles << value }
        when "foreign" then collect(node, reading) { |value| reading.foreign << value }
        else walk(node, reading)
        end
      end

      # A mention's value is its reading as it entered the text (notes and
      # deletions excluded by construction).
      def collect(node, reading)
        start = reading.buffer.length
        walk(node, reading)
        value = squash(reading.buffer[start..])
        yield value unless value.empty?
      end

      def deletion(node, reading)
        value = squash(node.text)
        reading.deletions << value unless value.empty?
      end

      def choice(node, reading)
        original = node.element_children.find { |child| ORIGINAL.include?(child.name) }
        corrected = node.xpath(".//*").find { |child| CORRECTED.include?(child.name) }
        return walk(node, reading) if original.nil?

        start = reading.buffer.length
        walk(original, reading)
        reading.corrections << { "sic" => squash(reading.buffer[start..]),
                                 "corr" => corrected && squash(corrected.text) }.compact
      end

      def register_note?(node)
        REGISTER_MARKS.include?(node["type"]) || node["resp"] == "#register"
      end

      def apparatus(node)
        { "resp" => node["resp"], "type" => node["type"], "text" => squash(node.text) }.compact
      end

      def person(node, value)
        { "name" => value, "key" => presence(node["n"].to_s), "role" => presence(node["role"].to_s) }.compact
      end

      # -- helpers -------------------------------------------------------------

      def integer(value) = value && Integer(value, 10, exception: false)

      # Fees are pence; four entries carry a halfpenny (4.5, 5.5, 7.5).
      def number(value)
        return nil if value.nil?

        Integer(value, 10, exception: false) || Float(value, exception: false)
      end

      def presence(value) = value.empty? ? nil : value

      def squash(text) = text.gsub(/\s+/, " ").strip
    end
  end
end
