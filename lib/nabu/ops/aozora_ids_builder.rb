# frozen_string_literal: true

module Nabu
  module Ops
    # P39-5: generator for config/gaiji/aozora-ids.tsv — the Aozora gaiji IDS
    # lane (rung 2 of the P38-2 display ladder). Reads the HELD, checked-in
    # census of composition descriptions (config/gaiji/aozora-descriptions.tsv,
    # snapshotted read-only from the parse-time gaiji_unresolved annotations)
    # and mechanically derives an Ideographic Description Sequence for the cases
    # a CONSERVATIVE grammar can prove, refusing everything else.
    #
    # == The honesty bar (why so conservative)
    #
    # A derived ⿰AB is a STRUCTURAL claim (this glyph is A-left, B-right), not an
    # identity claim, and it renders on the IDS rung — which is honest about
    # being a description, not a real codepoint. So the bar is: derive ONLY where
    # the description is mechanically unambiguous, and when in doubt REFUSE (the
    # sentinel ※［＃…］ stays in the text, the reader sees the raw notation). We
    # never guess a component, never resolve a radical NAME to its glyph, never
    # evaluate arithmetic on components.
    #
    # == The grammar (mechanical cases only)
    #
    #   「A＋B」  single ＋ between two literal CJK ideographs → ⿰AB (left-right)
    #   「A／B」  single ／ between two literal CJK ideographs → ⿱AB (top-bottom)
    #
    # "literal CJK ideograph" = a single \p{Han} character. This is exactly what
    # excludes the un-derivable majority: a kana radical NAME (にんべん, さんずい,
    # くさかんむり…) is not a component glyph, and a multi-char component
    # (鐶のつくり "the tsukuri of 鐶") is a prose description — both fail the
    # single-\p{Han} test and refuse.
    #
    # == Refusal classes (censused, never silent)
    #
    #   kana_component  a formula naming a radical/part in kana (にんべん＋巨) or a
    #                   kana-bearing multi-char component — no mechanical glyph.
    #   replace         「…」に代えて「…」 component-substitution prose.
    #   subtractive     a － (U+FF0D) removes a component: 旗－其＋冉 — not IDS.
    #   parenthesised   （…） grouping / nesting: needs a recursive parse we refuse.
    #   multi_operator  two or more ＋／ operators (禾＋尤／上／日) — ambiguous nesting.
    #   other           anything else the two rules do not match (non-Han operand
    #                   Ｙ＋Ｙ, a malformed unclosed 「…, a stray locator).
    #
    # == Input / output
    #
    # Input is the checked-in census (NOT canonical, NOT the 27 GB catalog): the
    # builder is a pure function of a small held TSV so `rake gaiji:aozora_ids`
    # runs anywhere. Output is desc<TAB>ids-sequence, desc-sorted for a stable
    # diff. The desc IS the lane KEY the render path looks up
    # (Nabu::Display::GAIJI_SENTINELS["aozora"] derives the identical string from
    # the in-text ※［＃…］ notation), so no per-book locator ever fragments it.
    class AozoraIdsBuilder
      # The two derivable shapes. \A…\z anchored: the WHOLE formula must be one
      # operator between two single Han ideographs, nothing else.
      DERIVE_LR = /\A(?<a>\p{Han})＋(?<b>\p{Han})\z/
      DERIVE_TB = /\A(?<a>\p{Han})／(?<b>\p{Han})\z/
      IDC_LR = "⿰" # ⿰ IDEOGRAPHIC DESCRIPTION CHARACTER LEFT TO RIGHT
      IDC_TB = "⿱" # ⿱ IDEOGRAPHIC DESCRIPTION CHARACTER ABOVE TO BELOW

      REFUSAL_ORDER = %i[kana_component replace subtractive parenthesised multi_operator other].freeze

      Census = Struct.new(:descriptions, :composition_occurrences, :derived, :derived_occurrences,
                          :refused, keyword_init: true)

      attr_reader :census, :lane

      # +census_path+ is config/gaiji/aozora-descriptions.tsv.
      def initialize(census_path:, generated_on: Time.now.strftime("%Y-%m-%d"))
        @census_path = census_path
        @generated_on = generated_on
        @lane = {}
        @refused = REFUSAL_ORDER.to_h { |cls| [cls, []] }
        build
      end

      # The config/gaiji/aozora-ids.tsv file text.
      def render
        rows = @lane.sort_by { |desc, _| desc }.map { |desc, ids| "#{desc}\t#{ids}" }
        (header + rows).join("\n") << "\n"
      end

      private

      def build
        descs = read_census
        occ = 0
        derived_occ = 0
        descs.each do |desc, count|
          occ += count
          if (ids = derive(desc))
            @lane[desc] = ids
            derived_occ += count
          else
            @refused[classify(desc)] << desc
          end
        end
        @census = Census.new(descriptions: descs.size, composition_occurrences: occ,
                             derived: @lane.size, derived_occurrences: derived_occ,
                             refused: @refused.transform_values(&:size))
      end

      # desc → IDS, or nil (refuse). Pure, order-independent.
      def derive(desc)
        if (m = DERIVE_LR.match(desc)) then "#{IDC_LR}#{m[:a]}#{m[:b]}"
        elsif (m = DERIVE_TB.match(desc)) then "#{IDC_TB}#{m[:a]}#{m[:b]}"
        end
      end

      # Bucket a refused desc for the census. Order matters: the first matching
      # trait wins (kana before subtraction before parens…), so each refused
      # desc is counted once, under its most salient un-derivable trait.
      def classify(desc)
        return :kana_component if desc.match?(/[\p{Hiragana}\p{Katakana}ー]/)
        return :replace if desc.include?("代えて")
        # The formula subtraction operator is U+FF0D FULLWIDTH HYPHEN-MINUS (and
        # U+2212 MINUS SIGN, defensively) — NOT the ASCII U+002D that trails a
        # page/line locator (…、252-11), which would false-positive here.
        return :subtractive if desc.match?(/[－−]/)
        return :parenthesised if desc.match?(/[（）]/)
        return :multi_operator if desc.scan(/[＋／]/).size >= 2

        :other
      end

      # count<TAB>desc rows, skipping blank/`#` lines. A row missing the tab is
      # skipped (never in the lane); the census counts the rows actually read.
      def read_census
        rows = {}
        File.foreach(@census_path, encoding: Encoding::UTF_8) do |line|
          line = line.chomp
          next if line.empty? || line.start_with?("#")

          count, desc = line.split("\t", 2)
          rows[desc] = count.to_i if desc && !desc.empty?
        end
        rows
      end

      def header
        r = @census.refused
        c = @census
        [
          "# Aozora gaiji ladder — lane 2 of 4: the IDS (Ideographic Description",
          "# Sequence) map (P39-5). GENERATED — do not edit by hand. Regenerate with:",
          "#   rake gaiji:aozora_ids   (reads config/gaiji/aozora-descriptions.tsv)",
          "#",
          "# desc <TAB> ids-sequence. The desc is the component-formula the aozora-ruby",
          "# parser stores for a class-(c) gaiji sentinel ※［＃…］; it is the lane KEY the",
          "# reading-mode render path derives from the in-text notation. An IDS here is a",
          "# STRUCTURAL claim (⿰AB = A-left/B-right), rendered on the description-honest",
          "# IDS rung — never an identity claim, never a real codepoint.",
          "#",
          "# GRAMMAR (mechanical only, Nabu::Ops::AozoraIdsBuilder): single ＋ between two",
          "# literal CJK ideographs -> ⿰; single ／ -> ⿱. Everything else REFUSED and left",
          "# as the loud sentinel — full policy + refusal classes on the builder.",
          "#",
          "# census: #{@lane.size}, #{@generated_on}, derived IDS lane — from " \
          "#{c.descriptions} composition descriptions",
          "#   (#{c.composition_occurrences} occurrences); derived #{@lane.size} " \
          "(#{c.derived_occurrences} occ, #{occ_pct}% of composition occurrences).",
          "# Refused #{refused_total}: #{r[:kana_component]} kana-component, " \
          "#{r[:replace]} 代えて-replace, #{r[:subtractive]} subtractive,",
          "#   #{r[:parenthesised]} parenthesised, #{r[:multi_operator]} multi-operator, " \
          "#{r[:other]} other (non-Han/malformed).",
          "#"
        ]
      end

      def refused_total = @census.refused.values.sum

      def occ_pct
        (100.0 * @census.derived_occurrences / @census.composition_occurrences).round(1)
      end
    end
  end
end
