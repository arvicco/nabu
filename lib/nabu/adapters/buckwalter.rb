# frozen_string_literal: true

module Nabu
  module Adapters
    # The extended Buckwalter transliteration (Tim Buckwalter's ASCII scheme
    # as extended by the Quranic Arabic Corpus for the Uthmani orthography —
    # corpus.quran.com's own table), rendered one-to-one back into the Arabic
    # letters and signs it encodes.
    #
    # ONE use: minting the quranic-corpus search form (conventions §9, the
    # parser-scoped derivation contract — QuranicCorpus.search_source). The
    # stored passage text stays upstream's Buckwalter byte for byte; only
    # text_normalized is folded from the rendering, through the house
    # Arabic pipeline (NFC → strip \p{Mn} → the ara rule), so the shelf
    # indexes exactly as the Cairo text's Arabic does. Why a rendering and
    # not a Latin fold: Buckwalter is CASE-significant (S ص ≠ s س, H ح ≠
    # h ه, A ا ≠ a fatḥa) and spells letters with punctuation characters
    # ({ ٱ, $ ش, * ذ, > أ, ~ shadda …) — the generic downcase merges the
    # emphatics and the FTS tokenizer splits words at those characters.
    # Rendered first, every word stays one Arabic token and every letter
    # keeps its identity.
    #
    # Inventory (the whole file's FORM column censused, 57 distinct
    # characters besides the space — every one in TABLE; the standard
    # Buckwalter | for alef-madda is mapped too, though the corpus spells
    # it A^). Strictly one character → one codepoint; anything outside the
    # table passes through unchanged. Lives under adapters/ on purpose: the
    # derivation fingerprint scopes adapter-tree code to the sources whose
    # parser closure references it, so this table stales only the
    # quranic-corpus stamps.
    module Buckwalter
      TABLE = {
        "'" => "ء", ">" => "أ", "&" => "ؤ", "<" => "إ", "}" => "ئ", "|" => "آ",
        "A" => "ا", "b" => "ب", "p" => "ة", "t" => "ت", "v" => "ث", "j" => "ج",
        "H" => "ح", "x" => "خ", "d" => "د", "*" => "ذ", "r" => "ر", "z" => "ز",
        "s" => "س", "$" => "ش", "S" => "ص", "D" => "ض", "T" => "ط", "Z" => "ظ",
        "E" => "ع", "g" => "غ", "_" => "ـ", "f" => "ف", "q" => "ق", "k" => "ك",
        "l" => "ل", "m" => "م", "n" => "ن", "h" => "ه", "w" => "و", "Y" => "ى",
        "y" => "ي",
        # vocalization: tanwīn, the short vowels, shadda, sukūn, maddah,
        # hamza above, dagger alif; alef wasla is a letter
        "F" => "ً", "N" => "ٌ", "K" => "ٍ", "a" => "َ", "u" => "ُ", "i" => "ِ",
        "~" => "ّ", "o" => "ْ", "^" => "ٓ", "#" => "ٔ", "`" => "ٰ", "{" => "ٱ",
        # the Quranic annotation signs and small letters
        ":" => "ۜ", "@" => "۟", '"' => "۠", "[" => "ۢ", ";" => "ۣ", "," => "ۥ",
        "." => "ۦ", "!" => "ۨ", "-" => "۪", "+" => "۫", "%" => "۬", "]" => "ۭ"
      }.freeze

      PATTERN = Regexp.union(TABLE.keys)
      private_constant :PATTERN

      module_function

      # The Arabic +text+ encodes, in upstream's character order (no
      # normalization — search_form's NFC is the next step).
      def to_arabic(text)
        text.to_s.gsub(PATTERN, TABLE)
      end
    end
  end
end
