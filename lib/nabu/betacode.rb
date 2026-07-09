# frozen_string_literal: true

module Nabu
  # Minimal TLG betacode → Unicode Greek decoder (P11-4). The Perseus LSJ TEI
  # carries ALL its Greek — entry keys, orths, quotes — in betacode
  # ("mh=nis", "o( mh\\ o)cudorkw=n"); the dictionary shelf needs the Unicode
  # forms for display and for folded-headword keying (conventions §9), so the
  # decoding happens once, at the adapter boundary, like every other text
  # normalization.
  #
  # Deliberately minimal: exactly the inventory the lexica use — the 24
  # letters + digamma, capitals (*x, with diacritics allowed between * and
  # the letter), breathings ) (, accents / \ =, iota subscript |, diaeresis +,
  # and the vowel-length marks ^ _ (metrical annotations, stripped). Anything
  # else (digits, punctuation, hyphens, Latin text) passes through unchanged —
  # the callers hand us lang="greek" content only, and an unknown character is
  # more honestly kept than guessed at.
  #
  # Combining marks are emitted in canonical order (diaeresis/breathing before
  # accent before iota subscript) regardless of source order — LSJ writes both
  # "i/+" and "i+/" — and the result is NFC-composed (Normalize's contract),
  # so "mh=nis" comes out as precomposed "μῆνις". Sigma is positional: σ
  # before a letter in the same word, ς at word end ("s1"/"s2"/"s3" forced
  # variants are not in the lexica's inventory and are not supported).
  module Betacode
    LETTERS = {
      "a" => "α", "b" => "β", "g" => "γ", "d" => "δ", "e" => "ε",
      "v" => "ϝ", "z" => "ζ", "h" => "η", "q" => "θ", "i" => "ι",
      "k" => "κ", "l" => "λ", "m" => "μ", "n" => "ν", "c" => "ξ",
      "o" => "ο", "p" => "π", "r" => "ρ", "s" => "σ", "t" => "τ",
      "u" => "υ", "f" => "φ", "x" => "χ", "y" => "ψ", "w" => "ω"
    }.freeze

    UPPER = LETTERS.transform_values { |ch| ch == "ϝ" ? "Ϝ" : ch.upcase }.freeze

    # Combining marks, keyed by their betacode sign, valued [codepoint,
    # canonical emission rank] (rank: 0 diaeresis/breathing, 1 accent,
    # 2 iota subscript — the composition order Unicode expects).
    MARKS = {
      ")" => ["̓", 0], "(" => ["̔", 0], "+" => ["̈", 0],
      "/" => ["́", 1], "\\" => ["̀", 1], "=" => ["͂", 1],
      "|" => ["ͅ", 2]
    }.freeze

    LENGTH_MARKS = ["^", "_"].freeze

    module_function

    # Decode one betacode string to NFC Unicode Greek. Non-betacode characters
    # pass through unchanged.
    def decode(str)
      out = +""
      chars = str.chars
      index = 0
      index = decode_at(chars, index, out) while index < chars.length
      finalize_sigmas(out).unicode_normalize(:nfc)
    end

    # Decode the token starting at +index+ into +out+; return the next index.
    def decode_at(chars, index, out)
      char = chars[index]
      if char == "*"
        decode_capital(chars, index + 1, out)
      elsif LETTERS.key?(char)
        decode_letter(chars, index, out, LETTERS.fetch(char))
      elsif LENGTH_MARKS.include?(char)
        index + 1 # metrical length annotation: stripped
      else
        out << char
        index + 1
      end
    end

    # "*" + (marks…) + letter: the marks precede the capital in betacode but
    # combine onto it in Unicode.
    def decode_capital(chars, index, out)
      marks = []
      while index < chars.length && MARKS.key?(chars[index])
        marks << MARKS.fetch(chars[index])
        index += 1
      end
      base = UPPER[chars[index]]
      unless base
        out << "*" << marks.map(&:first).join # not a capital after all: keep honestly
        return index
      end
      index = collect_marks(chars, index + 1, marks)
      emit(out, base, marks)
      index
    end

    def decode_letter(chars, index, out, base)
      marks = []
      index = collect_marks(chars, index + 1, marks)
      emit(out, base, marks)
      index
    end

    def collect_marks(chars, index, marks)
      loop do
        char = chars[index]
        if char && MARKS.key?(char)
          marks << MARKS.fetch(char)
          index += 1
        elsif char && LENGTH_MARKS.include?(char)
          index += 1
        else
          return index
        end
      end
    end

    def emit(out, base, marks)
      out << base
      marks.sort_by(&:last).each { |mark, _rank| out << mark }
    end

    # Positional sigma: a σ not followed by a Greek letter (marks were already
    # attached, and the string is still decomposed here) is word-final.
    def finalize_sigmas(str)
      str.gsub(/σ(?![\p{Greek}\p{Mn}])/, "ς")
    end
  end
end
