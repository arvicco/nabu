# frozen_string_literal: true

require "test_helper"

# Nabu::CharNumerals (P86-4b) — the letter-numeral fact tables. The suite
# pins the table's SHAPE (every scheme names itself and a registry script,
# values are positive integers) and spot-checks the systems' anchor values
# against the literature, so a slipped row can't ride in silently.
class CharNumeralsTest < Minitest::Test
  def test_every_scheme_is_well_formed_and_names_a_registry_script
    registry = Nabu::Lects.load(File.expand_path("fixtures/nabu-lects", __dir__))
    Nabu::CharNumerals.table.each do |scheme, row|
      assert row.key?("name"), "#{scheme}: a scheme names itself"
      assert registry.script?(row.fetch("script")),
             "#{scheme}: script #{row['script']} must be a registry tag"
      (row.fetch("values").values + row.fetch("extended_values", {}).values).each do |value|
        assert value.is_a?(Integer) && value.positive?, "#{scheme}: values are positive integers"
      end
    end
  end

  def test_the_milesian_structure_holds_per_scheme
    # Every alphabetic-numeral system here is Milesian-shaped: units 1–9,
    # tens 10–90, hundreds 100–900 (abjad adds 1000) — so each scheme's
    # value SET must be a subset of that shape, and the three Greek
    # bands must each be complete.
    milesian = (1..9).to_a + (1..9).map { |n| n * 10 } +
               (1..9).map { |n| n * 100 } + [1000]
    Nabu::CharNumerals.table.each do |scheme, row|
      values = row.fetch("values").values + row.fetch("extended_values", {}).values
      assert_empty values - milesian, "#{scheme}: every value fits the Milesian shape"
    end
    greek = Nabu::CharNumerals.table.fetch("isopsephy").fetch("values").values.uniq.sort
    assert_equal milesian - [1000], greek, "isopsephy covers all 27 slots"
  end

  def test_anchor_values
    assert_equal 1, lookup1("α").value
    assert_equal 6, lookup1("ϛ").value, "stigma, the episemon"
    assert_equal 900, lookup1("ϡ").value, "sampi"
    assert_equal 1, lookup1("א").value
    assert_equal 400, lookup1("ת").value
    assert_equal 1000, lookup1("غ").value, "the abjad's 28th value"
    assert_equal 700, lookup1("ѱ").value, "titlo psi, straight from the Greek"
    assert_equal 90, lookup1("ч").value, "červь took koppa's slot — NOT alphabet order"
    assert_equal 900, lookup1("𐍊").value, "the numeral-only Gothic 900"
  end

  def test_case_folds_and_extended_values_are_marked
    assert_equal 1, lookup1("Α").value, "uppercase alpha folds"
    final_mem = Nabu::CharNumerals.lookup("ם").first
    assert_equal 600, final_mem.value
    assert final_mem.extended, "sofit values carry the extended flag"
    refute lookup1("α").extended
  end

  def test_a_glyph_outside_every_table_answers_empty
    assert_empty Nabu::CharNumerals.lookup("q")
    assert_empty Nabu::CharNumerals.lookup("ᚠ"), "futhark is deliberately absent (no standard system)"
  end

  private

  def lookup1(glyph)
    hits = Nabu::CharNumerals.lookup(glyph)
    assert_equal 1, hits.size, "#{glyph}: expected exactly one scheme hit"
    hits.first
  end
end
