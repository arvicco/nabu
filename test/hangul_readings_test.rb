# frozen_string_literal: true

require "test_helper"

# Nabu::HangulReadings (P86, the owner's "Hangul cards need IPA or
# Romanized reading" request) — the shape guard over the fact table and
# the composition/divergence pins.
class HangulReadingsTest < Minitest::Test
  def test_the_modern_positional_inventory_is_complete
    by_position = Nabu::HangulReadings.table.values.group_by(&:position)
    assert_equal 19, by_position.fetch("choseong").size
    assert_equal 21, by_position.fetch("jungseong").size
    assert_equal 27, by_position.fetch("jongseong").size
  end

  def test_cluster_finals_carry_no_ipa_and_historical_letters_no_rr
    clusters = %w[11AA 11AC 11AD 11B0 11B1 11B2 11B3 11B4 11B5 11B6 11B9].map { |h| Integer(h, 16) }
    clusters.each do |codepoint|
      assert_nil Nabu::HangulReadings.lookup(codepoint).ipa,
                 "a cluster final's surface IPA depends on sound rules — absent is honest"
    end
    Nabu::HangulReadings.table.each_value do |reading|
      assert_nil reading.rr, "#{reading.note}: RR is a modern system — no rr on historical rows" if
        reading.position == "historical"
    end
  end

  def test_syllable_rr_composes_letter_wise
    assert_equal "ib", Nabu::HangulReadings.syllable_rr([0x110B, 0x1175, 0x11B8])
    assert_equal "ga", Nabu::HangulReadings.syllable_rr([0x1100, 0x1161])
  end

  def test_rr_diverges_from_unicode_jamo_names_where_the_standards_do
    assert_equal "wo", Nabu::HangulReadings.syllable_rr([0x110B, 0x116F]),
                 "워 is RR wo — Unicode's jamo short name says WEO"
    assert_equal "ui", Nabu::HangulReadings.syllable_rr([0x110B, 0x1174]),
                 "의 is RR ui — Unicode's jamo short name says YI"
  end

  def test_an_archaic_syllable_stays_unromanized
    assert_nil Nabu::HangulReadings.syllable_rr([0x110B, 0x119E]),
               "arae-a carries no RR — a half-romanized syllable would be an invention"
  end

  def test_describe_states_position_rr_and_ipa
    assert_equal "b (RR) · IPA [p̚] — final", Nabu::HangulReadings.describe(0x11B8)
    assert_match(/silent — the silent initial ieung/, Nabu::HangulReadings.describe(0x110B))
    assert_match(/arae-a/, Nabu::HangulReadings.describe(0x119E))
    assert_nil Nabu::HangulReadings.describe(0x0061)
  end
end
