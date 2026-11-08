# frozen_string_literal: true

module Nabu
  module Adapters
    # The manchu-wikisource parser family: MediaWiki wikitext as
    # Multilingual Wikisource writes its Manchu texts (censused 2026-11-08
    # over every main-namespace page of Category:ᠮᠠᠨᠵᡠ ᡤᡳᠰᡠᠨ, Category:Manchu
    # and the 清文啓蒙 sub-category). This class knows the SHAPES; the
    # adapter decides what they mean. Censused shapes:
    #
    # - the {{Manchu header}} template (also "Manchu Header", "Manchu_header")
    #   — title/author/section/notes params, captured, never text;
    # - {{MongolUnicode|…}} / {{MongolUnicode-div|lang=mnc|1=…}} — the
    #   vertical-script display wrappers: their text parameter IS the text
    #   (named 1= where given, else the last positional parameter);
    # - service templates ({{Manchu display}}, {{DISPLAYTITLE:…}}, {{Note2}},
    #   {{-}}, {{stage|…}}) — dropped;
    # - <poem> verse, <br> line breaks, == headings ==, # numbered lists and
    #   {| tables |} (the bilingual pages put the Manchu and Chinese in
    #   cells);
    # - the Manchu case-suffix spacing hack "&nbsp;&zwj;" — rendered as
    #   U+202F NARROW NO-BREAK SPACE, the Unicode-standard Mongolian-script
    #   suffix connector it imitates (declared).
    #
    # Output: one Line per non-empty text line (a prose paragraph, a verse
    # line, a list item or a table cell), with the heading path it sits
    # under. Lines with no letter (dotted fillers, hexagram glyphs, page
    # numbers) drop; lines under apparatus headings (External links,
    # References, Notes) drop. Text is NOT normalized here — NFC happens at
    # the adapter boundary (house rule).
    class ManchuWikisourceParser
      Line = Data.define(:text, :section)
      Result = Data.define(:header, :lines)

      CONTENT_TEMPLATES = %w[mongolunicode mongolunicode-div tcy].freeze
      HEADER_TEMPLATE = "manchu header"
      APPARATUS_SECTIONS = /\A(?:external links?|references?|notes?|translation\b.*)\z/i
      # A template parameter "name=value" (Manchu text carries no ASCII name).
      NAMED = /\A\s*([A-Za-z0-9 _-]+?)\s*=(.*)\z/m
      HEADING = /\A(=+)\s*(.*?)\s*\1\s*\z/
      # A dotted filler row, even one carrying a contributor's note
      # ("....up to here....", the Lunyu page) — editorial, never text.
      DOTTED_MARK = /\A[.…]{3,}/
      # A paragraph longer than LONG_LINE characters (censused: MYK juan
      # 2 and 3 are each ONE 30k-character line) splits after every Manchu
      # full stop (U+1809) — sentence grain, declared; shorter lines stay
      # whole.
      LONG_LINE = 1_500
      FULL_STOP = "᠉"
      SENTENCE_END = /(?<=᠉)/
      NNBSP = " "

      def parse(wikitext)
        header = {}
        text = fold_heading_breaks(strip_apparatus(wikitext.to_s))
        text = resolve_links(text)
        text = resolve_templates(text, header)
        text = resolve_html(text)
        Result.new(header: header, lines: text_lines(text))
      end

      private

      def strip_apparatus(text)
        text.gsub(/<!--.*?-->/m, "")
            .gsub(%r{<ref[^<>]*/>}, "")
            .gsub(%r{<ref[^<>]*>.*?</ref>}m, "")
            .gsub(/__[A-Z]+__/, "")
      end

      # Internal links keep their label (files, images and categories drop);
      # external links keep their label, a bare [url] drops.
      def resolve_links(text)
        text = text.gsub(/\[\[\s*(?:file|image|category):[^\[\]]*\]\]/i, "")
        loop do
          replaced = text.gsub(/\[\[([^\[\]|]*)\|([^\[\]]*)\]\]/) { Regexp.last_match(2) }
                         .gsub(/\[\[([^\[\]|]*)\]\]/) { Regexp.last_match(1).delete_prefix(":") }
          break if replaced == text

          text = replaced
        end
        text.gsub(%r{\[(?:https?:)?//[^\s\]]+\s+([^\]]*)\]}) { Regexp.last_match(1) }
            .gsub(%r{\[(?:https?:)?//[^\s\]]+\]}, "")
      end

      # Innermost-first: a nested {{MongolUnicode}} inside the header's
      # params resolves before the header is captured.
      def resolve_templates(text, header)
        loop do
          replaced = text.gsub(/\{\{([^{}]*)\}\}/m) { template(Regexp.last_match(1), header) }
          break if replaced == text

          text = replaced
        end
        text
      end

      def template(body, header)
        name, *params = body.split("|")
        name = name.to_s.strip.downcase.tr("_", " ")
        if CONTENT_TEMPLATES.include?(name)
          content_param(params)
        elsif name == HEADER_TEMPLATE
          capture_header(params, header)
          ""
        else
          ""
        end
      end

      def content_param(params)
        named = params.filter_map { |param| NAMED.match(param) }.to_h { |m| [m[1].downcase, m[2]] }
        return named["1"] if named.key?("1")

        params.grep_v(NAMED).last.to_s
      end

      def capture_header(params, header)
        params.each do |param|
          match = NAMED.match(param) or next
          value = resolve_html(match[2]).gsub(/\s+/, " ").strip
          header[match[1].downcase] = value unless value.empty?
        end
      end

      def resolve_html(text)
        text.gsub("&nbsp;&zwj;", NNBSP)
            .gsub("&nbsp;", " ").gsub("&zwj;", "").gsub("&bull;", "")
            .gsub(%r{<br\s*/?>}i, "\n")
            .gsub(%r{</?[a-z][^<>]*>}i, "")
            .gsub(/'{2,}/, "")
      end

      def text_lines(text)
        section = nil
        text.each_line.with_object([]) do |raw, lines|
          line = raw.strip
          next if line.empty? || line.start_with?("{|", "|}", "|-")

          if (match = HEADING.match(line))
            section = match[2].gsub(/\s+/, " ").strip
            section = nil if section.empty?
            next
          end
          next if section&.match?(APPARATUS_SECTIONS)

          line = table_cell(line).sub(/\A[*#:;]+\s*/, "").strip
          next unless line.match?(/\p{L}/)
          next if line.match?(DOTTED_MARK)

          split_long(line.gsub(/[ \t]+/, " ")).each { |part| lines << Line.new(text: part, section: section) }
        end
      end

      def split_long(line)
        return [line] if line.length <= LONG_LINE || !line.include?(FULL_STOP)

        line.split(SENTENCE_END).map(&:strip).grep(/\p{L}/)
      end

      # A heading's <br> (盛京賦 breaks its vertical-script headings) folds
      # to a space so the heading stays one line.
      def fold_heading_breaks(text)
        text.gsub(/^(=+)(.+)\1[ \t]*$/) do
          marks = Regexp.last_match(1)
          title = Regexp.last_match(2)
          "#{marks}#{title.gsub(%r{<br\s*/?>}i, ' ')}#{marks}"
        end
      end

      # A table cell line ("| text", "! text"); an attribute prefix
      # ('| width="100%" … |text') keeps only the text after its pipe.
      def table_cell(line)
        return line unless line.start_with?("|", "!")

        cell = line[1..].strip
        attributed = cell.match(/\A[^|]*="[^|]*\|(.*)\z/)
        attributed ? attributed[1] : cell
      end
    end
  end
end
