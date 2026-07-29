# frozen_string_literal: true

require "test_helper"

# Nabu::Xct (P50-W3): the Tibetan-script → EWTS transcoder GENERATED from the
# authored rule table (config/ewts/rules.csv, `rake fold:xct`). Every pinned
# word below is REAL corpus text: the Wylie↔script pairs come from the mvp
# fixture's bod-Latn/bod-Tibt <orth> quotes, the running lines from the
# derge-kangyur fixture, the Old Tibetan spellings from the old-tibetan
# conllu fixture — never hand-invented romanizations.
class XctTest < Minitest::Test
  # -- the mvp fixture's own Wylie ↔ Tibetan-script pairs -------------------

  MVP_PAIRS = {
    "sangs rgyas" => "སངས་རྒྱས",
    "bcom ldan 'das" => "བཅོམ་ལྡན་འདས",
    "de bzhin gshegs pa" => "དེ་བཞིན་གཤེགས་པ",
    "byang chub sems dpa'" => "བྱང་ཆུབ་སེམས་དཔའ",
    "zla mdzes" => "ཟླ་མཛེས",
    "kun dga' bo" => "ཀུན་དགའ་བོ",
    "lam chen bstan" => "ལམ་ཆེན་བསྟན",
    "gro bzhin skyes bye ba nyi shu pa" => "གྲོ་བཞིན་སྐྱེས་བྱེ་བ་ཉི་ཤུ་པ",
    "bstod pa" => "བསྟོད་པ",
    "bde ba" => "བདེ་བ",
    "gzhal yas" => "གཞལ་ཡས"
  }.freeze

  def test_the_mvp_wylie_script_pairs_transcode_exactly
    MVP_PAIRS.each do |wylie, tibetan|
      assert_equal wylie, Nabu::Xct.to_ewts(tibetan), "expected #{tibetan} → #{wylie.inspect}"
    end
  end

  # -- stack-heavy syllables (superscript + subjoined + prefix/suffix) ------

  def test_stack_heavy_syllables
    assert_equal "sgrub", Nabu::Xct.to_ewts("སྒྲུབ")
    assert_equal "bskyabs", Nabu::Xct.to_ewts("བསྐྱབས")
    assert_equal "rnying", Nabu::Xct.to_ewts("རྙིང")
    assert_equal "bsgrubs", Nabu::Xct.to_ewts("བསྒྲུབས")
  end

  # -- running canon text (derge-kangyur fixture lines) ---------------------

  def test_a_derge_kangyur_opening_line
    line = "༄༅༅། །རྒྱ་གར་སྐད་དུ། བི་ན་ཡ་བསྟུ། བོད་སྐད་དུ། འདུལ་བ་གཞི།"
    assert_equal "@##/ /rgya gar skad du/ bi na ya bstu/ bod skad du/ 'dul ba gzhi/",
                 Nabu::Xct.to_ewts(line)
  end

  def test_derge_homage_and_refuge_phrases
    assert_equal "dkon mchog gsum la phyag 'tshal lo",
                 Nabu::Xct.to_ewts("དཀོན་མཆོག་གསུམ་ལ་ཕྱག་འཚལ་ལོ")
    assert_equal "skyabs su mchi", Nabu::Xct.to_ewts("སྐྱབས་སུ་མཆི")
  end

  # -- Old Tibetan orthography (old-tibetan conllu fixture spellings) -------

  def test_old_tibetan_reversed_gi_gu_is_ewts_hyphen_i
    # The otannals fixture writes སྙྀང (snying) and གྱྀམ (gyim) with the
    # reversed gi-gu U+0F80 — EWTS "-i", OTDO's own convention.
    assert_equal "sny-ing", Nabu::Xct.to_ewts("སྙྀང")
    assert_equal "gy-im", Nabu::Xct.to_ewts("གྱྀམ")
    assert_equal "mtha' dag", Nabu::Xct.to_ewts("མཐའ་དག")
  end

  # -- the a-chung grammar --------------------------------------------------

  def test_suffix_a_chung_and_connective_particles
    assert_equal "dga'", Nabu::Xct.to_ewts("དགའ")
    assert_equal "dga'i", Nabu::Xct.to_ewts("དགའི")   # genitive rides the suffix a-chung
    assert_equal "bo'i", Nabu::Xct.to_ewts("བོའི")
    assert_equal "de'ang", Nabu::Xct.to_ewts("དེའང")  # medial a-chung opens an inner syllable
    assert_equal "na'ang", Nabu::Xct.to_ewts("ནའང")
  end

  def test_two_letter_and_three_letter_root_placement
    assert_equal "dag", Nabu::Xct.to_ewts("དག")     # root first: da + g suffix
    assert_equal "'das", Nabu::Xct.to_ewts("འདས")   # 'a-chung prefix: ' + da + s
    assert_equal "bcas", Nabu::Xct.to_ewts("བཅས")   # prefix pair b+c: b + ca + s
    assert_equal "sangs", Nabu::Xct.to_ewts("སངས")  # s is no prefix: sa + ng + s
    assert_equal "mangs", Nabu::Xct.to_ewts("མངས")  # curated ambiguous override (not mngas)
    assert_equal "bsams", Nabu::Xct.to_ewts("བསམས") # four bare letters: prefix + root + suffix + s
  end

  # -- Sanskrit-loan shapes (mantra text the canon carries) -----------------

  def test_sanskrit_loan_stacks_and_long_vowels
    assert_equal "oM", Nabu::Xct.to_ewts("ཨོཾ") # a-chen carrier + o + anusvara
    assert_equal "hU~M", Nabu::Xct.to_ewts("ཧཱུྃ") # A+u collapse to U, candrabindu
    assert_equal "padme", Nabu::Xct.to_ewts("པདྨེ")        # pa gets its a: p is no Tibetan prefix
    assert_equal "karma", Nabu::Xct.to_ewts("ཀརྨ")         # vowel-less loan stacks each carry a
    assert_equal "a", Nabu::Xct.to_ewts("ཨ")
    assert_equal "Ta", Nabu::Xct.to_ewts("ཊ")              # retroflex loan letter
  end

  def test_tibetan_digits
    assert_equal "123", Nabu::Xct.to_ewts("༡༢༣")
  end

  # -- transcoder contract --------------------------------------------------

  def test_ewts_and_other_latin_text_passes_through_unchanged
    ["byang chub sems dpa'", "sgrub", "Iliad 1.1", "bags kyis"].each do |text|
      assert_equal text, Nabu::Xct.to_ewts(text)
    end
  end

  def test_unknown_codepoints_pass_through_and_markup_survives
    assert_equal "[1b.1]{D1}rgya gar", Nabu::Xct.to_ewts("[1b.1]{D1}རྒྱ་གར")
  end

  def test_with_map_is_byte_identical_and_points_into_the_source
    text = "བྱང་ཆུབ་སེམས་དཔའ། ༡"
    ewts, map = Nabu::Xct.to_ewts_with_map(text)
    assert_equal Nabu::Xct.to_ewts(text), ewts
    assert_equal ewts.length, map.length
    chars = text.chars
    map.each { |index| assert_includes 0...chars.length, index }
    # The inherent a attributes to its root consonant: "bya..."'s a → བ's index 0.
    assert_equal 0, map[ewts.index("a")]
    # The digit at the tail attributes to the Tibetan digit character.
    assert_equal chars.index("༡"), map[ewts.index("1")]
  end

  # -- the fold wiring (script and Wylie meet in one query space) -----------

  def test_search_form_folds_script_and_wylie_to_the_same_skeleton
    MVP_PAIRS.each do |wylie, tibetan|
      %w[xct bod otb].each do |language|
        assert_equal Nabu::Normalize.search_form(wylie, language: language),
                     Nabu::Normalize.search_form(tibetan, language: language),
                     "#{tibetan} and #{wylie.inspect} must meet under #{language}"
      end
    end
  end

  def test_search_form_lowercases_ewts_capitals_symmetrically
    # downcase runs BEFORE the neutralizer, so the transcoder's spec-EWTS
    # capitals (oM, Ta, hU~M) must be case-folded by the language rule or a
    # typed "om"/"ta" query could never reach script text.
    assert_equal "om", Nabu::Normalize.search_form("ཨོཾ", language: "xct")
    assert_equal "ta", Nabu::Normalize.search_form("ཊ", language: "bod")
  end

  def test_query_forms_carry_the_ewts_variant_for_script_queries
    forms = Nabu::Normalize.query_forms("བྱང་ཆུབ་སེམས་དཔའ")
    assert_includes forms, "byang chub sems dpa'"
  end

  def test_query_forms_leave_wylie_queries_intact
    assert_includes Nabu::Normalize.query_forms("byang chub sems dpa"), "byang chub sems dpa"
  end

  def test_fold_with_map_composes_the_neutralizer_map
    text = "སངས་རྒྱས"
    folded, map = Nabu::Normalize.fold_with_map(text, language: "xct")
    assert_equal Nabu::Normalize.search_form(text, language: "xct"), folded
    assert_equal folded.length, map.length
    assert_equal 0, map[0] # "s..." points at ས
  end

  def test_generated_module_carries_the_rules_digest
    assert_match(/\A\h{64}\z/, Nabu::Xct::RULES_SHA256)
  end
end
