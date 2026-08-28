# frozen_string_literal: true

require "test_helper"

# Nabu::Ucd — the read seam over UnicodeData.txt (P85, Track B floor). Parses
# the trimmed real fixture (test/fixtures/ucd/) and answers the universal
# character-identity questions Ruby's own tables cannot: NAME, general
# category, decomposition, numeric value — for plain letters AND for the
# code points that live inside a "<..., First>/<..., Last>" range.
class UcdTest < Minitest::Test
  FIXTURE = File.expand_path("fixtures/ucd/UnicodeData.txt", __dir__)

  def setup
    @ucd = Nabu::Ucd.load(FIXTURE)
  end

  # -- feature-detect / load_default ---------------------------------------

  def test_load_default_is_nil_when_the_file_is_absent
    Dir.mktmpdir do |dir|
      config = Nabu::Config.load
      config.define_singleton_method(:canonical_dir) { dir }
      assert_nil Nabu::Ucd.load_default(config: config), "absent file → lane off"
    end
  end

  # -- lookup by glyph AND by codepoint ------------------------------------

  def test_lookup_by_glyph_and_by_codepoint_agree
    by_glyph = @ucd.lookup("A")
    by_cp = @ucd.lookup(0x41)
    refute_nil by_glyph
    assert_equal by_glyph, by_cp
    assert_equal "LATIN CAPITAL LETTER A", by_glyph.name
    assert_equal "Lu", by_glyph.category
    assert_equal "Uppercase Letter", by_glyph.category_label
    assert_equal "U+0041", by_glyph.hex
    assert_equal 0x61, by_glyph.lowercase
  end

  def test_lookup_of_an_unassigned_codepoint_is_nil
    assert_nil @ucd.lookup(0x0378), "a hole in the fixture, in no range → nil"
  end

  # -- names across scripts -------------------------------------------------

  def test_names_across_scripts
    assert_equal "GREEK SMALL LETTER ALPHA", @ucd.lookup("α").name
    assert_equal 0x391, @ucd.lookup("α").uppercase
    assert_equal "HEBREW LETTER ALEF", @ucd.lookup("א").name
    assert_equal "OLD ITALIC LETTER A", @ucd.lookup("𐌀").name
    assert_equal "EGYPTIAN HIEROGLYPH A001", @ucd.lookup("𓀀").name
  end

  # -- controls: name lives in the Unicode-1.0 column -----------------------

  def test_control_char_display_name_falls_back_to_unicode1_name
    null = @ucd.lookup(0x0000)
    assert_equal "<control>", null.name, "the raw name field is the angle-bracket label"
    assert_equal "NULL", null.display_name, "display name prefers the Unicode-1.0 label"
    assert_equal "Control", null.category_label
  end

  # -- decomposition: canonical and tagged ----------------------------------

  def test_canonical_decomposition
    grave_a = @ucd.lookup("À")
    decomp = grave_a.decomposition
    refute_nil decomp
    assert_nil decomp.kind, "canonical decomposition carries no tag"
    assert_equal [0x41, 0x300], decomp.codepoints
  end

  def test_tagged_decompositions
    half = @ucd.lookup("½")
    assert_equal "fraction", half.decomposition.kind
    assert_equal [0x31, 0x2044, 0x32], half.decomposition.codepoints
    assert_equal "compat", @ucd.lookup("Ⅰ").decomposition.kind
  end

  def test_a_plain_letter_has_no_decomposition
    assert_nil @ucd.lookup("A").decomposition
  end

  # -- numeric values -------------------------------------------------------

  def test_numeric_values
    assert_equal "4", @ucd.lookup("٤").numeric
    assert_equal "1", @ucd.lookup("Ⅰ").numeric
    assert_equal "6", @ucd.lookup("ↅ").numeric
    assert_equal "90", @ucd.lookup("𐍁").numeric
    assert_equal "1/2", @ucd.lookup("½").numeric
    assert_nil @ucd.lookup("A").numeric
  end

  # -- combining mark -------------------------------------------------------

  def test_combining_mark_carries_its_class
    grave = @ucd.lookup(0x0300)
    assert_equal "COMBINING GRAVE ACCENT", grave.name
    assert_equal 230, grave.combining_class
    assert_equal "Nonspacing Mark", grave.category_label
  end

  # -- ranges: derived names ------------------------------------------------

  def test_cjk_ideograph_inside_the_range_gets_a_derived_name
    zhong = @ucd.lookup("中") # U+4E2D, interior of 4E00..9FFF
    refute_nil zhong, "an interior code point resolves through the range pair"
    assert_equal "CJK UNIFIED IDEOGRAPH-4E2D", zhong.name
    assert_equal "Lo", zhong.category
  end

  def test_hangul_syllable_gets_an_algorithmic_jamo_name
    assert_equal "HANGUL SYLLABLE IB", @ucd.lookup("입").name # U+C785
    assert_equal "HANGUL SYLLABLE GA", @ucd.lookup("가").name # U+AC00, range start
    assert_equal "HANGUL SYLLABLE A", @ucd.lookup("아").name  # U+C544, null initial
  end

  def test_a_codepoint_past_every_range_and_line_is_nil
    assert_nil @ucd.lookup(0x1FFFF), "beyond the fixture's ranges → nil"
  end
end
