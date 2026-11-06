# frozen_string_literal: true

require "nokogiri"

require_relative "../normalize"
require_relative "source_read"

module Nabu
  module Adapters
    # The Antonomaz TEI family (first consumer: mazarinades) — the TEI P5
    # files of the Antonomaz project (Sorbonne Université), validated by the
    # project's ODD (github.com/Antonomaz/ODD). One file = one printed
    # pamphlet: a teiHeader carrying the bibliographic entry (the Moreau /
    # Mazarine / Carrier descriptions), and a <body> holding ONE <p> whose
    # content is the print page by page, line by line.
    #
    # == The body (censused 2026-11-05 over all 3,067 well-formed files)
    #
    # <pb/> milestones divide pages: @n (the printed page number — 2,441
    # files), @vue (the digitization's image number — 619 Mazarine scans),
    # or neither (20 files, 3 bare pb); @facs (a Gallica image URL, 115
    # files) and @manual_correction="yes" (upstream's flag on the pages it
    # corrected by hand — the first page in 3,046 files) ride along. <lb/>
    # opens a line; <lb break="no" rend="¬"/> opens a line that CONTINUES
    # the previous line's word (the print's hyphenation). <l> wraps a line —
    # in verse AND on prose title pages alike (upstream uses it as a line
    # box, so no verse claim is read from it; the header's form term is the
    # verse/prose claim), <lg> groups them, <cb/> breaks a column.
    # Whitespace inside a line is the file's pretty-printing, collapsed.
    #
    # Print furniture leaves the text and rides the page: <fw> running
    # heads, page numbers, signatures and catchwords ({type, place, text}),
    # <note place="margin-…"> marginalia ({place, text}), <figure> types,
    # <gap/> counts. <choice> keeps the print (<sic>) in the text and the
    # editor's <corr> beside it. <imprimatur> ("AVEC PERMISSION"), <hi>,
    # <foreign>, <unclear>, <title> are text. A page without a letter-bearing
    # line mints nothing (the blank versos and fly-leaves).
    #
    # == Page keys (frozen once minted)
    #
    # @n verbatim ("3", "NP", "II"); "v<vue>" for an image number; "pb<k>"
    # for the k-th bare pb; "pre" for text before the first pb. A key
    # repeated within a file (38 files renumber, see upstream's
    # problematic_numbering report) takes "~2", "~3" in order.
    #
    # == Refusals
    #
    # Malformed XML (13 upstream files, all MANUAL-suffixed — an
    # unescaped "&", mismatched tags) raises Nabu::ParseError: the document
    # quarantines, named, the sync goes on.
    class AntonomazTeiParser
      TEI = { "tei" => "http://www.tei-c.org/ns/1.0" }.freeze
      LETTER = /\p{L}/

      Parsed = Data.define(:header, :pages)

      Page = Data.define(:key, :n, :vue, :facs, :manual_correction, :text, :continued_lines,
                         :furniture, :notes, :figures, :gaps, :corrections)

      Header = Data.define(:xml_id, :title, :title_source, :bibl_title, :authors, :pub_place, :publisher, :dates,
                           :extent_pages, :format, :identifiers, :digitizations, :holding, :licence,
                           :availability, :file_dates, :text_origin, :origin_statement, :languages,
                           :abstracts, :forms, :genres, :subjects, :flags, :settings, :changes)

      def parse(path)
        doc = read(path)
        body = doc.at_xpath("/tei:TEI/tei:text/tei:body", TEI) or raise Nabu::ParseError, "#{path}: no <text><body>"
        Parsed.new(header: header(doc), pages: PageWalker.new.walk(body))
      end

      private

      def read(path)
        Nokogiri::XML(SourceRead.utf8_file(path, label: path), &:strict)
      rescue Nokogiri::XML::SyntaxError => e
        raise Nabu::ParseError, "#{path}: malformed XML (#{e.message.lines.first.to_s.strip})"
      end

      def header(doc)
        bibl = doc.at_xpath("//tei:sourceDesc/tei:bibl", TEI)
        main = doc.at_xpath("//tei:titleStmt/tei:title[@type='main']", TEI)
        project = doc.xpath("//tei:encodingDesc/tei:projectDesc/tei:p", TEI).map { |p| clean(p.text) }
        statement = project.reverse.find { |p| p.match?(/OCRisation|transcription/i) }
        Header.new(
          xml_id: doc.root["xml:id"], title: text_of(main), title_source: main&.[]("source"),
          bibl_title: text_of(bibl&.at_xpath("tei:title", TEI)),
          authors: authors(bibl), pub_place: pub_place(bibl), publisher: publisher(bibl), dates: dates(bibl),
          extent_pages: extent(bibl), format: text_of(bibl&.at_xpath("tei:note[@type='format']", TEI)),
          identifiers: identifiers(bibl), digitizations: attrs(bibl, "tei:ref", "target"),
          holding: holding(doc), licence: doc.at_xpath("//tei:availability/tei:licence", TEI)&.[]("target"),
          availability: availability(doc),
          file_dates: file_dates(doc), text_origin: origin(statement), origin_statement: statement,
          languages: languages(doc), abstracts: abstracts(doc),
          forms: terms(doc, "form"), genres: terms(doc, "genre"), subjects: subjects(doc), flags: flags(doc),
          settings: settings(doc), changes: changes(doc)
        )
      end

      def availability(doc)
        node = doc.at_xpath("//tei:availability", TEI) or return nil
        compact({ "n" => node["n"], "status" => node["status"] })
      end

      def origin(statement)
        case statement
        when /OCRisation/i then :ocr
        when /transcription manuelle/i then :manual
        end
      end

      def authors(bibl)
        return [] unless bibl

        bibl.xpath("tei:author", TEI).filter_map do |author|
          name = person_name(author)
          next if name.nil?

          compact({ "name" => name, "ref" => author["ref"], "role" => author["role"], "source" => author["source"] })
        end
      end

      def pub_place(bibl)
        place = bibl&.at_xpath("tei:pubPlace", TEI) or return nil
        compact({ "name" => text_of(place), "ref" => place["ref"], "source" => place["source"] })
      end

      def publisher(bibl)
        node = bibl&.at_xpath("tei:publisher", TEI) or return nil
        name = person_name(node) or return nil
        compact({ "name" => name, "ref" => node["ref"] })
      end

      # forename + surname when the persName is structured, else the text.
      def person_name(node)
        pers = node.at_xpath("tei:persName", TEI)
        parts = pers && %w[forename surname].filter_map { |part| text_of(pers.at_xpath("tei:#{part}", TEI)) }
        return parts.join(" ") if parts && !parts.empty?

        text_of(node)
      end

      def dates(bibl)
        return [] unless bibl

        bibl.xpath("tei:date", TEI).filter_map do |date|
          entry = compact({ "source" => date["source"], "when" => date["when"], "not_before" => date["notBefore"],
                            "not_after" => date["notAfter"], "text" => text_of(date) })
          entry unless entry.except("source").empty?
        end
      end

      def extent(bibl)
        quantity = bibl&.at_xpath("tei:extent/tei:measure[@unit='page']", TEI)&.[]("quantity").to_s
        quantity.match?(/\A\d+\z/) ? Integer(quantity, 10) : nil
      end

      def identifiers(bibl)
        return [] unless bibl

        bibl.xpath("tei:relatedItem[@type='identifier']", TEI).map do |item|
          compact({ "source" => item["source"], "subtype" => item["subtype"], "cert" => item["cert"],
                    "target" => item["target"] })
        end
      end

      def holding(doc)
        ms = doc.at_xpath("//tei:sourceDesc/tei:msDesc/tei:msIdentifier", TEI) or return nil
        fields = %w[settlement institution repository idno]
        compact(fields.to_h { |key| [key, text_of(ms.at_xpath("tei:#{key}", TEI))] })
      end

      def file_dates(doc)
        compact(doc.xpath("//tei:publicationStmt/tei:date", TEI).to_h { |date| [date["type"].to_s, date["when"]] })
      end

      def languages(doc)
        doc.xpath("//tei:profileDesc/tei:langUsage/tei:language", TEI).map do |lang|
          compact({ "ident" => lang["ident"], "label" => text_of(lang) })
        end
      end

      def abstracts(doc)
        doc.xpath("//tei:profileDesc/tei:abstract/tei:p", TEI).each_with_object({}) do |p, out|
          text = text_of(p) or next
          out[p["source"] || "unsourced"] = text
        end
      end

      def terms(doc, type)
        doc.xpath("//tei:textClass//tei:term[@type='#{type}']", TEI).filter_map { |term| text_of(term) }
      end

      def subjects(doc)
        doc.xpath("//tei:textClass//tei:term[@type='subject']", TEI).filter_map do |term|
          text = text_of(term) or next
          compact({ "text" => text, "ref" => term["ref"] })
        end
      end

      # The yes/no descriptors (handwritten_note, table_of_content, illustration).
      def flags(doc)
        doc.xpath("//tei:textClass//tei:term[@subtype='yes' or @subtype='no']", TEI)
           .to_h { |term| [term["type"], term["subtype"] == "yes"] }
      end

      def settings(doc)
        doc.xpath("//tei:settingDesc/tei:setting", TEI).filter_map do |setting|
          compact({ "id" => setting["xml:id"], "source" => setting["source"],
                    "label" => text_of(setting.at_xpath("tei:p", TEI)),
                    "when" => setting.at_xpath("tei:date", TEI)&.[]("when").to_s.then { |w| w.empty? ? nil : w } })
            .then { |entry| entry.key?("label") || entry.key?("when") ? entry : nil }
        end
      end

      def changes(doc)
        doc.xpath("//tei:revisionDesc/tei:change", TEI).map do |change|
          compact({ "status" => change["status"], "when" => change["when"], "who" => change["who"] })
        end
      end

      def attrs(node, xpath, attr)
        return [] unless node

        node.xpath(xpath, TEI).filter_map { |child| child[attr] }.reject(&:empty?)
      end

      def text_of(node)
        return nil unless node

        text = clean(node.text)
        text.empty? ? nil : text
      end

      def clean(text) = Nabu::Normalize.nfc(text.to_s.gsub(/\s+/, " ").strip)

      def compact(hash)
        return nil if hash.nil?

        hash.reject { |_key, value| value.nil? || (value.respond_to?(:empty?) && value.empty?) }
      end

      # The body walk: a page/line state machine over the document-order
      # node stream (class note).
      class PageWalker
        def walk(body)
          @pages = []
          @keys = Hash.new(0)
          @bare = 0
          open_page(nil)
          visit(body)
          close_page
          @pages
        end

        private

        def visit(node)
          node.children.each do |child|
            if child.text? || child.cdata?
              @line << child.text
            elsif child.element?
              element(child)
            end
          end
        end

        def element(node)
          case node.name
          when "pb"
            close_page
            open_page(node)
            visit(node) # four files wrap the page's lines IN the pb (class note)
          when "lb"
            new_line(continues: node["break"] == "no")
          when "cb"
            new_line(continues: false)
          when "l"
            new_line(continues: false)
            visit(node)
            new_line(continues: false)
          when "choice" then choice(node)
          when "fw" then @page[:furniture] << furniture(node)
          when "note" then @page[:notes] << margin_note(node)
          when "figure" then @page[:figures] << (node["type"] || "figure")
          when "gap" then @page[:gaps] += 1
          when "space" then nil
          else visit(node)
          end
        end

        def choice(node)
          sic = node.at_xpath("tei:sic", TEI) || node.element_children.first
          corr = node.at_xpath("tei:corr", TEI)
          visit(sic) if sic
          return unless sic && corr

          @page[:corrections] << { "sic" => squash(sic.text), "corr" => squash(corr.text) }
        end

        def furniture(node)
          { "type" => node["type"], "place" => node["place"], "text" => squash(node.text) }.compact
        end

        # Marginalia keep their own lb lines.
        def margin_note(node)
          lines = []
          buffer = +""
          node.traverse do |sub|
            if sub.element? && sub.name == "lb"
              lines << buffer
              buffer = +""
            elsif sub.text?
              buffer << sub.text
            end
          end
          lines << buffer
          text = lines.map { |line| squash(line) }.reject(&:empty?).join("\n")
          { "place" => node["place"], "text" => text }.compact
        end

        def new_line(continues:)
          flush_line
          @continues = continues
        end

        def flush_line
          text = squash(@line)
          @line = +""
          return if text.empty?

          @page[:lines] << text
          @page[:continued] << @page[:lines].size if @continues
          @continues = false
        end

        def open_page(milestone)
          @line = +""
          @continues = false
          @page = { pb: milestone, lines: [], continued: [], furniture: [], notes: [], figures: [], gaps: 0,
                    corrections: [] }
        end

        def close_page
          flush_line
          page = @page
          base = page_key(page[:pb])
          return unless page[:lines].any? { |line| line.match?(LETTER) }

          @keys[base] += 1
          key = @keys[base] == 1 ? base : "#{base}~#{@keys[base]}"
          pb = page[:pb]
          @pages << Page.new(
            key: key, n: pb&.[]("n"), vue: pb&.[]("vue"), facs: pb&.[]("facs"),
            manual_correction: pb&.[]("manual_correction") == "yes",
            text: page[:lines].join("\n"), continued_lines: page[:continued], furniture: page[:furniture],
            notes: page[:notes], figures: page[:figures], gaps: page[:gaps], corrections: page[:corrections]
          )
        end

        def page_key(milestone)
          return "pre" if milestone.nil?
          return milestone["n"] unless milestone["n"].to_s.strip.empty?
          return "v#{milestone['vue']}" unless milestone["vue"].to_s.strip.empty?

          @bare += 1
          "pb#{@bare}"
        end

        def squash(text) = Nabu::Normalize.nfc(text.to_s.gsub(/\s+/, " ").strip)
      end
    end
  end
end
