# frozen_string_literal: true

require "nokogiri"
require_relative "../normalize"

module Nabu
  module Adapters
    # One Lotsawa House text page → one Nabu::Document (the lotsawa-html
    # family). The page grammar, censused over the 2026-10-21 samples (bo,
    # en, fr, nl, zh pages; prose, verse and the trilingual liturgy shape):
    #
    #   <h1>                       the page title (page language)
    #   div.categories             topic tags (/<pre>/topics/<slug>/), the
    #                              collection link and the author link(s)
    #   p#lang-list                the languages the text is served in
    #   div#maintext               the text: either Markdown-converted
    #                              blocks (h2/p/blockquote, div.MDFile /
    #                              div.ChineseText wrappers) or the classed
    #                              liturgy blocks (HeadingTib, Heading3,
    #                              TibetanVerse / EnglishPhonetics /
    #                              EnglishText triples, TibetanExplanation /
    #                              Explanation pairs, EnglishMantra, gap)
    #     footnotes                div.footnotes ol li, or ol.Footnote li
    #                              after an empty div.footnotes
    #     credits                  "| Translated by …" lines (a /translators/
    #                              link), p.Credit, a Version line, the
    #                              h2.biblio / h2.CreditTitle source blocks
    #   div#further-info           Treasury of Lives + BDRC author links
    #   lh_init({restricted: …})   the site's restricted-practice flag
    #
    # Passages: one per leaf block of #maintext in document order, then one
    # per footnote. Furniture (gap paragraphs, credit/version/source lines)
    # becomes metadata, never text. A block's language: Tibetan-script
    # majority → xct; EnglishMantra → san (an IAST mantra); otherwise the
    # page language (a bo page's rare non-Tibetan block: eng when Latin,
    # else xct). An EnglishPhonetics line (phonetic Tibetan, the reading of
    # the verse before it) rides that xct passage's "phonetics" annotation;
    # with no Tibetan passage before it, it stands as a page-language
    # passage labeled layer: phonetics. <br> keeps its line break; footnote
    # markers are cut from the text and their numbers kept in "notes".
    class LotsawaHtmlParser
      LEAF_BLOCKS = %w[p h2 h3 h4 h5 li].freeze
      TIBETAN = /\p{Tibetan}/
      LETTER = /\p{L}/
      LATIN = /\p{Latin}/
      FURNITURE_CLASSES = %w[gap foot-title].freeze
      CREDIT_CLASSES = %w[Credit CreditTitle Source biblio].freeze

      # Page language code (the site's) → passage language.
      LANGUAGES = {
        "bo" => "xct", "en" => "eng", "de" => "deu", "es" => "spa", "fr" => "fra",
        "it" => "ita", "nl" => "nld", "pt" => "por", "zh" => "cmn"
      }.freeze

      # +lang+ is the site's page language ("bo", "en", …); +urn+ the
      # document urn; +metadata+ the caller's (path-derived) keys;
      # +original_urn+ the urn of the text's Tibetan page — a translation
      # page (lang ≠ bo) is marked kind translation, and translation_of
      # names that urn when the page's own language list carries Tibetan.
      def parse(path, urn:, lang:, metadata: {}, original_urn: nil)
        html = Nokogiri::HTML(File.read(path, encoding: "UTF-8"))
        @lang = lang
        @page_language = LANGUAGES.fetch(lang)
        main = html.at_css("div#maintext") or raise Nabu::ParseError, "#{path}: no div#maintext — not a text page"
        @credits = []
        @bibliography = []
        @bibliography_label = nil
        @version = nil
        @translators = main.css("a[href*='/translators/']").map { |link| squish(link.text) }.reject(&:empty?).uniq
        blocks = passages(main)
        raise Nabu::ParseError, "#{path}: no text blocks in div#maintext" if blocks.empty?

        meta = page_metadata(html, metadata).merge(furniture_metadata)
        mark_translation!(meta, original_urn)
        document = Nabu::Document.new(urn: urn, language: @page_language, title: title(html, path),
                                      canonical_path: path, metadata: meta)
        blocks.each_with_index do |(text, language, annotations), index|
          document << Nabu::Passage.new(urn: "#{urn}:#{index + 1}", language: language, sequence: index,
                                        text: text, annotations: annotations)
        end
        document
      end

      private

      def mark_translation!(meta, original_urn)
        return if @lang == "bo"

        meta["kind"] = "translation"
        meta["translation_of"] = original_urn if original_urn && Array(meta["languages"]).include?("bo")
      end

      def title(html, path)
        text = squish(html.at_css("div#content h1")&.text.to_s)
        raise Nabu::ParseError, "#{path}: no page title (h1)" if text.empty?

        Normalize.nfc(text)
      end

      # -- page metadata ---------------------------------------------------------

      def page_metadata(html, given)
        topics = html.css("div.categories a[href*='/topics/']").filter_map do |link|
          link["href"][%r{/topics/([^/]+)/?\z}, 1]
        end.uniq
        languages = html.css("p#lang-list a").filter_map { |link| link_language(link["href"]) }.uniq
        meta = given.merge(
          "lang" => @lang,
          "topics" => topics,
          "topic_labels" => html.css("div.categories a[href*='/topics/']").map { |link| squish(link.text) },
          "author" => author_name(html, given["author_slug"]),
          "restricted" => html.to_s.match?(/restricted:\s*true/),
          "languages" => languages,
          "bdrc_person" => html.css("div#further-info a").filter_map { |link| link["href"][/bdr:(P\w+)/, 1] }.first,
          "treasury_of_lives" => html.css("div#further-info a[href*='treasuryoflives.org']").map do |link|
            link["href"]
          end.first
        )
        facets = {}
        facets["topic"] = { "values" => topics } unless topics.empty?
        facets["collection"] = { "value" => given["collection"] } if given["collection"]
        meta["facets"] = facets unless facets.empty?
        meta.compact.reject { |_key, value| value.respond_to?(:empty?) && value.empty? }
      end

      def link_language(href)
        return nil if href.nil?

        prefix = href[%r{\A/([a-z]{2})/}, 1]
        prefix && LANGUAGES.key?(prefix) ? prefix : "en"
      end

      def author_name(html, slug)
        return nil if slug.nil?

        link = html.css("div.categories a").find { |candidate| candidate["href"].to_s.end_with?("/#{slug}/") }
        link && Normalize.nfc(squish(link.text))
      end

      def furniture_metadata
        meta = { "translators" => @translators, "credits" => @credits, "bibliography" => @bibliography,
                 "version" => @version }
        year = @credits.join(" ")[/\b(1[89]\d\d|20\d\d)\b/, 1]
        meta["translation_year"] = Integer(year, 10) if year && @lang != "bo"
        meta.compact.reject { |_key, value| value.respond_to?(:empty?) && value.empty? }
      end

      # -- passages ---------------------------------------------------------------

      def passages(main)
        out = []
        in_bibliography = false
        leaves(main).each do |node|
          next if note?(node)

          classes = node["class"].to_s.split
          in_bibliography = true if node.name == "h2" && classes.intersect?(%w[biblio CreditTitle])
          in_bibliography = false if node.name == "h2" && !classes.intersect?(%w[biblio CreditTitle])
          next if absorbed_as_furniture?(node, classes, in_bibliography)

          markers = cut_markers!(node)
          text = block_text(node)
          next if text.empty?

          if classes.any? { |name| name.include?("Phonetics") }
            attach_phonetics(out, text)
            next
          end
          annotations = { "block" => block_label(node, classes) }
          annotations["notes"] = markers unless markers.empty?
          out << [text, language_of(text, classes), annotations]
        end
        out + notes(main)
      end

      # Leaf blocks: block elements containing no other block element.
      def leaves(main)
        main.css(LEAF_BLOCKS.join(",")).reject { |node| node.at_css(LEAF_BLOCKS.join(",")) }
      end

      def note?(node)
        node.ancestors.any? do |ancestor|
          (ancestor.name == "div" && ancestor["class"].to_s.split.include?("footnotes")) ||
            (ancestor.name == "ol" && ancestor["class"].to_s.split.include?("Footnote"))
        end
      end

      # Page furniture → metadata; true when the block is consumed.
      def absorbed_as_furniture?(node, classes, in_bibliography)
        return true if classes.intersect?(FURNITURE_CLASSES)

        text = block_text(node)
        if text.match?(/\AVersion\s*:/)
          @version = text.sub(/\AVersion\s*:\s*/, "")
          return true
        end
        if node.at_css("a[href*='/translators/']") || text.start_with?("|")
          @credits << text
          return true
        end
        if in_bibliography || classes.intersect?(CREDIT_CLASSES)
          bibliography_line(node, text)
          return true
        end
        if small_only?(node)
          @credits << text
          return true
        end
        false
      end

      # Source/bibliography blocks: an h4 ("Tibetan Edition") labels the
      # citation after it; the section h2 itself is dropped.
      def bibliography_line(node, text)
        case node.name
        when "h2" then nil
        when "h3", "h4", "h5" then @bibliography_label = text
        else
          @bibliography << (@bibliography_label ? "#{@bibliography_label}: #{text}" : text)
          @bibliography_label = nil
        end
      end

      # A paragraph whose whole content is one <small> (the zh colophon).
      def small_only?(node)
        node.name == "p" && node.element_children.size == 1 && node.element_children.first.name == "small" &&
          node.children.reject { |child| child.text? && child.text.strip.empty? }.size == 1
      end

      # Removes footnote reference markers; returns their numbers.
      def cut_markers!(node)
        markers = []
        node.css("a.footnote, sup a[href^='#ref'], sup[id^='backref']").each do |marker|
          number = marker.text[/\d+/]
          markers << number if number
          marker.remove
        end
        markers.uniq
      end

      def attach_phonetics(out, text)
        previous = out.last
        if previous && previous[1] == "xct" && !previous[2].key?("phonetics")
          previous[2]["phonetics"] = text
        else
          out << [text, fallback_language(text), { "block" => "phonetics", "layer" => "phonetics" }]
        end
      end

      def block_label(node, classes)
        classes.empty? ? node.name : "#{node.name}.#{classes.join('.')}"
      end

      def language_of(text, classes)
        return "san" if classes.include?("EnglishMantra")
        return "xct" if tibetan_majority?(text)

        fallback_language(text)
      end

      def fallback_language(text)
        return @page_language unless @lang == "bo"

        text.scan(LATIN).size > text.scan(TIBETAN).size ? "eng" : "xct"
      end

      def tibetan_majority?(text)
        letters = text.scan(LETTER).size
        tibetan = text.scan(TIBETAN).size
        letters.positive? && tibetan * 2 >= letters
      end

      # -- footnotes ---------------------------------------------------------------

      def notes(main)
        items = main.css("div.footnotes li, ol.Footnote li")
        items.filter_map do |item|
          number = item["id"].to_s[/\d+/]
          item.css("a.reversefootnote, a.Noline").each(&:remove)
          text = block_text(item)
          next if text.empty?

          annotations = { "block" => "note" }
          annotations["note"] = number if number
          [text, language_of(text, []), annotations]
        end
      end

      # -- text --------------------------------------------------------------------

      # The block's text: <br> → line break, whitespace runs folded, each line
      # stripped, NFC.
      def block_text(node)
        copy = node.dup
        copy.css("br").each { |br| br.replace("\n") }
        lines = copy.text.split("\n").map { |line| squish(line) }.reject(&:empty?)
        Normalize.nfc(lines.join("\n"))
      end

      def squish(text) = text.to_s.gsub(/[[:space:]]+/, " ").strip
    end
  end
end
