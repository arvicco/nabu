# frozen_string_literal: true

module Nabu
  # The ATF transliteration line grammar → value tokens (P53-2), designed from
  # the grammar as the checked-in corpora actually write it (cdli C-ATF ASCII,
  # oracc Unicode ATF, the ETCSL TEI dialect) — the segmentation seam under
  # `nabu signs`. PURE: no SignList dependency; resolution (which token names
  # which sign) is Query::Signs' concern.
  #
  # == Segmentation
  #
  #   words        whitespace-separated; a leading C-ATF line number ("1.",
  #                "2'.") is stripped; bare word dividers ("," in the
  #                proto-cuneiform lexical lists, ";", ":") are skipped
  #   values       hyphen-joined within a word ("ur-{gesz}gigir-ta"), the
  #                split paren- and pipe-aware so "1(disz)-sze3" and
  #                "|SZESZ.AB|-ma" cut correctly
  #   {...}        determinative braces: stripped, every token inside marked
  #                determinative ({+ph} phonetic-complement "+" shed too)
  #   |X.Y|        compound sign names stay ONE token (kind :compound), the
  #                C-ATF times operator folded (|AxAN| → |A×AN|)
  #   UPPERCASE    sign names (kind :name; the ~a/~b1 variant suffixes of the
  #                proto-cuneiform corpus ride the value; a dotted group
  #                UD.ŠEŠ.KI stays one token — Query::Signs tries the
  #                compound before splitting it)
  #   valueₓ(SIGN) qualified values (kind :qualified, the explicit sign in
  #                +sign_spec+); C-ATF spells the subscript x bare, folded
  #                here ("zahx(SZESZ)" → zahₓ(ŠEŠ))
  #   N(notation)  numbers ("1(gesz2)", "1/2(disz)", "1(N01)"): one token,
  #                kind :number, the parenthesized notation carried — itself
  #                a value/sign lookup downstream (2(diš) is a real OSL value
  #                on MIN)
  #
  # == Damage and editorial marks
  #
  # #?! damage/query/correction flags, [...] break brackets, <...> editorial
  # insertions, half brackets and the C-ATF logogram underscores are STRIPPED
  # for lookup (the raw spelling stays on Token#raw) — but a token that IS
  # the damage ("x", "X", "[...]", "…") comes through as kind :broken, never
  # silently dropped. A scribal-correction group ("a!(DA)": the scribe wrote
  # DA, the editor reads a) drops the correction and keeps the corrected
  # value.
  #
  # == The folds
  #
  # :catf (default) — the C-ATF ASCII conventions, censused from the cdli
  # fixture: sz→š, s,→ṣ, t,→ṭ, '→ʾ (case preserved), letter-trailing digits
  # → subscripts (u2→u₂; N01-style zero-padded notations are NOT subscripts
  # and stay ASCII), x→ₓ before a qualifier paren. :etcsl adds the ETCSL
  # romanization on top: c→š, j→ŋ (the fixture's "cag4"/"kece2-da"), for the
  # etcsl shelf's URNs and the explicit --dialect etcsl flag.
  #
  # Structural ATF lines (&P headers, #protocols, @surfaces, $ states,
  # >>links) yield nil from #tokenize_line — callers count them as skipped,
  # they are not transliteration.
  class AtfTokenizer
    Token = Data.define(:raw, :value, :kind, :determinative, :sign_spec, :notation) do
      def initialize(determinative: false, sign_spec: nil, notation: nil, **) = super
    end

    # const: the two folds the held ATF corpora write — falsified by a new
    # corpus dialect, not by corpus growth
    DIALECTS = %i[catf etcsl].freeze

    LINE_NUMBER = /\A\d+'*\.\z/
    NUMBER = %r{\A\d+(?:/\d+)?\((.+)\)\z}
    QUALIFIED = /\A([^()|]+)\((.+)\)\z/
    BROKEN = /\A(?:\.+|…+|[xX])\z/
    SUBSCRIPT_DIGITS = %w[0123456789 ₀₁₂₃₄₅₆₇₈₉].freeze
    # Bare word dividers (the proto-cuneiform lexical lists' " , ").
    WORD_DIVIDERS = %w[, ; :].freeze
    STRIPPED_MARKS = "#?![]<>⸢⸣‹›«»_"

    def initialize(dialect: :catf)
      raise ArgumentError, "unknown ATF dialect #{dialect.inspect} (#{DIALECTS.join('/')})" unless
        DIALECTS.include?(dialect)

      @dialect = dialect
    end

    attr_reader :dialect

    # ATF structure (headers, protocols, surfaces, states, links) — not
    # transliteration text.
    def structural?(line)
      stripped = line.strip
      stripped.empty? || stripped.match?(/\A[&@$>=#]/)
    end

    # One transliteration line → Tokens, or nil for a structural/empty line.
    def tokenize_line(line)
      return nil if structural?(line)

      words = line.strip.split(/\s+/)
      words.shift if words.first&.match?(LINE_NUMBER)
      words.flat_map { |word| word_tokens(word) }
    end

    # The dialect's ASCII→Unicode fold, exposed for Query::Signs (sign-spec
    # folding) and the fold-pair tests.
    def fold(str)
      s = str.dup
      s.tr!("cCjJ", "šŠŋŊ") if @dialect == :etcsl
      s.gsub!("sz", "š")
      s.gsub!(/S[Zz]/, "Š")
      s.gsub!("s,", "ṣ")
      s.gsub!("S,", "Ṣ")
      s.gsub!("t,", "ṭ")
      s.gsub!("T,", "Ṭ")
      s.tr!("'", "ʾ")
      s.gsub!(/(?<=[[:alpha:]ʾ])([1-9]\d*)(?!\d)/) { Regexp.last_match(1).tr(*SUBSCRIPT_DIGITS) }
      s.gsub!(/(?<=[[:alpha:]])x(?=\()/, "ₓ")
      s
    end

    private

    def word_tokens(word)
      return [] if WORD_DIVIDERS.include?(word)

      word.split(/(\{[^}]*\})/).reject(&:empty?).flat_map do |part|
        if part.start_with?("{") && part.end_with?("}")
          inner = part[1..-2].delete_prefix("+")
          segments(inner).filter_map { |raw| classify(raw, determinative: true) }
        else
          segments(part).filter_map { |raw| classify(raw) }
        end
      end
    end

    # Split a word chunk on hyphens, but never inside (...) or |...|.
    def segments(str)
      out = []
      buffer = +""
      depth = 0
      pipes = false
      str.each_char do |char|
        case char
        when "(" then depth += 1
        when ")" then depth -= 1
        when "|" then pipes = !pipes
        when "-"
          unless depth.positive? || pipes
            out << buffer
            buffer = +""
            next
          end
        end
        buffer << char
      end
      out << buffer
      out.reject(&:empty?)
    end

    def classify(raw, determinative: false)
      cleaned = strip_annotations(raw)
      return nil if cleaned.empty?
      return Token.new(raw: raw, value: cleaned, kind: :broken, determinative: determinative) if
        cleaned.match?(BROKEN)

      folded = fold(cleaned)
      token_for(raw, folded, determinative)
    end

    def token_for(raw, folded, determinative)
      if folded.match?(/\A\|.+\|\z/)
        Token.new(raw: raw, value: fold_compound(folded), kind: :compound, determinative: determinative)
      elsif (number = NUMBER.match(folded))
        Token.new(raw: raw, value: folded, kind: :number, notation: number[1], determinative: determinative)
      elsif (qualified = QUALIFIED.match(folded))
        Token.new(raw: raw, value: qualified[1], kind: :qualified,
                  sign_spec: fold_compound(qualified[2]), determinative: determinative)
      else
        Token.new(raw: raw, value: folded, kind: name?(folded) ? :name : :value,
                  determinative: determinative)
      end
    end

    # Corrections ("a!(DA)") drop their group; the editorial mark set is
    # stripped wholesale (the raw spelling stays on the token).
    def strip_annotations(raw)
      raw.gsub(/!\([^)]*\)/, "").delete(STRIPPED_MARKS)
    end

    # The C-ATF times operator inside compound names: |AxAN| → |A×AN| (only
    # between name characters — uppercase, digits, subscripts, parens).
    def fold_compound(name)
      name.gsub(/(?<=[[:upper:]0-9₀-₉)])x(?=[[:upper:]0-9(|])/, "×")
    end

    # A sign name: has uppercase and no lowercase, judged without the
    # proto-cuneiform ~a/~b1 variant suffix ("GAL~a" is a name).
    def name?(segment)
      base = segment.sub(/(?:~[a-z0-9]+)+\z/, "")
      base.match?(/[[:upper:]]/) && !base.match?(/[[:lower:]]/)
    end
  end
end
