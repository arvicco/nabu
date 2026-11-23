# frozen_string_literal: true

module Nabu
  module Adapters
    # The estnltk-tsv family: one book of the National Library of
    # Estonia's DIGAR corpus as upstream serves it — a token table
    # (`<id>.pdf.txt.tsv`), one row per token, produced by Peeter Tinits
    # (Tallinn University) in 2018 from the pdf2txt export of each
    # DIGAR PDF, tokenized and morphologically analysed with EstNLTK
    # 1.4.1 in two regimes (`_simple` with guessing off, `_guess` with
    # it on).
    #
    # == The table
    #
    # Header: an unnamed row-index column, then word_texts_simple,
    # lemmas_simple, postag_descriptions_simple, word_texts_guess,
    # lemmas_guess, roots_guess, root_tokens_guess, forms_guess,
    # endings_guess, postags_guess, postag_descriptions_guess. The row
    # index runs 0..n-1 unbroken: the stream carries NO page, line or
    # sentence boundary (verified on the fixtures and a 6,345-token
    # sample, 2026-11-23) — upstream's export flattened them. The text
    # is upstream's own pre-tokenization cleaning (special characters
    # removed, non-Estonian diacritics simplified, OCR letter-spacing
    # collapsed — the corpus report's account), never ours.
    #
    # == What this family takes
    #
    # The token column word_texts_simple, verbatim, in row order. Two
    # exact token sequences are the digitizer's page stamp, not the
    # book's text, and are dropped (the DTA <fw> precedent — furniture,
    # not text): the horizontal stamp "Eesti Rahvusraamatukogu
    # digitaalarhiiv DIGAR" and the same stamp read up its vertical
    # rotation, letter by letter ("R A G D v I i i h r a l … R i t s e
    # E"). Anything else — OCR noise, pdf2txt's "( cid : 173 )" glyph
    # escapes, a mangled stamp — stays verbatim. The count of dropped
    # stamps is reported so the strip is auditable.
    #
    # The lemma/POS columns are NOT ingested (v1): EstNLTK 1.4.1's
    # automatic analysis of uncorrected OCR, at 5.7 GB unpacked for the
    # deposit, is an enrichment-lane decision, not parse-time text.
    #
    # == Passages
    #
    # With no boundaries upstream, passages are deterministic token
    # windows: a window closes on the first sentence-final token (".",
    # "!", "?") once it holds MIN_TOKENS tokens, or unconditionally at
    # MAX_TOKENS. Each passage's text is its tokens joined by single
    # spaces (the table's tokenization, unrepaired); its annotation
    # "rows" names the first and last table row it spans, so every
    # passage maps back onto the asset.
    class EstnltkTsvParser
      # The token column (index 0 is the unnamed row index).
      TOKEN_COLUMN = "word_texts_simple"

      SENTENCE_FINAL = %w[. ! ?].freeze

      MIN_TOKENS = 120
      MAX_TOKENS = 400

      # The digitizer's stamp, horizontally and read up the vertical —
      # the vertical sequence exactly as pdf2txt renders the rotated
      # stamp (not a clean reversal: "GD" for "GID", "vIii" for
      # "viih"), identical across the six books sampled 2026-11-23;
      # the rare OCR-mangled rendering is not matched and stays text.
      STAMP = %w[Eesti Rahvusraamatukogu digitaalarhiiv DIGAR].freeze
      VERTICAL_STAMP = "R A G D v I i i h r a l i a a t i g d u g o k u t a m a a r s u v h a R i t s e E"
                       .split.freeze

      Token = Data.define(:row, :text)
      Window = Data.define(:text, :first_row, :last_row)
      Book = Data.define(:windows, :token_count, :stamps)

      def parse(path)
        tokens = read_tokens(path)
        kept, stamps = strip_stamps(tokens)
        Book.new(windows: windows(kept), token_count: tokens.size, stamps: stamps)
      end

      # Header-only tables (pdf2txt found no text in the PDF) — the
      # discovery-time emptiness test, reading at most two lines.
      def self.empty?(path)
        line = SourceRead.utf8_lines(path, label: "estnltk-tsv table").first(2)[1]
        line.nil? || line.strip.empty?
      end

      private

      def read_tokens(path)
        lines = SourceRead.utf8_file(path, label: "estnltk-tsv table").split("\n")
        header = lines.shift.to_s.split("\t", -1)
        column = header.index(TOKEN_COLUMN)
        raise ParseError, "#{path}: no #{TOKEN_COLUMN} column in the header" if column.nil?

        lines.filter_map do |line|
          next if line.strip.empty?

          cells = line.split("\t", -1)
          raise ParseError, "#{path}: malformed row #{line[0, 40].inspect}" unless cells.size == header.size

          text = Normalize.nfc(cells[column]).strip
          Token.new(row: Integer(cells[0], 10), text: text) unless text.empty?
        end
      rescue ArgumentError => e
        raise ParseError, "#{path}: #{e.message}"
      end

      def strip_stamps(tokens)
        kept = []
        stamps = 0
        index = 0
        while index < tokens.size
          length = stamp_at(tokens, index)
          if length
            stamps += 1
            index += length
          else
            kept << tokens[index]
            index += 1
          end
        end
        [kept, stamps]
      end

      def stamp_at(tokens, index)
        [STAMP, VERTICAL_STAMP].each do |stamp|
          slice = tokens[index, stamp.size]
          return stamp.size if slice.size == stamp.size && slice.map(&:text) == stamp
        end
        nil
      end

      def windows(tokens)
        out = []
        current = []
        tokens.each do |token|
          current << token
          next unless current.size >= MAX_TOKENS ||
                      (current.size >= MIN_TOKENS && SENTENCE_FINAL.include?(token.text))

          out << window(current)
          current = []
        end
        out << window(current) unless current.empty?
        out
      end

      def window(tokens)
        Window.new(text: tokens.map(&:text).join(" "), first_row: tokens.first.row, last_row: tokens.last.row)
      end
    end
  end
end
