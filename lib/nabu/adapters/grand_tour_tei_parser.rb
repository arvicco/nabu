# frozen_string_literal: true

require "nokogiri"
require_relative "source_read"

module Nabu
  module Adapters
    # The grand-tour-tei parser family: the Herzog August Bibliothek's
    # "Grand Tour digital" edition of early-modern travel journals (HAB
    # Wolfenbüttel, 2022–2026; Zenodo 10.5281/zenodo.23055358) — HAB's
    # tei-p5-transcr customization with NER entity links into three
    # project registers. A family of its own because its reading rules
    # contradict the held page-grain families: insertions (<add>, the
    # <subst> pairs) belong to the text where ticha-tei reads them as
    # apparatus; the critical apparatus of 149.14 (<app>/<lem>/<rdg>
    # against three later copies) must keep the lemma and set the readings
    # aside; and every <rs> resolves through the registers (listPlace /
    # listPerson / listOrg) to its GeoNames / GND / Wikidata ref — no held
    # family joins a register.
    #
    # == The reading (per page)
    #
    # Page = the span between <pb/> breaks (pb@n = the folio when present
    # — 89 Blank. only — else the facsimile id in pb@facs); a page with no
    # text (a binding, a blank verso) mints nothing and is counted. Line =
    # <lb/> (pretty-printed at line START, so the whitespace before it is
    # layout), <cb/>, a table row, a list item. Two layers:
    #
    #   text         the TRANSCRIPTION as the edition gives it ("möglichst
    #                zeichengenau": abbreviations unexpanded, line-end
    #                hyphens kept): <choice> → sic | abbr | orig; <subst>
    #                → its <add>; <app> → its <lem>.
    #   regularized  the editors' layer: <choice> → corr | expan | reg, and
    #                every <w lemma> (the edition's join of a word broken
    #                at the line end, "Lo- / gierten") read as its lemma.
    #
    # Kept OUT of the text, as page annotations: <del> (struck text —
    # "deletions"), <rdg> (the copies' variants with witness and folio —
    # "variants"), the writers' own marginalia (<note type="contemporary">
    # with its place — "marginalia": mileages, running place names), and
    # the editors' notes (<note type="annotation"|"footnote">, modern
    # German — "editorial_notes"). <gap/>, <handShift/>, <milestone/> mint
    # nothing; <unclear>, <supplied>, <hi>, <date>, <cit>, <quote>, <ref>
    # read transparently.
    #
    # == Entities and dates
    #
    # Each <rs type="place|person|org" ref="#id …"> becomes a mention on its
    # page: resolved through the register to {"value" => the register's
    # display name, "ref" => its authority URL, "id"}; an empty "#" ref
    # (upstream NER not yet linked) or an id the register lacks keeps the
    # surface reading with "unresolved" => true. Each <date when> (ISO
    # year, year-month or day) is collected per page.
    class GrandTourTeiParser
      Page = Data.define(:n, :facs, :text, :regularized, :places, :persons, :orgs, :dates, :deletions,
                         :variants, :marginalia, :editorial_notes)
      Header = Data.define(:xml_id, :shelfmark, :title, :bibl, :statements, :publication_note)
      Result = Data.define(:header, :pages, :blank_pages)
      Register = Data.define(:places, :persons, :orgs) do
        def self.empty = new(places: {}, persons: {}, orgs: {})
      end

      ORIG_CHILDREN = %w[sic abbr orig].freeze
      REG_CHILDREN = %w[corr expan reg].freeze
      SILENT = %w[gap handShift milestone figure].freeze
      LINE_ELEMENTS = %w[row item].freeze
      RS_KINDS = { "place" => :places, "plac" => :places, "person" => :persons, "org" => :orgs }.freeze
      ISO_WHEN = /\A\d{4}(?:-\d{2}(?:-\d{2})?)?\z/

      # One register file → { xml:id => { "value", "ref" } } over its
      # +entry+ elements (place / person / org), the display-typed name
      # when an entry carries several.
      def self.load_register(path, entry:)
        return {} unless File.file?(path)

        doc = Nokogiri::XML(SourceRead.utf8_file(path, label: "grand-tour"), &:strict)
        doc.remove_namespaces!
        doc.xpath("//#{entry}[@id]").to_h do |node|
          names = node.xpath("./placeName|./persName|./orgName")
          name = names.find { |n| n["type"] == "display" } || names.first
          [node["id"], { "value" => name&.text.to_s.gsub(/\s+/, " ").strip, "ref" => name&.[]("ref") }.compact]
        end
      rescue Nokogiri::XML::SyntaxError => e
        raise Nabu::ParseError, "#{path}: register not well-formed: #{e.message}"
      end

      def initialize(register: Register.empty)
        @register = register
      end

      def parse(path)
        doc = Nokogiri::XML(SourceRead.utf8_file(path, label: "grand-tour"), &:strict)
        doc.remove_namespaces!
        body = doc.at_xpath("/TEI/text/body") or raise Nabu::ParseError, "#{path}: no <text><body>"

        @pages = []
        @blank = 0
        open_page(label: nil, facs: nil)
        walk(body, layers: %i[orig reg])
        close_page
        Result.new(header: header(doc), pages: @pages, blank_pages: @blank)
      rescue Nokogiri::XML::SyntaxError => e
        raise Nabu::ParseError, "#{path}: not well-formed: #{e.message}"
      end

      private

      def header(doc)
        root = doc.root
        h = doc.at_xpath("/TEI/teiHeader/fileDesc")
        title = h&.at_xpath("titleStmt/title[@type='main']") || h&.at_xpath("titleStmt/title")
        Header.new(
          xml_id: root["id"], shelfmark: root["n"], title: title && flat(title),
          bibl: h&.at_xpath("sourceDesc/bibl")&.then { |b| flat(b) },
          statements: h ? h.xpath("titleStmt/respStmt").map { |r| flat(r) }.reject(&:empty?) : [],
          publication_note: h&.at_xpath("publicationStmt/p")&.then { |p| flat(p) }&.then { |t| t.empty? ? nil : t }
        )
      end

      # -- the walk ---------------------------------------------------------------

      def walk(node, layers:)
        node.children.each do |child|
          if child.text?
            add_text(child.text, layers)
          elsif child.element?
            element(child, layers: layers)
          end
        end
      end

      def add_text(text, layers)
        layers.each { |layer| @out[layer].last << text }
      end

      def element(node, layers:)
        case node.name
        when "pb" then page_break(node) unless @capture == false
        when "lb", "cb" then line_break(layers)
        when *LINE_ELEMENTS then line_unit(node, layers)
        when "cell" then cell(node, layers)
        when "choice" then choice(node, layers: layers)
        when *ORIG_CHILDREN then walk(node, layers: layers & [:orig])
        when *REG_CHILDREN then walk(node, layers: layers & [:reg])
        when "w" then word(node, layers: layers)
        when "del" then aside(:deletions, node, layers)
        when "app" then app(node, layers: layers)
        when "rdg" then variant(node, layers)
        when "note" then note(node, layers)
        when "rs" then mention(node, layers: layers)
        when "date" then date(node, layers: layers)
        when *SILENT then nil
        else walk(node, layers: layers)
        end
      end

      # A table row / list item opens its own line.
      def line_unit(node, layers)
        line_break(layers)
        walk(node, layers: layers)
      end

      # Cells read space-separated within their row.
      def cell(node, layers)
        add_text(" ", layers)
        walk(node, layers: layers)
        add_text(" ", layers)
      end

      def choice(node, layers:)
        kids = node.element_children
        orig = kids.find { |k| ORIG_CHILDREN.include?(k.name) }
        reg = kids.find { |k| REG_CHILDREN.include?(k.name) }
        return walk(node, layers: layers) if orig.nil? && reg.nil?

        orig ||= reg
        reg ||= orig
        walk(orig, layers: layers & [:orig]) if layers.include?(:orig)
        walk(reg, layers: layers & [:reg]) if layers.include?(:reg)
      end

      # A <w lemma> is the edition's join of a line-broken word: the
      # transcription walks it, the regularized layer reads the lemma.
      def word(node, layers:)
        walk(node, layers: layers & [:orig])
        return unless layers.include?(:reg)

        lemma = node["lemma"]
        lemma.to_s.strip.empty? ? walk(node, layers: [:reg]) : add_text(lemma, [:reg])
      end

      def app(node, layers:)
        node.element_children.each do |kid|
          kid.name == "rdg" ? variant(kid, layers) : walk(kid, layers: layers)
        end
      end

      def variant(node, layers)
        return unless capturing?(layers)

        entry = { "wit" => node["wit"], "n" => node["n"], "text" => reading(node) }.compact
        @out[:variants] << entry
      end

      def note(node, layers)
        return unless capturing?(layers)

        text = reading(node)
        return if text.empty?

        if node["type"].to_s.strip.start_with?("cont") # contemporary (+ the 6 upstream misspellings)
          @out[:marginalia] << { "place" => node["place"], "text" => text }.compact
        else
          @out[:editorial_notes] << { "type" => node["type"], "text" => text }.compact
        end
      end

      def aside(key, node, layers)
        return unless capturing?(layers)

        text = reading(node)
        @out[key] << text unless text.empty?
      end

      def mention(node, layers:)
        if capturing?(layers)
          kind = RS_KINDS[node["type"].to_s.strip]
          @out[kind].concat(resolve(kind, node)) if kind
        end
        walk(node, layers: layers)
      end

      def resolve(kind, node)
        table = @register.public_send(kind)
        ids = node["ref"].to_s.split.map { |token| token.delete_prefix("#") }.reject(&:empty?)
        resolved = ids.filter_map { |id| table[id]&.merge("id" => id) }
        return resolved if !resolved.empty? && resolved.size == ids.size

        surface = reading(node)
        resolved + (surface.empty? ? [] : [{ "value" => surface, "unresolved" => true }])
      end

      def date(node, layers:)
        @out[:dates] << node["when"] if capturing?(layers) && node["when"].to_s.match?(ISO_WHEN)
        walk(node, layers: layers)
      end

      # Apparatus is captured once, from the main walk (both layers live) —
      # never again from inside a subtree reading.
      def capturing?(layers) = @capture != false && layers.include?(:orig)

      # One subtree's flat transcription (notes, variants, deletions, the
      # unresolved surface) — side-effect free.
      def reading(node)
        saved_out = @out
        saved_capture = @capture
        @capture = false
        @out = { orig: [+""], reg: [+""] }
        walk(node, layers: [:orig])
        flat_text(@out[:orig].join(" "))
      ensure
        @out = saved_out
        @capture = saved_capture
      end

      def line_break(layers)
        @out[:orig] << +"" if layers.include?(:orig)
        @out[:reg].last << " " if layers.include?(:reg)
      end

      def page_break(node)
        close_page
        open_page(label: node["n"], facs: node["facs"])
      end

      def open_page(label:, facs:)
        @page_n = label
        @page_facs = facs
        @out = { orig: [+""], reg: [+""], places: [], persons: [], orgs: [], dates: [], deletions: [], variants: [],
                 marginalia: [], editorial_notes: [] }
      end

      def close_page
        lines = @out[:orig].map { |line| flat_text(line) }.reject(&:empty?)
        if lines.empty?
          @blank += 1 unless @page_n.nil? && @page_facs.nil?
          return
        end

        @pages << Page.new(n: @page_n, facs: @page_facs, text: lines.join("\n"),
                           regularized: flat_text(@out[:reg].join(" ")), places: @out[:places].uniq,
                           persons: @out[:persons].uniq, orgs: @out[:orgs].uniq, dates: @out[:dates].uniq,
                           deletions: @out[:deletions], variants: @out[:variants], marginalia: @out[:marginalia],
                           editorial_notes: @out[:editorial_notes])
      end

      def flat(node) = flat_text(node.xpath(".//text()|.//lb").map { |n| n.text? ? n.text : " " }.join)

      def flat_text(text) = text.gsub(/\s+/, " ").strip
    end
  end
end
