# frozen_string_literal: true

module Nabu
  # The uncertainty doctrine core (P76 U-1, №R-6 — survey §4): three house
  # tiers **certain · probable · uncertain** (the Pleiades/LPF lineage),
  # mapped from each carrier's own vocabulary at RENDER TIME only — never a
  # storage substitution. The axioms every consumer composes:
  #
  # - **Absence is not a tier**: undated/unplaced/unstaged stay honest
  #   absences; an unknown upstream word maps to nil, never guessed.
  # - **Precision is not certainty**: width words (exact/range/year/period)
  #   carry NO tier — only genuine doubt words do.
  # - **Certain is silent; deviation is labeled; the upstream word rides
  #   verbatim** beside the house word in every gloss and payload.
  #
  # Surfaces: cards call #gloss (one parenthetical after the affected
  # value, nil = no ink); MCP payloads call #payload (a `certainty` object
  # merged only below certain — the credit_field empty-hash idiom, so
  # existing payloads stay byte-identical); specialized renders ("ca." on
  # a band span, "(script uncertain)" on the artifact line) read #tier and
  # keep their own surface idiom.
  module Certainty
    TIERS = %w[certain probable uncertain].freeze

    # Width vocabulary of the timeline precision column — the not_before/
    # not_after interval already expresses width; these words carry no doubt.
    PRECISION_WIDTH_WORDS = %w[exact range year period regnal-year regnal-reign].freeze

    # The survey §4.2 mapping, one lambda per carrier: upstream word →
    # house tier, nil = no tier (width, or an unmapped word — honest).
    # CIGS accuracy joins in U-4 once the grade semantics are confirmed
    # against CDLJ 2021-1 (the survey's flagged [claimed]).
    CARRIERS = {
      places_certainty: ->(word) { { "high" => "certain", "low" => "probable" }[word] },
      cataloguer_query: ->(word) { "probable" if word == "?" },
      hgv_precision: ->(word) { "uncertain" unless PRECISION_WIDTH_WORDS.include?(word) },
      band_note: ->(word) { "probable" if word.to_s.match?(/approximate|conventional/i) },
      lect_tier: ->(word) { { "certain" => "certain", "approximation" => "probable" }[word] },
      lect_fold: ->(_word) { "probable" },
      script_uncertain: ->(word) { "uncertain" if word == "uncertain" },
      kaikki_tag: ->(word) { "uncertain" if word == "uncertain" },
      pleiades_association: lambda { |word|
        { "certain" => "certain", "less-certain" => "probable", "uncertain" => "uncertain" }[word]
      }
    }.freeze

    # How each carrier names itself in a gloss — the upstream word verbatim,
    # in the carrier's own idiom.
    LABELS = {
      places_certainty: ->(word) { %(registry "#{word}") },
      cataloguer_query: ->(_word) { %(cataloguer's "?") },
      hgv_precision: ->(word) { %(hgv "#{word}") },
      band_note: ->(word) { String(word) },
      lect_tier: ->(word) { String(word) },
      lect_fold: ->(word) { %(#{word} → und fold) },
      script_uncertain: ->(_word) { "script_uncertain" },
      kaikki_tag: ->(word) { %(kaikki "#{word}") },
      pleiades_association: ->(word) { %(pleiades "#{word}") }
    }.freeze

    module_function

    # The house tier for (+carrier+, +upstream+): "certain"/"probable"/
    # "uncertain", or nil (no tier — width words, unmapped words). An
    # unknown carrier is a programming error, loudly.
    def tier(carrier, upstream)
      mapper = CARRIERS[carrier] or
        raise ArgumentError, "unknown certainty carrier #{carrier.inspect} " \
                             "(known: #{CARRIERS.keys.join(', ')})"
      mapper.call(upstream)
    end

    # The card parenthetical: "<tier> — <carrier's label>", nil when
    # certain or tier-less (no ink — the render axiom). +detail:+ prefixes
    # caller context ("rule akk-period") before the upstream word.
    def gloss(carrier, upstream, detail: nil)
      house = tier(carrier, upstream)
      return nil if house.nil? || house == "certain"

      label = LABELS.fetch(carrier).call(upstream)
      label = "#{detail}, #{label}" if detail
      "#{house} — #{label}"
    end

    # The MCP shape: {} at certain/tier-less (merged payloads stay
    # byte-identical — the empty-hash idiom), else one structured object,
    # upstream verbatim.
    def payload(carrier, upstream)
      house = tier(carrier, upstream)
      return {} if house.nil? || house == "certain"

      { certainty: { tier: house, upstream: upstream.to_s, carrier: carrier.to_s.tr("_", "-") } }
    end
  end
end
