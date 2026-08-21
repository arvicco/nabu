# frozen_string_literal: true

module Nabu
  module Adapters
    # The `sentence-lines` parser family (P80-6): ONE plain-text artifact,
    # one sentence per line, NO upstream ids — the shared carrier of the
    # small-languages pack (cv-sardinian, salom, aranese). Deliberately
    # thin: the family owns streaming, line numbering, the blank-line rule
    # and the encoding error contract; what a line MEANS (which language,
    # which document) stays in each adapter.
    #
    # - Identity: a sentence's number is its 1-based PHYSICAL line number
    #   in the file (the tla-hf line-number precedent) — blank lines yield
    #   nothing but still count, so an upstream blank can never re-flow
    #   every following urn.
    # - A final line without a trailing newline still yields (the Common
    #   Voice artifact's censused shape); a trailing blank line yields
    #   nothing (the Şalom artifact's censused `\n\n` tail).
    # - Text is yielded VERBATIM — NFC is the adapter boundary's job
    #   (Nabu::Normalize.nfc), never the parser's.
    # - Malformed UTF-8 raises Nabu::ParseError naming file and line.
    class SentenceLinesParser
      # Stream +path+ as [line_number, text] pairs for every non-blank
      # line, in file order. Returns an Enumerator without a block.
      def each_sentence(path, &block)
        return enum_for(:each_sentence, path) unless block

        File.foreach(path, encoding: Encoding::UTF_8).with_index(1) do |line, number|
          text = line.chomp
          unless text.valid_encoding?
            raise Nabu::ParseError, "sentence-lines: malformed UTF-8 at line #{number} of #{path}"
          end

          yield [number, text] unless text.strip.empty?
        end
      end
    end
  end
end
