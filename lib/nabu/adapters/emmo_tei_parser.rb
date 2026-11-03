# frozen_string_literal: true

require "nokogiri"
require_relative "source_read"

module Nabu
  module Adapters
    # The emmo-tei parser family: Early Modern Manuscripts Online's
    # word-tokenized TEI P5 transcriptions (Folger Shakespeare Library,
    # Dromio-encoded; emmo.folger.edu). A family of its own because EMMO's
    # TEXT MODEL is unlike any held TEI family: every word is a <w>, every
    # space a <c> and every punctuation mark a <pc>, so the whitespace text
    # nodes between elements are layout only (each element sits on its own
    # line) — a reader that keeps inter-element whitespace (ticha-tei,
    # dta-tei) would pad every comma; and EMMO's <add> is the writer's
    # own interlinear insertion INSIDE the sentence (ticha-tei reads <add>
    # as apparatus). Censused over the 2026-05-31 zip (100 files, all
    # well-formed): 26,053 <w>, 22,946 <c>, 8,170 <choice>.
    #
    # == The reading (per page)
    #
    # Page = the span between <pb/> breaks; pb@n is the leaf label ("leaf
    # 1 recto", "leaf 1 verso || leaf 2 recto" — a two-leaf opening). A
    # pb without @n (3 files: a turn inside an opening) starts an
    # unlabelled page when the open page has text, else joins it. Line =
    # <lb/>. Two layers:
    #
    #   text         the ORIGINAL spelling: <choice> → orig | abbr | sic.
    #                Expansions (<ex>, the editors' resolution of the
    #                abbreviation inside <orig>) are KEPT — the semi-
    #                diplomatic reading EMMO's own site renders; the
    #                scribal metamarks (insertion carets, expansion
    #                colons, hyphenation signs) are not reading text.
    #   regularized  upstream's regularized spelling (VARD-assisted):
    #                <choice> → reg (an English-language reg wins over a
    #                Latin one — Oxon<ex>iensis</ex> regularizes to both
    #                "Oxoniensis" and "Oxford") | expan | corr.
    #
    # <add> (authorial insertions) reads inline in both layers. Kept OUT of
    # the text, as page annotations: <del> (struck words — "deletions"),
    # <fw> (archival foliation — "forme_work") and the administrative
    # <note>s (call numbers, archivists' docket dates — "notes"); the
    # ENDORSEMENT notes (subtype="endorsement": the docket written on the
    # letter's outer leaf, fully transcribed) are manuscript text and read
    # inline. <gap/> mints nothing; <supplied>/<unclear>/<g>/<hi> are
    # transparent. A page left without text (an outer leaf carrying only a
    # call number) mints nothing and is counted.
    #
    # == Mentions and the writing place
    #
    # <placeName> and <name> (EMMO's tagsDecl: "Identifies personal names
    # in the text") are unlinked — no @ref anywhere — and ride each page as
    # "places"/"persons" in their REGULARIZED reading (the form the
    # project normalized: "Blythfield" → "Blithfield"). The first
    # <placeName> inside a <seg type="dateline"> is the place the letter
    # was written ("Oxoniensis this 27 of March 1620") — the result's
    # writing_place.
    class EmmoTeiParser
      Page = Data.define(:n, :text, :regularized, :deletions, :forme_work, :notes, :places, :persons, :foreign)
      Header = Data.define(:idno, :title, :author, :shelfmark, :collection, :repository, :bbid, :summary,
                           :text_lang, :origin_when, :origin_raw, :keywords, :licence, :edition, :surfaces)
      Result = Data.define(:header, :pages, :blank_pages, :writing_place)

      ORIG_CHILDREN = %w[orig abbr sic].freeze
      REG_CHILDREN = %w[reg expan corr].freeze
      SILENT = %w[metamark gap figure].freeze

      def parse(path)
        doc = Nokogiri::XML(SourceRead.utf8_file(path, label: "emmo"), &:strict)
        doc.remove_namespaces!
        body = doc.at_xpath("/TEI/text/body") or raise Nabu::ParseError, "#{path}: no <text><body>"

        @pages = []
        @blank = 0
        open_page(nil)
        walk(body, layers: %i[orig reg], lang: nil)
        close_page
        Result.new(header: header(doc), pages: @pages, blank_pages: @blank, writing_place: writing_place(body))
      rescue Nokogiri::XML::SyntaxError => e
        raise Nabu::ParseError, "#{path}: not well-formed: #{e.message}"
      end

      # One subtree's flat reading in +layer+ (:orig or :reg) — the
      # mentions, notes and the dateline place.
      def reading(node, layer:)
        saved = @out
        @out = { orig: [+""], reg: [+""], deletions: [], foreign: [] }
        walk(node, layers: [layer], lang: nil, capture: false)
        squash(@out[layer].join(" "))
      ensure
        @out = saved
      end

      private

      def header(doc)
        h = doc.at_xpath("/TEI/teiHeader")
        text = lambda do |xpath|
          node = h&.at_xpath(xpath) or next nil
          value = squash(node.text)
          value.empty? ? nil : value
        end
        origin = h&.at_xpath(".//msDesc/history/origin")
        Header.new(
          idno: text.call("fileDesc/publicationStmt/idno"), title: text.call("fileDesc/titleStmt/title"),
          author: text.call(".//msItem/author") || text.call("fileDesc/titleStmt/author"),
          shelfmark: text.call(".//msIdentifier/msName"), collection: text.call(".//msIdentifier/collection"),
          repository: text.call(".//msIdentifier/repository"), bbid: text.call(".//msIdentifier/idno[@type='BBID']"),
          summary: text.call(".//msContents/summary"), text_lang: text.call(".//msItem/textLang"),
          origin_when: origin&.[]("when"), origin_raw: origin && squash(origin.text),
          keywords: h ? h.xpath(".//textClass/keywords/term").map { |t| squash(t.text) }.reject(&:empty?) : [],
          licence: h&.at_xpath(".//availability/licence")&.[]("target"),
          edition: h&.at_xpath(".//editionStmt/edition")&.[]("n"),
          surfaces: doc.xpath("/TEI/sourceDoc/surface").to_h do |s|
            [s["n"].to_s, s.at_xpath("media")&.[]("url")]
          end
        )
      end

      def writing_place(body)
        body.xpath(".//seg[@type='dateline']").each do |seg|
          place = seg.at_xpath(".//placeName") or next
          value = reading(place, layer: :reg)
          return value unless value.empty?
        end
        nil
      end

      # -- the walk ---------------------------------------------------------------

      def walk(node, layers:, lang:, capture: true)
        node.children.each do |child|
          if child.text?
            add_text(child.text, layers)
          elsif child.element?
            element(child, layers: layers, lang: child["lang"] || lang, capture: capture)
          end
        end
      end

      # Whitespace-only text nodes are layout (class note): EMMO's spaces
      # are <c> elements.
      def add_text(text, layers)
        return if text.strip.empty?

        layers.each { |layer| @out[layer].last << text }
      end

      def element(node, layers:, lang:, capture:)
        case node.name
        when "pb" then page_break(node) if capture
        when "lb" then line_break(layers)
        when "c" then layers.each { |layer| @out[layer].last << " " }
        when "choice" then choice(node, layers: layers, lang: lang, capture: capture)
        when *ORIG_CHILDREN then walk(node, layers: layers & [:orig], lang: lang, capture: capture)
        when *REG_CHILDREN then walk(node, layers: layers & [:reg], lang: lang, capture: capture)
        when "del" then deletion(node, layers)
        when "fw" then @out[:forme_work] << flat(node) if capture
        when "note" then note(node, layers: layers, lang: lang, capture: capture)
        when *SILENT then nil
        when "placeName", "name" then mention(node, layers: layers, lang: lang, capture: capture)
        when "foreign" then foreign(node, layers: layers, lang: lang, capture: capture)
        else walk(node, layers: layers, lang: lang, capture: capture)
        end
      end

      def choice(node, layers:, lang:, capture:)
        kids = node.element_children
        orig = kids.find { |k| ORIG_CHILDREN.include?(k.name) }
        regs = kids.select { |k| REG_CHILDREN.include?(k.name) }
        reg = regs.find { |k| k["lang"] == "en" } || regs.first
        return walk(node, layers: layers, lang: lang, capture: capture) if orig.nil? && reg.nil?

        orig ||= reg
        reg ||= orig

        walk(orig, layers: layers & [:orig], lang: orig["lang"] || lang, capture: capture) if layers.include?(:orig)
        walk(reg, layers: layers & [:reg], lang: reg["lang"] || lang, capture: capture) if layers.include?(:reg)
      end

      def deletion(node, layers)
        return unless layers.include?(:orig) && @out[:deletions]

        text = reading(node, layer: :orig)
        @out[:deletions] << text unless text.empty?
      end

      def note(node, layers:, lang:, capture:)
        if node["subtype"] == "endorsement"
          line_break(layers)
          walk(node, layers: layers, lang: lang, capture: capture)
          line_break(layers)
          return
        end
        return unless capture

        entry = { "type" => node["type"], "subtype" => node["subtype"], "text" => reading(node, layer: :orig) }.compact
        @out[:notes] << entry unless entry["text"].empty?
      end

      def mention(node, layers:, lang:, capture:)
        if capture
          value = reading(node, layer: :reg)
          @out[node.name == "placeName" ? :places : :persons] << value unless value.empty?
        end
        walk(node, layers: layers, lang: lang, capture: capture)
      end

      def foreign(node, layers:, lang:, capture:)
        if capture
          text = reading(node, layer: :orig)
          @out[:foreign] << { "lang" => lang.to_s, "text" => text } unless text.empty?
        end
        walk(node, layers: layers, lang: lang, capture: capture)
      end

      def line_break(layers)
        @out[:orig] << +"" if layers.include?(:orig)
        @out[:reg].last << " " if layers.include?(:reg)
      end

      def page_break(node)
        return if node["n"].nil? && !page_text?

        close_page
        open_page(node["n"])
      end

      def open_page(number)
        @n = number
        @out = { orig: [+""], reg: [+""], deletions: [], forme_work: [], notes: [], places: [], persons: [],
                 foreign: [] }
      end

      def page_text? = @out[:orig].any? { |line| !line.strip.empty? }

      def close_page
        lines = @out[:orig].map { |line| squash(line) }.reject(&:empty?)
        if lines.empty?
          @blank += 1 unless @n.nil? && @pages.empty?
          return
        end

        @pages << Page.new(n: @n, text: lines.join("\n"), regularized: squash(@out[:reg].join(" ")),
                           deletions: @out[:deletions], forme_work: @out[:forme_work].reject(&:empty?),
                           notes: @out[:notes], places: @out[:places].uniq, persons: @out[:persons].uniq,
                           foreign: @out[:foreign])
      end

      def flat(node) = squash(node.text)

      def squash(text) = text.gsub(/\s+/, " ").strip
    end
  end
end
