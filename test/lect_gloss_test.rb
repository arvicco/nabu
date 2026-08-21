# frozen_string_literal: true

require "test_helper"

# Nabu::LectGloss (P81 U-5) — the render-side join from a materialized lect
# facet's provenance basis (the facet row's raw column) to the ruling's
# STATED tier word, glossed through Certainty's :lect_tier carrier. The
# render axiom composes: certain is silent, deviation is labeled with the
# tier word verbatim, and a basis nobody tiered glosses nothing — absence
# is not a tier.
class LectGlossTest < Minitest::Test
  def rules
    @rules ||= Nabu::LectRules.new(rules: [
                                     Nabu::LectRules::Rule.new(id: "sef", sources: ["sefaria"], code: "arc",
                                                               facet: "subshelf", map: {},
                                                               tier: "approximation"),
                                     Nabu::LectRules::Rule.new(id: "akk-period", sources: ["cdli"],
                                                               code: "akk", facet: "period", map: {},
                                                               tier: "certain")
                                   ])
  end

  def override_tiers
    { "etcsl" => { "sux" => "approximation" }, "dss" => { "arc" => "certain" } }
  end

  def test_an_approximation_rule_glosses_probable_with_the_rule_named
    assert_equal "probable — rule sef, approximation",
                 Nabu::LectGloss.gloss("rule:sef", rules: rules)
  end

  def test_a_certain_rule_and_an_owner_ruling_are_silent
    assert_nil Nabu::LectGloss.gloss("rule:akk-period", rules: rules)
    assert_nil Nabu::LectGloss.gloss("owner"), "an owner ruling is certain — no ink"
  end

  def test_untiered_bases_gloss_nothing
    assert_nil Nabu::LectGloss.gloss("codemap", rules: rules)
    assert_nil Nabu::LectGloss.gloss("overlay", rules: rules)
    assert_nil Nabu::LectGloss.gloss("rule:date-band", rules: rules),
               "the date-band inference names no rule in the file — honestly untiered"
    assert_nil Nabu::LectGloss.gloss(nil, rules: rules)
    assert_nil Nabu::LectGloss.gloss("rule:sef"), "no rules file loaded — no tier claim"
  end

  def test_an_override_basis_reads_the_promoted_tier_field_by_source_and_code
    assert_equal "probable — override etcsl, approximation",
                 Nabu::LectGloss.gloss("override:etcsl", code: "sux", override_tiers: override_tiers)
    assert_nil Nabu::LectGloss.gloss("override:dss", code: "arc", override_tiers: override_tiers),
               "a certain override row is silent"
    assert_nil Nabu::LectGloss.gloss("override:etcsl", code: "eng", override_tiers: override_tiers),
               "a code the override never tiered glosses nothing"
  end

  def test_the_payload_shape_merges_only_below_certain
    assert_equal({ lect_certainty: { tier: "probable", upstream: "approximation",
                                     carrier: "lect-tier" } },
                 Nabu::LectGloss.payload("rule:sef", rules: rules))
    assert_empty Nabu::LectGloss.payload("rule:akk-period", rules: rules)
    assert_empty Nabu::LectGloss.payload("owner")
    assert_empty Nabu::LectGloss.payload("codemap")
  end
end
