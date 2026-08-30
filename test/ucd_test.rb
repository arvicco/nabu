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

  # -- member context (P86-1, №R-49a: the useful-context tier) ---------------
  # The seam widens over the sibling member files landed by the UCD.zip fetch;
  # every lookup degrades to nil/[] when its member file is absent — feature
  # detection at MEMBER grain, so a partial canonical stays honest.

  def test_block_names_the_containing_block
    block = @ucd.block(0x16A0)
    assert_equal "Runic", block.name
    assert_equal (0x16A0..0x16FF), block.range
    assert_equal "CJK Unified Ideographs", @ucd.block(0x4E01).name
    assert_nil @ucd.block(0xE0000), "outside every fixture block → nil"
  end

  def test_script_carries_long_name_and_short_code
    script = @ucd.script(0x16A0)
    assert_equal "Runic", script.name
    assert_equal "Runr", script.code
    assert_equal "Old Italic", @ucd.script(0x10300).name
    assert_equal "Ital", @ucd.script(0x10300).code
    assert_equal "Hangul", @ucd.script(0xAC00).name
    assert_nil @ucd.script(0xE0000)
  end

  def test_script_extensions_list_short_codes
    exts = @ucd.script_extensions(0x30FC)
    assert_includes exts, "Hira"
    assert_includes exts, "Kana"
    assert_empty @ucd.script_extensions(0x0061), "no extensions line → empty"
  end

  def test_name_aliases_carry_corrections_and_control_names
    fe18 = @ucd.name_aliases(0xFE18)
    assert(fe18.any? { |a| a.type == "correction" && a.name.include?("BRACKET") },
           "the famous BRAKCET typo carries its correction alias")
    null = @ucd.name_aliases(0x0000)
    assert(null.any? { |a| a.type == "control" && a.name == "NULL" })
    assert(null.any? { |a| a.type == "abbreviation" && a.name == "NUL" })
    assert_empty @ucd.name_aliases(0x0061)
  end

  def test_age_states_the_unicode_version
    assert_equal "3.0", @ucd.age(0x16A0)
    assert_equal "1.1", @ucd.age(0x0061)
    assert_nil @ucd.age(0xE0000)
  end

  def test_annotations_carry_chart_aliases_notes_and_crossrefs
    alef = @ucd.annotations(0x05D0)
    assert_includes alef.aliases, "aleph"
    alpha = @ucd.annotations(0x03B1)
    assert(alpha.crossrefs.any? { |ref| ref.codepoint == 0x0251 },
           "α cross-references latin small letter alpha")
    assert_nil @ucd.annotations(0x16A0).aliases.first, "runic fehu has no chart alias in the fixture"
  end

  def test_cjk_radical_join
    radical = @ucd.cjk_radical(0x2F4A) # KANGXI RADICAL WOOD
    assert_equal 75, radical.number
    assert_equal 0x6728, radical.unified # 木
    assert_equal 0x6728, @ucd.equivalent_unified(0x2F4A)
    assert_nil @ucd.cjk_radical(0x0061)
  end

  def test_confusables_cluster_both_directions
    partners = @ucd.confusables(0x0061)
    assert_includes partners, 0xFF41, "a ↔ fullwidth a"
    assert_includes @ucd.confusables(0xFF41), 0x0061, "reverse direction holds"
    refute_includes partners, 0x0061, "never lists itself"
    assert_empty @ucd.confusables(0x16A0)
  end

  def test_tangut_source_fields
    fields = @ucd.tangut_source(0x17000)
    refute_nil fields
    assert fields.key?("kTGT_RSUnicode")
    assert_nil @ucd.tangut_source(0x0061)
  end

  def test_standardized_variants_named_sequences_and_do_not_emit
    variants = @ucd.variants(0x0030)
    assert_equal 1, variants.size
    assert_equal "short diagonal stroke form", variants.first.description
    assert_equal 0xFE00, variants.first.selector

    sequences = @ucd.named_sequences(0x0030)
    assert_includes sequences, "KEYCAP DIGIT ZERO"

    discouraged = @ucd.do_not_emit(0x0905)
    assert_equal "0904", discouraged.first.preferred
    assert_equal "Indic_Vowel_Letter", discouraged.first.type
    assert_empty @ucd.variants(0x16A0)
    assert_empty @ucd.named_sequences(0x16A0)
    assert_empty @ucd.do_not_emit(0x16A0)
  end

  def test_jamo_short_name
    assert_equal "G", @ucd.jamo_short_name(0x1100)
    assert_nil @ucd.jamo_short_name(0x0061)
  end

  def test_hangul_jamo_decomposition_is_algorithmic
    assert_equal [0x110B, 0x1175, 0x11B8], @ucd.hangul_jamo(0xC785) # 입 = ᄋ ᅵ ᆸ
    assert_equal [0x1100, 0x1161], @ucd.hangul_jamo(0xAC00), "가 has no trailing jamo"
    assert_nil @ucd.hangul_jamo(0x0061), "not a Hangul syllable → nil"
  end

  def test_member_lookups_degrade_when_files_are_absent
    Dir.mktmpdir do |dir|
      FileUtils.cp(FIXTURE, File.join(dir, "UnicodeData.txt"))
      seam = Nabu::Ucd.load(File.join(dir, "UnicodeData.txt"))
      assert_nil seam.block(0x16A0)
      assert_nil seam.script(0x16A0)
      assert_empty seam.script_extensions(0x30FC)
      assert_empty seam.name_aliases(0x0000)
      assert_nil seam.age(0x0061)
      assert_nil seam.annotations(0x05D0)
      assert_nil seam.cjk_radical(0x2F4A)
      assert_empty seam.confusables(0x0061)
      assert_nil seam.tangut_source(0x17000)
      assert_nil seam.jamo_short_name(0x1100)
    end
  end
end
