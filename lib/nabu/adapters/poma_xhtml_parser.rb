# frozen_string_literal: true

require "nokogiri"

module Nabu
  module Adapters
    # The poma-xhtml parser family (P117-5): one page of the Royal Danish
    # Library's Guaman Poma edition (poma.kb.dk). Everything below the
    # site chrome lives in #contentPage > div, a flat run of <blockquote>
    # and <p> blocks — classified here by their own markup (census over
    # the whole crawl, 2026-10-11):
    #
    #   blockquote           the edition's drawing caption ("Dibujo 39. …")
    #                        → drawing {number, caption}
    #   p.regpagenumber      "315 [317]": Guaman Poma's own page number
    #                        (or "s.n.") + the standard pagination in
    #                        brackets; a span.textdesc ("[portada]")
    #   p > sup#commentid…   the editors' commentary notes (Murra/Adorno/
    #                        Urioste 1980/1987 + the 2004 Adorno/Boserup
    #                        notes, "[2004:]") → commentary
    #   p > sup (first)      the letter-keyed gloss line ("a señor
    #                        poderoso | b poderoso", "a GH, p. 273") → glosses
    #   p "/ <em>…</em> /"   the edition's modern-orthography list of the
    #                        page's Andean terms ("/ taki / qhapaq apukuna /")
    #                        → andean_terms (split on " / ")
    #   p (only span.trans)  a paragraph-long editorial translation →
    #                        attached to the preceding text paragraph
    #   any other p          TRANSCRIPTION — a passage
    #
    # Inside a transcription paragraph the editors' bracketed insertions
    # are spans: trans (Spanish translation of an Andean term), regname
    # (the standard name), explicit (an explicitation), sic, ref; and
    # <sup> note markers point at commentary (digits) or glosses
    # (letters). The passage text drops all of them (recorded per passage
    # as "editorial" and "notes"); the edition's display reading — the
    # same paragraph WITH its bracketed insertions — rides as
    # "edition_text" when it differs. Brackets inside a word (S[EÑ]OR,
    # Ju[an]) are the transcription's own expansions and stay. Whitespace
    # collapses (the source files wrap prose and verse alike — line
    # structure is not recoverable, declared). <em> runs ride as "italic":
    # the edition italicizes Quechua, Aymara and Latin words alike and
    # tags no language (316 lang attributes on the whole site, every one
    # lang="es" on a bibliography link).
    class PomaXhtmlParser
      Page = Data.define(:page, :page_notes, :gp_page, :textdesc, :section, :drawing, :paragraphs,
                         :commentary, :glosses, :andean_terms, :see_page, :image)
      Paragraph = Data.define(:text, :edition_text, :italic, :editorial, :notes, :translation)

      EDITORIAL_CLASSES = %w[trans regname explicit sic ref].freeze
      DRAWING = /\ADibujo (\d+)\.\s*(.*)\z/m
      CUT = "\u0001" # an excised editorial node's place (#closed)
      SEE_PAGE = /\AFor the transcription of page \d+, see page (\d+)\.\z/

      def parse(path)
        doc = Nokogiri::HTML(File.read(path, encoding: "UTF-8"))
        body = doc.at_css("#contentPage > div") or raise Nabu::ParseError, "#{path}: no #contentPage block"

        @state = { page: nil, page_notes: [], gp_page: nil, textdesc: nil, drawing: nil, paragraphs: [],
                   commentary: [], glosses: [], andean_terms: [], see_page: nil }
        body.element_children.each { |block| classify(block) }
        Page.new(**@state, section: section(doc), image: doc.at_css("#contentPage > img")&.[]("src"))
      end

      private

      def classify(block)
        return drawing(block) if block.name == "blockquote"
        return page_number(block) if block.at_css("span.regpagenumber")
        return commentary(block) if leading(block)&.matches?("sup[id^='commentid']")
        return gloss_line(block) if leading(block)&.name == "sup"
        return translation_only(block) if translation_only?(block)
        return andean_terms(block) if andean_terms?(block)
        return see_page(block) if SEE_PAGE.match?(squash(block.text))

        paragraph(block)
      end

      # The first non-blank child node.
      def leading(block)
        block.children.find { |c| !(c.text? && c.text.strip.empty?) }
      end

      def drawing(block)
        text = squash(block.text)
        match = DRAWING.match(text)
        @state[:drawing] = match ? { "number" => match[1].to_i, "caption" => squash(match[2]) } : { "caption" => text }
      end

      # pp. 834–837 carry a note marker inside the bracket ("[834<sup>1</sup>]")
      # — the marker is a note pointer, never part of the page number.
      def page_number(block)
        reg = block.at_css("span.regpagenumber").dup
        @state[:page_notes] = reg.css("sup").map { |s| s.text.strip }
        reg.css("sup").each(&:remove)
        @state[:page] = reg.text.strip.delete_prefix("[").delete_suffix("]")
        @state[:textdesc] = block.at_css("span.textdesc")&.text&.strip
        own = block.children.select(&:text?).map(&:text).join.strip
        @state[:gp_page] = own unless own.empty?
      end

      def commentary(block)
        marker = block.at_css("sup[id^='commentid']")
        n = marker.text.strip
        marker.remove
        @state[:commentary] << { "n" => n, "text" => squash(block.text) }
      end

      # The double-page Mapa Mundi (pp. 1001–1002): p. 1002 carries only
      # the edition's pointer "For the transcription of page 1002, see
      # page 1001." — editorial, never transcription.
      def see_page(block)
        @state[:see_page] = SEE_PAGE.match(squash(block.text))[1]
      end

      def gloss_line(block)
        @state[:glosses] << squash(block.text)
      end

      def translation_only?(block)
        kids = block.children.reject { |c| c.text? && c.text.strip.empty? }
        !kids.empty? && kids.all? { |c| c.element? && c.name == "span" && c["class"] == "trans" }
      end

      def translation_only(block)
        text = squash(block.text)
        last = @state[:paragraphs].pop
        return if text.empty? # an empty trans span (five in the census) carries nothing

        if last.nil?
          @state[:glosses] << text
        else
          @state[:paragraphs] << last.with(translation: [last.translation, text].compact.join(" "))
        end
      end

      # "/ <em>taki / qhapaq apukuna</em> /": a lone "/" then an italic
      # run opens the line ("/ INRI /" and "/ S[acra] C[atólica] … /" are
      # transcription: their slash leads text, not an <em>). On the song
      # pages the line also carries the normalized songs themselves, with
      # upstream's plain-text Dios/sino and [?] between the italic runs.
      def andean_terms?(block)
        first = leading(block)
        return false unless first&.text? && first.text.strip == "/"

        following = first.next_sibling
        following = following.next_sibling while following&.text? && following.text.strip.empty?
        following&.element? && following.name == "em"
      end

      def andean_terms(block)
        @state[:andean_terms].concat(squash(block.text).split(%r{\s*/\s*}).map(&:strip).reject(&:empty?))
      end

      def paragraph(block)
        notes = block.css("sup").map { |s| s.text.strip }
        editorial = block.css("span").filter_map do |span|
          klass = span["class"].to_s
          { "type" => klass, "text" => squash(span.text) } if EDITORIAL_CLASSES.include?(klass)
        end
        italic = block.css("em, i").map { |e| squash(e.text) }.reject(&:empty?)
        edition = block.dup
        edition.css("sup").each { |node| node.replace(Nokogiri::XML::Text.new(CUT, edition.document)) }
        edition_text = closed(edition.text)
        edition.css(EDITORIAL_CLASSES.map { |k| "span.#{k}" }.join(", ")).each do |node|
          node.replace(Nokogiri::XML::Text.new(CUT, edition.document))
        end
        text = closed(edition.text)
        return if text.empty?

        @state[:paragraphs] << Paragraph.new(text: text, edition_text: edition_text, italic: italic,
                                             editorial: editorial, notes: notes, translation: nil)
      end

      # Excised nodes leave a CUT mark; a run of cuts (and the whitespace
      # that only separated them) closes up before punctuation — "cachiua
      # <span>[…]</span> <sup>a</sup>, haylli" reads "cachiua, haylli" —
      # and is a plain space elsewhere.
      def closed(text)
        squash(text.gsub(/[\s#{CUT}]*#{CUT}[\s#{CUT}]*(?=[.,;:!?])/o, "").tr(CUT, " "))
      end

      # The page's section label from the content header ("16. El capítulo
      # de las fiestas (317-329) [318]" → without the bracketed page).
      def section(doc)
        header = doc.at_css("#contentHeader h1")&.text or return nil
        label = squash(header).sub(/\s*\[[^\]]*\]?\z/, "") # "[834" when a note marker cut the h1
        label.empty? ? nil : label
      end

      def squash(text)
        text.gsub(/\s+/, " ").strip
      end
    end
  end
end
