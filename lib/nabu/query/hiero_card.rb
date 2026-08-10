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
                         :fval, :jsesh, :hg, :ifao, :alt_seq, :corpus)
      Result = Data.define(:input, :card)

      # Gardiner-style code shape (kEH_JSesh: A1, G43, Aa27D, P8h, O29v…).
      CODE = /\A[A-Z][A-Za-z]?\d{1,3}[A-Za-z]{0,2}\z/

      # census: aes, 2026-08-09 — the one held source whose token
      # annotations carry Gardiner codes (hiero_inventar); a new
      # hiero-annotated shelf joins this list. The scan is scoped to these
      # sources' documents so a desk card never walks the whole passages
      # table (8M+ rows; the unscoped LIKE scan measured in MINUTES).
      HIERO_SOURCES = %w[aes].freeze

      def initialize(hieroglyphs:, catalog: nil)
        @signs = hieroglyphs
        @catalog = catalog
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
          alt_seq: sign.alt_seq, corpus: corpus_panel(sign)
        )
      end

      # Passage + token counts of the sign's Gardiner code over held
      # hiero_inventar annotations (aes). SQL LIKE prefilters the scoped
      # scan; the count is semicolon-bounded in Ruby — N35 must never
      # count N35A. No catalog / no passages table / no code → {}.
      def corpus_panel(sign)
        code = sign.jsesh
        return {} unless code && @catalog&.table_exists?(:passages)

        passages = 0
        tokens = 0
        escaped = code.gsub(/[%_\\]/) { |c| "\\#{c}" }
        source_ids = @catalog[:sources].where(slug: HIERO_SOURCES).select(:id)
        document_ids = @catalog[:documents].where(source_id: source_ids).select(:id)
        @catalog[:passages]
          .where(withdrawn: false, document_id: document_ids)
          .where(Sequel.like(:annotations_json, "%hiero_inventar%", escape: "\\"))
          .where(Sequel.like(:annotations_json, "%#{escaped}%", escape: "\\"))
          .select_map(:annotations_json).each do |json|
          count = json.to_s.scan(/"hiero_inventar":\s*"([^"]*)"/)
                      .sum { |(value)| value.split(";").count(code) }
          next if count.zero?

          passages += 1
          tokens += count
        end
        passages.zero? ? {} : { "passages" => passages, "signs" => tokens }
      end
    end
  end
end
