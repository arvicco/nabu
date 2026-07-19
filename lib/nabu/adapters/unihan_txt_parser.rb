# frozen_string_literal: true

module Nabu
  module Adapters
    # Parser family "unihan-txt" (P32-4): the Unihan database's plain-text
    # per-field lines (`U+4E00<TAB>kJapaneseOn<TAB>ICHI ITSU`, one line per
    # (codepoint, field) pair, `#` comments) folded into one DictionaryEntry
    # per codepoint. The carried field set is the P32-4 census verdict, not
    # the whole database: of Unihan 17.0's Readings fields the Sinoxenic
    # bridge carries the definition, the Chinese readings incl. the two
    # historical strata (fanqie spellings, Tang-era readings), the three
    # Japanese layers — kJapanese (51,583 codepoints, added in Unicode 15.1,
    # DENSER than the legacy kJapaneseOn 13,177 / kJapaneseKun 11,296 it
    # supersedes, so all three ride) — and the Korean/Vietnamese Sinoxenic
    # readings; plus every Variants field. Censused out (density/scope,
    # counts at 17.0): kCantonese 29,936, kHangul 8,525, kXHC1983 11,072,
    # kSMSZD2003Readings 8,110, kTGHZ2013 8,105, kHanyuPinlu 3,799,
    # kZhuang 2,472 — modern-lect/auxiliary layers the ancient-text shelf
    # does not promise. A codepoint with NO carried field mints nothing.
    class UnihanTxtParser
      # Readings-file fields carried, body order (verified dense at 17.0:
      # kDefinition 23,285 · kMandarin 44,348 · kHanyuPinyin 34,130 ·
      # kFanqie 20,222 · kTang 3,811 · kJapanese 51,583 · kJapaneseOn
      # 13,177 · kJapaneseKun 11,296 · kKorean 9,050 · kVietnamese 8,306).
      READING_FIELDS = %w[
        kDefinition kMandarin kHanyuPinyin kFanqie kTang
        kJapanese kJapaneseOn kJapaneseKun kKorean kVietnamese
      ].freeze

      # Variants-file fields — ALL six (kSimplifiedVariant 6,929 ·
      # kTraditionalVariant 6,475 · kSemanticVariant 3,538 ·
      # kSpecializedSemanticVariant 525 · kSpoofingVariant 349 ·
      # kZVariant 149). Values stay verbatim (`U+8A9E<kMeyerWempe` keeps
      # its source tag) — canonical means canonical.
      VARIANT_FIELDS = %w[
        kTraditionalVariant kSimplifiedVariant kSemanticVariant
        kSpecializedSemanticVariant kZVariant kSpoofingVariant
      ].freeze

      FIELD_ORDER = (READING_FIELDS + VARIANT_FIELDS).freeze

      # One DictionaryEntry per codepoint that carries at least one carried
      # field, sorted by numeric codepoint (the upstream files sort by the
      # ASCII of "U+…", which interleaves plane 2 before the BMP CJK blocks
      # — numeric order is the stable, honest shelf order).
      def entries(readings_path, variants_path: nil, language: "zho")
        fields = Hash.new { |hash, key| hash[key] = {} }
        collect(readings_path, READING_FIELDS, fields)
        collect(variants_path, VARIANT_FIELDS, fields) if variants_path && File.file?(variants_path)
        fields.keys.sort_by { |code| codepoint(code) }
                   .map { |code| entry(code, fields[code], language) }
      end

      private

      def collect(path, carried, fields)
        File.foreach(path, encoding: Encoding::UTF_8) do |line|
          next if line.start_with?("#") || line.strip.empty?

          code, field, value = line.chomp.split("\t", 3)
          next unless carried.include?(field) && value && !value.empty?

          fields[code][field] = value
        end
      end

      def codepoint(code)
        hex = code[/\AU\+(\h{4,6})\z/, 1] or
          raise Nabu::ParseError, "unihan-txt: malformed codepoint key #{code.inspect}"
        hex.to_i(16)
      end

      def entry(code, values, language)
        character = Normalize.nfc([codepoint(code)].pack("U"))
        Nabu::DictionaryEntry.new(
          entry_id: code, key_raw: code, language: language,
          headword: character,
          headword_folded: Normalize.search_form(character, language: language),
          gloss: gloss(values["kDefinition"]),
          body: Normalize.nfc(FIELD_ORDER.filter_map { |field| "#{field}: #{values[field]}" if values[field] }
                                         .join("\n"))
        )
      end

      # Short first gloss, best-effort: the first `;`-separated sense of
      # kDefinition ("one; a, an; alone" → "one"); nil when absent.
      def gloss(definition)
        return nil if definition.nil?

        first = definition.split(";").first.to_s.strip
        first.empty? ? nil : Normalize.nfc(first)
      end
    end
  end
end
