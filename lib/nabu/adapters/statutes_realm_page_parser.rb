# frozen_string_literal: true

require "nokogiri"

require_relative "source_read"
require_relative "statutes_realm_dating"
require_relative "statutes_realm_toc"

module Nabu
  module Adapters
    # One British History Online Statutes of the Realm act page → a
    # Nabu::Document (the statutes-realm parser family, P160-7).
    #
    # == The page (census 2026-11-05 over 43 real pages across vols 5–7)
    #
    #   h2.page-title span       the act title, "<Reign>, <session>: <title>"
    #   article p                the volume line ("Statutes of the Realm:
    #                            Volume 5, 1625-80. Originally published by
    #                            Great Britain Record Commission, s.l, 1819.")
    #                            and the licence line ("This free content was
    #                            digitised by double rekeying. Public Domain.")
    #   p.bho                    the citation ("ed. John Raithby")
    #   div.xsl-formatter        the text; its header ("In this section") is
    #     div.inner              navigation, never read. Inside .inner:
    #       h2 / h3 [id=hN-sK]   section heads — h2 the act's first section
    #                            (often empty, or "Chapter I.", or a topic
    #                            head), h3 the numbered sections ("II. …" —
    #                            Raithby's marginal note for the section)
    #       h4                   a sub-head inside a section (the county
    #                            lists of the aid acts) — a body line
    #       p                    a paragraph; one wholly in <em> is the
    #                            section's marginal summary
    #       div.table-wrap table the rate schedules — one line per row,
    #                            cells joined " | "
    #     footer.footnotes       Raithby's apparatus: a[id=fnnN] li "N. text"
    #
    # == Passage = the SECTION
    #
    # urn <doc>:s<K>, K = upstream's own section id (h2-s1, h3-s2, …).
    # Text = the section's enacted text, one line per paragraph / table row
    # / sub-head, whitespace collapsed (the printed line breaks are layout).
    # The section head rides as annotation "heading", em-only paragraphs as
    # "marginal_notes" (both Raithby's 1819 editorial apparatus, not the
    # statute's words), the footnotes a section anchors as "footnotes"
    # ([{n, text}], each once; the inline "(fn. N)" marker leaves the text,
    # the editor's brackets stay). A section with no body lines mints no
    # passage; its head is kept in document metadata "empty_sections".
    #
    # The text is kept AS REKEYED: the double rekeying dropped the
    # contraction marks of the record type ("enaed" for enacted, "Cmons"
    # for Commons) — canonical means canonical, no repair at parse.
    #
    # == Language
    #
    # en for every document: the asset marks no language anywhere (no lang
    # attribute below the page shell's own lang="en"). The roll's Latin
    # formulae (the private-act schedules' "Item quedam Petitiones …") and
    # any Law French ride inside en passages, deliberately coarse —
    # declared, never guessed.
    class StatutesRealmPageParser
      LANGUAGE = "en"

      BASE_URL = "https://www.british-history.ac.uk"

      LICENSE_STATEMENT = "This free content was digitised by double rekeying. Public Domain."

      VOLUME_LINE = /(Statutes of the Realm: Volume (\d+), [\d-]+)\.\s*Originally published by\s*(.+?)\.?\s*\z/m

      def parse(path, urn:, row: nil)
        page = Nokogiri::HTML(SourceRead.utf8_file(path, label: "statutes-realm page"))
        title = squish(page.at_css("h2.page-title span")&.text.to_s)
        raise Nabu::ParseError, "#{path}: no page title" if title.empty?

        check_license!(page, path)
        inner = page.at_css("div.xsl-formatter div.inner")
        raise Nabu::ParseError, "#{path}: no act text (no div.inner)" if inner.nil?

        @footnotes = footnotes(page)
        sections, empty = sections(inner)
        raise Nabu::ParseError, "#{path}: no act text (no section carries a body)" if sections.empty?

        document = Nabu::Document.new(urn: urn, language: LANGUAGE, title: title, canonical_path: path,
                                      metadata: metadata(page, title, path, row, empty))
        sections.each_with_index do |section, index|
          document << Nabu::Passage.new(urn: "#{urn}:s#{section[:id]}", language: LANGUAGE,
                                        text: section[:lines].join("\n"), sequence: index + 1,
                                        annotations: section[:annotations])
        end
        document
      rescue ArgumentError => e
        raise Nabu::ParseError, "#{path}: #{e.message}"
      end

      private

      # The per-page licence line is the licence basis (it overrides the
      # site-wide terms "unless otherwise stated") — a page without it is
      # refused, never admitted under the series' class.
      def check_license!(page, path)
        statement = page.css("article p").map { |p| squish(p.text) }.find { |text| text.include?("double rekeying") }
        return if statement == LICENSE_STATEMENT

        raise Nabu::ParseError, "#{path}: the page lacks \"#{LICENSE_STATEMENT}\" (read #{statement.inspect}) — " \
                                "no Public Domain basis for this page"
      end

      # {"1" => "Constable O."} from the page footer.
      def footnotes(page)
        page.css("footer.footnotes a[id^=fnn]").each_with_object({}) do |anchor, notes|
          number = anchor["id"].delete_prefix("fnn")
          text = squish(anchor.text).sub(/\A#{Regexp.escape(number)}\.\s*/, "")
          notes[number] ||= text
        end
      end

      def sections(inner)
        sections = []
        empty = []
        current = new_section("0")
        each_block(inner) do |node|
          if %w[h2 h3].include?(node.name)
            flush(current, sections, empty)
            current = new_section(node["id"].to_s[/-s(\d+)\z/, 1] || "0")
            note_refs(node, current)
            current[:heading] = clean(node)
          else
            add_block(node, current)
          end
        end
        flush(current, sections, empty)
        [sections, empty]
      end

      # The block-level children of .inner, table wrappers descended.
      def each_block(inner, &block)
        inner.element_children.each do |node|
          if node.name == "div"
            each_block(node, &block)
          else
            yield node
          end
        end
      end

      def new_section(id) = { id: id, heading: nil, lines: [], marginal: [], notes: [] }

      def add_block(node, section)
        note_refs(node, section)
        case node.name
        when "table"
          node.css("tr").each do |tr|
            cells = tr.css("td, th").map { |cell| clean(cell) }.reject(&:empty?)
            section[:lines] << cells.join(" | ") unless cells.empty?
          end
        when "p", "h4"
          text = clean(node)
          return if text.empty?

          if marginal?(node, text)
            section[:marginal] << text.delete_suffix(".")
          else
            section[:lines] << text
          end
        end
      end

      # A paragraph wholly in one <em> (bar a closing full stop) is the
      # section's marginal summary.
      def marginal?(node, text)
        return false unless node.name == "p"

        ems = node.element_children
        return false unless ems.size == 1 && ems.first.name == "em"

        squish(ems.first.text).delete_suffix(".") == text.delete_suffix(".")
      end

      # The footnotes a block anchors, each once per section, in order.
      def note_refs(node, section)
        node.css("a[href^='#fnn']").each do |anchor|
          number = anchor["href"].delete_prefix("#fnn")
          section[:notes] << number if @footnotes.key?(number) && !section[:notes].include?(number)
        end
      end

      def flush(section, sections, empty)
        if section[:lines].empty?
          empty << section[:heading] if section[:heading] && !section[:heading].empty?
          return
        end

        annotations = {}
        annotations["heading"] = section[:heading] if section[:heading] && !section[:heading].empty?
        annotations["marginal_notes"] = section[:marginal] unless section[:marginal].empty?
        unless section[:notes].empty?
          annotations["footnotes"] = section[:notes].map { |n| { "n" => n, "text" => @footnotes[n] } }
        end
        sections << { id: section[:id], lines: section[:lines], annotations: annotations }
      end

      # A node's text with the footnote markers removed.
      def clean(node)
        copy = node.dup
        copy.css("a[href^='#fnn']").each(&:remove)
        copy.css("br").each { |br| br.replace(" ") }
        squish(copy.text)
      end

      def metadata(page, title, path, row, empty)
        volume_line = page.css("article p").map { |p| squish(p.text) }.find { |text| VOLUME_LINE.match?(text) }
        match = volume_line && VOLUME_LINE.match(volume_line)
        raise Nabu::ParseError, "#{path}: no volume line" if match.nil?

        volume = Integer(match[2], 10)
        slug = File.basename(path, ".html")
        heading = StatutesRealmDating.heading(title)
        meta = {
          "volume" => volume, "volume_title" => match[1], "originally_published" => match[3],
          "editor" => editor(page), "upstream_url" => "#{BASE_URL}/statutes-realm/vol#{volume}/#{slug}",
          "license_statement" => LICENSE_STATEMENT, "document_type" => document_type(title)
        }
        meta["pages"] = row.pages if row && !row.pages.empty?
        if heading
          meta["reign"] = heading.reign
          meta["session"] = heading.session
          chapter = heading.rest[/\[Chapter ([IVXLC]+)\b/, 1]
          meta["chapter"] = chapter if chapter
          roll = heading.rest[/\[Chapter [IVXLC]+\.?\s*(R[oa]t\. Parl\..*?)\]?\s*\z/, 1]
          meta["roll_reference"] = roll.strip if roll
          regnal = StatutesRealmDating.regnal(title)
          meta["regnal"] = regnal if regnal
          meta["date"] = StatutesRealmDating.date(title)
        end
        meta["empty_sections"] = empty unless empty.empty?
        meta
      end

      def document_type(title)
        StatutesRealmToc.grain(title) == :private_acts ? "private acts list" : "act"
      end

      def editor(page)
        squish(page.at_css("p.bho")&.text.to_s)[/ed\.\s+(.+?)\s+\(/, 1]
      end

      def squish(text)
        Nabu::Normalize.nfc(text.tr(" ", " ").gsub(/[[:space:]]+/, " ").strip)
      end
    end
  end
end
