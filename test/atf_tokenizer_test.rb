# frozen_string_literal: true

require "test_helper"

# Nabu::AtfTokenizer (P53-2): the ATF transliteration line grammar → value
# tokens for the `nabu signs` surface. Every multi-token expectation below is
# a REAL line from the checked-in corpus fixtures (cdli / oracc / etcsl —
# never invented ATF), so the tokenizer is tested against upstream reality:
# C-ATF ASCII (cdli), Unicode ATF (oracc), and the ETCSL c/j dialect.
class AtfTokenizerTest < Minitest::Test
  def tokenizer(dialect: :catf)
    Nabu::AtfTokenizer.new(dialect: dialect)
  end

  def tokens(line, dialect: :catf)
    tokenizer(dialect: dialect).tokenize_line(line)
  end

  def values(line, dialect: :catf)
    tokens(line, dialect: dialect).map(&:value)
  end

  # -- the C-ATF ASCII fold ---------------------------------------------------

  def test_fold_pairs
    t = tokenizer
    assert_equal "šeš", t.fold("szesz")
    assert_equal "ŠEŠ", t.fold("SZESZ")
    assert_equal "u₂", t.fold("u2")
    assert_equal "du₁₁", t.fold("du11")
    assert_equal "ṣil₃", t.fold("s,il3")
    assert_equal "ṭup", t.fold("t,up")
    assert_equal "Ṣ", t.fold("S,")
    assert_equal "Ṭ", t.fold("T,")
    assert_equal "aʾ", t.fold("a'")
    assert_equal "geš₂", t.fold("gesz2")
  end

  def test_fold_leaves_leading_digits_and_zero_padded_notations_ascii
    t = tokenizer
    assert_equal "1(geš₂)", t.fold("1(gesz2)")
    assert_equal "1(N01)", t.fold("1(N01)"), "N01-style notations are not value subscripts"
    assert_equal "1/2(diš)", t.fold("1/2(disz)")
  end

  def test_fold_turns_x_before_a_qualifier_paren_into_subscript_x
    assert_equal "zahₓ(ŠEŠ)", tokenizer.fold("zahx(SZESZ)")
  end

  def test_etcsl_dialect_fold
    t = tokenizer(dialect: :etcsl)
    assert_equal "šag₄", t.fold("cag4")
    assert_equal "keše₂", t.fold("kece2")
    assert_equal "aŋ", t.fold("aj")
    assert_equal "Ŋ", t.fold("J")
  end

  def test_catf_dialect_leaves_c_and_j_alone
    assert_equal "c", tokenizer.fold("c")
    assert_equal "ji", tokenizer.fold("ji")
  end

  # -- segmentation on real cdli C-ATF lines ---------------------------------

  def test_cdli_ur3_line_splits_numbers_values_and_hyphen_chains
    # test/fixtures/cdli/cdliatf_unblocked.atf, P469841 obverse 1
    line = "1(gesz2) 4(disz) 1/2(disz) gurusz u4 1(disz)-sze3"
    assert_equal %w[1(geš₂) 4(diš) 1/2(diš) guruš u₄ 1(diš) še₃], values(line)
    assert_equal %i[number number number value value number value], tokens(line).map(&:kind)
    assert_equal "geš₂", tokens(line).first.notation
  end

  def test_cdli_determinative_word_splits_braces_and_hyphens
    # P469841 obverse 3: "3. ki ur-{gesz}gigir-ta" — line number stripped
    line = "3. ki ur-{gesz}gigir-ta"
    toks = tokens(line)
    assert_equal %w[ki ur geš gigir ta], toks.map(&:value)
    assert_equal [false, false, true, false, false], toks.map(&:determinative)
  end

  def test_cdli_proto_cuneiform_line_keeps_notation_skips_the_word_divider
    # P000001 obverse column 1 line 2': "2'. 1(N01) , TIM ABGAL#"
    toks = tokens("2'. 1(N01) , TIM ABGAL#")
    assert_equal ["1(N01)", "TIM", "ABGAL"], toks.map(&:value)
    assert_equal %i[number name name], toks.map(&:kind)
    assert_equal "ABGAL#", toks.last.raw, "damage marks stripped for lookup, raw kept"
  end

  def test_cdli_broken_tokens_are_broken_not_values
    # P000725 reverse column 1: "1. [...] , MUSZ3~a# SI A AMA~b# X [...]"
    toks = tokens("1. [...] , MUSZ3~a# SI A AMA~b# X [...]")
    assert_equal %w[broken name name name name broken broken],
                 toks.map(&:kind).map(&:to_s)
    assert_equal "MUŠ₃~a", toks[1].value, "the ~variant suffix rides the folded name"
  end

  def test_bracketed_n_is_a_name_token_not_broken
    # P000001 reverse: "1. [N] , [...]"
    toks = tokens("1. [N] , [...]")
    assert_equal %w[N], toks.take(1).map(&:value)
    assert_equal :broken, toks.last.kind
  end

  # -- segmentation on real oracc Unicode ATF lines --------------------------

  def test_oracc_urartian_line_with_determinatives
    # test/fixtures/oracc (P&type urartian): "{d}hal-di-ni-ni uš-ma-a-ši-ni"
    toks = tokens("{d}hal-di-ni-ni uš-ma-a-ši-ni")
    assert_equal %w[d hal di ni ni uš ma a ši ni], toks.map(&:value)
    assert toks.first.determinative
    refute toks[1].determinative
  end

  def test_oracc_logogram_line_keeps_subscripted_names_uppercase
    # oracc fixture: "2(BARIG) ZI₃ US₂ a-na GEŠBUN"
    toks = tokens("2(BARIG) ZI₃ US₂ a-na GEŠBUN")
    assert_equal %w[2(BARIG) ZI₃ US₂ a na GEŠBUN], toks.map(&:value)
    assert_equal %i[number name name value value name], toks.map(&:kind)
  end

  def test_oracc_elamite_line_ends_in_an_illegible_sign
    # oracc fixture: "{DIŠ}da-ri-ia-ma-u-iš x"
    toks = tokens("{DIŠ}da-ri-ia-ma-u-iš x")
    assert_equal "DIŠ", toks.first.value
    assert toks.first.determinative
    assert_equal :name, toks.first.kind, "an uppercase determinative is still a sign name"
    assert_equal :broken, toks.last.kind
  end

  # -- segmentation on real etcsl dialect lines ------------------------------

  def test_etcsl_line_folds_c_and_trailing_digits
    # test/fixtures/etcsl c.2.5.2.3: "lugal-me-en cag4-ta"
    assert_equal %w[lugal me en šag₄ ta], values("lugal-me-en cag4-ta", dialect: :etcsl)
  end

  def test_etcsl_damage_ellipses_are_broken
    # c.1.8.2.1 damaged line: "… ul-e suh10 kece2-da …"
    toks = tokens("… ul-e suh10 kece2-da …", dialect: :etcsl)
    assert_equal %w[broken value value value value value broken], toks.map(&:kind).map(&:to_s)
    assert_equal %w[ul e suh₁₀ keše₂ da], toks[1..5].map(&:value)
  end

  # -- compounds, qualified values, corrections ------------------------------

  def test_piped_compounds_stay_whole_and_fold_the_times_operator
    toks = tokens("|AxAN| |SZESZ.AB|")
    assert_equal ["|A×AN|", "|ŠEŠ.AB|"], toks.map(&:value)
    assert_equal %i[compound compound], toks.map(&:kind)
  end

  def test_qualified_value_carries_its_explicit_sign
    token = tokens("zahx(SZESZ)").first
    assert_equal :qualified, token.kind
    assert_equal "zahₓ", token.value
    assert_equal "ŠEŠ", token.sign_spec
  end

  def test_dotted_uppercase_group_stays_one_name_token
    token = tokens("UD.SZESZ.KI").first
    assert_equal :name, token.kind
    assert_equal "UD.ŠEŠ.KI", token.value
  end

  def test_scribal_correction_group_is_dropped_keeping_the_corrected_value
    # C-ATF a!(DA): the scribe wrote DA, the editor reads a.
    toks = tokens("a!(DA)")
    assert_equal ["a"], toks.map(&:value)
    assert_equal [:value], toks.map(&:kind)
  end

  def test_editorial_marks_are_stripped_for_lookup
    assert_equal %w[še₃ ur e₂ gal], values("sze3! ur? [e2-gal]")
  end

  # -- structural lines -------------------------------------------------------

  def test_structural_lines_yield_no_tokens
    [
      "&P000001 = CDLI Lexical 000002, ex. 065",
      "#atf: lang qpc",
      "@obverse",
      "$ beginning broken",
      ">>Q000002 014"
    ].each do |line|
      assert_nil tokens(line), "#{line.inspect} is ATF structure, not transliteration"
    end
    assert_nil tokens("   ")
  end

  def test_unknown_dialect_is_refused
    assert_raises(ArgumentError) { Nabu::AtfTokenizer.new(dialect: :klingon) }
  end
end
