# frozen_string_literal: true

require "nokogiri"

require_relative "../normalize"

module Nabu
  module Adapters
    # The wikisource-html parser family (P116-3): turns ONE page's
    # server-rendered HTML (api.php action=parse, pinned to the page's
    # revid) into passages. The Slavic wikisources transclude their
    # proofread texts from scan pages (<pages index> with fromsection/
    # tosection, page-name ranges, labelled sections) and wrap them in
    # header templates with per-wiki machinery; the rendered page is the
    # one shape where all of that has already resolved, so the parse
    # needs no per-wiki template policy.
    #
    # == Text root (in order)
    #
    # 1. div.prp-pages-output — the ProofreadPage transclusion output IS
    #    the text (headers, licence boxes and "see also" lists sit
    #    outside it);
    # 2. div.text — the ru/uk text-body wrapper;
    # 3. the whole .mw-parser-output minus furniture.
    #
    # == Furniture (removed before reading)
    #
    # Anything hidden (display:none — including the [Korekta] print
    # readings, so the text reads as the page shows it), .ws-noexport
    # (page-number markers, nav), header/footer templates (#headertemplate,
    # #ws-footer, #mojNaglowek, table.textinfo, .navigacePaP), reference
    # markers and lists, figures, navboxes, licence boxes, TOCs, styles.
    #
    # Renderer red links (a.new) whose text is the bare namespaced target —
    # the placeholders for missing scan pages / templates — are removed
    # too (#placeholder_redlink?).
    #
    # == Segmentation
    #
    # Block boundaries (p, div, tr/td, li, dd, headings…) separate
    # passages; <br> is a line break kept INSIDE a passage (verse lines
    # stay lines, a blank line splits stanzas); source-formatting
    # whitespace collapses. Headings h2–h4 become the "section" of the
    # passages after them, never passages themselves. A paragraph of
    # nothing but punctuation and digits (dates, numbering) is dropped, and
    # so is a list item/paragraph whose every letter sits inside a link
    # (edition lists, TOCs, "see also" — navigation, never text).
    class WikisourceHtmlParser
      Passage = Data.define(:text, :section)

      FURNITURE = [
        "[style*='display:none']", "[style*='display: none']",
        ".ws-noexport", ".ws-pagenum", "#headertemplate", "#ws-footer", "#mojNaglowek",
        "#mojaStopka", "#Template_law", "table.textinfo", ".navigacePaP", ".toccolours",
        "sup.reference", ".mw-references-wrap", "ol.references", ".reference",
        "figure", ".thumb", ".navbox", ".metadata", ".noprint", "#toc", ".toc",
        ".mw-editsection", ".catlinks", "style", "script", "link", "img",
        ".interwiki-extra", ".mw-empty-elt",
        # maintenance banners ("Tato stránka potřebuje úpravy." — cs labels)
        ".label-pageinfo", ".ambox",
        # cs: the Kralice print's marginal summaries (Wikizdroje renders
        # them inline) — marginalia, kept out of the verse text
        ".poznamkapostrane"
      ].freeze

      BLOCKS = %w[p div table tbody tr td th ul ol li dl dd dt blockquote center pre section].freeze
      HEADINGS = %w[h1 h2 h3 h4 h5 h6].freeze
      SECTION_MARK = "\u0001"
      BREAK = "\u0002"

      def parse(html)
        root = Nokogiri::HTML5.fragment(html.to_s)
        root.css("a.new").each { |link| link.remove if placeholder_redlink?(link) }
        root.css(FURNITURE.join(", ")).each(&:remove)
        root.css("li, dd, dt, p").each { |node| node.remove if link_only?(node) }
        # Hand-made note markers outside the cite machinery (ru: a link to
        # the edition's endnote page wrapping <sup>[пр.1]</sup>).
        root.css("sup").each { |node| node.remove if node.text.strip.match?(/\A\[[^\[\]]{1,12}\]\z/) }
        buffer = +""
        text_roots(root).each do |node|
          walk(node, buffer)
          buffer << "\n\n"
        end
        segment(buffer)
      end

      private

      def text_roots(root)
        pages = root.css("div.prp-pages-output")
        return pages unless pages.empty?

        bodies = root.css("div.text")
        return bodies unless bodies.empty?

        output = root.css("div.mw-parser-output")
        output.empty? ? [root] : output
      end

      # A red link the RENDERER emitted for a transclusion target that does
      # not exist — a not-yet-created scan page ("Laman:X.pdf/9") or a
      # missing template ("Templat:U"): its text is the bare namespaced
      # target title, never a word of the text (P120-3, the ms manuscript
      # ranges run far past the transcribed pages).
      def placeholder_redlink?(link)
        return false unless link["href"].to_s.include?("redlink=1")

        text = link.text.gsub(/[[:space:]]+/, " ").strip
        text.include?(":") && link["title"].to_s.gsub(/[[:space:]]+/, " ").start_with?(text)
      end

      # A list item / paragraph whose every letter sits inside a link is
      # navigation (edition lists, TOCs, "see also"), never text.
      def link_only?(node)
        links = node.css("a")
        return false if links.empty?

        outside = node.text.dup
        links.each { |link| outside = outside.sub(link.text, "") }
        !outside.match?(/\p{L}/)
      end

      def walk(node, buffer)
        node.children.each do |child|
          if child.text?
            buffer << child.text.gsub(/[[:space:]]+/, " ")
          elsif child.element?
            name = child.name.downcase
            if name == "br"
              buffer << BREAK
            elsif HEADINGS.include?(name)
              buffer << "\n\n#{SECTION_MARK}#{child.text.gsub(/[[:space:]]+/, ' ').strip}\n\n"
            elsif BLOCKS.include?(name)
              buffer << "\n\n"
              walk(child, buffer)
              buffer << "\n\n"
            else
              walk(child, buffer)
            end
          end
        end
      end

      # Block boundaries are "\n\n"; <br> is BREAK. A stanza break is two
      # BREAKs with only spaces between them.
      def segment(buffer)
        section = nil
        passages = []
        buffer.split(/\n\s*\n/).each do |chunk|
          chunk.split(/#{BREAK}[[:blank:]]*#{BREAK}/o).each do |stanza|
            if stanza.strip.start_with?(SECTION_MARK)
              section = Nabu::Normalize.nfc(stanza.strip.delete_prefix(SECTION_MARK).strip)
              section = nil if section.empty?
              next
            end

            text = stanza.split(BREAK).map { |line| line.gsub(/[[:space:]]+/, " ").strip }
                                      .reject(&:empty?).join("\n")
            # punctuation/number-only lines are dates and numbering, not text
            next if text.match?(/\A[[:punct:][:space:]\d]*\z/)

            passages << Passage.new(text: Nabu::Normalize.nfc(text), section: section)
          end
        end
        passages
      end
    end
  end
end
