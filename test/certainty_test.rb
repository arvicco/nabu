# frozen_string_literal: true

require "test_helper"

# Nabu::Certainty (P76 U-1, the №R-6 doctrine core): the three house tiers
# and the survey §4.2 carrier mapping, applied at RENDER TIME only.
# Axioms pinned here: certain is SILENT (nil gloss); precision is width,
# not doubt (no tier); absence stays absence (unknown upstream words map
# to nil, never guessed); the upstream word rides verbatim in every gloss
# and payload.
class CertaintyTest < Minitest::Test
  # -- the tier mapping (§4.2) ----------------------------------------------

  def test_places_certainty_high_is_certain_low_is_probable
    assert_equal "certain", Nabu::Certainty.tier(:places_certainty, "high")
    assert_equal "probable", Nabu::Certainty.tier(:places_certainty, "low")
    assert_nil Nabu::Certainty.tier(:places_certainty, "dubious"),
               "an unknown upstream word maps to NO tier — honest, never guessed"
  end

  def test_the_cataloguer_query_family_is_probable
    assert_equal "probable", Nabu::Certainty.tier(:cataloguer_query, "?")
  end

  def test_precision_width_words_carry_no_tier_but_low_is_uncertain
    %w[exact range year period].each do |width|
      assert_nil Nabu::Certainty.tier(:hgv_precision, width),
                 "#{width} is a width word — precision is not certainty"
    end
    assert_equal "uncertain", Nabu::Certainty.tier(:hgv_precision, "low")
  end

  def test_band_notes_with_approximation_language_are_probable
    assert_equal "probable", Nabu::Certainty.tier(:band_note, "approximate span")
    assert_equal "probable", Nabu::Certainty.tier(:band_note, "Conventional dating (middle chronology)")
    assert_nil Nabu::Certainty.tier(:band_note, "attested regnal span")
  end

  def test_lect_tiers_map_certain_and_approximation
    assert_equal "certain", Nabu::Certainty.tier(:lect_tier, "certain")
    assert_equal "probable", Nabu::Certainty.tier(:lect_tier, "approximation")
  end

  def test_script_uncertain_and_kaikki_uncertain_are_uncertain
    assert_equal "uncertain", Nabu::Certainty.tier(:script_uncertain, "uncertain")
    assert_equal "uncertain", Nabu::Certainty.tier(:kaikki_tag, "uncertain")
    assert_nil Nabu::Certainty.tier(:kaikki_tag, "borrowed"), "only the uncertain tag maps"
  end

  def test_pleiades_association_maps_one_to_one
    assert_equal "certain", Nabu::Certainty.tier(:pleiades_association, "certain")
    assert_equal "probable", Nabu::Certainty.tier(:pleiades_association, "less-certain")
    assert_equal "uncertain", Nabu::Certainty.tier(:pleiades_association, "uncertain")
  end

  def test_an_unknown_carrier_is_a_programming_error
    assert_raises(ArgumentError) { Nabu::Certainty.tier(:no_such_carrier, "x") }
  end

  # -- the card gloss (§4.3: house word — upstream verbatim) ----------------

  def test_certain_is_silent
    assert_nil Nabu::Certainty.gloss(:places_certainty, "high")
    assert_nil Nabu::Certainty.gloss(:lect_tier, "certain")
  end

  def test_width_words_gloss_nothing
    assert_nil Nabu::Certainty.gloss(:hgv_precision, "range")
  end

  def test_the_gloss_carries_the_house_word_and_the_upstream_verbatim
    assert_equal "uncertain — hgv \"low\"", Nabu::Certainty.gloss(:hgv_precision, "low")
    assert_equal "probable — cataloguer's \"?\"", Nabu::Certainty.gloss(:cataloguer_query, "?")
    assert_equal "probable — registry \"low\"", Nabu::Certainty.gloss(:places_certainty, "low")
    assert_equal "uncertain — kaikki \"uncertain\"", Nabu::Certainty.gloss(:kaikki_tag, "uncertain")
  end

  def test_the_gloss_takes_a_detail_prefix
    assert_equal "probable — rule akk-period, approximation",
                 Nabu::Certainty.gloss(:lect_tier, "approximation", detail: "rule akk-period")
  end

  # -- the MCP payload shape (§4.3: merged only below certain) --------------

  def test_payload_is_empty_at_certain_and_structured_below
    assert_empty Nabu::Certainty.payload(:places_certainty, "high")
    assert_empty Nabu::Certainty.payload(:hgv_precision, "range"), "width words merge nothing"
    assert_equal({ certainty: { tier: "uncertain", upstream: "low", carrier: "hgv-precision" } },
                 Nabu::Certainty.payload(:hgv_precision, "low"))
    assert_equal({ certainty: { tier: "probable", upstream: "?", carrier: "cataloguer-query" } },
                 Nabu::Certainty.payload(:cataloguer_query, "?"))
  end
end
