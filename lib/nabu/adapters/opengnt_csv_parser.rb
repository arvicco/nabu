# frozen_string_literal: true

require_relative "source_read"
require_relative "../normalize"

module Nabu
  module Adapters
    # The opengnt-csv family: eliranwong/OpenGNT's base-text CSV
    # (OpenGNT_version3_3.csv inside OpenGNT_BASE_TEXT.zip). One row per
    # word in OGNTsort order, 13 TAB-separated columns, several of which
    # pack sub-columns as 〔a｜b｜c〕 (U+3014/U+3015 brackets, U+FF5C
    # separators). The header row is pinned verbatim: the license split
    # (Nabu::Adapters::Opengnt) is enforced BY COLUMN POSITION, so a column
    # drift must fail loudly rather than shift an excluded column into a
    # kept slot.
    #
    # == Columns read (the rest are never decoded into any value)
    #
    #   0  OGNTsort                              → token "id"
    #   6  〔Book｜Chapter｜Verse〕                → the verse key
    #   7  〔OGNTk｜OGNTu｜OGNTa｜lexeme｜rmac｜sn〕 → "form" (OGNTa), "lemma",
    #                                              "rmac", "strong"
    #   8  〔…｜LN-LouwNidaNumbers〕               → "ln" (the last sub-column)
    #  11  〔PMpWord｜PMfWord〕                    → "pmp" / "pmf" (marks
    #                                              unwrapped from <pm>…</pm>)
    #  12  〔Note｜Mvar｜Mlexeme｜Mrmac｜Msn｜MTBESG〕 → "note", "mvar",
    #                                              "mlexeme", "mrmac", "msn"
    #                                              (MTBESG, a gloss, never)
    #
    # NEVER read: 3 LevinsohnClauseID, 4 OTquotation (the SIL discourse
    # layer), 10 〔TBESG｜IT｜LT｜ST｜Español〕 (glosses and translations),
    # and MTBESG — see the adapter's license note. Also not carried (not
    # license-bound, declared coarse in the adapter): 1–2 and 5 (sort keys
    # into other OpenGNT files), OGNTk/OGNTu (font-encoded and unaccented
    # renderings of the same word), the BDAG/EDNT/Mounce catchwords and GK
    # numbers (lookup keys into lexica not held), 9 the transliterations.
    #
    # Empty sub-columns become absent keys (the ConlluParser `_` rule).
    # Every kept value is NFC'd here, at the boundary: upstream's lexeme
    # column carries a handful of decomposed forms (U+1FC6 U+0345 for ῇ in
    # πεζῇ/εἰκῇ/κρυφῇ), and its punctuation column the Greek ano teleia
    # U+0387 / question mark U+037E, which NFC maps to U+00B7 / U+003B.
    class OpengntCsvParser
      HEADER = [
        "OGNTsort", "TANTTsort", "FEATURESsort1", "LevinsohnClauseID", "OTquotation",
        "〔BGBsortI｜LTsortI｜STsortI〕", "〔Book｜Chapter｜Verse〕",
        "〔OGNTk｜OGNTu｜OGNTa｜lexeme｜rmac｜sn〕",
        "〔BDAGentry｜EDNTentry｜MounceEntry｜GoodrickKohlenbergerNumbers｜LN-LouwNidaNumbers〕",
        "〔transSBLcap｜transSBL｜modernGreek｜Fonética_Transliteración〕",
        "〔TBESG｜IT｜LT｜ST｜Español〕", "〔PMpWord｜PMfWord〕",
        "〔Note｜Mvar｜Mlexeme｜Mrmac｜Msn｜MTBESG〕"
      ].join("\t").freeze

      COLUMN_COUNT = 13
      REF = /\A〔(\d+)｜(\d+)｜(\d+)〕\z/
      MARK = %r{<pm>(.*?)</pm>}

      # Layout marks in the punctuation columns: ¶ ends a paragraph, ¬
      # opens an indented (quoted/poetic) line. Kept on the token, never
      # in the running text.
      LAYOUT_MARKS = %w[¶ ¬].freeze

      # One word row, decoded. +token+ is the lean annotation hash.
      Word = Data.define(:book, :chapter, :verse, :token, :text_before, :text_after)

      # The first line must be the pinned header (ParseError otherwise).
      def check_header!(line, label:)
        header = Normalize.nfc(line.to_s.chomp)
        return if header == HEADER

        raise Nabu::ParseError, "#{label}: header drift — expected the OpenGNT v3.3 column set, " \
                                "got #{header[0, 200].inspect}"
      end

      # The book number of a data line, cheaply (no sub-column decode).
      def book_number(line, label:)
        ref = line.split("\t", 8)[6].to_s
        match = REF.match(ref) or raise Nabu::ParseError, "#{label}: malformed verse ref #{ref.inspect}"
        Integer(match[1], 10)
      end

      # Decode data lines into Words, in file order. +bytes+ is a run of
      # whole data lines (no header).
      def words(bytes, label:)
        text = SourceRead.utf8(bytes, label: label)
        text.each_line(chomp: true).reject(&:empty?).map { |line| word(line, label: label) }
      end

      # The verse's running text: each word with its non-layout marks,
      # single-space joined.
      def verse_text(words)
        words.map { |w| "#{w.text_before}#{w.token['form']}#{w.text_after}" }.join(" ")
      end

      private

      def word(line, label:)
        cols = line.split("\t", -1)
        unless cols.size == COLUMN_COUNT
          raise Nabu::ParseError,
                "#{label}: row #{cols.first.inspect} has #{cols.size} columns, expected #{COLUMN_COUNT}"
        end

        book, chapter, verse = verse_ref(cols[6], label: label)
        _koine, _unaccented, form, lemma, rmac, strong = packed(cols[7], 6, label: label)
        ln = packed(cols[8], 5, label: label).last
        pmp, pmf = packed(cols[11], 2, label: label).map { |pm| marks(pm) }
        note, mvar, mlexeme, mrmac, msn, _mtbesg = packed(cols[12], 6, label: label)
        raise Nabu::ParseError, "#{label}: row #{cols[0]} has no accented form" if form.empty?

        token = lean("id" => cols[0], "form" => form, "lemma" => lemma, "rmac" => rmac,
                     "strong" => strong, "ln" => ln, "pmp" => pmp.join, "pmf" => pmf.join,
                     "note" => note, "mvar" => mvar, "mlexeme" => mlexeme, "mrmac" => mrmac, "msn" => msn)
        Word.new(book: book, chapter: chapter, verse: verse, token: token,
                 text_before: textual(pmp), text_after: textual(pmf))
      end

      def verse_ref(field, label:)
        match = REF.match(field) or raise Nabu::ParseError, "#{label}: malformed verse ref #{field.inspect}"
        match.captures.map { |n| Integer(n, 10) }
      end

      # 〔a｜b｜c〕 → ["a", "b", "c"] (NFC), exactly +arity+ sub-columns.
      def packed(field, arity, label:)
        unless field.start_with?("〔") && field.end_with?("〕")
          raise Nabu::ParseError, "#{label}: unbracketed packed column #{field[0, 80].inspect}"
        end

        parts = field[1...-1].split("｜", -1)
        unless parts.size == arity
          raise Nabu::ParseError, "#{label}: packed column #{field[0, 80].inspect} has #{parts.size} " \
                                  "sub-columns, expected #{arity}"
        end
        parts.map { |part| Normalize.nfc(part) }
      end

      def marks(field) = field.scan(MARK).flatten

      def textual(marks) = (marks - LAYOUT_MARKS).join

      def lean(hash) = hash.reject { |_key, value| value.nil? || value.empty? }
    end
  end
end
