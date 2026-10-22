# frozen_string_literal: true

require "nokogiri"

require_relative "../normalize"
require_relative "source_read"

module Nabu
  module Adapters
    # Parser family "gretil-legacy": GRETIL's pre-TEI e-texts — the *.htm
    # files of the per-language download zips (2_prakrt, 3_nia, 4_drav …),
    # the Unicode conversions GRETIL made of its older plain-text corpus.
    # Every file has the same three-part shape, inspected in the real bytes:
    #
    #   <body> HEADER — title line, edition ("Based on …"), input credit,
    #          sometimes NOTES / reference-system / metre legends
    #   <hr>   GRETIL'S NOTICE — "THIS GRETIL TEXT FILE IS FOR REFERENCE
    #          PURPOSES ONLY! / COPYRIGHT AND TERMS OF USAGE AS FOR SOURCE
    #          FILE.", the transliteration legend table, the format pointers
    #   <hr>   THE TEXT — physical lines ended by <BR>, no structural markup
    #
    # The notice is the anchor (NOTICE): a file without it is not a GRETIL
    # legacy e-text and raises ParseError, never guessed. The header is the
    # stretch between <body> and the <hr> that opens the notice block; the
    # text opens after the first <hr> following the notice.
    #
    # The honest grain is the PHYSICAL LINE (the madurai-html precedent):
    # every <br> and block boundary ends one, whitespace collapses, NFC. A
    # line is kept when it holds a letter or a digit; separator lines
    # ("______", "* * *") are dropped and COUNTED (dropped), never silently.
    # The files' own reference markers ("||4.17||", "HSS_1ab", "// Jyo_1.1
    # //") vary per file and stay in the text verbatim — the citation is
    # the line ordinal, flagged non-canonical by the adapter.
    module GretilLegacyParser
      Etext = Data.define(:title, :header, :notice, :lines, :dropped)

      # Words separated by whitespace, &nbsp; or markup (the notice wraps
      # "GRETIL" in a link).
      GAP = /(?:\s|&nbsp;|<[^>]*>)+/
      NOTICE = /THIS#{GAP}GRETIL#{GAP}TEXT#{GAP}FILE#{GAP}IS#{GAP}FOR#{GAP}REFERENCE#{GAP}PURPOSES#{GAP}ONLY/i
      NOTICE_LINE = /REFERENCE PURPOSES ONLY|COPYRIGHT AND TERMS OF USAGE/i
      HR = /<hr\b[^>]*>/i
      BODY_OPEN = /<body\b[^>]*>/i
      KEEP = /[\p{L}\p{N}]/
      BOM = "﻿"

      # The edition statement opens on "Based on …" and runs through its
      # continuation lines; it stops at the input credit, a bracketed note,
      # a ruled separator, or a capitalized label (NOTES:, METER:, "BASED
      # ON THE CSX VERSION").
      EDITION_START = /\ABased on\b/
      EDITION_STOP = /\A(?:Input\b|\[|_{3,}|[A-Z][A-Z ]{3,}(?::|\b(?:THE|VERSION)\b))/

      BREAKS = %w[br].freeze
      BLOCKS = %w[p div h1 h2 h3 h4 h5 h6 li tr td th center ul ol dl dd dt blockquote table pre hr].freeze
      SKIP = %w[script style head title].freeze

      module_function

      def etext(bytes, path:)
        html = decode(bytes, path: path)
        notice = NOTICE.match(html) or
          raise Nabu::ParseError, "#{File.basename(path)}: no GRETIL notice (not a GRETIL legacy e-text)"
        header_end = last_hr_before(html, notice.begin(0))
        body_hr = HR.match(html, notice.end(0)) or
          raise Nabu::ParseError, "#{File.basename(path)}: no <hr> closes the GRETIL notice block"
        body_open = BODY_OPEN.match(html)
        header_start = body_open && body_open.end(0) < header_end ? body_open.end(0) : 0
        body = lines_of(html[body_hr.end(0)..])
        kept = body.grep(KEEP)
        Etext.new(
          title: html[%r{<title>(.*?)</title>}im, 1]&.then { |t| clean(t) },
          header: lines_of(html[header_start...header_end]),
          notice: lines_of(html[header_end...body_hr.begin(0)]).grep(NOTICE_LINE),
          lines: kept,
          dropped: body.size - kept.size
        )
      end

      # The header's edition statement, continuation lines joined, or nil.
      def edition(header)
        start = header.index { |line| line.match?(EDITION_START) } or return nil
        run = [header[start]]
        header[(start + 1)..].each do |line|
          break if line.match?(EDITION_STOP)

          run << line
        end
        run.join(" ")
      end

      # The header's input credits ("Input by …"), verbatim.
      def input_credits(header)
        header.grep(/\AInput\b/i)
      end

      def decode(bytes, path:)
        SourceRead.utf8(bytes, label: File.basename(path)).delete_prefix(BOM)
      end

      def last_hr_before(html, position)
        last = nil
        html.scan(HR) do
          match = Regexp.last_match
          break if match.begin(0) >= position

          last = match
        end
        last ? last.begin(0) : position
      end

      def lines_of(fragment_html)
        lines = [+""]
        walk(Nokogiri::HTML::DocumentFragment.parse(fragment_html), lines)
        lines.filter_map do |text|
          cleaned = clean(text)
          cleaned.empty? ? nil : cleaned
        end
      end

      def walk(node, lines)
        node.children.each do |child|
          if child.text?
            lines.last << child.text
          elsif child.element?
            name = child.name.downcase
            next if SKIP.include?(name)

            if BREAKS.include?(name)
              lines << +""
            elsif BLOCKS.include?(name)
              lines << +""
              walk(child, lines)
              lines << +""
            else
              walk(child, lines)
            end
          end
        end
      end

      def clean(text)
        Normalize.nfc(text.to_s.gsub(/[[:space:] ]+/, " ").strip)
      end
    end
  end
end
