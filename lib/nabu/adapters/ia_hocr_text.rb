# frozen_string_literal: true

require "json"
require "zlib"

require_relative "../normalize"

module Nabu
  module Adapters
    # The ia-hocr-text parser family (Q105) — archive.org's hOCR derivative
    # PAIR read back into pages, the cheap page-grain route over an item's
    # OCR (the full _hocr.html runs ~50 MB per volume; this pair ~1 MB):
    #
    #   <stem>_hocr_searchtext.txt.gz  the OCR text, one line per hOCR
    #                                  paragraph (archive-hocr-tools)
    #   <stem>_hocr_pageindex.json.gz  one [text_start, text_end,
    #                                  hocr_start, hocr_end] row per hOCR
    #                                  page, in page order
    #
    # Censused 2026-10-11 over 77 items (every Q105 adoption among them):
    # the text offsets count CHARACTERS (code points), not bytes — the
    # last row's text_end equals the text's character length on every
    # item — and rows are contiguous (a blank leaf is an empty [n, n]
    # span). The printed page numbers
    # (_page_numbers.json) are NOT read: their leafNum keys align with the
    # hOCR page order on some items and are shifted by one on others
    # (scandata leaves vs access pages), so no per-page printed number is
    # claimed; the 1-based hOCR page ordinal is the page identity.
    #
    # Text discipline: the slice is upstream's, verbatim, except that runs
    # of horizontal whitespace fold to one space (the OCR pads word gaps
    # with double spaces), lines are stripped, and blank lines drop. OCR
    # misreadings are NEVER corrected — canonical means canonical.
    module IaHocrText
      SEARCHTEXT_SUFFIX = "_hocr_searchtext.txt.gz"
      PAGEINDEX_SUFFIX = "_hocr_pageindex.json.gz"

      Page = Data.define(:ordinal, :text)

      # A whitespace token that reads as a word: two or more letters, an
      # optional trailing punctuation mark.
      WORDLIKE = /\A\p{L}{2,}[.,;:]?\z/

      # { searchtext:, pageindex: } for an item dir + file stem.
      def self.paths(dir, stem)
        { searchtext: File.join(dir, "#{stem}#{SEARCHTEXT_SUFFIX}"),
          pageindex: File.join(dir, "#{stem}#{PAGEINDEX_SUFFIX}") }
      end

      # Every hOCR page in order (blank pages included, text ""). Raises
      # Nabu::ParseError on an unreadable gzip, non-UTF-8 text, or an index
      # whose offsets are malformed, overlapping or past the text.
      def self.read_pages(searchtext_path:, pageindex_path:)
        codepoints = read_text(searchtext_path).unpack("U*")
        rows = read_index(pageindex_path)
        previous_end = 0
        rows.each_with_index.map do |row, i|
          start, stop = bounds(row, i, previous_end, codepoints.size, pageindex_path)
          previous_end = stop
          Page.new(ordinal: i + 1, text: clean(codepoints[start...stop].pack("U*")))
        end
      end

      # The share of whitespace tokens across +texts+ that read as words —
      # a coarse, deterministic OCR-quality reading (nil when no tokens).
      def self.wordlike_share(texts)
        tokens = texts.flat_map(&:split)
        return nil if tokens.empty?

        tokens.count { |token| token.match?(WORDLIKE) }.fdiv(tokens.size).round(2)
      end

      def self.clean(slice)
        lines = slice.split("\n").map { |line| line.gsub(/[[:blank:]]+/, " ").strip }
        Normalize.nfc(lines.reject(&:empty?).join("\n"))
      end

      def self.read_text(path)
        text = Zlib::GzipReader.open(path, &:read).force_encoding(Encoding::UTF_8)
        raise ParseError, "#{path}: search text is not valid UTF-8" unless text.valid_encoding?

        text
      rescue Zlib::Error, Errno::ENOENT => e
        raise ParseError, "#{path}: unreadable hOCR search text (#{e.message})"
      end

      def self.read_index(path)
        rows = JSON.parse(Zlib::GzipReader.open(path, &:read))
        raise ParseError, "#{path}: page index is not a list of rows" unless rows.is_a?(Array)

        rows
      rescue Zlib::Error, Errno::ENOENT, JSON::ParserError => e
        raise ParseError, "#{path}: unreadable hOCR page index (#{e.message})"
      end

      def self.bounds(row, index, previous_end, length, path)
        start, stop = row.is_a?(Array) ? row.first(2) : nil
        unless start.is_a?(Integer) && stop.is_a?(Integer) && start >= previous_end && stop >= start &&
               stop <= length
          raise ParseError, "#{path}: page #{index + 1} has bad text offsets #{row.inspect} " \
                            "(previous end #{previous_end}, text length #{length})"
        end

        [start, stop]
      end
      private_class_method :clean, :read_text, :read_index, :bounds
    end
  end
end
