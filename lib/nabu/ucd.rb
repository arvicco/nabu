# frozen_string_literal: true

module Nabu
  # A pure READ seam over the Unicode Character Database core (UnicodeData.txt),
  # landed by `nabu sync ucd` under canonical/ucd/. The universal
  # character-identity FLOOR of the `nabu char` redesign (№R-44 = Shape C): the
  # NAME, general category, canonical/compatibility decomposition and numeric
  # value of EVERY code point — the properties Ruby's own Unicode tables do not
  # expose (Ruby gives script membership and case, but not names or numeric
  # values). Feature-module posture (kind: module), the SignList/FormLemma
  # shape: absent file → #load_default is nil and the char card degrades to its
  # pure-Ruby reduced form, byte-identical.
  #
  # == UnicodeData.txt — the format (grounded in test/fixtures/ucd/)
  #
  # Fifteen semicolon-separated fields per line, no header, code-point order:
  #   0 code point (hex)     5 decomposition       10 Unicode-1.0 name
  #   1 name                 6 decimal digit       11 ISO comment (obsolete)
  #   2 general category     7 digit               12 uppercase mapping
  #   3 combining class      8 numeric value       13 lowercase mapping
  #   4 bidi class           9 bidi mirrored       14 titlecase mapping
  #
  # RANGES: the big uniform blocks (CJK & Tangut ideographs, Hangul syllables,
  # Private Use, surrogates) are given as a "<…, First>"/"<…, Last>" line PAIR
  # — the interior code points are NOT listed, their names are DERIVED
  # algorithmically. This seam expands the derivation for the families a corpus
  # actually meets: CJK/Tangut ideographs (NAME-hhhh) and Hangul syllables
  # (jamo composition, so `char 입` → HANGUL SYLLABLE IB), and keeps the block
  # label for the rest (Private Use…).
  module Ucd
    SLUG = "ucd"
    DUMP_FILE = "UnicodeData.txt"

    # General category → human label (the two-letter codes UnicodeData carries
    # in field 2). Only the categories a text corpus meets need naming; an
    # unlisted code falls back to the raw pair, never a lie.
    CATEGORY_LABELS = {
      "Lu" => "Uppercase Letter", "Ll" => "Lowercase Letter", "Lt" => "Titlecase Letter",
      "Lm" => "Modifier Letter", "Lo" => "Other Letter",
      "Mn" => "Nonspacing Mark", "Mc" => "Spacing Mark", "Me" => "Enclosing Mark",
      "Nd" => "Decimal Number", "Nl" => "Letter Number", "No" => "Other Number",
      "Pc" => "Connector Punctuation", "Pd" => "Dash Punctuation", "Ps" => "Open Punctuation",
      "Pe" => "Close Punctuation", "Pi" => "Initial Punctuation", "Pf" => "Final Punctuation",
      "Po" => "Other Punctuation",
      "Sm" => "Math Symbol", "Sc" => "Currency Symbol", "Sk" => "Modifier Symbol",
      "So" => "Other Symbol",
      "Zs" => "Space Separator", "Zl" => "Line Separator", "Zp" => "Paragraph Separator",
      "Cc" => "Control", "Cf" => "Format", "Cs" => "Surrogate", "Co" => "Private Use",
      "Cn" => "Unassigned"
    }.freeze

    # A parsed decomposition. +kind+ is nil for a CANONICAL decomposition
    # (À → A + ◌̀); otherwise the compatibility tag verbatim ("compat",
    # "fraction", "font", "circle", …). +codepoints+ are the targets, in order.
    Decomposition = Data.define(:kind, :codepoints)

    # One code point's identity record. Range-derived points carry the block's
    # shared fields (category, etc.) with an algorithmic +name+.
    Char = Data.define(
      :codepoint, :glyph, :name, :category, :combining_class,
      :decomposition, :numeric, :unicode1_name, :uppercase, :lowercase
    ) do
      def hex = format("U+%04X", codepoint)

      def category_label = CATEGORY_LABELS.fetch(category, category)

      # The name to SHOW: for code points whose name field is an angle-bracket
      # label (<control>, <control>…) the real mnemonic lives in the
      # Unicode-1.0 column (NULL, BELL…) — prefer it when present.
      def display_name
        return unicode1_name if name.start_with?("<") && !unicode1_name.to_s.empty?

        name
      end
    end

    # A "<…, First>/<…, Last>" block: the inclusive code-point +range+, the
    # stripped label ("CJK Ideograph", "Hangul Syllable", …) and the shared
    # field row every interior point inherits.
    RangeBlock = Data.define(:range, :label, :fields)

    class << self
      # Build a seam from a UnicodeData.txt-shaped file.
      def load(path)
        by_cp = {}
        ranges = []
        pending = nil
        File.foreach(path, encoding: Encoding::UTF_8) do |line|
          line = line.chomp
          next if line.empty?

          fields = line.split(";", -1)
          cp = Integer(fields[0], 16)
          case fields[1]
          when /, First>\z/ then pending = [cp, fields]
          when /, Last>\z/
            first_cp, first_fields = pending
            ranges << RangeBlock.new(range: first_cp..cp, label: range_label(first_fields[1]),
                                     fields: first_fields)
            pending = nil
          else
            by_cp[cp] = build_char(cp, fields)
          end
        end
        new(by_cp, ranges)
      end

      # Feature-detect the seam from the owner's canonical tree: nil when
      # `nabu sync ucd` has not landed the dump (the SignList/FormLemma
      # posture). Memoized per path; reset! clears the cache (tests).
      def load_default(config: Nabu::Config.load)
        path = File.join(config.canonical_dir, SLUG, DUMP_FILE)
        return nil unless File.file?(path)

        (@cache ||= {})[path] ||= load(path)
      end

      def reset! = (@cache = nil)

      def new(by_cp, ranges) = Seam.new(by_cp, ranges)

      # -- record construction ------------------------------------------------

      def build_char(code, fields)
        Char.new(
          codepoint: code, glyph: glyph_for(code), name: fields[1], category: fields[2],
          combining_class: fields[3].to_i, decomposition: parse_decomposition(fields[5]),
          numeric: presence(fields[8]), unicode1_name: presence(fields[10]),
          uppercase: hex_or_nil(fields[12]), lowercase: hex_or_nil(fields[13])
        )
      end

      # A range interior point: the derived name over the block's shared fields.
      def build_range_char(code, block)
        fields = block.fields
        Char.new(
          codepoint: code, glyph: glyph_for(code), name: derived_name(code, block.label),
          category: fields[2], combining_class: fields[3].to_i,
          decomposition: nil, numeric: presence(fields[8]),
          unicode1_name: nil, uppercase: nil, lowercase: nil
        )
      end

      def parse_decomposition(str)
        return nil if str.nil? || str.empty?

        if str.start_with?("<")
          tag, *rest = str.split
          Decomposition.new(kind: tag.delete_prefix("<").delete_suffix(">"),
                            codepoints: rest.map { |h| Integer(h, 16) })
        else
          Decomposition.new(kind: nil, codepoints: str.split.map { |h| Integer(h, 16) })
        end
      end

      # "<CJK Ideograph, First>" → "CJK Ideograph".
      def range_label(name) = name.delete_prefix("<").sub(/, (First|Last)>\z/, "")

      def derived_name(code, label)
        case label
        when /\ACJK Ideograph/ then format("CJK UNIFIED IDEOGRAPH-%04X", code)
        when /\ACJK Compatibility Ideograph/ then format("CJK COMPATIBILITY IDEOGRAPH-%04X", code)
        when /Tangut Ideograph/ then format("TANGUT IDEOGRAPH-%04X", code)
        when /\AHangul Syllable/ then hangul_name(code)
        else label # Private Use, Surrogate, Plane N Private Use — keep the block label
        end
      end

      # The algorithmic Hangul syllable name (Unicode §3.12): decompose the
      # syllable index into leading/vowel/trailing jamo and concatenate their
      # short names. This is what makes `char 입` honest (→ HANGUL SYLLABLE IB).
      HANGUL_BASE = 0xAC00
      # Jamo short names (Unicode §3.12): leading has a null initial ("") at
      # index 11 (ieung), trailing has no final ("") at index 0.
      JAMO_LEADING = %w[G GG N D DD R M B BB S SS].push("", "J", "JJ", "C", "K", "T", "P", "H").freeze
      JAMO_VOWEL = %w[A AE YA YAE EO E YEO YE O WA WAE OE YO U WEO WE WI YU EU YI I].freeze
      JAMO_TRAILING = ["", "G", "GG", "GS", "N", "NJ", "NH", "D", "L", "LG", "LM", "LB", "LS",
                       "LT", "LP", "LH", "M", "B", "BS", "S", "SS", "NG", "J", "C", "K", "T",
                       "P", "H"].freeze

      def hangul_name(code)
        index = code - HANGUL_BASE
        trailing = index % 28
        vowel = (index / 28) % 21
        leading = index / (28 * 21)
        "HANGUL SYLLABLE #{JAMO_LEADING[leading]}#{JAMO_VOWEL[vowel]}#{JAMO_TRAILING[trailing]}"
      end

      def presence(str) = str.nil? || str.empty? ? nil : str

      def hex_or_nil(str) = str.nil? || str.empty? ? nil : Integer(str, 16)

      def glyph_for(code)
        code.chr(Encoding::UTF_8)
      rescue RangeError
        nil # surrogates and other non-scalar code points have no glyph
      end
    end

    # The resolver. Holds the listed code points and the range blocks; a lookup
    # tries the listed table first, then the ranges.
    class Seam
      def initialize(by_cp, ranges)
        @by_cp = by_cp
        @ranges = ranges
      end

      # Glyph (String) or code point (Integer) → its Char record, or nil when
      # the code point is assigned to no listed line and no range.
      def lookup(input)
        cp = input.is_a?(Integer) ? input : input.to_s.each_char.first&.ord
        return nil if cp.nil?

        @by_cp[cp] || range_char(cp)
      end

      # How many listed code points the seam indexed (a diagnostic; range
      # interiors are computed on demand, not counted here).
      def size = @by_cp.size

      private

      def range_char(code)
        block = @ranges.find { |b| b.range.cover?(code) } or return nil
        Ucd.build_range_char(code, block)
      end
    end
  end
end
