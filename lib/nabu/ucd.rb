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

    # -- member-context records (P86-1, №R-49a) -----------------------------
    # The context tier over the sibling UCD member files the UCD.zip fetch
    # lands next to UnicodeData.txt. Each lookup feature-detects its OWN
    # member file — a partial canonical answers what it holds and nothing
    # more (nil / empty, never a guess).

    # A named block from Blocks.txt: `16A0..16FF; Runic`.
    Block = Data.define(:range, :name)

    # A script identity: the ISO 15924 +code+ ("Runr", via
    # PropertyValueAliases.txt) and the display +name+ ("Runic", the
    # Scripts.txt long value with underscores unfolded).
    Script = Data.define(:code, :name)

    # A formal name alias from NameAliases.txt (+type+: correction, control,
    # alternate, figment, abbreviation).
    Alias = Data.define(:name, :type)

    # A code-chart cross-reference from NamesList.txt: `x (text - 05D0)`.
    Crossref = Data.define(:codepoint, :text)

    # One character's NamesList.txt chart entry: informal +aliases+ (`= `),
    # usage +notes+ (`* `), +crossrefs+ (`x `). Informative, not normative —
    # rendered as the charts annotation layer, labeled as such.
    Annotations = Data.define(:aliases, :notes, :crossrefs)

    # A CJKRadicals.txt row: Kangxi/CJK radical +number+, the radical
    # character and its unified-ideograph equivalent.
    Radical = Data.define(:number, :radical, :unified)

    class << self
      # Build a seam from a UnicodeData.txt-shaped file. The file's directory
      # is remembered as the member root: sibling files (Blocks.txt,
      # Scripts.txt, security/confusables.txt…) load lazily on first use.
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
        Seam.new(by_cp, ranges, dir: File.dirname(path))
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

      def new(by_cp, ranges, dir: nil) = Seam.new(by_cp, ranges, dir: dir)

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
    # tries the listed table first, then the ranges. Member context (blocks,
    # scripts, aliases, age, charts annotations, radicals, confusables, Tangut
    # sources, jamo names) loads lazily from the sibling files under +dir+ —
    # each member feature-detected independently, absent = empty answers.
    class Seam
      def initialize(by_cp, ranges, dir: nil)
        @by_cp = by_cp
        @ranges = ranges
        @dir = dir
        @members = {}
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

      # -- member context ----------------------------------------------------

      # Blocks.txt: the named block containing +codepoint+, or nil.
      def block(codepoint)
        find_range(member(:blocks) { parse_ranges("Blocks.txt") }, codepoint)
          &.then { |(range, name)| Block.new(range: range, name: name) }
      end

      # Scripts.txt (+ PropertyValueAliases.txt for the short code): the
      # script identity of +codepoint+, or nil.
      def script(codepoint)
        long = find_range(member(:scripts) { parse_ranges("Scripts.txt") }, codepoint)&.last
        return nil unless long

        Script.new(code: script_short_codes[long], name: long.tr("_", " "))
      end

      # ScriptExtensions.txt: the extension script short codes of +codepoint+ ([]
      # when none — most characters have no extensions line).
      def script_extensions(codepoint)
        find_range(member(:script_ext) { parse_ranges("ScriptExtensions.txt") }, codepoint)
          &.last&.split || []
      end

      # NameAliases.txt: the formal aliases of +codepoint+ (corrections, control
      # names, abbreviations…), [] when none.
      def name_aliases(codepoint)
        member(:name_aliases) { parse_name_aliases }.fetch(codepoint, [])
      end

      # DerivedAge.txt: the Unicode version that introduced +codepoint+, or nil.
      def age(codepoint)
        find_range(member(:age) { parse_ranges("DerivedAge.txt") }, codepoint)&.last
      end

      # NamesList.txt: the code-chart annotations of +codepoint+, or nil when the
      # charts carry no entry (or the member is absent).
      def annotations(codepoint)
        member(:names_list) { parse_names_list }[codepoint]
      end

      # CJKRadicals.txt: the radical row +codepoint+ appears in (as the radical
      # character or its unified equivalent), or nil.
      def cjk_radical(codepoint)
        member(:radicals) { parse_cjk_radicals }[codepoint]
      end

      # EquivalentUnifiedIdeograph.txt: the unified ideograph +codepoint+ (a Kangxi
      # radical or CJK-radical char) is equivalent to, or nil.
      def equivalent_unified(codepoint)
        find_range(member(:equiv_unified) { parse_ranges("EquivalentUnifiedIdeograph.txt") }, codepoint)
          &.last&.then { |hex| Integer(hex, 16) }
      end

      # security/confusables.txt (UTS #39): code points visually confusable
      # with +codepoint+ — its skeleton cluster minus itself, both directions. [] when
      # none or the member is absent.
      def confusables(codepoint)
        sources_by_target, target_by_source = member(:confusables) { parse_confusables }
        return [] unless sources_by_target

        cluster = []
        if (target = target_by_source[codepoint])
          cluster.concat(sources_by_target.fetch(target, []))
          cluster << target.first if target.size == 1
        end
        cluster.concat(sources_by_target.fetch([codepoint], []))
        cluster.uniq.reject { |other| other == codepoint }.sort
      end

      # TangutSources.txt / NushuSources.txt: the per-character source fields
      # ({"kRSTUnicode" => "9.1", …}), or nil.
      def tangut_source(codepoint) = member(:tangut) { parse_tab_sources("TangutSources.txt") }[codepoint]
      def nushu_source(codepoint) = member(:nushu) { parse_tab_sources("NushuSources.txt") }[codepoint]

      # Jamo.txt: the jamo short name of +codepoint+ ("G" for U+1100; "" is real —
      # the null-initial ieung), or nil for a non-jamo code point.
      def jamo_short_name(codepoint)
        member(:jamo) { parse_jamo }[codepoint]
      end

      private

      def range_char(code)
        block = @ranges.find { |b| b.range.cover?(code) } or return nil
        Ucd.build_range_char(code, block)
      end

      # -- member machinery --------------------------------------------------

      # Load-once per member key; the block parses the file. Absent dir or
      # file → the parser sees nil and answers its empty shape.
      def member(key, &parser)
        return @members[key] if @members.key?(key)

        @members[key] = parser.call
      end

      def member_path(filename)
        return nil unless @dir

        path = File.join(@dir, filename)
        File.file?(path) ? path : nil
      end

      # The shared "HHHH[..HHHH] ; value # comment" reader (Blocks, Scripts,
      # ScriptExtensions, DerivedAge, EquivalentUnifiedIdeograph — Blocks uses
      # "; " without the aligned padding, same grammar). → sorted
      # [[range, value], …] for bsearch, or nil when the member is absent.
      def parse_ranges(filename)
        path = member_path(filename) or return nil

        rows = []
        File.foreach(path, encoding: Encoding::UTF_8) do |line|
          next unless (m = line.match(/\A([0-9A-F]{4,6})(?:\.\.([0-9A-F]{4,6}))?\s*;\s*([^#\n]+)/))

          first = Integer(m[1], 16)
          last = m[2] ? Integer(m[2], 16) : first
          rows << [first..last, m[3].strip]
        end
        rows.sort_by! { |(range, _)| range.first }
        rows
      end

      def find_range(rows, codepoint)
        return nil unless rows

        row = rows.bsearch { |(range, _)| range.last >= codepoint }
        row if row && row[0].cover?(codepoint)
      end

      # PropertyValueAliases.txt `sc ;` lines: long name → short code
      # ("Runic" is stored under its file spelling "Runic"; multi-word names
      # keep their underscores as Scripts.txt writes them).
      def script_short_codes
        member(:script_codes) do
          path = member_path("PropertyValueAliases.txt")
          codes = {}
          if path
            File.foreach(path, encoding: Encoding::UTF_8) do |line|
              next unless (m = line.match(/\Asc\s*;\s*(\w+)\s*;\s*(\w+)/))

              codes[m[2]] = m[1]
            end
          end
          codes
        end
      end

      def parse_name_aliases
        path = member_path("NameAliases.txt")
        aliases = Hash.new { |h, k| h[k] = [] }
        if path
          File.foreach(path, encoding: Encoding::UTF_8) do |line|
            next unless (m = line.match(/\A([0-9A-F]{4,6});([^;]+);(\w+)/))

            aliases[Integer(m[1], 16)] << Alias.new(name: m[2], type: m[3])
          end
        end
        aliases.default = nil
        aliases
      end

      # NamesList.txt char entries: `XXXX<tab>NAME` opens an entry; indented
      # `= / * / x` lines annotate it. `x` carries either `(text - XXXX)` or a
      # bare `XXXX`. Everything else in the chart grammar (@ headers, #
      # decompositions, ~ variations) is deliberately skipped — identity and
      # decomposition already come from UnicodeData itself.
      def parse_names_list
        path = member_path("NamesList.txt")
        entries = {}
        if path
          current = nil
          File.foreach(path, encoding: Encoding::UTF_8) do |line|
            if (m = line.match(/\A([0-9A-F]{4,6})\t/))
              current = entries[Integer(m[1], 16)] =
                Annotations.new(aliases: [], notes: [], crossrefs: [])
            elsif current && (m = line.match(/\A\t= (.+)/))
              current.aliases << m[1].strip
            elsif current && (m = line.match(/\A\t\* (.+)/))
              current.notes << m[1].strip
            elsif current && (m = line.match(/\A\tx \((.+) - ([0-9A-F]{4,6})\)/))
              current.crossrefs << Crossref.new(codepoint: Integer(m[2], 16), text: m[1].strip)
            elsif current && (m = line.match(/\A\tx ([0-9A-F]{4,6})\b\s*(.*)/))
              current.crossrefs << Crossref.new(codepoint: Integer(m[1], 16), text: m[2].strip)
            elsif !line.start_with?("\t")
              current = nil
            end
          end
        end
        entries
      end

      # CJKRadicals.txt `number[']; radical char; unified char` — indexed by
      # BOTH characters, so either resolves the row.
      def parse_cjk_radicals
        path = member_path("CJKRadicals.txt")
        rows = {}
        if path
          File.foreach(path, encoding: Encoding::UTF_8) do |line|
            next unless (m = line.match(/\A(\d+)'?\s*;\s*([0-9A-F]{4,6})\s*;\s*([0-9A-F]{4,6})/))

            row = Radical.new(number: m[1].to_i, radical: Integer(m[2], 16),
                              unified: Integer(m[3], 16))
            rows[row.radical] = row
            rows[row.unified] ||= row
          end
        end
        rows
      end

      # confusables.txt `source ; target(s) ; MA` → the two indexes the
      # cluster walk needs. Targets can be multi-code-point skeletons — the
      # cluster key is the whole target sequence.
      def parse_confusables
        path = member_path("security/confusables.txt") || member_path("confusables.txt")
        return [nil, nil] unless path

        sources_by_target = Hash.new { |h, k| h[k] = [] }
        target_by_source = {}
        File.foreach(path, encoding: Encoding::UTF_8) do |line|
          next unless (m = line.match(/\A([0-9A-F]{4,6})\s*;\s*([0-9A-F]{4,6}(?:\s+[0-9A-F]{4,6})*)\s*;/))

          source = Integer(m[1], 16)
          target = m[2].split.map { |hex| Integer(hex, 16) }
          sources_by_target[target] << source
          target_by_source[source] = target
        end
        sources_by_target.default = nil
        [sources_by_target, target_by_source]
      end

      # TangutSources/NushuSources: `codepoint<tab>field<tab>value` per line.
      def parse_tab_sources(filename)
        path = member_path(filename)
        rows = Hash.new { |h, k| h[k] = {} }
        if path
          File.foreach(path, encoding: Encoding::UTF_8) do |line|
            next unless (m = line.match(/\AU\+([0-9A-F]{4,6})\t(\w+)\t(.+)/)) ||
                        (m = line.match(/\A([0-9A-F]{4,6})\t(\w+)\t(.+)/))

            rows[Integer(m[1], 16)][m[2]] = m[3].strip
          end
        end
        rows.default = nil
        rows
      end

      # Jamo.txt `1100; G # …` — the value may be legitimately empty (110B).
      def parse_jamo
        path = member_path("Jamo.txt")
        rows = {}
        if path
          File.foreach(path, encoding: Encoding::UTF_8) do |line|
            next unless (m = line.match(/\A([0-9A-F]{4,6});\s*(\w*)/))

            rows[Integer(m[1], 16)] = m[2]
          end
        end
        rows
      end
    end
  end
end
