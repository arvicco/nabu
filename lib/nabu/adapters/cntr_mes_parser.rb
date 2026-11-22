# frozen_string_literal: true

require_relative "source_read"

module Nabu
  module Adapters
    # The `cntr-mes` parser family: one CNTR electronic transcription in the
    # Manuscript Encoding Specification (MES) — the Center for New Testament
    # Restoration's verse-keyed markup for early Greek NT witnesses. A
    # standalone, individually tested component (the Cntr adapter composes
    # it). Call shape: #parse(path, urn:, title:, language:, metadata:).
    #
    # == The grammar (upstream's MES.g4, read first-hand at the pin)
    #
    # One line per verse: `BBCCCVVV<space>(text | empty)`. BB = the book
    # (40 Matthew … 66 Revelation), CCC chapter, VVV verse. `empty` is a
    # verse with no letters: `-` (absent), `-~` (absent by vid), `+~`
    # (present by vid). `text` is space-separated segments, each a word or
    # a CORRECTION:
    #
    #   word       = prefix  attribute  glyph+  suffix
    #   prefix     = (⋄ digits)?  break*  &?  *?
    #   attribute  = (+ | -)?  ~?  (= | $)?
    #   glyph      = LETTER (% | ^)?   |   break
    #   suffix     = *?  &?  break*
    #   break      = (\ | | | /) digits*       page / column / line
    #   correction = (x{words?} )? {words?} ( [a-c]{words?})*
    #
    # LETTER is α–ω (one sigma, σ — the witnesses do not distinguish a final
    # form), plus ¯ (the terminating-nu overline), ϛ ϟ ͵ (numerals), ⳨ (the
    # staurogram), ϗ (the kai ligature), U+E001 (the private-use μου
    # ligature) and U+FFFD (a letter present but undecipherable). Anything
    # off-grammar raises Nabu::ParseError (the document quarantines) — the
    # repo is a database export, and a silent half-parse of a changed format
    # is the failure this family refuses.
    #
    # Upstream's meanings (README.md table + the CNTR Technical Reference
    # §1.2.1, greekcntr.org/resources/technical.pdf): % = character damaged
    # (traces remain — the Leiden underdot); ^ = character missing,
    # supplied from context (the Leiden square bracket); ~ = word supplied;
    # + = word supplied by vid (videtur — the space or grammar makes one
    # reading highly probable); +~ = supplied by transpositional vid; = =
    # nomen sacrum (written with an overline); $ = numeric abbreviation; & =
    # a gap in the characters of a line (lacuna); * = a gap of unknown text
    # relative to the verse; ⋄N = where an alternate versification's verse
    # N begins; break digits = how many units are skipped (0 = an unknown
    # number). In a correction, x{…} is the original scribe's UNCORRECTED
    # reading, the unmarked {…} is the original scribe's own (corrected or
    # standing) reading, a{…} b{…} c{…} are later hands (CNTR treats each
    # later hand as a separate witness state, within its terminus ad quem).
    #
    # == Preservation: what lands where (declared, nothing silently flat)
    #
    # TEXT = what a print edition's main text would read (the house Leiden
    # policy, DdbdpParser's header): the ORIGINAL SCRIBE's reading. Damaged
    # (%) letters read through; missing (^) letters and supplied words (~ +
    # +~) read through too — restorations ARE the readable text in print
    # practice; every & and * contributes the single lacuna marker "[…]"
    # (adjacent markers collapse to one), so a search never matches across a
    # gap as if the text were contiguous. Breaks drop from the text (a
    # word-internal line break joins the word); ⋄N drops (it rides the
    # alt_verses annotation). Nomina sacra and numerals stay AS WRITTEN —
    # the contracted ιηυ, θσ, κσ, never expanded (upstream gives no
    # expansion and canonical means canonical); their marks ride the tokens.
    # The overline ¯, the ligatures and U+FFFD stay verbatim. Letters are
    # upstream's: lowercase, unaccented, unpunctuated, one sigma — the
    # witnesses' own state, which NFC leaves byte-identical.
    #
    # In a correction the TEXT takes the unmarked edit (the first hand's
    # standing reading). The x{} uncorrected reading and every later hand's
    # reading ride the "corrections" annotation (rendered by the same text
    # policy), never the text: CNTR models the hands as distinct witness
    # states (01*, 01, 01a), not as cancelled-but-legible ink, and inlining
    # them (the ⟦…⟧ choice DDbDP makes for <del>) would double every
    # substituted word in search.
    #
    # ANNOTATIONS (per verse passage):
    #   mes          the verse's MES markup VERBATIM — the lossless layer:
    #                every break, condition, attribute and hand survives
    #                here even where text and tokens abstract it.
    #   tokens       one per word of the TEXT: form (letters only), the
    #                citation_part the nt alignment hub reads ("JOHN
    #                18.31"), plus only non-default marks — supplied
    #                (word | vid | transpositional-vid), abbreviation
    #                (nomen-sacrum | numeral), damaged / missing (letter
    #                counts), corrected (true inside a correction's edit).
    #   extant       the reading with every supplied stretch collapsed to
    #                "[…]" — what the witness itself still shows (only when
    #                it differs from the text).
    #   leiden       {supplied_chars, unclear_chars, gaps} — the DDbDP
    #                counts shape (zero counts omitted; absent when all 0).
    #   corrections  [{scribe, original?, a?, b?, c?}] in reading order.
    #   alt_verses   [N, …] from ⋄N.
    #   split_lines  the number of upstream lines merged into this verse
    #                (only when > 1 — see below).
    #
    # Two upstream shapes are folded, both counted:
    # - a ref on SEVERAL lines (a scribe's dittography deleted in
    #   correction, the second copy keyed to the same verse — 4 lines in 01
    #   and 03 at the pin): the lines MERGE into one passage in file order
    #   (the corrected reading then reads right: the deleted repeat
    #   contributes nothing), split_lines records it.
    # - a verse with no letters (- / -~ / +~): no passage (a passage must
    #   carry text); the ref lands in the document metadata's
    #   absent_verses / absent_verses_vid / present_verses_vid lists, and in
    #   the parse census.
    # A verse whose TEXT is empty because the first hand wrote nothing that
    # survives (x{…} {} alone) still mints — its text is the gap marker,
    # its corrections carry what was written.
    class CntrMesParser
      # Upstream book number → [sblgnt's urn stem, the nt hub's work token].
      BOOKS = {
        "40" => %w[matt MATT], "41" => %w[mark MARK], "42" => %w[luke LUKE], "43" => %w[john JOHN],
        "44" => %w[acts ACTS], "45" => %w[rom ROM], "46" => %w[1cor 1COR], "47" => %w[2cor 2COR],
        "48" => %w[gal GAL], "49" => %w[eph EPH], "50" => %w[phil PHIL], "51" => %w[col COL],
        "52" => %w[1thess 1THESS], "53" => %w[2thess 2THESS], "54" => %w[1tim 1TIM],
        "55" => %w[2tim 2TIM], "56" => %w[titus TIT], "57" => %w[phlm PHILEM], "58" => %w[heb HEB],
        "59" => %w[jas JAS], "60" => %w[1pet 1PET], "61" => %w[2pet 2PET], "62" => %w[1john 1JOHN],
        "63" => %w[2john 2JOHN], "64" => %w[3john 3JOHN], "65" => %w[jude JUDE], "66" => %w[rev REV]
      }.freeze

      LINE = /\A(?<book>\d{2})(?<chapter>\d{3})(?<verse>\d{3}) (?<body>.+)\z/

      # The grammar's LETTER set (MES.g4, verbatim).
      LETTERS = "α-ω¯ϛϟ⳨ϗ͵�"
      LETTER = /[#{LETTERS}]/
      BREAKS = { "\\" => "page", "|" => "column", "/" => "line" }.freeze
      CONDITIONS = { "%" => :damaged, "^" => :missing }.freeze
      HANDS = %w[a b c].freeze

      EMPTY_VERSES = { "-" => "absent_verses", "-~" => "absent_verses_vid",
                       "+~" => "present_verses_vid" }.freeze

      GAP_MARKER = "[…]"

      # One parsed word. +letters+ is an array of [char, condition-or-nil].
      Word = Data.define(:letters, :vid, :supplied, :abbreviation, :gap_before, :gap_after, :alt_verse)
      # One correction: +edits+ maps hand ("x", "scribe", "a", "b", "c") to its words.
      Correction = Data.define(:edits)

      # What a parse saw beyond the passages — the fixture/census numbers.
      Census = Data.define(:verse_lines, :merged_lines, :empty_verses, :anomalies)

      attr_reader :census

      # Parse +path+ into one Nabu::Document of verse passages, in file
      # order (a manuscript's own book order). +metadata+ seeds the
      # document metadata (the adapter's class/identifier facts).
      def parse(path, urn:, title:, language: "grc", metadata: {})
        verses, empties, lines = read_verses(path)
        doc_metadata = metadata.merge(empties.transform_values(&:dup)).merge("books" => books_of(verses))
        document = Nabu::Document.new(urn: urn, language: language, title: title,
                                      canonical_path: File.expand_path(path), metadata: doc_metadata)
        verses.each { |key, entry| document << passage(urn, key, entry, language, document.size) }
        raise ParseError, "#{path}: no verse carries text" if document.empty?

        @census = Census.new(verse_lines: lines, merged_lines: verses.sum { |_, e| e[:bodies].size - 1 },
                             empty_verses: empties.values.sum(&:size),
                             anomalies: verses.sum { |_, e| e[:anomalies].size })
        document
      rescue Nabu::ValidationError => e
        raise ParseError, "#{path}: #{e.message}"
      end

      # Parse one line's body (no ref) into its segments — public for the
      # grammar tests. Returns [:empty, list-key] for a letterless verse.
      def segments(body)
        scan(body).first
      end

      # [segments, anomalies] for one body.
      def scan(body)
        return [[:empty, EMPTY_VERSES.fetch(body)], []] if EMPTY_VERSES.key?(body)

        scanner = Scanner.new(body)
        [scanner.segments, scanner.anomalies]
      end

      private

      def read_verses(path)
        verses = {}
        empties = Hash.new { |h, k| h[k] = [] }
        count = 0
        SourceRead.utf8_lines(path, label: "cntr") do |raw|
          line = raw.chomp
          next if line.empty?

          count += 1
          match = LINE.match(line) ||
                  raise(ParseError, "#{path}:#{count}: not a MES verse line: #{line[0, 40].inspect}")
          stem, token = BOOKS[match[:book]] ||
                        raise(ParseError, "#{path}:#{count}: unknown book #{match[:book]}")
          key = "#{stem}.#{match[:chapter].to_i}.#{match[:verse].to_i}"
          citation = "#{token} #{match[:chapter].to_i}.#{match[:verse].to_i}"
          parsed, anomalies = begin
            scan(match[:body])
          rescue ParseError => e
            raise ParseError, "#{path}:#{count} (#{citation}): #{e.message}"
          end
          if parsed.first == :empty
            empties[parsed.last] << citation
            next
          end
          entry = (verses[key] ||= { citation: citation, bodies: [], segments: [], anomalies: [] })
          entry[:bodies] << match[:body]
          entry[:segments].concat(parsed)
          entry[:anomalies].concat(anomalies)
        end
        [verses, empties.to_h, count]
      end

      def books_of(verses)
        verses.keys.map { |key| key.split(".").first }.uniq
      end

      def passage(urn, key, entry, language, sequence)
        render = Render.new(entry[:segments], entry[:citation])
        annotations = { "mes" => entry[:bodies].join("\n"), "citation" => entry[:citation],
                        "tokens" => render.tokens }
        annotations["extant"] = render.extant if render.extant != render.text
        annotations["leiden"] = render.leiden unless render.leiden.empty?
        annotations["corrections"] = render.corrections unless render.corrections.empty?
        annotations["alt_verses"] = render.alt_verses unless render.alt_verses.empty?
        annotations["split_lines"] = entry[:bodies].size if entry[:bodies].size > 1
        annotations["mes_anomalies"] = entry[:anomalies] unless entry[:anomalies].empty?
        Nabu::Passage.new(urn: "#{urn}:#{key}", language: language, text: Normalize.nfc(render.text),
                          sequence: sequence, annotations: annotations)
      end

      # A strict recursive-descent reader of one verse body, MES.g4's rules
      # one method each.
      class Scanner
        attr_reader :anomalies

        def initialize(body)
          @chars = body.chars
          @pos = 0
          @anomalies = []
        end

        def segments
          result = [segment]
          while peek == " "
            advance
            result << segment
          end
          fail!("trailing input") unless eof?
          result
        end

        private

        def segment
          correction_start? ? correction : word
        end

        # x{ or { or a{ … opens a correction (x/a-c are never letters).
        def correction_start?
          peek == "{" || ((peek == "x" || HANDS.include?(peek)) && peek(1) == "{")
        end

        def correction
          edits = {}
          if peek == "x"
            advance
            edits["x"] = edit
            expect(" ")
          end
          edits["scribe"] = edit
          while peek == " " && HANDS.include?(peek(1)) && peek(2) == "{"
            advance
            hand = advance
            fail!("hand #{hand} repeated") if edits.key?(hand)
            edits[hand] = edit
          end
          Correction.new(edits: edits)
        end

        def edit
          expect("{")
          words = []
          unless peek == "}"
            words << word
            while peek == " "
              advance
              words << word
            end
          end
          expect("}")
          words
        end

        def word
          start = @pos
          alt = alt_reference
          skip_breaks
          gap_before = remnant!
          vid = %w[+ -].include?(peek) ? advance : nil
          supplied = peek == "~" ? (advance && true) : false
          abbreviation = { "=" => "nomen-sacrum", "$" => "numeral" }[peek]
          advance if abbreviation
          letters = glyphs(layout_only: @pos > start)
          gap_after = remnant!
          skip_breaks
          Word.new(letters: letters, vid: vid, supplied: supplied, abbreviation: abbreviation,
                   gap_before: gap_before, gap_after: gap_after, alt_verse: alt)
        end

        def alt_reference
          return nil unless peek == "⋄"

          advance
          digits = take_digits
          fail!("⋄ without a verse number") if digits.empty?
          digits.to_i
        end

        # REMNANT_LINE? REMNANT_VERSE? before the word, REMNANT_VERSE?
        # REMNANT_LINE? after it — either order, each once.
        def remnant!
          found = false
          2.times do
            break unless %w[& *].include?(peek)

            advance
            take_digits # & may carry an approximate missing-character count
            found = true
          end
          found
        end

        # glyph+ — a letter (with its condition) or a break. A word may be
        # breaks only (x{/} — an edit that moved nothing but a line end;
        # the prefix's break* has already consumed them, +layout_only+);
        # it contributes no letters. A condition mark with no letter before
        # it is off-grammar: tolerated at the word's first glyph ONLY (one
        # line at the pin, Orig 1 John 3:2 "^εφα%ν%ε…"), recorded as an
        # anomaly and ignored — the MES annotation keeps it verbatim.
        def glyphs(layout_only: false)
          letters = []
          glyphs = 0
          loop do
            if BREAKS.key?(peek)
              advance
              take_digits
            elsif peek&.match?(LETTER)
              char = advance
              letters << [char, CONDITIONS.key?(peek) ? CONDITIONS.fetch(advance) : nil]
            elsif glyphs.zero? && CONDITIONS.key?(peek)
              @anomalies << "stray #{peek} before a word's first letter at column #{@pos + 1}"
              advance
            else
              break
            end
            glyphs += 1
          end
          fail!("a word with no glyphs") if glyphs.zero? && !layout_only
          letters
        end

        def skip_breaks
          while BREAKS.key?(peek)
            advance
            take_digits
          end
        end

        def take_digits
          digits = +""
          digits << advance while peek&.match?(/\d/)
          digits
        end

        def expect(char)
          fail!("expected #{char.inspect}") unless peek == char
          advance
        end

        def peek(offset = 0) = @chars[@pos + offset]
        def eof? = @pos >= @chars.size

        def advance
          char = @chars[@pos]
          @pos += 1
          char
        end

        def fail!(why)
          raise ParseError, "MES grammar: #{why} at column #{@pos + 1} " \
                            "(#{@chars[[@pos - 8, 0].max, 16].join.inspect})"
        end
      end

      # Renders one verse's segments into the text, tokens and the
      # annotation layers (class header).
      class Render
        attr_reader :text, :extant, :tokens, :leiden, :corrections, :alt_verses

        def initialize(segments, citation)
          @citation = citation
          @tokens = []
          @corrections = []
          @alt_verses = []
          @counts = Hash.new(0)
          text_parts = []
          extant_parts = []
          segments.each do |segment|
            words = segment.is_a?(Correction) ? segment.edits.fetch("scribe") : [segment]
            @corrections << correction_note(segment) if segment.is_a?(Correction)
            words.each do |word|
              append_word(text_parts, extant_parts, word, corrected: segment.is_a?(Correction))
            end
          end
          @text = join(text_parts)
          @text = GAP_MARKER if @text.empty?
          @extant = join(extant_parts)
          @extant = GAP_MARKER if @extant.empty?
          @leiden = { "supplied_chars" => @counts[:supplied], "unclear_chars" => @counts[:unclear],
                      "gaps" => @counts[:gaps] }.reject { |_, n| n.zero? }
        end

        private

        def append_word(text_parts, extant_parts, word, corrected:)
          @alt_verses << word.alt_verse if word.alt_verse
          if word.gap_before
            gap!(text_parts)
            gap!(extant_parts, count: false)
          end
          unless word.letters.empty? # a breaks-only word carries layout, no letters
            form = word.letters.map(&:first).join
            text_parts << form
            extant_parts.concat(extant_pieces(word))
            @tokens << token(word, form, corrected)
            count_letters(word)
          end
          return unless word.gap_after

          gap!(text_parts)
          gap!(extant_parts, count: false)
        end

        def gap!(parts, count: true)
          @counts[:gaps] += 1 if count && parts.last != GAP_MARKER
          parts << GAP_MARKER unless parts.last == GAP_MARKER
        end

        # The word as the witness shows it: a wholly supplied word is a gap;
        # inside a word each run of missing letters is one gap, fused to the
        # surviving letters (ημε[…]).
        def extant_pieces(word)
          return [GAP_MARKER] if supplied_word?(word)

          rendered = +""
          word.letters.each do |char, condition|
            if condition == :missing
              rendered << GAP_MARKER unless rendered.end_with?(GAP_MARKER)
            else
              rendered << char
            end
          end
          rendered == GAP_MARKER ? [GAP_MARKER] : [rendered]
        end

        def supplied_word?(word)
          word.supplied || word.vid == "+"
        end

        def count_letters(word)
          word.letters.map(&:last).each do |condition|
            if supplied_word?(word) || condition == :missing
              @counts[:supplied] += 1
            elsif condition == :damaged
              @counts[:unclear] += 1
            end
          end
        end

        def token(word, form, corrected)
          token = { "form" => form, "citation_part" => @citation }
          supplied = supplied_kind(word)
          token["supplied"] = supplied if supplied
          token["abbreviation"] = word.abbreviation if word.abbreviation
          damaged = word.letters.count { |_, c| c == :damaged }
          missing = word.letters.count { |_, c| c == :missing }
          token["damaged"] = damaged if damaged.positive?
          token["missing"] = missing if missing.positive?
          token["corrected"] = true if corrected
          token
        end

        def supplied_kind(word)
          if word.vid == "+" && word.supplied then "transpositional-vid"
          elsif word.vid == "+" then "vid"
          elsif word.supplied then "word"
          end
        end

        def correction_note(correction)
          note = { "scribe" => reading(correction.edits.fetch("scribe")) }
          note["original"] = reading(correction.edits["x"]) if correction.edits.key?("x")
          HANDS.each { |hand| note[hand] = reading(correction.edits[hand]) if correction.edits.key?(hand) }
          note
        end

        # A hand's reading under the text policy (letters read through, gaps
        # marked); an empty edit (an omission) is the empty string.
        def reading(words)
          parts = []
          words.each do |word|
            parts << GAP_MARKER if word.gap_before && parts.last != GAP_MARKER
            parts << word.letters.map(&:first).join unless word.letters.empty?
            parts << GAP_MARKER if word.gap_after && parts.last != GAP_MARKER
          end
          Normalize.nfc(join(parts))
        end

        def join(parts)
          parts.chunk_while { |a, b| a == GAP_MARKER && b == GAP_MARKER }.map(&:first).join(" ")
        end
      end
    end
  end
end
