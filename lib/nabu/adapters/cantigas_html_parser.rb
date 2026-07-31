# frozen_string_literal: true

require "nokogiri"

require_relative "../normalize"

module Nabu
  module Adapters
    # Parser family "cantigas-html" (P55-1): one edition page of Cantigas
    # Medievais Galego-Portuguesas (cantigas.fcsh.unl.pt; Projeto Littera,
    # IEM/FCSH-NOVA) — a Classic ASP server-rendered HTML page per cantiga.
    # DOM-based: pages are 25–45 KB (census 2026-07-31), far under the
    # >5 MB Reader rule. A NEW family, not an otdo-html composition: OTDO's
    # grammar is span-labelled lines split on <br> inside div.textBody1;
    # Littera's is a 4-column layout table with class-family verse cells,
    # nbsp stanza-break rows, a sidebar section walk and a Windows-1252
    # decode boundary — no shared seam beyond Nokogiri.
    #
    # == The decode boundary (the corpus's key quirk)
    #
    # The Content-Type header carries no charset, the in-page meta claims
    # ISO-8859-1, and the ACTUAL bytes are Windows-1252 (0x92 ’, 0x93/0x94
    # curly quotes, 0x96 – verified in the wild). Every page decodes
    # Windows-1252 → UTF-8 here (the kradfile force_encoding pattern), then
    # NFC per house rule; an undecodable byte quarantines loudly. Medieval
    # nasals (ũ ẽ Ũ) arrive as numeric character entities — Nokogiri
    # decodes them, NFC keeps the precomposed forms.
    #
    # == Page anatomy (scout ground truth 2026-07-31, fixture evidence)
    #
    # div#main holds nested layout tables. The VERSE TABLE is the one whose
    # rows carry td.left11/.left13/.left15 (the class family varies with
    # the tamanho font parameter — anchor on the family, never the width):
    #
    #   author row     p.titulo-autor > a[href*="autor.asp?…cdaut=<id>"]
    #   rubric label   a 4-td row whose text td reads "Rubrica:" (brown
    #                  font), sometimes present; the NEXT 4-td row holds
    #                  the italic rubric text
    #   verse row      4 tds: icons | line number (every 5th) | spacer |
    #                  the line text (the left1X class)
    #   stanza break   a tr whose SINGLE td holds &nbsp;&nbsp;
    #
    # The sidebar div#col-dta2 carries span.tit sections: *Descrição*
    # (first line = the genre, then the formal features), *Fontes
    # manuscritas* (sigla text lines: "B 1, L 1", "(C 1)"), *Versões
    # musicais* (out of scope). The Nota geral apparatus stays in the
    # canonical file, never in passages or metadata.
    #
    # Both page variants parse identically: the crawl lands
    # semanotacoes=true pages (note apparatus stripped), but the
    # with-notes shape (glossary icons in the first td, inline span.ref
    # wrappers around verse words) reads the same — the text td's visible
    # text IS the verse either way.
    #
    # == Passage = the verse LINE, 1-based ordinal
    #
    #   urn = <document-urn>:<n>   (urn:nabu:cantigas:600:5)
    #
    # The ordinal is cross-checked against the edition's own printed
    # numbers (every 5th line) — a mismatch means the numbering scheme
    # drifted and quarantines, so the ordinal IS the edition's line number,
    # never a synthetic. Stanza structure rides annotations
    # ({"line" => n, "stanza" => s}, the ASPR line-ordinal precedent plus a
    # stanza counter over the nbsp break rows); title = the incipit (the
    # first verse line). Language: roa-opt, Old Galician-Portuguese
    # (D55-a — the code already lives in the catalog's dictionary/name
    # space, so etymology and cognate joins connect for free).
    #
    # == Identity
    #
    # The page's own self-links carry its cdcant (the print link
    # cantiga_print.asp?cdcant=N rides every cantiga page); drift between
    # the filename-minted urn and the served page quarantines.
    class CantigasHtmlParser
      URN_PREFIX = "urn:nabu:cantigas:"

      # Old Galician-Portuguese (D55-a, the registry's roa-opt lane).
      LANGUAGE = "roa-opt"

      # The verse-cell class family — one class per tamanho font size.
      VERSE_TD_CSS = "td.left11, td.left13, td.left15"

      RUBRIC_LABEL = "Rubrica:"

      # The censused genre labels (letter-A index + sidebar, 2026-07-31),
      # keyed by Unicode downcase — the index prints BOTH "Escárnio e
      # maldizer" and "Escárnio e Maldizer", one facet value comes out.
      # const: genre census 2026-07-31, extend as new letters surface labels
      CANONICAL_GENRES = [
        "Amigo", "Amor", "Escárnio e maldizer", "Género incerto", "Tenção",
        "Tenção de amor", "Lai", "Loor", "Sirventês moral", "Espúria"
      ].to_h { |genre| [genre.downcase, genre] }.freeze

      # The sidebar's "Cantiga de Amigo" / "Cantigas de amor" wrapper — the
      # stored facet is the bare genre.
      GENRE_PREFIX = /\Acantigas? d[eo] /i

      # One normalized facet value per genre: strip the "Cantiga de "
      # wrapper, then fold the censused case variants to their canonical
      # spelling; an un-censused label passes through prefix-stripped.
      def self.normalize_genre(raw)
        stripped = raw.sub(GENRE_PREFIX, "").strip
        CANONICAL_GENRES.fetch(stripped.downcase, stripped)
      end

      def parse(path, urn:)
        cdcant = expected_cdcant(urn)
        page = Nokogiri::HTML(decode(path))
        check_identity!(page, cdcant, path)
        main = page.at_css("div#main") or
          raise Nabu::ValidationError, "no div#main content block — the page shape drifted (#{path})"
        lines = verse_lines(main, path)
        document = build_document(urn, path, lines, metadata(page, main))
        append_lines!(document, urn, lines)
        document
      end

      private

      def expected_cdcant(urn)
        unless urn.start_with?(URN_PREFIX)
          raise Nabu::ValidationError, "urn #{urn.inspect} does not carry the #{URN_PREFIX} prefix"
        end

        urn.delete_prefix(URN_PREFIX)
      end

      # Windows-1252 → UTF-8, the one decode boundary (class note). The
      # in-page meta's ISO-8859-1 claim is FALSE — trusting it would turn
      # 0x92/0x93/0x96 into C1 control characters.
      def decode(path)
        File.binread(path).force_encoding(Encoding::Windows_1252).encode(Encoding::UTF_8)
      rescue EncodingError => e
        raise Nabu::ValidationError, "#{path}: not decodable as Windows-1252 (#{e.message}) — " \
                                     "the upstream encoding drifted; re-census before parsing"
      end

      # Every cantiga page self-references its cdcant in the print link;
      # drift between the filename-minted urn and the served page
      # quarantines (the crawl landed a different page under this id).
      def check_identity!(page, cdcant, path)
        served = page.to_html[/cantiga_print\.asp\?cdcant=(\d+)/, 1]
        return if served == cdcant

        raise Nabu::ValidationError,
              "page self-links say cdcant=#{served || 'none'}, expected #{cdcant} (#{path}) — " \
              "the crawl landed a different page under this id"
      end

      def build_document(urn, path, lines, metadata)
        Nabu::Document.new(
          urn: urn, language: LANGUAGE, canonical_path: path,
          title: lines.first[:text], metadata: metadata
        )
      end

      # -- the verse table --------------------------------------------------------

      # [{text:, line:, stanza:}, …] — the verse rows of the one table that
      # carries the left1X class family, with the stanza counter driven by
      # the nbsp break rows and the printed every-5th numbers cross-checked
      # against the 1-based ordinal.
      def verse_lines(main, path)
        anchor = main.at_css(VERSE_TD_CSS) or
          raise Nabu::ValidationError, "no verse lines (no #{VERSE_TD_CSS} cell) — every cantiga " \
                                       "page carries verse, so the page shape drifted (#{path})"
        lines = []
        stanza = 1
        break_pending = false
        anchor.ancestors("table").first.xpath("./tr | ./tbody/tr").each do |row|
          tds = row.xpath("./td")
          if verse_row?(tds)
            stanza += 1 if break_pending
            break_pending = false
            lines << verse_line(tds, lines.size + 1, stanza, path)
          elsif stanza_break?(tds) && lines.any?
            break_pending = true
          end
        end
        raise Nabu::ValidationError, "zero verse lines in the verse table — the page shape drifted (#{path})" if
          lines.empty?

        lines
      end

      def verse_row?(tds)
        tds.size == 4 && tds.last.matches?(VERSE_TD_CSS)
      end

      # The break row: one td holding only no-break spaces.
      def stanza_break?(tds)
        tds.size == 1 && tds.first.text.include?(" ") &&
          tds.first.text.match?(/\A[[:space:]]*\z/)
      end

      def verse_line(tds, ordinal, stanza, path)
        printed = fold(tds[1].text)
        if !printed.empty? && printed != ordinal.to_s
          raise Nabu::ValidationError,
                "printed line number #{printed.inspect} against ordinal #{ordinal} (#{path}) — " \
                "the edition's numbering scheme drifted; the ordinal must BE the edition's number"
        end

        text = fold(tds.last.text)
        raise Nabu::ValidationError, "verse line #{ordinal} is empty (#{path}) — the page shape drifted" if
          text.empty?

        { text: text, line: ordinal, stanza: stanza }
      end

      def append_lines!(document, urn, lines)
        lines.each do |line|
          document << Nabu::Passage.new(
            urn: "#{urn}:#{line[:line]}", language: LANGUAGE, text: line[:text],
            annotations: { "line" => line[:line], "stanza" => line[:stanza] },
            sequence: line[:line] - 1
          )
        end
      end

      # nbsp → space, whitespace folded, NFC at the boundary.
      def fold(text)
        Nabu::Normalize.nfc(text.tr(" ", " ").gsub(/[[:space:]]+/, " ").strip)
      end

      # -- metadata ---------------------------------------------------------------

      def metadata(page, main)
        metadata = author_fields(main)
        sections = sidebar_sections(page)
        genre_line, *form = sections["Descrição"]
        raise Nabu::ValidationError, "no Descrição genre line in the sidebar — the page shape drifted" if
          genre_line.nil? || genre_line.empty?

        metadata["genre"] = self.class.normalize_genre(genre_line)
        metadata["form"] = form unless form.empty?
        manuscripts = sections.fetch("Fontes manuscritas", [])
        metadata["manuscripts"] = manuscripts unless manuscripts.empty?
        rubric = rubric_text(main)
        metadata["rubric"] = rubric if rubric
        metadata
      end

      def author_fields(main)
        link = main.at_css("p.titulo-autor a[href*='autor.asp']") or
          raise Nabu::ValidationError, "no p.titulo-autor author link — the page shape drifted"
        cdaut = link["href"][/cdaut=(\d+)/, 1] or
          raise Nabu::ValidationError, "author link #{link['href'].inspect} carries no cdaut id"
        { "author" => fold(link.text), "author_id" => Integer(cdaut, 10) }
      end

      # The italic rubric text: the first 4-td non-verse row FOLLOWING the
      # "Rubrica:" label row (both precede the verse). Pages without the
      # label honestly yield nil.
      def rubric_text(main)
        label = main.xpath(".//tr[count(td) = 4]").find { |row| fold(row.text) == RUBRIC_LABEL } or
          return nil
        row = label.xpath("./following-sibling::tr[count(td) = 4]").first or return nil
        text = fold(row.xpath("./td").last.text)
        text.empty? ? nil : text
      end

      # {"Descrição" => ["Lai", "Mestria", …], "Fontes manuscritas" =>
      # ["B 1, L 1", "(C 1)"], …} — a linear walk of the div#col-dta2
      # sidebar: a .tit element opens a section, <br> flushes a line, text
      # and inline <i> accumulate, any other element closes the section
      # (the (Saber mais) em, the manuscript thumbnail links).
      def sidebar_sections(page)
        sidebar = page.at_css("div#col-dta2") or return {}
        sections = Hash.new { |hash, key| hash[key] = [] }
        current = nil
        buffer = +""
        flush = lambda do
          line = fold(buffer)
          sections[current] << line if current && !line.empty?
          buffer = +""
        end
        sidebar.children.each do |node|
          if node.element? && node.classes.include?("tit")
            flush.call
            current = fold(node.text)
          elsif node.name == "br"
            flush.call
          elsif node.text? || node.name == "i"
            buffer << node.text
          elsif node.element? && node.matches?("p.tz-horizontal")
            nil # the section rule, decorative
          else
            flush.call
            current = nil
          end
        end
        flush.call
        sections
      end
    end
  end
end
