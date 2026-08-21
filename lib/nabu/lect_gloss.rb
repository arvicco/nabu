# frozen_string_literal: true

require_relative "certainty"

module Nabu
  # The render-side join for a materialized lect facet's provenance (P81
  # U-5, closing the design crux found at P76 close): Store::LectFacets
  # records WHERE a resolution came from in the facet row's raw column —
  # the journal row's own basis ("owner", "rule:<id>"), "override:<slug>",
  # "codemap" — and this module maps that basis to the ruling's STATED tier
  # word (the rule's `tier:` in config/lect_facet_rules.yml; the override
  # row's `tier:` in config/lect_overrides.yml) and on through
  # Nabu::Certainty's :lect_tier carrier.
  #
  # The render axiom composes exactly: certain is silent (an owner ruling,
  # a tier-certain rule); a basis nobody tiered — "codemap", the date-band
  # inference (rule:date-band names no rule in the file), a rule id since
  # retired — glosses nothing, because absence is not a tier; and the tier
  # word rides verbatim beside the house word ("probable — rule
  # sefaria-arc-subshelf, approximation").
  module LectGloss
    module_function

    # [tier word, human detail] for +basis+, or nil when no ruling states
    # one. +rules+ is a Nabu::LectRules (or nil — no rules file);
    # +override_tiers+ the {slug => {code => tier}} map
    # (Nabu::Lects.override_tiers); +code+ is the document's stored code,
    # the key override rows are filed under.
    def tier_word(basis, code: nil, rules: nil, override_tiers: nil)
      case basis.to_s
      when "owner"
        ["certain", "owner ruling"]
      when /\Arule:/
        id = basis.to_s.delete_prefix("rule:")
        word = rules&.find(id)&.tier
        word && [word, "rule #{id}"]
      when /\Aoverride:/
        slug = basis.to_s.delete_prefix("override:")
        word = override_tiers&.dig(slug, code.to_s)
        word && [word, "override #{slug}"]
      end
    end

    # The card parenthetical body ("probable — rule akk-period,
    # approximation"), or nil — certain and untiered bases keep the card
    # ink-free (the render axiom; callers fall back to printing the bare
    # basis as provenance).
    def gloss(basis, code: nil, rules: nil, override_tiers: nil)
      word, detail = tier_word(basis, code: code, rules: rules, override_tiers: override_tiers)
      word && Certainty.gloss(:lect_tier, word, detail: detail)
    end

    # The MCP shape: {} at certain/untiered (the empty-hash idiom — merged
    # payloads stay byte-identical), else one structured object under the
    # :lect_certainty key, the tier word verbatim as upstream. The basis
    # itself rides the payload's own lect_basis key, not here.
    def payload(basis, code: nil, rules: nil, override_tiers: nil)
      word, = tier_word(basis, code: code, rules: rules, override_tiers: override_tiers)
      return {} unless word

      body = Certainty.payload(:lect_tier, word)
      body.empty? ? {} : { lect_certainty: body.fetch(:certainty) }
    end
  end
end
