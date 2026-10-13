# frozen_string_literal: true

require "nokogiri"

require_relative "../normalize"

module Nabu
  module Adapters
    # Parser family "madurai-html" (P122-3): Project Madurai's hand-made
    # Unicode HTML e-texts (pm_etexts/utf8/pmuniNNNN[_NN].html) and its
    # cumulative works list (pmworks.html). Two readings:
    #
    # == .etext — one e-text file
    #
    # Every file opens with the project's HEADER PAGE (title block,
    # acknowledgements, "© Project Madurai", and the distribution
    # condition "You are welcome to freely distribute this file, provided
    # this header page is kept intact."), then the work, then — after a
    # final <hr> — an English FOOTER (first put up / last revised dates,
    # the webmaster's address). The header and footer are not the work:
    # - the body opens after the first <hr> following the distribution
    #   sentence (HEADER_END); a file without that sentence raises
    #   ParseError — the header is the license condition, never guessed;
    # - the footer is cut at the LAST <hr> only when everything after it
    #   carries no Tamil letter (an internal part separator never loses
    #   text).
    # Header and footer ride the result verbatim (tag-stripped lines) —
    # the header travels with every document, honoring its condition.
    #
    # The body is hand-keyed HTML with no structural markup to speak of:
    # verse lines end in <br>, stanzas and sections in <p>/<h3>, numbers
    # trail the lines ("…உலகு. 1"). The honest grain is the PHYSICAL LINE:
    # every <br> and block boundary ends one; a line is kept when it holds
    # a Tamil letter (its text verbatim — whitespace collapsed, NFC). Lines
    # with letters but no Tamil script (English notes, a Devanagari śloka)
    # are dropped and COUNTED (non_tamil_lines), never silently. A line
    # keyed inside <h1>–<h6> carries heading: true.
    #
    # == .catalog — pmworks.html
    #
    # The sortable works table: Work no. · Title · Author · Genre · PDF ·
    # Unicode links. One Work no. can span several rows (an anthology's
    # member works) and several Unicode files (a long work in parts); the
    # reading groups rows by Unicode FILE: file → work numbers, titles,
    # authors, genres (each list deduplicated, catalog order).
    module MaduraiHtmlParser
      Line = Data.define(:text, :heading)
      Etext = Data.define(:lines, :header, :footer, :html_title, :non_tamil_lines)
      Entry = Data.define(:file, :work_numbers, :titles, :authors, :genres)

      # The distribution sentence, its words separated by whitespace, &nbsp;
      # or markup — the hand-made files break it across <br> lines ("provided
      # this<br>\nheader page is kept intact."); censused variants: "header
      # PART is kept intact" (pmuni0300), "iskept" run together (pmuni0336).
      WORD_GAP = /(?:\s|&nbsp;| |<[^>]*>)+/
      HEADER_END = /provided#{WORD_GAP}this#{WORD_GAP}header#{WORD_GAP}(?:page|part)#{WORD_GAP}
                    is#{WORD_GAP}?kept#{WORD_GAP}intact/xi
      HR = /<hr\b[^>]*>/i
      TAMIL = /\p{Tamil}/
      LETTER = /\p{L}/
      BOM = "﻿"

      BREAKS = %w[br].freeze
      BLOCKS = %w[p div h1 h2 h3 h4 h5 h6 li tr td th center ul ol dl dd dt blockquote table pre hr].freeze
      HEADINGS = %w[h1 h2 h3 h4 h5 h6].freeze
      SKIP = %w[script style head title].freeze

      module_function

      def etext(html, path:)
        html = decode(html, path: path)
        header_match = HEADER_END.match(html) or
          raise Nabu::ParseError,
                "#{File.basename(path)}: no Project Madurai header page (distribution sentence missing)"
        hr = HR.match(html, header_match.end(0))
        body_start = hr ? hr.end(0) : header_match.end(0)
        body_end = footer_start(html, body_start)
        body = lines_of(html[body_start...body_end])
        kept = body.select { |line| line.text.match?(TAMIL) }
        Etext.new(
          lines: kept,
          header: plain(html[0...body_start]),
          footer: plain(html[body_end..]),
          html_title: html[%r{<title>(.*?)</title>}im, 1]&.then { |t| clean(t) },
          non_tamil_lines: body.count { |line| !line.text.match?(TAMIL) && line.text.match?(LETTER) }
        )
      end

      def catalog(html)
        doc = Nokogiri::HTML(decode(html, path: "pmworks.html"))
        files = Hash.new { |hash, key| hash[key] = { works: [], titles: [], authors: [], genres: [] } }
        doc.xpath("//table[@id='sortabletable']/tbody/tr").each do |tr|
          cells = tr.xpath("./td").map { |td| clean(td.text) }
          next if cells.size < 4

          tr.xpath(".//a/@href").map(&:value).grep(%r{/utf8/pmuni[^/]*\.html\z}).each do |href|
            entry = files[File.basename(href)]
            entry[:works] |= [cells[0]]
            entry[:titles] |= [cells[1]]
            entry[:authors] |= [cells[2]]
            entry[:genres] |= [cells[3]]
          end
        end
        files.map do |file, row|
          Entry.new(file: file, work_numbers: row[:works], titles: row[:titles].reject(&:empty?),
                    authors: row[:authors].reject(&:empty?), genres: row[:genres].reject(&:empty?))
        end
      end

      def decode(bytes, path:)
        text = bytes.dup.force_encoding(Encoding::UTF_8)
        raise Nabu::ParseError, "#{File.basename(path)}: not valid UTF-8" unless text.valid_encoding?

        text.delete_prefix(BOM)
      end

      # The footer cut: the last <hr> after the body start, when nothing
      # Tamil follows it; else the document's end.
      def footer_start(html, body_start)
        last = nil
        html.scan(HR) { last = Regexp.last_match.begin(0) }
        return html.length if last.nil? || last < body_start
        return html.length if html[last..].match?(TAMIL)

        last
      end

      def lines_of(fragment_html)
        lines = [[+"", false]]
        walk(Nokogiri::HTML::DocumentFragment.parse(fragment_html), lines, heading: false)
        lines.filter_map do |text, heading|
          cleaned = clean(text)
          cleaned.empty? ? nil : Line.new(text: cleaned, heading: heading)
        end
      end

      def walk(node, lines, heading:)
        node.children.each do |child|
          if child.text?
            lines.last[0] << child.text
            lines.last[1] ||= heading unless child.text.strip.empty?
          elsif child.element?
            name = child.name.downcase
            next if SKIP.include?(name)

            if BREAKS.include?(name)
              lines << [+"", false]
            elsif BLOCKS.include?(name)
              lines << [+"", false]
              walk(child, lines, heading: heading || HEADINGS.include?(name))
              lines << [+"", false]
            else
              walk(child, lines, heading: heading)
            end
          end
        end
      end

      def plain(html)
        lines_of(html).map(&:text).join("\n")
      end

      def clean(text)
        Normalize.nfc(text.to_s.gsub(/[[:space:] ]+/, " ").strip)
      end
    end
  end
end
