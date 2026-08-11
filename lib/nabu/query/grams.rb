# frozen_string_literal: true

module Nabu
  module Query
    # The shared gram builder (docs/intertext-design.md §1 rider i, §5): the
    # already-folded text_normalized → elision-stripped tokens → overlapping
    # n-grams. ONE copy so Parallels (§1, pointed OUTWARD: probe each gram as an
    # FTS phrase against the whole index) and Formulas (§5, pointed INWARD: count
    # grams within a slice) tokenize and shingle IDENTICALLY — a formula mined
    # here re-probes as a parallel there, no drift between the two surfaces.
    #
    # Mixed into a query class (both hold their own catalog/fulltext handles);
    # these two methods are the whole of the shared "fold, elision strip,
    # tokenize, shingle" machinery the design named.
    module Grams
      # Elision apostrophes stripped at gram-build: U+02BC modifier letter
      # (SBLGNT — a LETTER to unicode61, so ἐπʼ indexes as ONE token), U+2019/
      # U+2018 quotes and ASCII ' (First1K/Swete/others), U+02B9 prime, plus the
      # Greek oxia/psili spacing accents (U+0384 U+1FBD U+1FBF) that ride the
      # same apostrophe slot in some editions. Design §1 rider i: without the
      # strip a gram spanning the apostrophe never matches its cross-edition twin.
      ELISION = /[ʼʹ‘’'΄᾽᾿]/

      # P72-3 (Edubba FR-3): the char-grain switch for spaceless CJK. A
      # maximal letter/number run is ONE word token — which makes an lzh
      # clause a single opaque token and the Analects "4,625 tokens" (the
      # survey's finding). Splitting Han runs into single characters puts
      # 子曰 / 不亦…乎 within gram reach; non-Han runs keep word grain, so
      # mixed text grams sanely.
      HAN_CHAR = /\p{Han}/
      NON_HAN_RUN = /[[\p{L}\p{N}]&&[^\p{Han}]]+/

      # Grain-aware display/identity join: an all-Han gram reads (and keys)
      # as the run itself — 子曰, not "子 曰"; mixed/word grams keep spaces.
      def self.join(tokens)
        tokens.all? { |token| token.match?(/\A\p{Han}\z/) } ? tokens.join : tokens.join(" ")
      end

      private

      # Tokens for gramming: strip elision apostrophes, then take maximal
      # letter/number runs — reproducing unicode61's tokenization (punctuation is
      # a separator) so a phrase built here re-tokenizes, and matches the FTS
      # index, identically. Input is text_normalized (already folded to the search
      # form at the adapter boundary).
      def gram_tokens(text_normalized)
        text_normalized.gsub(ELISION, "").scan(/[\p{L}\p{N}]+/).flat_map do |run|
          run.match?(HAN_CHAR) ? run.scan(Regexp.union(HAN_CHAR, NON_HAN_RUN)) : [run]
        end
      end

      # Overlapping +size+-token shingles of +tokens+ (each a token Array). Empty
      # when the token run is shorter than one gram (Homer 8-token line, size 4 →
      # 5 grams; n tokens → n − size + 1 grams).
      def shingle(tokens, size)
        return [] if tokens.size < size

        (0..(tokens.size - size)).map { |i| tokens[i, size] }
      end
    end
  end
end
