# frozen_string_literal: true

module Nabu
  module Adapters
    # The wikisource-slavic parser family (P116-2): MediaWiki wikitext as the
    # South Slavic Wikisource projects write TEXT pages — censused 2026-10-10
    # over random 80-page samples of the sr/hr/sl/mk cones plus the whole bg
    # cone. The WikisourceHanParser (P78-5) cannot serve these: its leading-
    # template split swallows the sr {{Поезија|…}} verse wrapper and the mk
    # {{Заглавје|…|текст=…}} header that CARRIES the text, and it has no verse
    # grain. This class knows the SHAPES; each adapter decides what they mean.
    #
    # == Censused shapes
    #
    # - The work header — {{заглавље}} (sr), {{zaglavlje}} (hr), {{naslov}} /
    #   {{naslov-mp}} (sl), {{Заглавје}} (mk), {{Творба}} (bg) — found
    #   anywhere in the page by brace balance; its params come back
    #   verbatim-but-flattened in Result#header. When a TEXT param
    #   (текст/tekst) carries the body (the mk shape), the body is that
    #   param's value.
    # - Author pages ({{Автор}}/{{Author}}/{{Avtor}}/{{Autor}}) — biography
    #   furniture, never a text: Result#author_page is true.
    # - Verse containers: <poem>…</poem>, {{Поезија|…}}/{{Poezija|…}}, lines
    #   ending in <br />, and paragraphs whose lines are mostly ":"-indented
    #   (the hr Judita couplet layout). Verse is LINE grain: one passage per
    #   verse line, its stanza (blank-line block) riding beside it.
    #   Everything else is prose at PARAGRAPH grain (blank-line separated;
    #   the page's own soft line breaks kept as "\n" — the sl dLib layer
    #   carries the print's line breaks, never re-flowed here).
    # - Apparatus sections (headings named in +apparatus_headings+ — the
    #   sr Извор/Избор source line, the Erlangen edition's Интервенције/
    #   Напомене/Коментар, the bg modern-language rendering) are cut from
    #   the text and returned in Result#apparatus, heading → flattened body.
    # - <ref> footnotes are cut from the text and returned in Result#refs.
    #
    # == Inline policy
    #
    # Verse-number markers ({{стих|5}}, the Erlangen edition's zero-padded
    # "0001" line prefixes) are the edition's numbering, not the text; a
    # line wholly in [square brackets] is an editorial siglum ("[IIIв 552.]",
    # Vuk's manuscript reference); a line wholly in <center> is a heading
    # (the poem's own title repeated above it) and becomes the section.
    # Service templates with no arguments render nothing; any other
    # template renders its LAST positional argument (the display form by
    # MediaWiki convention — {{font color|red|X}} → X, {{Уникод|ѣ}} → ѣ,
    # {{Script/Slavonic|cu|2=X}} → X). Wiki links render their label;
    # category/file links and HTML tags drop (their text content stays);
    # numeric/named HTML entities decode. Text is NOT normalized here —
    # NFC happens at the adapter boundary (house rule).
    class WikisourceSlavicParser
      Passage = Data.define(:text, :section, :verse, :stanza)
      # +index_items+ counts the link-dominated list items the prose pass
      # dropped as navigation — a page that is mostly such items is an
      # index page (the adapter's call).
      Result = Data.define(:header, :passages, :apparatus, :refs, :author_page, :index_items)

      AUTHOR_TEMPLATES = %w[автор author avtor autor].freeze
      VERSE_TEMPLATES = %w[поезија poezija].freeze
      TEXT_PARAMS = %w[текст tekst text].freeze
      # Pure service templates (no reading-text content even when they
      # carry arguments): quality/licence/maintenance stamps, page breaks,
      # verse-number markers, reference lists, chapter-numbering switches.
      SERVICE_TEMPLATES = [
        "стих", "stih", "квалитет", "textquality", "licencija", "reflist", "references",
        "prelom strani", "wikipedija", "wikipedia", "dijelovi", "other versions",
        "neoštevilčena poglavja", "rimska poglavja", "rimska poglavja s piko",
        "внимание-непристојно", "pagename", "fc"
      ].freeze

      VERSE_START = "\u0001VS\u0001"
      VERSE_END = "\u0001VE\u0001"
      BR_MARK = "\u0002"
      HEADING_MARK = "\u0003"

      HEADING = /\A(={2,6})\s*(.*?)\s*\1\s*\z/

      MEDIA_PREFIX = /\[\[\s*(?:category|kategorija|категорија|категория|file|image|slika|datoteka|
                       датотека|слика|файл|изображение|media)\s*:/xi

      # The split_top_level tokens — a token scan, not char indexing: String#[] on a multibyte string is
      # O(index), which made a char loop quadratic on the long Cyrillic
      # template bodies (the mk text param, the bg charters).
      SPLIT_TOKENS = /\{\{|\}\}|\[\[|\]\]|\||[^{}\[\]|]+|./m

      ENTITIES = { "nbsp" => " ", "amp" => "&", "lt" => "<", "gt" => ">", "quot" => '"',
                   "ndash" => "–", "mdash" => "—", "hellip" => "…" }.freeze

      def initialize(header_templates:, apparatus_headings: [])
        @header_templates = header_templates.map { |name| fold(name) }
        @apparatus_headings = apparatus_headings.map { |name| fold(name) }
      end

      def parse(wikitext)
        text, refs = strip_page_apparatus(wikitext.to_s)
        author_page = author_page?(text)
        header, body = split_header(text)
        body, apparatus = cut_apparatus_sections(body)
        passages, index_items = extract_passages(body)
        Result.new(header: header, passages: passages, apparatus: apparatus,
                   refs: refs, author_page: author_page, index_items: index_items)
      end

      # The contents of every {{+name+|…}} template, in page order, flattened
      # — the bg original-script lane ({{Script/Slavonic|cu|2=…}} marks the
      # hosted original, wherever the page puts it: body or image caption).
      # Each entry is the list of its non-empty lines.
      def template_texts(wikitext, name:)
        text, = strip_page_apparatus(wikitext.to_s)
        wanted = fold(name)
        each_template(text).filter_map do |inner|
          template_name, *args = split_top_level(inner)
          next unless fold(template_name) == wanted

          value = positional(args).last.to_s
          lines = flatten_inline(value.gsub(%r{</?br\s*/?>}i, "\n")).split("\n").map(&:strip)
          lines.reject(&:empty?)
        end.reject(&:empty?)
      end

      private

      def fold(name) = name.to_s.tr("_", " ").strip.downcase

      # -- page-level apparatus -----------------------------------------------

      def strip_page_apparatus(text)
        refs = []
        body = text.gsub(/<!--.*?-->/m, "")
                   .gsub(%r{<noinclude>.*?</noinclude>}m, "")
                   .gsub(%r{<ref[^<>]*/>}, "")
                   .gsub(%r{<ref[^<>]*>(.*?)</ref>}m) do
                     refs << flatten_inline(::Regexp.last_match(1)).strip
                     ""
                   end
                   .gsub(%r{<references\s*/>}i, "")
                   .gsub(/__[A-ZА-Я]+__/, "")
        [body, refs.reject(&:empty?)]
      end

      def author_page?(text)
        each_template(text).any? { |inner| AUTHOR_TEMPLATES.include?(fold(split_top_level(inner).first)) }
      end

      # -- the work header ----------------------------------------------------

      # The first header-named template anywhere on the page (brace-balanced),
      # its params flattened; the body is the page minus that block — or the
      # TEXT param's value, when the header carries the text (mk).
      def split_header(text)
        each_template_span(text) do |start, stop, inner|
          name, *args = split_top_level(inner)
          next unless @header_templates.include?(fold(name))

          params = named_params(args)
          text_key = params.keys.find { |key| TEXT_PARAMS.include?(fold(key)) }
          rest = text[...start] + text[stop..]
          body = text_key && !params[text_key].strip.empty? ? "#{params.delete(text_key)}\n\n#{rest}" : rest
          params.delete(text_key) if text_key
          header = params.transform_values { |value| flatten_inline(value).gsub(/\s+/, " ").strip }
          return [header.reject { |_, value| value.empty? }, body]
        end
        [{}, text]
      end

      def named_params(args)
        args.each_with_object({}) do |fragment, params|
          key, eq, value = fragment.partition("=")
          next if eq.empty? || key.strip.empty?

          params[key.strip] = value
        end
      end

      def positional(args)
        numbered = {}
        plain = []
        args.each do |fragment|
          if (match = fragment.match(/\A\s*(\d+)\s*=(.*)\z/m))
            numbered[match[1].to_i] = match[2]
          elsif !fragment.match?(/\A\s*[^\s=|]+\s*=/)
            plain << fragment
          end
        end
        numbered.each { |index, value| plain[index - 1] = value }
        plain.compact
      end

      # -- apparatus sections ---------------------------------------------------

      def cut_apparatus_sections(body)
        kept = []
        apparatus = {}
        cutting = nil
        body.each_line do |line|
          if (match = line.chomp.match(HEADING))
            level = match[1].length
            title = flatten_inline(match[2]).strip
            if cutting && level > cutting[:level]
              apparatus[cutting[:title]] << line
              next
            end
            cutting = nil
            if @apparatus_headings.include?(fold(title.delete_suffix(":").delete_suffix(".")))
              cutting = { level: level, title: title }
              apparatus[title] = +""
              next
            end
          elsif cutting
            apparatus[cutting[:title]] << line
            next
          end
          kept << line
        end
        [kept.join, apparatus.transform_values { |value| flatten_inline(value).strip }.reject { |_, v| v.empty? }]
      end

      # -- passages -----------------------------------------------------------

      def extract_passages(body)
        state = { passages: [], section: nil, index_items: 0 }
        verse = false
        mark_verse_containers(body).split(/(#{VERSE_START}|#{VERSE_END})/o).each do |chunk|
          case chunk
          when VERSE_START then verse = true
          when VERSE_END then verse = false
          else verse ? verse_block!(state, chunk) : prose_block!(state, chunk)
          end
        end
        [state[:passages], state[:index_items]]
      end

      # <poem> and the verse-wrapper templates become VERSE markers; every
      # other template expands by the inline policy; links/tags flatten.
      def mark_verse_containers(body)
        # A <br> inside a heading line is the heading's own layout (sl
        # chapter titles), never a verse break.
        text = body.gsub(/^(={2,6}.*={2,6})[ \t]*$/) { ::Regexp.last_match(1).gsub(%r{\s*</?br\s*/?>\s*}i, " ") }
        text = text.gsub(/<poem[^>]*>/i, "\n#{VERSE_START}\n").gsub(%r{</poem>}i, "\n#{VERSE_END}\n")
        # A centered line heads what follows; a TRAILING one (a letter's
        # signature, nothing but links/templates/markup after it) is text.
        text = text.gsub(%r{^[ \t]*<center>(.*?)</center>[ \t]*$}i) do
          inner = ::Regexp.last_match(1)
          trailing = ::Regexp.last_match.post_match.gsub(/\[\[[^\]]*\]\]|\{\{[^{}]*\}\}|<[^>]*>|\s/, "").empty?
          trailing ? inner : "#{HEADING_MARK}#{inner}"
        end
        text = expand_templates(text, verse_markers: true)
        text = text.gsub(%r{</?br\s*/?>[ \t]*\n}i, "#{BR_MARK}\n").gsub(%r{</?br\s*/?>}i, "#{BR_MARK}\n")
        flatten_links_and_tags(text)
      end

      # One passage per verse line; a blank line opens the next stanza (the
      # stanza counter runs across the whole page).
      def verse_block!(state, chunk)
        chunk.split(/\n[ \t#{BR_MARK}]*\n/o).each do |block|
          opened = false
          block.split("\n").filter_map { |line| verse_line(line) }.each do |line|
            next note_section!(state, line) if line.start_with?(HEADING_MARK)

            unless opened
              state[:stanza] = state[:stanza].to_i + 1
              opened = true
            end
            state[:heading_run] = false
            state[:passages] << Passage.new(text: line, section: state[:section], verse: true,
                                            stanza: state[:stanza])
          end
        end
      end

      def verse_line(raw)
        line = raw.delete(BR_MARK).delete("\u0004").sub(/\A[:;*#]+\s*/, "").sub(/\A\d{4}\s+/, "").strip
        return nil if line.empty? || table_markup?(line)
        return nil if line.match?(/\A\[[^\[\]]*\]\z/) # an editorial siglum, never the text

        heading = raw.include?(HEADING_MARK) || raw.lstrip.start_with?(";")
        return "#{HEADING_MARK}#{line.delete(HEADING_MARK)}" if heading

        line
      end

      def table_markup?(line) = line.match?(/\A\s*(\{\||\|\}|\|-)/)

      # Consecutive heading lines (a title and its provenance subtitle)
      # join into one section path; any passage closes the run.
      def note_section!(state, line)
        heading = line.delete(HEADING_MARK).strip
        return if heading.empty? || heading.match?(/\A[\d.\s]+\z/)

        state[:section] = state[:heading_run] && state[:section] ? "#{state[:section]} · #{heading}" : heading
        state[:heading_run] = true
      end

      def prose_block!(state, chunk)
        chunk.split(/\n[ \t]*\n/).each do |block|
          lines = block.split("\n").map(&:rstrip).reject { |line| line.strip.empty? }
          next if lines.empty?

          lines = take_headings!(state, lines)
          next if lines.empty?

          if verse_paragraph?(lines)
            verse_block!(state, lines.join("\n"))
          else
            text = lines.reject { |line| table_markup?(line) }
                        .map { |line| line.delete(BR_MARK).sub(/\A[:*#|!]+\s*/, "").strip }
                        .reject(&:empty?).join("\n")
            next if text.empty? || text.match?(/\A\[[^\[\]]*\]\z/)

            state[:heading_run] = false
            state[:passages] << Passage.new(text: text, section: state[:section], verse: false, stanza: nil)
          end
        end
      end

      # Headings (== x ==, single-line <center> titles, ";" terms) set the
      # section and leave the paragraph; navigation list lines drop.
      def take_headings!(state, lines)
        lines.filter_map do |line|
          if (match = line.match(HEADING))
            heading = match[2].strip
            unless heading.empty?
              state[:section] = heading
              state[:heading_run] = true
            end
            nil
          elsif line.start_with?(HEADING_MARK) || line.start_with?(";")
            note_section!(state, line.sub(/\A;/, ""))
            nil
          elsif line.match?(/\A[*#]/) && line.include?("\u0004")
            state[:index_items] += 1
            nil # a link-dominated list item: navigation, never text
          else
            line.delete("\u0004")
          end
        end
      end

      def verse_paragraph?(lines)
        return false if lines.size < 2

        marked = lines.count { |line| line.end_with?(BR_MARK) || line.start_with?(":") }
        marked * 2 >= lines.size
      end

      # -- inline wikitext ----------------------------------------------------

      def flatten_inline(text)
        flatten_links_and_tags(expand_templates(text.to_s, verse_markers: false))
          .delete(BR_MARK).delete(HEADING_MARK).delete("\u0004")
      end

      # Innermost-first template expansion (nested templates resolve
      # inside-out; the verse wrappers become markers when asked).
      def expand_templates(text, verse_markers:)
        result = text
        8.times do
          changed = result.gsub(/\{\{((?:(?!\{\{|\}\}).)*)\}\}/m) do
            expand_template(::Regexp.last_match(1), verse_markers: verse_markers)
          end
          break if changed == result

          result = changed
        end
        result
      end

      def expand_template(inner, verse_markers:)
        name, *args = split_top_level(inner)
        folded = fold(name)
        values = positional(args)
        if VERSE_TEMPLATES.include?(folded)
          body = values.first.to_s
          return verse_markers ? "\n#{VERSE_START}\n#{body}\n#{VERSE_END}\n" : body
        end
        return "" if SERVICE_TEMPLATES.include?(folded) || folded.start_with?("јс-", "автор-јс")
        return "" if @header_templates.include?(folded) || AUTHOR_TEMPLATES.include?(folded)

        values.last.to_s
      end

      # Link-dominated list items get a \u0004 tag so the prose pass can drop
      # them (the Vuk volume index pages — the song list is navigation).
      def flatten_links_and_tags(text)
        flat = remove_media_links(text)
        flat = flat.gsub(/^([*#][^\n]*)$/) { |line| link_only_item?(line) ? "#{line}\u0004" : line }
        # Bare interwiki/language links ([[sr:Title]]) are sister-wiki
        # furniture, never text; piped ones keep their label below.
        flat = flat.gsub(/\[\[\s*:?[a-z]{1,3}(?:-[a-z]+)?\s*:[^\[\]|]*\]\]/, "")
        flat = flat.gsub(/\[\[[^\[\]|]*\|([^\[\]]*)\]\]/, '\1')
                   .gsub(/\[\[([^\[\]]*)\]\]/, '\1')
                   .gsub(%r{\[(?:https?:)?//[^\s\]]+\s+([^\]]*)\]}, '\1')
                   .gsub(%r{\[(?:https?:)?//[^\s\]]+\]}, "")
                   .gsub(/'''?/, "")
                   .gsub(%r{</?[a-zA-Z][^<>]*>}, "")
        decode_entities(flat)
      end

      # Category/file links drop whole — file captions nest links, so this
      # walks bracket depth rather than trusting a regex.
      def remove_media_links(text)
        out = +""
        index = 0
        while (start = text.index(MEDIA_PREFIX, index))
          out << text[index...start]
          depth = 0
          cursor = start
          while cursor < text.length
            pair = text[cursor, 2]
            if pair == "[["
              depth += 1
              cursor += 2
            elsif pair == "]]"
              depth -= 1
              cursor += 2
              break if depth.zero?
            else
              cursor += 1
            end
          end
          index = cursor
        end
        out << text[index..].to_s
      end

      def link_only_item?(line)
        return false unless line.include?("[[")

        line.sub(/\A[*#]+\s*(?:\d+[.)]?)?/, "")
            .gsub(/\[\[[^\[\]]*\]\]/, "")
            .gsub(/\([^()]*\)/, "")
            .gsub(%r{</?[a-zA-Z][^<>]*>}, "")
            .gsub(/'{2,}/, "")
            .gsub(/[[:punct:][:space:]←→]/, "")
            .empty?
      end

      def decode_entities(text)
        text.gsub(/&#x([0-9a-f]+);/i) { [::Regexp.last_match(1).to_i(16)].pack("U") }
            .gsub(/&#(\d+);/) { [::Regexp.last_match(1).to_i].pack("U") }
            .gsub(/&([a-z]+);/i) { ENTITIES.fetch(::Regexp.last_match(1).downcase, ::Regexp.last_match(0)) }
            .gsub(/[  ]/, " ")
      end

      # -- template scanning --------------------------------------------------

      def each_template(text)
        spans = []
        each_template_span(text) { |_start, _stop, inner| spans << inner }
        spans
      end

      # Every TOP-LEVEL {{…}} span, brace-balanced: yields start, stop and the
      # inner text (sans the outer braces).
      def each_template_span(text)
        depth = 0
        start = nil
        text.to_enum(:scan, /\{\{|\}\}/).each do
          match = ::Regexp.last_match
          if match[0] == "{{"
            start = match.begin(0) if depth.zero?
            depth += 1
          elsif depth.positive?
            depth -= 1
            yield start, match.end(0), text[(start + 2)...match.begin(0)] if depth.zero?
          end
        end
      end

      # Top-level "|" split with {{…}}/[[…]] depth tracked.
      def split_top_level(content)
        parts = [+""]
        depth = 0
        content.scan(SPLIT_TOKENS) do |token|
          case token
          when "{{", "[[" then depth += 1
          when "}}", "]]" then depth -= 1
          when "|"
            if depth.zero?
              parts << +""
              next
            end
          end
          parts.last << token
        end
        parts
      end
    end
  end
end
