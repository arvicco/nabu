# frozen_string_literal: true

require "nokogiri"
require "tmpdir"

require_relative "../normalize"
require_relative "../shell"

module Nabu
  module Adapters
    # The `elektire-epub` parser family (P117-2): one eLektire book — an
    # EPUB produced by Bulaja naklada for CARNET's school reading portal —
    # read as the work's text, the edition's rights statement and the
    # author's life years. Two production generations are censused
    # (2026-10-11, the 231 Croatian-literature books): v2 (2011–2017, Sigil
    # from Word, `<author>_<work>_N.htm`, footnotes as `#_ftnN` anchors
    # with an inline gloss `span.middleNNNpx`, verse as <br>-split lines
    # with Courier-styled line numbers) and v3 (2018+, CARNET-commissioned,
    # named files — Impresum, O-autoru, Rjecnik, Prije, Metodicki,
    # Poticaji, Quiz — footnotes as `span.FootnoteReference` noterefs,
    # glossary words as links into Rjecnik.xhtml).
    #
    # == Text vs apparatus (the edition's own split)
    #
    # Every impressum says it: the work is public domain, but "sva autorska
    # prava na opremu knjige (rječnik, napomene, bilješka o piscu...) su
    # pridržana" — the apparatus (glossary, notes, author note, didactic
    # pages) is the publisher's and is never text here. Spine items are
    # apparatus by their first heading (Rječnik, Impressum, Sadržaj,
    # Bilješke, Bilješka o autoru, Prije čitanja, Kviz, Metodički
    # instrumentarij, Poticaji, a later author's "Dopuna"…), by their v3
    # file name, by carrying the impressum ("Nakladnik"), or by being the
    # e-book's own title page (`p.Autornaslov`, TitlePage, cover). Inside
    # the text, footnote anchors, inline glosses, footnote bodies and the
    # Courier line numbers are removed; glossary LINKS keep their word.
    #
    # == Passages
    #
    # One passage per text LINE: each block (p, h1–h6, li) is split at its
    # <br>s; a prose paragraph is one line, a verse stanza several. A line
    # with no letter or digit (the "* * *" section dividers, dotted
    # elisions) mints nothing.
    # Hidden headings (display:none — the editor's bracketed labels) are
    # skipped. Citation <spine position>.<line ordinal> — the position
    # counts every spine item (apparatus included), so the numbering is
    # the book's structure, not our filter.
    class ElektireEpubParser
      # "Bilješke" alone is the editor's endnotes; an author's own notes
      # ("Bilješka autora", "Bilješke M. A. Relkovića uz Satir") stay text.
      APPARATUS_HEADING = /\A(?:rje?čnik|riječnik|tumač|impres+um|sadržaj|bilješke\s*\z|
                             bilješk[ae]\so\s(?:autor|pisc|djel)|o\sautoru|prije\sčitanja|kviz|metodički|
                             poticaji|periodika|o\s.*dopun|.*:\s*dopuna|rječnik\s)/ix
      APPARATUS_FILE = /\A(?:coverpage|titlepage|logos|nav|quiz|kviz|metodicki|poticaji|prije.*|o-autoru|
                          impres+um|rjecnik|sadrzaj|biljeske|tumac|periodika|dopuna|.*_(?:rjecnik|biljeska|
                          impressum))\z/ix
      AUTHOR_NOTE = /\A(?:bilješka o (?:autoru|autorici|piscu)|o autoru)/i
      # The note's life line: "Split, 18. kolovoza 1450. - Split, 5. siječnja
      # 1524." / "(Dubrovnik, 1508. – Venecija, 2.5.1567.)" — the first
      # dash with a four-digit year before it and one after it.
      LIFE_LINE = /(?<!\d)(\d{4})\D{0,12}?\s[–—-]\s.{0,70}?(?<!\d)(\d{4})(?!\d)/m
      PD_PHRASE = /javn\w*\s+(?:dobr|domen)|ne postoje/i
      RESERVED_TRANSLATION = /prava za prijevod|redaktur\w*\s+prijevod|©\s*za prijevod|za prijevod:\s*©/i
      ANONYMOUS = /anonim|nepoznat/i
      BLOCKS = %w[p h1 h2 h3 h4 h5 h6 li].freeze
      DROP_SELECTOR = "[class*='Footnote'], [class*='footnote'], [class*='Endnote'], [class*='endnote'], " \
                      "[class^='middle'], [class*=' middle'], div[id^='ftn'], div[id^='edn'], aside, " \
                      "[class~='biljeske']"
      NOTE_HREF = /#_?(?:ftn|edn)\d/
      LINE_BREAK = ""

      Rights = Data.define(:statement, :reserved, :anonymous, :author_birth, :author_death, :life_line,
                           :isbn, :editor)
      Line = Data.define(:citation, :kind, :text)
      Opf = Data.define(:title, :creators, :language, :dates, :publisher, :identifiers, :subjects)
      Book = Data.define(:opf, :rights, :lines)

      # Rights + OPF only — what discovery's admission rule needs.
      def rights(path)
        with_book(path) { |root, opf_path| [read_opf(root, opf_path), read_rights(root, opf_path)] }
      end

      def parse(path)
        with_book(path) do |root, opf_path|
          opf = read_opf(root, opf_path)
          Book.new(opf: opf, rights: read_rights(root, opf_path), lines: read_lines(root, opf_path))
        end
      end

      private

      # Unpacks the EPUB into a scratch dir (one unzip per book, through
      # Nabu::Shell) and yields its root and the OPF path.
      def with_book(path)
        Dir.mktmpdir("nabu-elektire") do |root|
          Nabu::Shell.run("unzip", "-q", "-o", path, "-d", root)
          container = File.join(root, "META-INF", "container.xml")
          raise Nabu::ParseError, "#{path}: no META-INF/container.xml (not an EPUB)" unless File.file?(container)

          rootfile = xml(File.read(container), path).at_xpath("//rootfile")&.[]("full-path") or
            raise Nabu::ParseError, "#{path}: container names no rootfile"
          yield root, File.join(root, rootfile)
        end
      rescue Nabu::Shell::Error => e
        raise Nabu::ParseError, "#{path}: unreadable EPUB (#{e.message})"
      end

      def xml(source, path)
        doc = Nokogiri::XML(source)
        doc.remove_namespaces!
        doc
      rescue Nokogiri::XML::SyntaxError => e
        raise Nabu::ParseError, "#{path}: malformed XML: #{e.message}"
      end

      def read_opf(_root, opf_path)
        doc = xml(File.read(opf_path, encoding: "UTF-8"), opf_path)
        meta = doc.at_xpath("//metadata") or raise Nabu::ParseError, "#{opf_path}: OPF without metadata"
        texts = ->(name) { meta.xpath(name).map { |n| squeeze(n.text) }.reject(&:empty?) }
        dates = meta.xpath("date").to_h { |d| [d["event"] || "date", squeeze(d.text)] }
        Opf.new(title: texts.call("title").first, creators: texts.call("creator"),
                language: texts.call("language").first, dates: dates, publisher: texts.call("publisher").first,
                identifiers: texts.call("identifier"), subjects: texts.call("subject"))
      end

      # [[href, path, heading, html]] in spine order.
      def spine(opf_path)
        doc = xml(File.read(opf_path, encoding: "UTF-8"), opf_path)
        manifest = doc.xpath("//manifest/item").to_h { |item| [item["id"], item["href"]] }
        base = File.dirname(opf_path)
        doc.xpath("//spine/itemref").filter_map do |ref|
          href = manifest[ref["idref"]] or next
          path = File.join(base, href.split("#").first)
          next unless File.file?(path)

          html = Nokogiri::HTML5(File.read(path, encoding: "UTF-8"))
          heading = html.at_css("h1, h2, h3")
          [href, path, heading ? squeeze(heading.text) : "", html]
        end
      end

      def read_rights(_root, opf_path)
        items = spine(opf_path)
        impressum = items.find { |(_h, _p, _head, html)| plain(html).include?("Nakladnik") }
        text = impressum ? plain(impressum[3]) : ""
        sentences = text.split(/(?<=[.!?])\s+/)
        statement = sentences.grep(PD_PHRASE).first
        reserved = sentences.grep(/prijevod|redaktur/i).grep_v(/istekl|javn/i).first ||
                   text[RESERVED_TRANSLATION]
        birth, death, life = life_years(items)
        opf_creators = read_opf(nil, opf_path).creators
        Rights.new(
          statement: statement, reserved: reserved,
          anonymous: (opf_creators.any? && opf_creators.all? { |c| c.match?(ANONYMOUS) }) ||
                     statement.to_s.match?(/anonimn/i),
          author_birth: birth, author_death: death, life_line: life,
          isbn: text[/ISBN:?\s*([0-9X-]{10,17})/, 1],
          editor: text[/Urednik:\s*(.+?)(?=\s+\p{Lu}[\p{Ll} ]*:|\s*$)/, 1]
        )
      end

      def life_years(items)
        note = items.find do |(href, _p, heading, _html)|
          heading.match?(AUTHOR_NOTE) || File.basename(href, ".*").casecmp?("O-autoru")
        end
        return [nil, nil, nil] unless note

        body = note[3].at_css("body")&.dup or return [nil, nil, nil]
        body.at_css("h1, h2, h3")&.remove
        head = plain(body)[0, 170]
        match = head.match(LIFE_LINE) or return [nil, nil, nil]

        [match[1].to_i, match[2].to_i, squeeze(match[0])]
      end

      def read_lines(_root, opf_path)
        lines = []
        spine(opf_path).each_with_index do |(href, _path, heading, html), index|
          next if apparatus?(href, heading, html)

          ordinal = 0
          text_lines(html).each do |kind, text|
            lines << Line.new(citation: "#{index + 1}.#{ordinal += 1}", kind: kind, text: text)
          end
        end
        lines
      end

      def apparatus?(href, heading, html)
        File.basename(href, ".*").match?(APPARATUS_FILE) ||
          heading.match?(APPARATUS_HEADING) ||
          html.at_css("p.Autornaslov") ||
          plain(html).include?("Nakladnik")
      end

      def text_lines(html)
        body = html.at_css("body") or return []

        body.css(DROP_SELECTOR).each(&:remove)
        body.css("a[href]").each do |a|
          a.remove if a["href"].match?(NOTE_HREF) || a["epub:type"].to_s.include?("noteref")
        end
        # Courier-styled spans hold the edition's line numbers AND the verse
        # <br>s: keep only the breaks. Breaks become a private-use sentinel
        # (libxml merges adjacent text nodes, so a plain "\n" placeholder
        # would melt into the whitespace fold); source newlines are HTML
        # whitespace, folded — the <br>s are the only line breaks.
        body.css("span[style*='Courier'], span[style*='courier']").each do |span|
          span.replace(Nokogiri::XML::Text.new(LINE_BREAK * span.css("br").size, body.document))
        end
        body.css("br").each { |br| br.replace(Nokogiri::XML::Text.new(LINE_BREAK, body.document)) }
        body.css(BLOCKS.join(", ")).reject { |b| b.ancestors.any? { |a| BLOCKS.include?(a.name) } }
                                   .flat_map do |block|
                                     next [] if block["style"].to_s.match?(/display:\s*none/)

                                     kind = block.name.start_with?("h") ? "head" : "line"
                                     block.text.split(LINE_BREAK).map { |line| squeeze(line) }.grep(/[\p{L}\p{N}]/)
                                          .map do |line|
                                       [
                                         kind, Normalize.nfc(line)
                                       ]
                                     end
                                   end
      end

      def plain(node)
        squeeze(node.text)
      end

      def squeeze(text)
        text.to_s.gsub(/[[:space:]]+/, " ").strip
      end
    end
  end
end
