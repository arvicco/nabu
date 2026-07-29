# frozen_string_literal: true

require "test_helper"

# The asl parser family (P53-1): the Oracc Sign List's line-oriented ASL
# grammar (00lib/osl.asl) → sign records for the Nabu::SignList read seam.
# The fixture is a trimmed byte-verbatim excerpt of the real file (see
# test/fixtures/osl/README.md); every expectation below is hand-counted
# from those bytes.
class AslParserTest < Minitest::Test
  FIXTURE = File.join(Nabu::TestSupport.fixtures("osl"), "osl.asl")

  def result
    @result ||= Nabu::Adapters::AslParser.new.parse_file(FIXTURE)
  end

  def sign(name)
    record = result.signs.find { |s| s.name == name }
    refute_nil record, "expected sign #{name} in the fixture parse"
    record
  end

  # --- the census -----------------------------------------------------------

  def test_all_eleven_sign_blocks_parse_in_file_order
    assert_equal ["|A.BARA₂|", "|A×AN|", "|A×GAN₂@t|", "AK", "|AN.SAG@g|", "|IGI.DIB|",
                  "MIN", "|MIN.MIN|", "|NU×U@c|", "ŠEŠ", "|ŠEŠ.AB|", "|ŠEŠ.KI|",
                  "|UD.ŠEŠ.KI|"],
                 result.signs.map(&:name)
  end

  def test_the_pcun_block_does_not_leak_a_sign_record
    assert_nil result.signs.find { |s| s.name == "1(N01@f)" },
               "the @pcun ACN-proposal block is not a sign"
  end

  # The censused ignore: every unmodeled directive is skipped WITHOUT error
  # but COUNTED — including modeled-looking directives outside any sign
  # block (the @pcun innards) and wrapped continuation lines. Hand-counted
  # from the fixture bytes.
  def test_ignored_directives_are_censused_not_silent
    assert_equal({
                   "@project" => 1, "@signlist" => 1, "@domain" => 1,
                   "@inote" => 11, "(continuation)" => 6, "@listdef" => 2,
                   "@lit" => 2, "@note" => 2, "@scriptdef" => 5,
                   "@uage" => 6, "@link" => 12, "@fake" => 1,
                   "@compoundonly" => 1, "@ref" => 1, "@pcun" => 1,
                   "@oid" => 1, "@list" => 1, "@uname" => 1, "@ucun" => 1,
                   "@v" => 1, "@end pcun" => 1
                 }, result.ignored)
    assert_equal 59, result.ignored.values.sum
  end

  # --- the simple encoded sign (ŠEŠ) ---------------------------------------

  def test_shesh_carries_the_single_codepoint_from_list_u_plus
    shesh = sign("ŠEŠ")
    assert_equal "o0002834", shesh.oid
    refute shesh.deprecated
    assert_equal "CUNEIFORM SIGN SHESH", shesh.uname
    assert_equal "𒋀", shesh.ucun
    assert_equal "U+122C0", shesh.codepoint
    assert_nil shesh.useq
    assert_equal ["U+122C0"], shesh.codepoints, "single codepoint reads as a one-element sequence"
    assert_predicate shesh, :encoded?
    assert_empty shesh.forms
  end

  def test_shesh_values_hand_counted_with_x_subscript_readings
    values = sign("ŠEŠ").values
    assert_equal 23, values.size
    assert_includes values.map(&:value), "šeš"
    # The ₓ-values ride the same @v seam, verbatim.
    assert_includes values.map(&:value), "sasₓ"
    assert_includes values.map(&:value), "zaₓ"
    assert(values.none?(&:deprecated))
    assert(values.all? { |v| v.language.nil? })
  end

  def test_shesh_list_concordances_exclude_the_u_plus_line
    numbers = sign("ŠEŠ").list_numbers
    assert_equal 13, numbers.size
    assert_includes numbers, "MZL535"
    assert_includes numbers, "LAK032"
    refute_includes numbers, "U+122C0", "@list U+xxxxx is the codepoint, not a concordance"
  end

  # --- the compound with @useq (|ŠEŠ.AB| — the uri₅ story) ------------------

  def test_shesh_ab_compound_carries_the_useq_sequence
    compound = sign("|ŠEŠ.AB|")
    assert_nil compound.codepoint
    assert_equal %w[U+122C0 U+1200A], compound.useq
    assert_equal %w[U+122C0 U+1200A], compound.codepoints
    assert_equal "𒋀𒀊", compound.ucun
    assert_includes compound.values.map(&:value), "uri₅"
    assert_equal 6, compound.values.size
  end

  def test_shesh_ab_form_is_a_sub_record_with_its_own_encoding
    forms = sign("|ŠEŠ.AB|").forms
    assert_equal 1, forms.size
    form = forms.first
    assert_equal "|AB.ŠEŠ|", form.name
    assert_equal "o0025697", form.oid
    assert_equal %w[U+1200A U+122C0], form.useq, "the variant form's own (reversed) sequence"
    assert_equal "𒀊𒋀", form.ucun
    assert_empty form.values
  end

  # @form+ (9 upstream occurrences) is a plain variant form; a form may
  # itself be honestly unencoded (LAK433 carries only its concordance).
  def test_form_plus_parses_as_a_variant_and_forms_can_be_unencoded
    forms = sign("|IGI.DIB|").forms
    assert_equal ["|IGI.LU|", "LAK433"], forms.map(&:name)
    plus = forms.first
    refute plus.deprecated, "@form+ is not a deprecation"
    assert_equal %w[U+12146 U+121FB], plus.useq
    lak = forms.last
    assert_nil lak.codepoints, "a form with no encoding reports nil, not an error"
    assert_equal ["LAK433"], lak.list_numbers
  end

  def test_shesh_ki_form_carries_its_own_values_and_concordances
    form = sign("|ŠEŠ.KI|").forms.first
    assert_equal "|ŠEŠ.NA|", form.name
    assert_equal ["nannaₓ"], form.values.map(&:value)
    assert_equal ["BAU012"], form.list_numbers
    assert_equal %w[U+122C0 U+1223E], form.useq
  end

  # --- the numeric sign (MIN) ----------------------------------------------

  def test_min_is_a_numeric_sign_with_the_two_dish_value
    min = sign("MIN")
    assert_equal "CUNEIFORM NUMERIC SIGN MIN", min.uname
    assert_equal "U+1222B", min.codepoint
    assert_includes min.values.map(&:value), "2(diš)"
    assert_includes min.values.map(&:value), "šin₂?", "the query-marked value is kept verbatim"
    assert_equal 6, min.values.size
    assert_equal 7, min.list_numbers.size
  end

  # --- absence of encoding is data -----------------------------------------

  def test_a_times_an_is_honestly_unencoded
    compound = sign("|A×AN|")
    assert_nil compound.codepoint
    assert_nil compound.useq
    assert_nil compound.upua
    assert_nil compound.ucun
    assert_nil compound.codepoints
    refute_predicate compound, :encoded?
    assert_equal ["BAU417a"], compound.list_numbers
  end

  # --- deprecations ---------------------------------------------------------

  def test_sign_dash_marks_the_record_deprecated
    dead = sign("|A×GAN₂@t|")
    assert dead.deprecated
    assert_equal "U+12003", dead.codepoint, "deprecation is orthogonal to encoding"
    assert_equal "𒀃", dead.ucun
  end

  def test_v_dash_marks_the_value_deprecated
    values = sign("AK").values
    assert_equal 15, values.size
    dead = values.find { |v| v.value == "aŋ" }
    assert dead.deprecated
    refute values.find { |v| v.value == "ak" }.deprecated
  end

  # --- language-qualified values -------------------------------------------

  def test_percent_lang_prefix_becomes_the_value_language
    values = sign("|AN.SAG@g|").values
    assert_equal 2, values.size
    akk = values.find { |v| v.value == "ṣillu" }
    assert_equal "akk", akk.language
    assert_nil values.find { |v| v.value == "ṣil₃" }.language
  end

  # --- aliases --------------------------------------------------------------

  def test_aka_aliases_are_recorded
    assert_equal ["|A.BARAG|"], sign("|A.BARA₂|").aka
  end

  # --- the NU×U@c quirk block ----------------------------------------------

  def test_space_separated_directives_upua_and_end_closed_form
    quirky = sign("|NU×U@c|")
    assert_equal "U+F009B", quirky.upua, "@upua with a SPACE separator"
    assert_equal "\u{F009B}", quirky.ucun, "the private-use rendered glyph"
    assert_nil quirky.codepoint
    form = quirky.forms.first
    refute_nil form, "the one upstream form closed by @end sign with no @@ must still parse"
    assert_equal "|NU×U|", form.name
    assert_equal "o0048857", form.oid, "@oid with a SPACE separator inside the form"
  end

  # --- malformed structural lines ------------------------------------------

  def test_nested_sign_raises_parse_error
    error = assert_raises(Nabu::ParseError) do
      Nabu::Adapters::AslParser.new.parse("@sign A\n@sign B\n@end sign\n")
    end
    assert_match(/nested @sign/, error.message)
  end

  def test_end_sign_without_open_sign_raises_parse_error
    assert_raises(Nabu::ParseError) { Nabu::Adapters::AslParser.new.parse("@end sign\n") }
  end

  def test_form_outside_a_sign_raises_parse_error
    assert_raises(Nabu::ParseError) { Nabu::Adapters::AslParser.new.parse("@form X\n") }
  end

  def test_form_terminator_without_open_form_raises_parse_error
    assert_raises(Nabu::ParseError) { Nabu::Adapters::AslParser.new.parse("@sign A\n@@\n@end sign\n") }
  end

  def test_sign_without_a_name_raises_parse_error
    assert_raises(Nabu::ParseError) { Nabu::Adapters::AslParser.new.parse("@sign\n@end sign\n") }
  end

  def test_unclosed_sign_at_eof_raises_parse_error
    error = assert_raises(Nabu::ParseError) { Nabu::Adapters::AslParser.new.parse("@sign A\n@v aa\n") }
    assert_match(/unclosed/, error.message)
  end

  def test_non_directive_junk_line_raises_parse_error
    assert_raises(Nabu::ParseError) { Nabu::Adapters::AslParser.new.parse("no directive here\n") }
  end

  # --- stability ------------------------------------------------------------

  def test_two_parses_are_equal
    twice = Nabu::Adapters::AslParser.new.parse_file(FIXTURE)
    assert_equal result.signs, twice.signs
    assert_equal result.ignored, twice.ignored
  end
end
