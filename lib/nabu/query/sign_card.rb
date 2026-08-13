# frozen_string_literal: true

require_relative "../atf_tokenizer"
require_relative "term_frequency"

module Nabu
  module Query
    # The cuneiform sign desk card (P65-1): `nabu char 𒊬` / `nabu char SAR`
    # / `nabu char szesz` — one sign in (glyph, name, or value spelling),
    # the full held identity out. NO new source: the card re-joins the held
    # OSL (CC0 — names, @aka, values with %lang, the @list print
    # concordances MZL/LAK/ABZL/HZL/ŠL…, variant forms, codepoints) with
    # the CDLI meaning glosses riding in the same repo's 00etc
    # (Nabu::CdliSignReadings) and an optional corpus panel off the
    # fulltext index. The `nabu char` honesty rule binds: an absent shelf
    # (no readings file, no fulltext) yields an absent section, never "—";
    # ambiguous value input lists ALL candidates, never one silently (the
    # `nabu signs` contract).
    #
    # == Input lanes (in order)
    #
    #   glyph   every char in the Cuneiform blocks → SignList#sign_for_glyph
    #   name    C-ATF fold, then name/@aka/form lookup (SZESZ → ŠEŠ)
    #   value   C-ATF fold, then value lookup — 1 candidate = the card,
    #           N = candidates listed, 0 = an honestly empty result; a
    #           trailing ASCII x retries as the ₓ subscript (idx → idₓ —
    #           nobody types subscripts, P65 gate feedback)
    #   list    a @list concordance number, qualified (MZL535) or bare
    #           (535, matched across every held list) — candidates name
    #           the matching token (via)
    class SignCard
      # One sign value on the card. language = the %lang qualifier or nil;
      # deprecated values stay listed (texts using them exist), marked.
      Value = Data.define(:value, :language, :deprecated)
      Gloss = Data.define(:reading, :preferred, :meaning)
      # One Wiktionary sense (P68-2): the wiktionary-sux shelf's entries
      # whose headword IS the sign's rendered glyph.
      Sense = Data.define(:pos, :gloss)
      FormRef = Data.define(:name, :codepoints, :glyph)
      # +via+ is the matched @list token on list-number candidates ("70" →
      # AK via ASY070) and nil on value-lane candidates.
      Candidate = Data.define(:name, :codepoints, :glyph, :form_of, :via) do
        def initialize(via: nil, **) = super
      end

      # The card. lists groups @list concordance numbers by list name
      # ({"MZL" => ["535"], …} — the U+ codepoint lines are identity, not
      # concordance). parent is the owning sign's name when this record is
      # a variant form. corpus maps spelled value → fulltext document
      # frequency ({} when no fulltext handle or nothing attested).
      Card = Data.define(:name, :uname, :oid, :deprecated, :codepoints, :glyph,
                         :aka, :lists, :values, :glosses, :forms, :parent, :corpus, :senses,
                         :didactic) do
        def initialize(senses: [], didactic: nil, **) = super
      end

      # card XOR candidates (both empty = unknown input, said plainly).
      Result = Data.define(:input, :card, :candidates)

      # The Cuneiform blocks: base, Numbers & Punctuation, Early Dynastic.
      CUNEIFORM = /\A[\u{12000}-\u{1254F}]+\z/

      # The sense-join shelf (P68-2): the kaikki Sumerian extraction's
      # dictionary slug.
      WIKTIONARY_SLUG = "wiktionary-sux"

      # +overlay+ (P77-8): the Nabu::EdubbaOverlay read seam, or nil when
      # the module is unsynced — the card degrades to no didactic section
      # (the hiero-card mold).
      def initialize(sign_list:, readings: nil, fulltext: nil, catalog: nil, overlay: nil)
        @list = sign_list
        @readings = readings
        @fulltext = fulltext
        @catalog = catalog
        @overlay = overlay
        @tokenizer = Nabu::AtfTokenizer.new(dialect: :catf)
      end

      def run(input)
        input = Nabu::Normalize.nfc(input.to_s.strip)
        return from_glyph(input) if input.match?(CUNEIFORM)

        folded = @tokenizer.fold_name(input)
        record = @list.sign(folded)
        return Result.new(input: input, card: card(record), candidates: []) if record

        from_value(input, folded)
      end

      # -- the frozen JSON contract (Edubba consumes) ------------------------
      #
      # One object: input, card (null when none), candidates[]. Card keys
      # are always present except the present-only pair on values
      # (language/deprecated) and parent/uname/oid/glyph, which are null
      # when absent. Existing keys never change; additions are new keys.
      def self.json_payload(result)
        {
          "input" => result.input,
          "card" => result.card && card_record(result.card),
          "candidates" => result.candidates.map do |candidate|
            record = { "name" => candidate.name, "codepoints" => candidate.codepoints || [],
                       "glyph" => candidate.glyph, "form_of" => candidate.form_of }
            record["via"] = candidate.via if candidate.via
            record
          end
        }
      end

      def self.card_record(card)
        {
          "name" => card.name, "uname" => card.uname, "oid" => card.oid,
          "deprecated" => card.deprecated, "codepoints" => card.codepoints || [],
          "glyph" => card.glyph, "aka" => card.aka, "lists" => card.lists,
          "values" => card.values.map do |value|
            record = { "value" => value.value }
            record["language"] = value.language if value.language
            record["deprecated"] = true if value.deprecated
            record
          end,
          "glosses" => card.glosses.map do |gloss|
            { "reading" => gloss.reading, "preferred" => gloss.preferred, "meaning" => gloss.meaning }
          end,
          "forms" => card.forms.map do |form|
            { "name" => form.name, "codepoints" => form.codepoints || [], "glyph" => form.glyph }
          end,
          "senses" => card.senses.map { |sense| { "pos" => sense.pos, "gloss" => sense.gloss } },
          "parent" => card.parent, "corpus" => card.corpus
        }
      end

      private

      def from_glyph(input)
        record = @list.sign_for_glyph(input)
        Result.new(input: input, card: record && card(record), candidates: [])
      end

      def from_value(input, folded)
        records = @list.lookup(folded)
        records = @list.lookup(folded.sub(/x\z/, "ₓ")) if records.empty? && folded.end_with?("x")
        if records.empty?
          pairs = @list.signs_for_list_number(input)
          return from_list_pairs(input, pairs) unless pairs.empty?
        end

        case records.size
        when 0 then Result.new(input: input, card: nil, candidates: [])
        when 1 then Result.new(input: input, card: card(records.first), candidates: [])
        else
          candidates = records.map do |record|
            Candidate.new(name: record.name, codepoints: record.codepoints,
                          glyph: glyph(record), form_of: record.parent_name)
          end
          Result.new(input: input, card: nil, candidates: candidates)
        end
      end

      # List-number matches, grouped by sign: one distinct sign = its full
      # card (LAK032 and KWU032 are both ŠEŠ); several = candidates, each
      # naming the token that matched (via).
      def from_list_pairs(input, pairs)
        grouped = pairs.group_by(&:first)
        return Result.new(input: input, card: card(grouped.keys.first), candidates: []) if grouped.size == 1

        candidates = grouped.map do |record, matches|
          Candidate.new(name: record.name, codepoints: record.codepoints, glyph: glyph(record),
                        form_of: record.parent_name, via: matches.map(&:last).join(", "))
        end
        Result.new(input: input, card: nil, candidates: candidates)
      end

      def card(record)
        return nil unless record

        Card.new(
          name: record.name, uname: record.uname, oid: record.oid,
          deprecated: record.deprecated, codepoints: record.codepoints,
          glyph: glyph(record), aka: record.aka, lists: lists(record),
          values: record.values.map { |v| Value.new(value: v.value, language: v.language, deprecated: v.deprecated) },
          glosses: glosses(record), forms: forms(record),
          parent: record.parent_name, corpus: corpus_panel(record),
          senses: senses(record), didactic: didactic_panel(record)
        )
      end

      # The Edubba cuneiform overlay for this sign (P77-8): the pools key
      # by display name AND osl_name, so the card's OSL name always
      # reaches the entry. nil = no overlay module or no entry — an
      # absent section, never a placeholder (the hiero-card mold).
      def didactic_panel(record)
        entry = @overlay&.cuneiform(record.name)
        entry && Nabu::Query::Char.serialize(entry).merge(
          "attribution" => Nabu::EdubbaOverlay::ATTRIBUTION
        )
      end

      # The Wiktionary sense join (P68-2): wiktionary-sux entries whose
      # headword IS this sign's rendered glyph — sense gloss + the pos
      # riding the entry id ("𒋀:noun:1"). No catalog / no shelf → [].
      def senses(record)
        glyph = glyph(record)
        return [] unless glyph && @catalog&.table_exists?(:dictionary_entries)

        @catalog[:dictionary_entries]
          .join(:dictionaries, id: Sequel[:dictionary_entries][:dictionary_id])
          .where(Sequel[:dictionaries][:slug] => WIKTIONARY_SLUG,
                 Sequel[:dictionary_entries][:headword] => glyph,
                 Sequel[:dictionary_entries][:withdrawn] => false)
          .order(Sequel[:dictionary_entries][:entry_id])
          .select_map([Sequel[:dictionary_entries][:entry_id], Sequel[:dictionary_entries][:gloss]])
          .filter_map do |entry_id, gloss|
            Sense.new(pos: entry_id.to_s.split(":")[1], gloss: gloss) if gloss
          end
      end

      # "@list MZL535" → {"MZL" => ["535"]}; the "@list U+122C0" codepoint
      # line is identity, not a concordance — excluded.
      def lists(record)
        record.list_numbers.each_with_object({}) do |token, out|
          next if token.match?(/\AU\+\h+\z/)

          list, number = token.match(/\A([A-Z]+)(.*)\z/)&.captures
          next unless list

          (out[list] ||= []) << number
        end
      end

      def glosses(record)
        return [] unless @readings

        @readings.readings_for(record.name).map do |reading|
          Gloss.new(reading: reading.reading, preferred: reading.preferred, meaning: reading.meaning)
        end
      end

      def forms(record)
        record.forms.map do |form|
          FormRef.new(name: form.name, codepoints: form.codepoints, glyph: glyph(form))
        end
      end

      # The "in the wild" panel: fulltext document frequency per live value,
      # probed via the fts5vocab seam (TermFrequency) under BOTH the OSL
      # spelling and its C-ATF ASCII unfold (corpora differ; a spelling the
      # index's tokenizer would not emit bounds at 0 — fail-open). Zero
      # rows are omitted; no fulltext handle → {} (absent section).
      def corpus_panel(record)
        return {} unless @fulltext

        probe = TermFrequency.new(fulltext: @fulltext)
        record.values.reject(&:deprecated).each_with_object({}) do |value, out|
          spellings = [value.value, ascii_unfold(value.value)].uniq
          count = spellings.sum { |spelling| probe.candidate_ceiling([spelling]) || 0 }
          out[value.value] = count if count.positive?
        end
      end

      # The reverse C-ATF fold for index probing (š→sz, subscripts→digits,
      # ʾ→'; ṣ/ṭ stay — their ASCII spellings ("s,") are not index tokens).
      def ascii_unfold(value)
        value.gsub("š", "sz").gsub("Š", "SZ").tr("ʾₓ", "'x")
             .tr("₀₁₂₃₄₅₆₇₈₉", "0123456789")
      end

      def glyph(record)
        return record.ucun if record.ucun

        codepoints = record.codepoints or return nil
        chars = codepoints.filter_map { |code| code[/\AU\+(\h+)\z/, 1]&.to_i(16)&.chr(Encoding::UTF_8) }
        chars.empty? ? nil : chars.join
      end
    end
  end
end
