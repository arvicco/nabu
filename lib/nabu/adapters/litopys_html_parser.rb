# frozen_string_literal: true

require "nokogiri"
require_relative "../normalize"

module Nabu
  module Adapters
    # The Izbornyk (litopys.org.ua) static-HTML parser family (P117, row
    # 252). The site serves hand-built windows-1251 pages; everything below
    # was censused against the live pages on 2026-10-11 (the 41 Ipatiev
    # chronicle pages and the «Лексикони» glossaries).
    #
    # == Decoding (the adapter boundary)
    #
    # Bytes are windows-1251 (every page declares it in its meta tag); the
    # Old Cyrillic letters the codepage lacks ride as numeric entities
    # (&#1123; ѣ, &#1127; ѧ, &#1155; titlo …) which Nokogiri resolves. One
    # SITE-DECLARED FONT SUBSTITUTION is decoded here: a lone "Ђ", "А" or
    # "Ж" wrapped in <small> is the site's "Litopys New Roman" font hack for
    # ять / юс малий / юс великий — the pages say so themselves ("Старо-
    # слов’янські букви передаються традиційно: Ђ — ять, А — юс малий, Ж —
    # юс великий", zyzlex/zyz101.htm). Decoding a declared glyph hack is
    # reading the text, not "cleaning" it; any OTHER <small> content is
    # either a censused editorial marker (below) or a ParseError.
    # Everything else is verbatim — notably the site's own renderings of
    # iotated letters with U+0131 dotless i ("ıє" for ѥ, "бъı" for ы),
    # which are real codepoints upstream chose and stay untouched.
    module LitopysHtmlParser
      ENCODING = "Windows-1251"
      FONT_SUBSTITUTIONS = { "Ђ" => "ѣ", "А" => "ѧ", "Ж" => "ѫ" }.freeze

      # The statement of a later edition's year: any year 1931+ in an
      # edition statement (the ru-wikisource EDITION_TAINT_POST_1930 shape).
      TAINT_YEAR = /(?<!\d)(193[1-9]|19[4-9]\d|20\d\d)(?!\d)/

      # Chronicle-page markers, all inside <small> within the text:
      #   [<a id="l6360">6360</a> (<a id="r852">852</a>)]  — the SITE's annal-year
      #       key (AM + AD), not in the 1908 print → annotation, never text
      #   <small id="lyst2">//</small>, /л.3/, /л.3об./,
      #   /л.2.об./                                       — Ipatiev-codex folio
      #       breaks (id lystN = recto, lystobN = verso) → annotation
      #       "folios" (census 2026-10-11: 304 recto + 301 verso + 3 bare //)
      #   [II, 74] / [I, 9]                              — bracketed
      #       volume/page references the site carries (191, unexplained
      #       upstream); twice fused into a folio mark ("/л.112 II, 15/")
      #   [КІНЕЦЬ ІПАТІЇВСЬКОГО СПИСКУ]                 — the site's own
      #       end note (ipat41) → annotation "marks", verbatim
      FOLIO_TEXT = %r{\A(?://|/л\.\s*\d+\s*\.?\s*(?:об\.)?\s*(?<mark>[IVX]+,\s*\d+)?/)\z}
      MARK_TEXT = /\A\[[^\[\]]+\]\z/
      FOLIO_ID = /\Alyst(ob)?(\d+)\z/
      STATEMENT_COLUMNS = /Стлб\.\s*(\d+)\s*-\s*(\d+)/

      APPARATUS_CLASSES = %w[dop4 dop5 dop7 dop00 dop0].freeze

      Column = Data.define(:number, :paragraphs, :years, :folios, :marks, :variants, :notes)
      ChroniclePage = Data.define(:statement, :first_column, :last_column, :columns)
      GlossaryEntry = Data.define(:headword, :gloss)
      GlossaryPage = Data.define(:title, :statement, :entries)

      module_function

      def decode(bytes, path:)
        text = bytes.dup.force_encoding(ENCODING)
        raise Nabu::ParseError, "litopys: #{path}: invalid windows-1251 bytes" unless text.valid_encoding?

        text.encode(Encoding::UTF_8)
      end

      def html(bytes, path:)
        Nokogiri::HTML(decode(bytes, path: path))
      end

      # The page's main content block (the site's div.dop3 frame).
      def content(doc, path:)
        doc.at_css("div.dop3") or raise Nabu::ParseError, "litopys: #{path}: no div.dop3 content block"
      end

      def tainted?(statement)
        statement.to_s.match?(TAINT_YEAR)
      end

      # --- the chronicle (ipatlet/ipatNN.htm) --------------------------------

      def chronicle(bytes, path:, errata: {})
        doc = html(bytes, path: path)
        statement_node = doc.at_css("p.Vary_cent") or
          raise Nabu::ParseError, "litopys: #{path}: no edition statement (p.Vary_cent)"
        statement = squish(statement_node.text)
        first, last = statement.match(STATEMENT_COLUMNS)&.captures&.map { |n| Integer(n, 10) }
        raise Nabu::ParseError, "litopys: #{path}: statement names no column range: #{statement}" unless first

        columns = walk_columns(content(doc, path: path), first: first, last: last, path: path, errata: errata)
        ChroniclePage.new(statement: statement, first_column: first, last_column: last, columns: columns)
      end

      def walk_columns(content, first:, last:, path:, errata:)
        columns = {}
        current = first
        pending_variants = []
        column = ->(number) { columns[number] ||= new_column(number) }
        content.xpath(".//p | .//h1 | .//h2 | .//h3").each do |node|
          css = node["class"].to_s
          if css.start_with?("Mber")
            current = column_marker(node, current: current, range: first..last, path: path, errata: errata)
            column.call(current).variants.concat(pending_variants)
            pending_variants = []
          elsif css == "Vary" && node.text.include?("Варіанты")
            pending_variants << apparatus_text(node, "Варіанты")
          elsif css == "Prym" && node.text.include?("Примѣчанія")
            column.call(current).notes << apparatus_text(node, "Примѣчанія")
          elsif text_block?(node, css)
            add_paragraph(column.call(current), node, path: path)
          end
        end
        columns.values.reject { |col| col.paragraphs.empty? }.sort_by(&:number)
      end

      def new_column(number)
        Column.new(number: number, paragraphs: [], years: [], folios: [], marks: [], variants: [], notes: [])
      end

      # "стб.1" / "2" — and two upstream quirks: <p class=Mberid="st91">
      # (ipat05: the space before id= is missing, so the class attribute
      # swallows it — the number is still the marker's own text), and the
      # TEXTLESS continuation anchors <p class=Mber id="st360_1"><br></p>
      # that open a page continuing a column (ipat16/18) — the number is
      # the id's; a continuation anchor naming two columns ("809п 810",
      # ipat36: the page carries nothing of 809) means its LAST number.
      # One upstream anchor is mislabeled outright (ipat05's "58" between
      # 91 and 93) — the adapter's censused +errata+ map corrects it. A
      # page whose first column starts on it opens with that column's own
      # marker, so the current column may repeat; going backwards or past
      # the statement's range is a ParseError.
      def column_marker(node, current:, range:, path:, errata:)
        number = node.text.scan(/\d+/).last || node.to_html[/st(\d+)/, 1] or
          raise Nabu::ParseError, "litopys: #{path}: column marker without a number"
        number = Integer(number, 10)
        number = errata.fetch(number, number)
        unless number >= current && range.cover?(number)
          raise Nabu::ParseError, "litopys: #{path}: column marker #{number} out of order " \
                                  "(after #{current}, range #{range.first}-#{range.last})"
        end
        number
      end

      # K1/KF paragraphs and h1–h3 headings are text; K3 is the site's
      # navigation-bar class ("Попередня · Зміст · Наступна") — EXCEPT where
      # upstream mis-classed a text paragraph as K3 (ipat41 cols 926–927,
      # census 2026-10-11): a link-free K3 is text.
      def text_block?(node, css)
        text_class = %w[K1 KF].include?(css) || node.name.match?(/\Ah[1-3]\z/) ||
                     (css == "K3" && node.at_css("a").nil?)
        return false unless text_class

        node.ancestors("div").none? { |div| APPARATUS_CLASSES.include?(div["class"].to_s) }
      end

      def add_paragraph(column, node, path:)
        sink = { text: +"", years: column.years, folios: column.folios, marks: column.marks }
        inline(node, sink, path: path)
        text = squish(sink[:text])
        column.paragraphs << Nabu::Normalize.nfc(text) unless text.empty?
      end

      def apparatus_text(node, label)
        Nabu::Normalize.nfc(squish(node.text).sub(/\A#{label}\s*:\s*/, ""))
      end

      # One inline walk: text verbatim; <sup class="q"> (the manuscript's
      # superscript letters) inline; a bare <sup> (the 1908 apparatus keys)
      # dropped; <small> decoded or lifted to annotations; images dropped.
      def inline(node, sink, path:)
        node.children.each do |child|
          if child.text?
            sink[:text] << child.text
          elsif child.element?
            inline_element(child, sink, path: path)
          end
        end
      end

      def inline_element(child, sink, path:)
        case child.name
        when "sup"
          inline(child, sink, path: path) if child["class"] == "q"
        when "small" then small(child, sink, path: path)
        when "br" then sink[:text] << " "
        when "img", "script", "form", "input" then nil
        else inline(child, sink, path: path)
        end
      end

      def small(node, sink, path:)
        text = node.text.strip
        if (am = node.at_css("a[id^='l']")) && (ad = node.at_css("a[id^='r']"))
          sink[:years] << { "am" => Integer(am.text.strip, 10), "ad" => Integer(ad.text.strip, 10) }
        elsif FONT_SUBSTITUTIONS.key?(text)
          sink[:text] << FONT_SUBSTITUTIONS.fetch(text)
        elsif (folio = text.match(FOLIO_TEXT))
          sink[:folios] << folio_label(node["id"], text)
          sink[:marks] << "[#{folio[:mark]}]" if folio[:mark]
        elsif text.match?(MARK_TEXT)
          sink[:marks] << text
        else
          raise Nabu::ParseError, "litopys: #{path}: unrecognized <small> content #{text.inspect}"
        end
      end

      def folio_label(id, text)
        match = id.to_s.match(FOLIO_ID)
        return text unless match

        match[1] ? "#{match[2]}об" : match[2]
      end

      # --- the glossaries (zyzlex/zyz100–102.htm) ------------------------------

      # Entries are the site's "<p class=K1><b>headword</b>, gloss.</p>"
      # lines; a bold-comma line named in +headers+ is the print's own
      # column header (zyz100's "по слове(н)ску, просто") — censused, not
      # an entry. A K1 line that is wholly "[…]" is the page's edition
      # statement (zyz100's "[Амфілохієва публікація: … М., 1884.]").
      def glossary(bytes, path:, headers: [])
        doc = html(bytes, path: path)
        block = content(doc, path: path)
        title = block.at_css("h1, h2")&.then do |node|
          sink = { text: +"", years: [], folios: [], marks: [] }
          inline(node, sink, path: path)
          squish(sink[:text])
        end
        entries = []
        statement = nil
        block.css("p.K1").each do |node|
          next unless text_block?(node, "K1")

          plain = squish(node.text)
          statement ||= plain if plain.start_with?("[") && plain.end_with?("]")
          entry = glossary_entry(node, path: path)
          entries << entry if entry && !headers.include?(entry.headword)
        end
        GlossaryPage.new(title: title && Nabu::Normalize.nfc(title), statement: statement, entries: entries)
      end

      def glossary_entry(node, path:)
        lead = node.children.reject { |child| child.text? && child.text.strip.empty? }
        bold = lead.first
        return nil unless bold&.element? && bold.name == "b"

        head = { text: +"", years: [], folios: [], marks: [] }
        inline(bold, head, path: path)
        rest = { text: +"", years: [], folios: [], marks: [] }
        lead.drop(1).each do |child|
          child.text? ? rest[:text] << child.text : inline_element(child, rest, path: path)
        end
        headword = squish(head[:text])
        tail = squish(rest[:text])
        return nil if headword.empty? || !tail.start_with?(",")

        gloss = tail.sub(/\A,\s*/, "")
        return nil if gloss.empty?

        GlossaryEntry.new(headword: Nabu::Normalize.nfc(headword), gloss: Nabu::Normalize.nfc(gloss))
      end

      def squish(text)
        text.to_s.gsub(/[[:space:]]+/, " ").strip
      end
    end
  end
end
