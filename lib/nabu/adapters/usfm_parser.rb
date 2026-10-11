# frozen_string_literal: true

require_relative "../normalize"

module Nabu
  module Adapters
    # The `usfm` parser family (P117-2, first consumer vuk-danicic): one
    # Unified Standard Format Markers file = one bible book. The library's
    # bibles so far arrive as USFX XML (UsfxParser — eng-web, vulgate); this
    # is the plain-text sibling for repositories that ship .usfm per book.
    #
    # == What is read
    #
    # \id CODE (the book code; trailing text is a comment) · \h (the running
    # heading) · \toc1/\toc2/\toc3 · \c N · \v N[-M] text. A verse's text
    # runs until the next \v or \c, across physical lines and across
    # paragraph/poetry markers (\p, \m, \q1 … — layout: the marker is
    # dropped, any text after it continues the running verse). Headings
    # and titles (\s*, \ms*, \mt*, \r, \d, \sp, \cl, intro markers) are not
    # verse text and are skipped without ending the verse. The Rs1Bible
    # conversion carries \p and \s5 chunk markers imported from an English
    # edition — structure foreign to the Serbian text, deliberately unread.
    # Footnotes and cross-references (\f … \f*, \fe … \fe*, \x … \x*) are
    # apparatus, dropped whole; every other character marker (\add, \nd,
    # \w …) is dropped while its text is kept.
    #
    # Malformed structure is loud: a verse before any \c, a \c or \v
    # without a number, or a file with no \id raises ParseError.
    class UsfmParser
      Verse = Data.define(:chapter, :verse, :text)
      Book = Data.define(:id, :heading, :toc, :verses)

      PARAGRAPH = /\A\\(?:p|m|pi\d?|mi|pm|pc|pr|ph\d?|li\d?|q\d?|qr|qc|qm\d?|nb|b)(?:\s+|\z)/
      HEADING = /\A\\(?:s\d*|ms\d*|mr|sr|r|d|sp|mt\d*|mte\d*|cl|cp|ca|va|i[a-z]*\d*|rem|sts|usfm|ide)\b/
      NOTE_SPAN = /\\(?:f|fe|x)\s.*?\\(?:f|fe|x)\*/m
      CHAR_MARKER = /\\\+?[a-z]+[0-9]*\*?\s?/
      VERSE_NUMBER = /\A\d+[a-z]?(?:-\d+[a-z]?)?\z/

      def parse(path)
        @path = path
        @verses = []
        @chapter = nil
        @current = nil
        id = nil
        heading = nil
        toc = {}
        File.read(path, encoding: "UTF-8").sub(/\A\uFEFF/, "").lines(chomp: true).each_with_index do |raw, index|
          @where = "#{path}:#{index + 1}"
          line = raw.strip
          line = line.sub(PARAGRAPH, "") while line.match?(PARAGRAPH)
          next if line.empty?

          case line
          when /\A\\id\s+(\S+)/ then id = Regexp.last_match(1).upcase
          when /\A\\h\s+(.*)\z/ then heading = clean(Regexp.last_match(1))
          when /\A\\toc([123])\s+(.*)\z/ then toc[Regexp.last_match(1)] = clean(Regexp.last_match(2))
          when /\A\\c\b\s*(\S*)/ then open_chapter(Regexp.last_match(1))
          when HEADING then next
          else verse_segments(line)
          end
        end
        flush
        raise Nabu::ParseError, "#{path}: no \\id line" unless id

        Book.new(id: id, heading: heading, toc: toc, verses: @verses)
      end

      private

      def open_chapter(number)
        flush
        raise Nabu::ParseError, "#{@where}: \\c without a chapter number" unless number.match?(/\A\d+\z/)

        @chapter = number
      end

      # A line may carry text continuing the running verse, then any number
      # of "\v N text" segments.
      def verse_segments(line)
        head, *segments = line.split(/(?=\\v\s)/)
        if head.start_with?("\\v ")
          segments.unshift(head)
        elsif @current
          @current[:parts] << head
        end
        segments.each do |segment|
          flush
          match = segment.match(/\A\\v\s+(\S+)\s*(.*)\z/m)
          raise Nabu::ParseError, "#{@where}: verse before any \\c" if @chapter.nil?
          raise Nabu::ParseError, "#{@where}: \\v without a verse number" unless match && match[1].match?(VERSE_NUMBER)

          @current = { chapter: @chapter, verse: match[1], parts: [match[2]] }
        end
      end

      def flush
        return unless @current

        text = clean(@current[:parts].join(" "))
        @verses << Verse.new(chapter: @current[:chapter], verse: @current[:verse], text: text) unless text.empty?
        @current = nil
      end

      def clean(text)
        Normalize.nfc(text.gsub(NOTE_SPAN, " ").gsub(CHAR_MARKER, "").gsub(/[[:space:]]+/, " ").strip)
      end
    end
  end
end
