# frozen_string_literal: true

require_relative "../normalize"

module Nabu
  module Query
    # The Egyptian sign desk card (P65-2): `nabu char 𓅃` / `nabu char G5`
    # — one hieroglyph in (glyph or Gardiner-style code), the Unikemet
    # identity out: catalog code, description, function, phonetic value,
    # the JSesh/Hieroglyphica/IFAO concordances, core-vs-legacy — plus an
    # "in the wild" panel counting the sign's Gardiner code across the held
    # aes corpus's hiero_inventar token annotations. The `nabu char`
    # honesty rule binds: absent upstream fields are absent sections; no
    # catalog handle → no panel, never "—".
    class HieroCard
      # The card is the seam's Sign record plus the corpus panel
      # ({"passages" => n, "signs" => m}, {} when unprobed/empty).
      Card = Data.define(:glyph, :codepoint, :cat, :unik, :core, :desc, :func,
                         :fval, :jsesh, :hg, :ifao, :alt_seq, :corpus, :didactic)
      Result = Data.define(:input, :card)

      # Gardiner-style code shape (kEH_JSesh: A1, G43, Aa27D, P8h, O29v…).
      CODE = /\A[A-Z][A-Za-z]?\d{1,3}[A-Za-z]{0,2}\z/

      # census: P96 assumption audit (Q68, generalized P97-4) — each
      # hiero-annotated shelf carries its OWN annotation key and counting
      # shape; a new shelf adds a row here. The scan stays scoped to these
      # sources' documents so a desk card never walks the whole passages
      # table (8M+ rows; the unscoped LIKE scan measured in MINUTES).
      #   aes    — "hiero_inventar": semicolon-joined Gardiner codes
      #            (measured 2026-08-09).
      #   tla-hf — "hieroglyphs": rendered glyph runs with inline
      #            <g>CODE</g> escapes for signs without codepoints
      #            (3,606 annotated passages measured at the P96 audit).
      HIERO_SOURCES = { "aes" => :inventar, "tla-hf" => :glyph_run }.freeze

      # +overlay+ (P72-6): the Nabu::EdubbaOverlay read seam, or nil when
      # the module is unsynced — the card degrades to no didactic section.
      def initialize(hieroglyphs:, catalog: nil, overlay: nil)
        @signs = hieroglyphs
        @catalog = catalog
        @overlay = overlay
      end

      def run(input)
        input = Nabu::Normalize.nfc(input.to_s.strip)
        sign = input.match?(CODE) ? @signs.sign_for_code(input) : @signs.sign_for_glyph(input)
        Result.new(input: input, card: sign && card(sign))
      end

      # The frozen JSON contract (the SignCard shape): input + card (null
      # when none); absent card fields are null. Existing keys never
      # change; additions are new keys.
      def self.json_payload(result)
        {
          "input" => result.input,
          "card" => result.card&.to_h&.transform_keys(&:to_s)
        }
      end

      private

      def card(sign)
        Card.new(
          glyph: sign.glyph, codepoint: sign.codepoint, cat: sign.cat,
          unik: sign.unik, core: sign.core, desc: sign.desc, func: sign.func,
          fval: sign.fval, jsesh: sign.jsesh, hg: sign.hg, ifao: sign.ifao,
          alt_seq: sign.alt_seq, corpus: corpus_panel(sign),
          didactic: didactic_panel(sign)
        )
      end

      # The Edubba overlay for the sign's Gardiner code (P72-6): the
      # contract's stable fields as a plain hash (rides the JSON contract
      # additively). JOIN KEY correction (relayed to Edubba): their
      # `gardiner` matches our card's JSESH field (G43) — our `cat` is
      # the Gardiner-PLUS kEH_Cat shape (G-12-002). hg is the fallback.
      # nil = no overlay module or no entry — an absent section, never a
      # placeholder.
      def didactic_panel(sign)
        return nil unless @overlay

        entry = (sign.jsesh && @overlay[sign.jsesh]) || (sign.hg && @overlay[sign.hg])
        entry && Nabu::Query::Char.serialize(entry).merge("attribution" => Nabu::EdubbaOverlay::ATTRIBUTION)
      end

      # Passage + token counts of the sign over every held hiero-annotated
      # shelf, each counted by its own shape (HIERO_SOURCES): aes's
      # semicolon-bounded Gardiner codes (N35 must never count N35A) and
      # tla-hf's glyph runs (the rendered codepoint plus the <g>CODE</g>
      # no-codepoint escape). SQL LIKE prefilters each scoped scan.
      # No catalog / no passages table / no code → {}.
      def corpus_panel(sign)
        code = sign.jsesh
        return {} unless code && @catalog&.table_exists?(:passages)

        passages = 0
        tokens = 0
        HIERO_SOURCES.each do |slug, shape|
          count_source(slug, shape, sign) do |passage_tokens|
            passages += 1
            tokens += passage_tokens
          end
        end
        passages.zero? ? {} : { "passages" => passages, "signs" => tokens }
      end

      def count_source(slug, shape, sign)
        code = sign.jsesh
        key = shape == :inventar ? "hiero_inventar" : "hieroglyphs"
        # The tla-hf prefilter must OR both spellings: a sign upstream
        # lacked a codepoint for is written ONLY as its <g>CODE</g>
        # escape, never as the glyph Unikemet later assigned.
        needles = shape == :inventar ? [code] : [sign.glyph, "<g>#{code}</g>"].compact
        spellings = needles.map do |needle|
          escaped = needle.gsub(/[%_\\]/) { |c| "\\#{c}" }
          Sequel.like(:annotations_json, "%#{escaped}%", escape: "\\")
        end
        source_ids = @catalog[:sources].where(slug: slug).select(:id)
        document_ids = @catalog[:documents].where(source_id: source_ids).select(:id)
        @catalog[:passages]
          .where(withdrawn: false, document_id: document_ids)
          .where(Sequel.like(:annotations_json, "%#{key}%", escape: "\\"))
          .where(Sequel.|(*spellings))
          .select_map(:annotations_json).each do |json|
          count = count_in(json.to_s, shape, sign)
          yield count unless count.zero?
        end
      end

      # One passage's token count under the source's shape.
      def count_in(json, shape, sign)
        code = sign.jsesh
        if shape == :inventar
          json.scan(/"hiero_inventar":\s*"([^"]*)"/)
              .sum { |(value)| value.split(";").count(code) }
        else
          json.scan(/"hieroglyphs":\s*"((?:[^"\\]|\\.)*)"/).sum do |(value)|
            run = value.gsub(/\\u([0-9a-fA-F]{4})/) { [Regexp.last_match(1).hex].pack("U") }
            glyphs = sign.glyph ? run.scan(sign.glyph).size : 0
            glyphs + run.scan("<g>#{code}</g>").size
          end
        end
      end
    end
  end
end
