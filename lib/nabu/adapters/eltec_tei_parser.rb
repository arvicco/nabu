# frozen_string_literal: true

require "nokogiri"

require_relative "../normalize"

module Nabu
  module Adapters
    # The ELTeC level-1 TEI family (P117-2, first consumer eltec-srp): one
    # file = one novel of the European Literary Text Collection (COST Action
    # CA16204), encoded to the shared eltec-1 schema
    # (distantreading.github.io/Schema/eltec-1.rng) every language collection
    # follows — so the family is collection-neutral and the per-collection
    # adapter supplies only identity, language and its admission rule.
    #
    # == The header (read cheaply for discovery, fully at parse)
    #
    # titleStmt: the work title with the collection's edition suffix
    # (" : ELTeC издање" / " : ELTeC edition") stripped, the English title,
    # the author as "Surname, Name (birth-death)" — "????" marks an unknown
    # year upstream, honoured as nil — with viaf/wikidata refs, and the
    # respStmt chain (scanning, OCR + correction, ELTeC encoding).
    # sourceDesc: up to three bibls by @type — firstEdition (the work's
    # first publication: its <date> elements are the typed dating, its
    # pubPlace the place), printSource (the printed edition actually
    # digitized — the NAMED EDITION layer, e.g. a 1987 Matica srpska
    # reprint) and digitalSource. profileDesc/textDesc: the ELTeC sampling
    # keys (authorGender, size, reprintCount, timeSlot) verbatim.
    #
    # == The text
    #
    # Blocks are <head>, <p>, <l> and <trailer> — whatever the nesting
    # (<l> inside <quote>, <p> inside <quote>), each is one passage; a block
    # nested inside another block (an <l> inside a <p>) stays part of its
    # container's text. <note>, <gap>, <ref> (empty note anchors),
    # <milestone> and <pb> mint no text; pb@n tracks the printed page a
    # block starts on (annotation "page").
    #
    # Zones: the body always; front and back divs except the furniture
    # types — "titlepage" (the digitized print's title page, not the work)
    # and "notes" (ELTeC moves all notes to back/div[@type=notes]; in the
    # Serbian collection they are the modern editors' "Прим. прир." notes —
    # editorial apparatus of the print source, never the novel's text).
    #
    # == Citation (frozen once minted)
    #
    # <zone><div ordinals>.<block ordinal>: div ordinals are 1-based among
    # sibling divs (ALL divs count, skipped furniture included, so the
    # numbering is upstream's structure, not our filter), joined by "."; the
    # block ordinal counts the blocks a div owns directly (a nested div's
    # blocks belong to it). Blocks outside any div sit under "0".
    # Zones: body bare ("3.12", "2.4.7", "0.1"), front "f" ("f2.1",
    # "f0.1"), back "b" ("b1.4").
    class EltecTeiParser
      # const: the ELTeC sampling keys (profileDesc/textDesc children), not a corpus claim
      TEXT_DESC_KEYS = { "authorGender" => "author_gender", "size" => "size",
                         "reprintCount" => "reprint_count", "timeSlot" => "time_slot" }.freeze

      BLOCKS = %w[head p l trailer].freeze
      SILENT = %w[note gap ref milestone pb fw].freeze
      FURNITURE_DIVS = %w[titlepage notes].freeze
      ZONES = [["front", "f"], ["body", ""], ["back", "b"]].freeze
      EDITION_SUFFIX = /\s*:\s*ELTeC[\s-]*\p{L}*\s*\z/

      Bibl = Data.define(:titles, :place, :publisher, :years, :raw_date, :idnos) do
        def to_h
          { "titles" => titles, "place" => place, "publisher" => publisher, "date" => raw_date,
            "idnos" => idnos }.compact.reject { |_k, v| v.respond_to?(:empty?) && v.empty? }
        end
      end

      Header = Data.define(:xml_id, :lang_tag, :title, :title_en, :author, :author_birth,
                           :author_death, :author_refs, :title_refs, :words, :first_edition,
                           :print_source, :digital_source, :responsibility, :text_desc, :licence)

      Block = Data.define(:citation, :kind, :text, :page)

      Parsed = Data.define(:header, :blocks)

      # The teiHeader alone, without parsing the text — discovery's admission
      # rule (an author's death year) reads only this.
      def header(path)
        raw = File.read(path, encoding: "UTF-8")
        cut = raw.index("</teiHeader>") or raise Nabu::ParseError, "#{path}: no </teiHeader>"
        head = raw[0, cut + "</teiHeader>".size]
        read_header(xml("#{head}</TEI>", path), path)
      end

      def parse(path)
        doc = xml(File.read(path, encoding: "UTF-8"), path)
        header = read_header(doc, path)
        text = doc.at_xpath("/TEI/text") or raise Nabu::ParseError, "#{path}: no <text>"
        blocks = []
        @page = nil
        ZONES.each do |name, zone|
          node = text.at_xpath(name) or next
          walk_container(node, zone: zone, ords: [], blocks: blocks)
        end
        Parsed.new(header: header, blocks: blocks)
      end

      private

      def xml(source, path)
        doc = Nokogiri::XML(source) { |config| config.strict.nonet }
        doc.remove_namespaces!
        doc
      rescue Nokogiri::XML::SyntaxError => e
        raise Nabu::ParseError, "#{path}: malformed TEI: #{e.message}"
      end

      # A zone element (front/body/back) or a div: its own blocks get the
      # owner's label; each child div recurses with its sibling ordinal.
      def walk_container(node, zone:, ords:, blocks:)
        own = 0
        div_ordinal = 0
        each_owned(node) do |child|
          if child.name == "div"
            div_ordinal += 1
            if FURNITURE_DIVS.include?(child["type"])
              note_pages(child)
            else
              walk_container(child, zone: zone, ords: ords + [div_ordinal], blocks: blocks)
            end
          else
            text = block_text(child)
            start_page = @page
            note_pages(child)
            next if text.empty?

            own += 1
            blocks << Block.new(citation: citation(zone, ords, own), kind: child.name, text: text, page: start_page)
          end
        end
      end

      # Yields the divs and the blocks this node owns directly, in document
      # order — descending through non-block wrappers (quote, lg, sp, hi …)
      # but never into a block or a nested div; pb milestones on the way
      # update the running page.
      def each_owned(node, &block)
        node.element_children.each do |child|
          if child.name == "pb"
            @page = child["n"] if child["n"]
          elsif child.name == "div" || BLOCKS.include?(child.name)
            yield child
          elsif !SILENT.include?(child.name)
            each_owned(child, &block)
          end
        end
      end

      def note_pages(node)
        node.xpath(".//pb[@n]").each { |pb| @page = pb["n"] }
      end

      def citation(zone, ords, ordinal)
        "#{zone}#{ords.empty? ? '0' : ords.join('.')}.#{ordinal}"
      end

      def block_text(node)
        parts = []
        collect_text(node, parts)
        Normalize.nfc(parts.join.gsub(/[[:space:]]+/, " ").strip)
      end

      def collect_text(node, parts)
        node.children.each do |child|
          if child.text?
            parts << child.text
          elsif child.element? && !SILENT.include?(child.name)
            collect_text(child, parts)
          elsif child.element?
            parts << " " # a silent element still separates words
          end
        end
      end

      def read_header(doc, path)
        root = doc.root
        raise Nabu::ParseError, "#{path}: root is <#{root&.name}>, not <TEI>" unless root&.name == "TEI"

        title_stmt = doc.at_xpath("/TEI/teiHeader/fileDesc/titleStmt") or
          raise Nabu::ParseError, "#{path}: no titleStmt"
        author_name, birth, death = author_parts(title_stmt.at_xpath("author"))
        Header.new(
          xml_id: root["id"] || raise(Nabu::ParseError, "#{path}: TEI carries no xml:id"),
          lang_tag: root["lang"],
          title: work_title(title_stmt, path),
          title_en: squeeze(title_stmt.at_xpath("title[@lang='en']")&.text)&.sub(EDITION_SUFFIX, ""),
          author: author_name, author_birth: birth, author_death: death,
          author_refs: split_refs(title_stmt.at_xpath("author")&.[]("ref")),
          title_refs: split_refs(title_stmt.at_xpath("title[not(@lang)]")&.[]("ref")),
          words: doc.at_xpath("//fileDesc/extent/measure[@unit='words']")&.text.to_s[/\d+/]&.to_i,
          first_edition: bibl(doc, "firstEdition"),
          print_source: bibl(doc, "printSource"),
          digital_source: bibl(doc, "digitalSource"),
          responsibility: title_stmt.xpath("respStmt").map { |r| responsibility(r) }.compact,
          text_desc: text_desc(doc),
          licence: doc.at_xpath("//publicationStmt/availability/licence")&.[]("target")
        )
      end

      def work_title(title_stmt, path)
        node = title_stmt.at_xpath("title[not(@lang)]") || title_stmt.at_xpath("title")
        title = squeeze(node&.text)&.sub(EDITION_SUFFIX, "")
        raise Nabu::ParseError, "#{path}: titleStmt carries no title" if title.nil? || title.empty?

        title
      end

      # "Атанацковић, Богобој (1826-1858)" → name + years; "????" (upstream's
      # unknown-year mark) and an absent parenthesis give nil years.
      def author_parts(node)
        return [nil, nil, nil] unless node

        text = squeeze(node.text)
        match = text.match(/\A(.*?)\s*\(([0-9?]{4})?\s*[-–]\s*([0-9?]{4})?\)\s*\z/)
        return [text, nil, nil] unless match

        [match[1], year(match[2]), year(match[3])]
      end

      def year(value)
        value.to_s.match?(/\A\d{4}\z/) ? value.to_i : nil
      end

      def split_refs(value)
        value.to_s.split.reject(&:empty?)
      end

      def bibl(doc, type)
        node = doc.at_xpath("//sourceDesc/bibl[@type='#{type}']") or return nil

        raw_dates = node.xpath(".//date").map { |d| squeeze(d.text) }.reject(&:empty?)
        Bibl.new(
          titles: node.xpath("title").map { |t| squeeze(t.text) }.reject(&:empty?),
          place: squeeze(node.at_xpath("pubPlace")&.text),
          publisher: squeeze(node.at_xpath("publisher")&.text),
          years: raw_dates.flat_map { |d| d.scan(/\b(1\d{3})\b/).flatten.map(&:to_i) },
          raw_date: raw_dates.empty? ? nil : raw_dates.join("; "),
          idnos: node.xpath("idno").map { |i| squeeze(i.text) }.reject(&:empty?)
        )
      end

      def responsibility(node)
        resp = squeeze(node.at_xpath("resp")&.text)
        name = squeeze(node.at_xpath("name")&.text)
        return nil if resp.to_s.empty? && name.to_s.empty?

        { "resp" => resp, "name" => name }.compact
      end

      def text_desc(doc)
        desc = doc.at_xpath("//profileDesc/textDesc") or return {}

        TEXT_DESC_KEYS.each_with_object({}) do |(element, key), out|
          value = desc.at_xpath(element)&.[]("key")
          out[key] = value if value && !value.empty?
        end
      end

      def squeeze(text)
        return nil if text.nil?

        text.gsub(/[[:space:]]+/, " ").strip
      end
    end
  end
end
