# frozen_string_literal: true

require_relative "../normalize"
require_relative "../romaji"
require_relative "../jpn"
require_relative "../kangxi_radicals"
require_relative "../adapters/ids_txt_parser"
require_relative "define"

module Nabu
  module Query
    # The character card (P37-4): `nabu char 棄` — the join no single upstream
    # offers. One Han character's held shelves composed into a structure +
    # reading + diachronic card, matching Jisho's SYNCHRONIC completeness
    # field-for-field where a shelf backs it and EXCEEDING it diachronically
    # (the Old Chinese / Middle Chinese / early-Japan / TLS column). The
    # binding honesty rule (survey): a field whose shelf can't back this
    # character is ABSENT, never rendered "—".
    #
    # Every section reads the same `headword_folded` join `nabu define` runs
    # (reused verbatim), then partitions the rows by dictionary slug and peels
    # each shelf's free-text `body` to its structured pieces. The new
    # decomposition sources (babelstone-ids, kradfile) plus the held
    # unihan/kanjidic2/baxter-sagart/tshet-uinh/hdic/tls shelves and a corpus
    # attestation count over the passages table make the card; a shelf the
    # catalog does not hold simply yields an empty section.
    class Char
      # KangXi radical of a codepoint: number + its glyph + English name.
      Radical = Data.define(:number, :glyph, :name)
      # One IDS decomposition: the description sequence, its region sources
      # (the "(GHTP)" tag) and the direct component glyphs.
      Ids = Data.define(:sequence, :sources, :components)
      # One character-variant edge (trad/simp/semantic/z-variant…).
      Variant = Data.define(:relation, :glyph, :codepoint)
      # A held-shelf entry surfaced with its slug/title/gloss/body lines and
      # its resolved attestation count (dictionary_citations — TLS).
      ShelfEntry = Data.define(:slug, :title, :urn, :gloss, :lines, :attestations)

      # The whole card. Any section may be nil/empty — the renderer omits it
      # (never a placeholder). `radical`/`total_strokes`/readings/variants ride
      # Unihan; `ids` BabelStone; `components` KRADFILE; the diachronic buckets
      # their named shelves; `corpus` the passages table.
      Card = Data.define(
        :glyph, :codepoint, :radical, :total_strokes,
        :ids, :components, :variants,
        :readings_ja, :readings_sinoxenic, :pedagogy, :desk_reference,
        :old_chinese, :middle_chinese, :early_japan, :tls, :corpus, :held_shelves
      )

      # const: the five HDIC databases as their own diachronic buckets — a
      # fixed shelf-slug list (the P32-4 census), not a corpus count.
      HDIC_SLUGS = %w[yyp ktb tsj syp krm].freeze

      # The sinoxenic reading strata Unihan carries (Jisho shows Mandarin +
      # kun'yomi; nabu adds Korean/Vietnamese and the historical kJapanese
      # unified layer). Only present strata appear.
      SINOXENIC = {
        "kMandarin" => "Mandarin", "kCantonese" => "Cantonese",
        "kKorean" => "Korean", "kVietnamese" => "Vietnamese",
        "kJapanese" => "Japanese (Unihan)"
      }.freeze

      VARIANT_RELATIONS = {
        "kTraditionalVariant" => "traditional", "kSimplifiedVariant" => "simplified",
        "kSemanticVariant" => "semantic", "kSpecializedSemanticVariant" => "specialized-semantic",
        "kZVariant" => "z-variant", "kSpoofingVariant" => "spoofing"
      }.freeze

      def initialize(catalog:, fulltext: nil)
        @catalog = catalog
        @define = Define.new(catalog: catalog, fulltext: fulltext)
      end

      def shelf? = @catalog.table_exists?(:dictionary_entries)

      # -- the reading→character reverse lane (P65 gate: `nabu char wen`) ----

      # One reading hit: the character, the reading AS THE SHELF SPELLS IT
      # (tone marks, okurigana dots), and which layer answered
      # ("pinyin" | "on" | "kun").
      ReadingMatch = Data.define(:glyph, :reading, :kind)

      # Latin input (toned or toneless pinyin, optional tone digit) and kana
      # input — the two reading shapes the lane accepts.
      PINYIN_INPUT = /\A\p{Latin}+[1-5]?\z/
      KANA_INPUT = /\A[\p{Hiragana}\p{Katakana}ー]+\z/

      # A reading → every Han character carrying it: pinyin against unihan
      # kMandarin (toned input matches exactly; toneless/tone-digit input
      # matches with tones folded), kana against kanjidic2 on/kun (katakana
      # and hiragana fold together; kun okurigana dots and the -affix marks
      # are notation — ひと reaches both 人 ひと and 一 ひと.つ). Romaji
      # works without a kana keyboard, on the dictionary-caps convention
      # (P65 gate): ALL-CAPS input is an on'yomi (TAI → タイ), lowercase
      # romaji answers as kun'yomi AND pinyin together (each hit labeled).
      # Sorted by codepoint; [] when no shelf or no match.
      def characters_for_reading(input)
        return [] unless shelf?

        input = Nabu::Normalize.nfc(input.to_s.strip)
        return kana_matches(input, on: true, kun: true) if input.match?(KANA_INPUT)
        return [] unless input.match?(PINYIN_INPUT)

        if input.match?(/[A-Z]/) && input == input.upcase
          kana = Nabu::Romaji.to_hiragana(input)
          kana ? kana_matches(kana, on: true, kun: false) : []
        else
          kana = input == input.downcase ? Nabu::Romaji.to_hiragana(input) : nil
          kun = kana ? kana_matches(kana, on: false, kun: true) : []
          (pinyin_matches(input) + kun).sort_by { |match| match.glyph.each_char.first.ord }
        end
      end

      # Build the Card for one single Han character, or nil when the shelf is
      # absent. The caller has already validated single-character grain.
      def run(glyph)
        return nil unless shelf?

        glyph = Nabu::Normalize.nfc(glyph.to_s)
        results = @define.run(glyph, limit: nil)
        by_slug = results.group_by(&:dictionary_slug)
        unihan = by_slug["unihan"]&.first

        Card.new(
          glyph: glyph, codepoint: codepoint(glyph),
          radical: radical(unihan), total_strokes: total_strokes(unihan),
          ids: ids_of(by_slug["babelstone-ids"]&.first),
          components: components_of(by_slug["kradfile"]&.first),
          variants: variants_of(unihan) + jpn_reform_variants(glyph),
          readings_ja: ja_readings(by_slug["kanjidic2"]&.first),
          readings_sinoxenic: sinoxenic_readings(unihan),
          pedagogy: pedagogy(by_slug["kanjidic2"]&.first),
          desk_reference: desk_reference(glyph, by_slug["kanjidic2"]&.first),
          old_chinese: shelf_entries(by_slug, %w[baxter-sagart-oc]),
          middle_chinese: shelf_entries(by_slug, %w[baxter-sagart-mc guangyun]),
          early_japan: shelf_entries(by_slug, HDIC_SLUGS),
          tls: shelf_entries(by_slug, %w[tls-words tls-concepts]),
          corpus: corpus_attestation(glyph),
          held_shelves: by_slug.keys.sort
        )
      end

      private

      # unihan kMandarin values ("wén", space-separated when several) vs the
      # input: toned input (any non-ASCII Latin) matches exactly; toneless
      # or tone-digit input matches with the tones folded away.
      def pinyin_matches(input)
        toned = input.match?(/[^\x00-\x7F]/)
        target = fold_pinyin(input)
        matches = dictionary_rows("unihan", "%kMandarin: %").flat_map do |headword, body|
          line = body[/^kMandarin: (.+)$/, 1] or next []
          line.split(/\s+/).filter_map do |value|
            hit = toned ? value == input : fold_pinyin(value) == target
            ReadingMatch.new(glyph: headword, reading: value, kind: "pinyin") if hit
          end
        end
        matches.uniq.sort_by { |match| match.glyph.each_char.first.ord }
      end

      def fold_pinyin(value)
        value.unicode_normalize(:nfd).gsub(/\p{Mn}/, "").downcase.sub(/[1-5]\z/, "")
      end

      # kanjidic2 on (katakana) / kun (hiragana, okurigana dots and -affix
      # marks as notation; the pre-dot stem answers too) vs kana input,
      # katakana and hiragana folded together. The on/kun flags carry the
      # romaji caps convention (CAPS asks on only, lowercase kun only).
      def kana_matches(input, on:, kun:)
        target = to_hiragana(input)
        matches = dictionary_rows("kanjidic2", nil).flat_map do |headword, body|
          on_hits = if on
                      body_list(body, "on").filter_map do |reading|
                        ReadingMatch.new(glyph: headword, reading: reading, kind: "on") if
                          to_hiragana(reading) == target
                      end
                    else
                      []
                    end
          kun_hits = if kun
                       body_list(body, "kun").filter_map do |reading|
                         base = reading.delete("-")
                         ReadingMatch.new(glyph: headword, reading: reading, kind: "kun") if
                           [base.delete("."), base.split(".").first].map do |form|
                             to_hiragana(form)
                           end.include?(target)
                       end
                     else
                       []
                     end
          on_hits + kun_hits
        end
        matches.uniq.sort_by { |match| match.glyph.each_char.first.ord }
      end

      def to_hiragana(text) = text.tr("ァ-ヶ", "ぁ-ゖ")

      def body_list(body, label)
        line = body.lines.map(&:chomp).find { |l| l.start_with?("#{label}: ") }
        line ? line.delete_prefix("#{label}: ").split("、") : []
      end

      # [headword, body] rows of one dictionary shelf (an optional SQL LIKE
      # prefilter narrows the scan).
      def dictionary_rows(slug, like)
        rows = @catalog[:dictionary_entries]
               .join(:dictionaries, id: Sequel[:dictionary_entries][:dictionary_id])
               .where(Sequel[:dictionaries][:slug] => slug)
               .where(Sequel[:dictionary_entries][:withdrawn] => false)
        rows = rows.where(Sequel.like(Sequel[:dictionary_entries][:body], like)) if like
        rows.select_map([Sequel[:dictionary_entries][:headword], Sequel[:dictionary_entries][:body]])
      end

      def codepoint(glyph) = format("U+%04X", glyph.each_char.first.ord)

      # -- Unihan-backed sections -------------------------------------------------

      # kRSUnicode "75.8" (or "75.8 76.4" for polyradical chars — first wins,
      # the primary KangXi classification) → radical 75 = 木 tree.
      def radical(unihan)
        value = body_field(unihan, "kRSUnicode") or return nil
        number = value.split(/\s+/).first.to_s.split(".").first
        glyph, name = Nabu::KangxiRadicals.lookup(number) || return
        Radical.new(number: number.to_i, glyph: glyph, name: name)
      end

      def total_strokes(unihan)
        value = body_field(unihan, "kTotalStrokes") or return nil
        value.split(/\s+/).first.to_i
      end

      def sinoxenic_readings(unihan)
        SINOXENIC.filter_map do |field, label|
          value = body_field(unihan, field)
          [label, value] if value
        end
      end

      def variants_of(unihan)
        VARIANT_RELATIONS.flat_map do |field, relation|
          value = body_field(unihan, field) or next []
          value.split(/\s+/).filter_map do |token|
            code = token[/\AU\+\h{4,6}/] or next
            Variant.new(relation: relation, glyph: codepoint_to_glyph(code), codepoint: code)
          end
        end
      end

      # The Japanese kyūjitai↔shinjitai reform cross-reference (P38-4): a
      # shinjitai names its old form, a kyūjitai its new form — the hani-fold
      # display precedent, from the held-Unihan-derived Nabu::Jpn table (not a
      # dictionary shelf, so surfaced here even when no CJK shelf backs the
      # card). Empty for characters that are not one of the 173 reform pairs.
      def jpn_reform_variants(glyph)
        [["kyūjitai (Japanese old form)", Nabu::Jpn.old_form(glyph)],
         ["shinjitai (Japanese new form)", Nabu::Jpn.new_form(glyph)]].filter_map do |relation, other|
          next unless other

          Variant.new(relation: relation, glyph: other, codepoint: format("U+%04X", other.ord))
        end
      end

      # -- BabelStone IDS + KRADFILE ----------------------------------------------

      def ids_of(entry)
        return [] unless entry

        entry.body.lines.map(&:chomp).reject(&:empty?).map do |field|
          Ids.new(
            sequence: Nabu::Adapters::IdsTxtParser.sequence(field),
            sources: field[/\(([^)]*)\)\s*\z/, 1],
            components: Nabu::Adapters::IdsTxtParser.components(field)
          )
        end
      end

      def components_of(entry)
        return [] unless entry

        line = entry.body.lines.map(&:chomp).find { |l| l.start_with?("components:") }
        line ? line.delete_prefix("components:").strip.split(/\s+/) : []
      end

      # -- kanjidic2 (ja readings, pedagogy, desk reference) ----------------------

      def ja_readings(entry)
        return nil unless entry

        readings = {
          on: kd_list(entry, "on"), kun: kd_list(entry, "kun"),
          nanori: kd_list(entry, "nanori"), meanings: kd_list(entry, "meaning")
        }
        readings.any? { |_, v| v.any? } ? readings : nil
      end

      def pedagogy(entry)
        misc = kd_misc(entry) or return nil
        pedagogy = misc.slice("grade", "jlpt", "freq")
        pedagogy.empty? ? nil : pedagogy
      end

      # Desk reference: the Unicode codepoint always (computed), plus every
      # kanjidic2 desk code the shelf carries (four-corner/SKIP/JIS/dic
      # numbers — zero suppressed; absent until the edrdg query-code
      # expansion populates them, then they ride here).
      def desk_reference(glyph, entry)
        block = { "Unicode" => codepoint(glyph) }
        if entry
          %w[four_corner skip jis208 jis212 jis213 kuten].each do |field|
            value = body_field(entry, field)
            block[field] = value if value
          end
          dic = kd_list(entry, "dic")
          block["dic"] = dic.join(", ") unless dic.empty?
        end
        block
      end

      def kd_list(entry, label)
        line = entry.body.lines.map(&:chomp).find { |l| l.start_with?("#{label}: ") }
        line ? line.delete_prefix("#{label}: ").split("、") : []
      end

      # The kanjidic2 misc line: "grade 8 · stroke_count 7 · freq 1509 · jlpt 1"
      # → { "grade" => "8", ... } (space-separated key value, · joined).
      def kd_misc(entry)
        return nil unless entry

        line = entry.body.lines.map(&:chomp).find { |l| l.match?(/\A(grade|stroke_count|freq|jlpt) /) }
        return nil unless line

        line.split(" · ").to_h { |token| token.split(" ", 2) }
      end

      # -- diachronic + corpus ----------------------------------------------------

      def shelf_entries(by_slug, slugs)
        slugs.flat_map { |slug| by_slug[slug] || [] }.map do |result|
          ShelfEntry.new(
            slug: result.dictionary_slug, title: result.dictionary_title, urn: result.urn,
            gloss: result.gloss, lines: result.body.to_s.lines.map(&:chomp).reject(&:empty?),
            attestations: result.citations.size
          )
        end
      end

      # Corpus attestation: passages carrying the glyph, per passage language.
      # A containment scan (Han text is not word-tokenized) restricted to live
      # passages — the honest count at research scale (a char-posting index is
      # future work). Absent when the catalog holds no passages table.
      def corpus_attestation(glyph)
        return {} unless @catalog.table_exists?(:passages)

        @catalog[:passages]
          .where(withdrawn: false)
          .where(Sequel.like(:text, "%#{glyph.gsub(/[%_\\]/) { |c| "\\#{c}" }}%", escape: "\\"))
          .group_and_count(:language)
          .to_h { |row| [row.fetch(:language), row.fetch(:count)] }
      end

      # -- body helpers -----------------------------------------------------------

      # The value of a "field: value" line in an entry body (multi-value lines
      # keep their upstream separator). nil when the field or entry is absent.
      def body_field(entry, field)
        return nil unless entry

        line = entry.body.lines.map(&:chomp).find { |l| l.start_with?("#{field}: ") } or return nil
        value = line.delete_prefix("#{field}: ").strip
        value.empty? ? nil : value
      end

      def codepoint_to_glyph(code)
        hex = code[/\AU\+(\h{4,6})/, 1] or return code
        Nabu::Normalize.nfc([hex.to_i(16)].pack("U"))
      end
    end
  end
end
