# frozen_string_literal: true

module Nabu
  module Adapters
    # The `esukhia-text` parser family (P48-1): the Esukhia Derge line
    # format — the plain-text carrier of the Digital Derge Kangyur and
    # Tengyur (github.com/Esukhia/derge-kangyur, …/derge-tengyur).
    #
    # == The line grammar (censused over 16 real volumes, both canons)
    #
    # Every line opens with its own citation bracket — `[1b]` (page/folio)
    # or `[1b.1]` (page.line); duplicated pages carry an `x` (`[355xa]`).
    # There is NO cross-line citation state: a line is fully self-cited,
    # which is what makes documented line-range fixture trims structurally
    # valid. Inside the text:
    #
    #   {D846}/{T846}    Tohoku text boundary. The Kangyur README documents
    #                    `{TX}` but the data at the pinned HEADs uses `D`
    #                    (rKTs style) — reality wins, both prefixes parse.
    #                    Dash suffix = subindex ({D1-1}); letter suffix =
    #                    text missing from the Tohoku catalog ({D846a}).
    #                    Markers appear mid-line (one physical line can end
    #                    one text and open the next).
    #   (X,Y)            potential error X, correction suggestion Y.
    #   {X,Y}            archaic spelling X, modern equivalent Y (used in
    #                    BOTH canons though only the Tengyur README says so).
    #   [X]              error candidate / un-transcribable characters.
    #   #                peydurma diplomatic-edition note reinsertion point.
    #
    # Exact-representation doctrine for all three pair/candidate shapes: the
    # FIRST element — what the woodblock carves — stays in the passage text;
    # the editorial layer rides the apparatus with its offset into the
    # CLEANED text. `#` anchors are removed and their offsets recorded.
    # A curly group that is neither a marker nor a pair is left verbatim
    # and censused (unrecognized_curly), never silently dropped.
    #
    # Volume files are streamed line by line (3–6 MB each, 103 + 213 files
    # upstream — never slurped); the Tengyur files open with a UTF-8 BOM
    # (the README claims none; reality wins) which is stripped before any
    # parsing.
    class EsukhiaTextParser
      BOM = "\u{FEFF}"
      MARKER = /\{[TD](\d+[a-zA-Z]?(?:-\d+)?)\}/
      CITATION = /\A\[(\d+x?[ab])(?:\.(\d+))?\]/
      VOLUME_FILENAME = /\A(\d+)_.*\.txt\z/

      # One markup shape per alternative, priority order: pair-curly,
      # pair-paren, bracket candidate, note anchor, stray curly (censused).
      MARKUP = /\{([^{}]*),([^{}]*)\}|\(([^()]*),([^()]*)\)|\[([^\[\]]*)\]|\#|\{[^{}]*\}/

      # A Tohoku boundary: +marker+ verbatim without braces ("D846a"),
      # +payload+ the number/suffix part ("846a"), positions 0-based with
      # char_start/char_end the brace-inclusive extent in the (BOM-stripped)
      # line — a zero-width span between two adjacent markers is how the
      # {D1}{D1-1} container shape surfaces.
      Marker = Data.define(:marker, :payload, :file_index, :line_index, :char_start, :char_end)

      # The whole-corpus marker index plus the preamble census (text-bearing
      # lines before the first marker of the corpus — no Toh text owns them).
      Scan = Data.define(:markers, :preamble_text_lines)

      # One citable slice of one line inside a document span. +line+ is nil
      # for text riding a page-only bracket ([1a]…).
      Segment = Data.define(:volume, :page, :line, :text)

      # clean()'s result: markup-free text, the apparatus entries
      # (JSON-ready string-keyed hashes), note-anchor offsets, and the
      # count of curly groups the grammar does not recognize.
      Cleaned = Data.define(:text, :apparatus, :note_marks, :unrecognized_curly)

      # The volume number a filename declares (001_འདུལ་བ།_ཀ.txt → 1), nil
      # for anything that is not a volume file.
      def volume_number(path)
        match = VOLUME_FILENAME.match(File.basename(path))
        match && Integer(match[1], 10)
      end

      # Stream every volume file once, indexing Tohoku markers in corpus
      # order and counting preamble text lines.
      def scan(paths)
        markers = []
        preamble = 0
        paths.each_with_index do |path, file_index|
          each_line(path) do |line, line_index|
            found = index_markers(markers, line, file_index, line_index)
            preamble += 1 if markers.empty? && !found && text_bearing?(line)
          end
        end
        Scan.new(markers: markers, preamble_text_lines: preamble)
      end

      # [page, line-number-or-nil, text-start-offset] for a line's leading
      # citation bracket, nil when the line carries none (censused: never in
      # the real corpus).
      def citation(line)
        match = CITATION.match(line) or return nil
        [match[1], match[2], match.end(0)]
      end

      # Yield the citable Segments of one document span. +paths+ are the
      # span's volume files in order; the span starts at
      # (start_line, start_char) of the first and ends before
      # (end_line, end_char) of the last — end_line nil means end of corpus.
      # Marker-only and empty slices yield nothing.
      def each_segment(paths, start_line:, start_char:, end_line:, end_char:, &block)
        unless block
          return enum_for(:each_segment, paths, start_line: start_line, start_char: start_char,
                                                end_line: end_line, end_char: end_char)
        end

        last_index = paths.size - 1
        paths.each_with_index do |path, index|
          volume = volume_number(path)
          each_line(path) do |line, line_index|
            next if index.zero? && line_index < start_line
            break if index == last_index && end_line && line_index > end_line

            emit_segment(block, line, volume,
                         from: (start_char if index.zero? && line_index == start_line),
                         to: (end_char if index == last_index && line_index == end_line))
            break if index == last_index && end_line && line_index == end_line
          end
        end
        self
      end

      # Extract the editorial markup from one segment (see the class note
      # for the doctrine: originals stay, the layer rides the apparatus).
      def clean(segment)
        text = +""
        apparatus = []
        note_marks = []
        unrecognized = 0
        position = 0
        while (match = MARKUP.match(segment, position))
          text << segment[position...match.begin(0)]
          unrecognized += apply_markup(match, text, apparatus, note_marks)
          position = match.end(0)
        end
        text << segment[position..]
        Cleaned.new(text: text, apparatus: apparatus, note_marks: note_marks,
                    unrecognized_curly: unrecognized)
      end

      private

      # Stream one file's lines (chomped, BOM-stripped) with 0-based indexes.
      def each_line(path)
        index = 0
        File.foreach(path, chomp: true, encoding: Encoding::UTF_8) do |line|
          line = line.delete_prefix(BOM) if index.zero?
          yield line, index
          index += 1
        end
      end

      def index_markers(markers, line, file_index, line_index)
        found = false
        position = 0
        while (match = MARKER.match(line, position))
          markers << Marker.new(marker: match[0][1..-2], payload: match[1],
                                file_index: file_index, line_index: line_index,
                                char_start: match.begin(0), char_end: match.end(0))
          found = true
          position = match.end(0)
        end
        found
      end

      def text_bearing?(line)
        cite = citation(line)
        rest = cite ? line[cite[2]..] : line
        !rest.strip.empty?
      end

      def emit_segment(block, line, volume, from:, to:)
        cite = citation(line)
        page, line_no, text_start = cite || [nil, nil, 0]
        first = [text_start, from || 0].max
        last = [line.length, to || line.length].min
        return if first >= last

        text = line[first...last]
        return if text.strip.empty?

        block.call(Segment.new(volume: volume, page: page, line: line_no, text: text))
      end

      # Returns the unrecognized-curly increment (0 or 1) so clean() can
      # census stray shapes without a second scan.
      def apply_markup(match, text, apparatus, note_marks)
        offset = text.length
        if match[1]
          apparatus << { "kind" => "archaic", "original" => match[1], "modern" => match[2],
                         "offset" => offset }
          text << match[1]
        elsif match[3]
          apparatus << { "kind" => "suggestion", "original" => match[3], "suggested" => match[4],
                         "offset" => offset }
          text << match[3]
        elsif match[5]
          apparatus << { "kind" => "error_candidate", "reading" => match[5], "offset" => offset }
          text << match[5]
        elsif match[0] == "#"
          note_marks << offset
        else
          text << match[0]
          return 1
        end
        0
      end
    end
  end
end
