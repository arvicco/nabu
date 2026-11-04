# frozen_string_literal: true

require "cgi"
require "uri"

require_relative "source_read"

module Nabu
  module Adapters
    # The glt-html family: the hand-made HTML of glt.goarch.org, the Greek
    # Orthodox Archdiocese of America's Greek liturgical-texts site (the
    # Glt adapter). Two upstream markup generations meet here, both
    # verified against the fixtures:
    #
    # - the SOUP pages (most of the site: "Shell Script (Linux)" or
    #   hand-edited): line structure by <br/> and unbalanced </p>, ink by
    #   <FONT COLOR=…> that freely spans line breaks (a red rubric opened
    #   before a </p> still governs the text after it, as a browser renders
    #   it) — so the page is read as a TAG STREAM with a font stack, never
    #   through a DOM repair that would move those spans;
    # - the LibreOffice exports (e.g. texts/Sep/14b.html): one <p
    #   class="western"> per line, ink by per-word <font color> runs, raw
    #   newlines inside a paragraph being plain whitespace.
    #
    # == The line and its role (the rubric distinction, mined)
    #
    # A LINE is the run of text between two breaks (<br>, a <p>/<div>/
    # <h1–6>/table-cell boundary). Every line carries the ink of each of its
    # text runs (the innermost <font color> in force), and the site's ink
    # IS its rubrication: red (#ff0000) and maroon (#800000) are the
    # rubrics — titles, tones, melody incipits, hymn-type labels, the
    # typikon's instructions. So each line takes a role: "rubric" (every run
    # rubric-inked), "text" (none), "mixed" (a text line carrying an inline
    # rubric — the Euchologion's "(τὴν δούλην)" alternates, "(ἐκ γ')"
    # repetition marks — whose rubric spans also ride annotations, the text
    # keeping them verbatim). The Euchologion/Horologion pages add two
    # inks the parser records without interpreting: blue (#0000ff, the
    # deacon's petitions there) and green (#008000, the people's or
    # choir's responses), plus bold (the priest's exclamations) — recorded
    # as "ink"/"bold" when the whole line carries it.
    #
    # The recordings: a melody incipit links its model melody as an mp3
    # ("<a href=../../music/4018.mp3>ΤΟ ΑΚΟΥΤΕ</a>", "listen to it"); the
    # link text is site chrome and leaves the line, the mp3 path rides the
    # line's "recordings".
    class GltHtmlParser
      Run = Data.define(:text, :ink, :bold)
      Line = Data.define(:runs, :recordings) do
        def text = runs.map(&:text).join.gsub(/\s+/, " ").strip

        def inked_runs = runs.reject { |run| run.text.strip.empty? }

        def role
          inks = inked_runs.map { |run| GltHtmlParser.rubric_ink?(run.ink) }.uniq
          return "rubric" if inks == [true]
          return "text" if inks == [false]

          "mixed"
        end

        # The rubric-inked spans of a mixed line, in order.
        def rubric_spans
          spans = []
          runs.chunk_while { |a, b| GltHtmlParser.rubric_ink?(a.ink) == GltHtmlParser.rubric_ink?(b.ink) }
              .each do |chunk|
            next unless GltHtmlParser.rubric_ink?(chunk.first.ink)

            span = chunk.map(&:text).join.gsub(/\s+/, " ").strip
            spans << span unless span.empty?
          end
          spans
        end

        # The one non-rubric, non-default ink of a whole line (blue/green).
        def uniform_ink
          inks = inked_runs.map(&:ink).uniq
          inks.size == 1 && inks.first && !GltHtmlParser.rubric_ink?(inks.first) ? inks.first : nil
        end

        def all_bold? = inked_runs.all?(&:bold)
      end
      Page = Data.define(:title, :lines)
      IndexEntry = Data.define(:rel, :href, :label, :group, :list)

      # The site's inks, by the hex its markup spells (case-folded).
      INKS = {
        "#ff0000" => "red", "#800000" => "maroon", "#0000ff" => "blue",
        "#008000" => "green", "#008080" => "teal", "#ff00ff" => "magenta", "#000000" => nil
      }.freeze
      RUBRIC_INKS = %w[red maroon].freeze

      # Tags that end a line (block boundaries); <br> is the line break proper.
      BREAK_TAGS = %w[br p div h1 h2 h3 h4 h5 h6 tr td th table li blockquote].freeze
      TOKEN = /<!--.*?-->|<[^>]*>|[^<]+/m

      def self.rubric_ink?(ink) = RUBRIC_INKS.include?(ink)

      # The page's lines (see the class comment). +text+ is the decoded
      # page (UTF-8, not yet NFC — the adapter normalizes each line).
      def self.page(text)
        title = text[%r{<title[^>]*>(.*?)</title>}mi, 1]
        title &&= clean(decode(title))
        Page.new(title: title.nil? || title.empty? ? nil : title, lines: lines(body_of(text)))
      end

      # The <a href> list of an index page (index.html / extra.htm) with the
      # index's own labels: +label+ the link text, +group+ the green
      # sub-heading the link sits under (Σεπτέμβριος, Ήχος α', ΤΟΥ ΑΣΩΤΟΥ,
      # ΜΕΣΟΝΥΚΤΙΚΟΝ). A group governs the links after it up to the end of
      # the first paragraph that carries links (extra.htm sets the heading
      # in its own <p> above the links' <p>; index.html's Menaia close each
      # month's paragraph, and the next, heading-less paragraph — the
      # Synekdemos links — is no longer the month's). +rel+ is the
      # site-relative path, percent-decoded; +href+ the link as written.
      # One entry per rel, first occurrence wins.
      def self.index_entries(text, list:)
        entries = {}
        group = nil
        group_buffer = nil
        links_since_group = false
        link = nil
        stack = []
        each_token(body_of(text)) do |kind, name, raw|
          if kind == :text
            if link
              link[:label] << raw
            elsif stack.last == "green"
              group_buffer = (group_buffer || +"") << raw
            end
            next
          end

          case name
          when "font"
            stack.push(font_ink(raw))
          when "/font"
            if stack.last == "green" && group_buffer && !clean(decode(group_buffer)).empty?
              group = clean(decode(group_buffer))
              links_since_group = false
            end
            group_buffer = nil if stack.last == "green"
            stack.pop
          when "a"
            href = href_of(raw)
            link = href && !href.start_with?("#") ? { href: href, label: +"" } : nil
          when "/a"
            if link
              add_entry(entries, link, group: group, list: list)
              links_since_group = true
            end
            link = nil
          when "p", "/p"
            if links_since_group
              group = nil
              links_since_group = false
            end
          end
        end
        entries.values
      end

      # Record the closed +link+ unless its rel is external or already listed.
      def self.add_entry(entries, link, group:, list:)
        rel = site_rel(link[:href])
        return if rel.nil? || entries.key?(rel)

        label = clean(decode(link[:label]))
        entries[rel] = IndexEntry.new(rel: rel, href: link[:href], label: label.empty? ? nil : label,
                                      group: group, list: list)
      end

      def self.href_of(raw) = raw[/\bhref\s*=\s*"([^"]*)"/i, 1] || raw[/\bhref\s*=\s*([^\s>]+)/i, 1]

      # A site-relative path for an in-site href ("./texts/Sep/01b.html",
      # "texts/Oro/Esperinos%20Sunday.html"), nil for external links.
      def self.site_rel(href)
        return nil if href.match?(/\A[a-z][a-z0-9+.-]*:/i) || href.start_with?("/")

        URI.decode_uri_component(href.sub(%r{\A(\./)+}, "").sub(/[?#].*\z/, ""))
      end

      # --- the tag stream ---------------------------------------------------------

      def self.body_of(text)
        start = text =~ /<body\b[^>]*>/i
        body = start ? text[(start + Regexp.last_match(0).length)..] : text.sub(%r{\A.*</head>}mi, "")
        body.gsub(%r{<script\b.*?</script>}mi, "").gsub(%r{<style\b.*?</style>}mi, "")
      end

      def self.each_token(body)
        body.scan(TOKEN) do |token|
          if token.start_with?("<!--")
            next
          elsif token.start_with?("<")
            name = token[%r{\A</?\s*([A-Za-z0-9]+)}, 1]
            next unless name

            yield :tag, (token.start_with?("</") ? "/" : "") + name.downcase, token
          else
            yield :text, nil, token
          end
        end
      end

      def self.lines(body)
        lines = []
        runs = []
        recordings = []
        stack = []
        bold = 0
        in_recording = false
        flush = lambda do
          line = Line.new(runs: merge(runs), recordings: recordings)
          lines << line unless line.text.empty?
          runs = []
          recordings = []
        end
        each_token(body) do |kind, name, raw|
          if kind == :text
            next if in_recording

            text = decode(raw)
            runs << Run.new(text: text, ink: stack.compact.last, bold: bold.positive?) unless text.empty?
            next
          end

          tag = name.delete_prefix("/")
          if BREAK_TAGS.include?(tag)
            flush.call
          elsif name == "font"
            stack.push(font_ink(raw))
          elsif name == "/font"
            stack.pop
          elsif %w[b strong].include?(name)
            bold += 1
          elsif %w[/b /strong].include?(name)
            bold -= 1 if bold.positive?
          elsif name == "a"
            href = href_of(raw)
            in_recording = href&.match?(/\.mp3\z/i) || false
            recordings << href.sub(%r{\A(\.\./|\./)+}, "") if in_recording
          elsif name == "/a"
            in_recording = false
          end
        end
        flush.call
        lines
      end

      # nil = the default ink (no color attribute, or black); otherwise the
      # ink's name (INKS), or the raw hex for an ink the table does not know.
      def self.font_ink(raw)
        color = raw[/\bcolor\s*=\s*"?\s*(#?[0-9a-z]+)/i, 1]
        return nil if color.nil?

        hex = color.downcase
        INKS.fetch(hex) { hex }
      end

      def self.merge(runs)
        runs.each_with_object([]) do |run, merged|
          last = merged.last
          if last && last.ink == run.ink && last.bold == run.bold
            merged[-1] = last.with(text: last.text + run.text)
          else
            merged << run
          end
        end
      end

      def self.decode(raw)
        CGI.unescapeHTML(raw.gsub(/&nbsp;|&#160;/i, " ")).tr(" ", " ")
      end

      def self.clean(text) = text.gsub(/\s+/, " ").strip
    end
  end
end
