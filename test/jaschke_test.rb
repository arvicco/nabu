# frozen_string_literal: true

require "test_helper"

# Nabu::Jaschke — Jäschke's 1881 romanisation ↔ Unicode Tibetan. The
# ground truth is the print itself: every headword pair below was read off
# the scan of pp. 1–2 (archive.org tibetanenglishdi00jsuoft, leaves 27–28;
# the fixture PDF test/fixtures/jaschke-1881/ holds exactly those two page
# images), script and romanisation side by side. Stress accents are printed
# as on the page (they are prosodic and fold away).
class JaschkeTest < Minitest::Test
  J = Nabu::Jaschke

  # [Tibetan as printed, romanisation as printed, print page].
  VERIFIED_PAIRS = [
    ["ཀ", "ka", 1],
    ["ཀ་ཀ", "ka-ká", 1],
    ["ཀཱ་ཀ", "kā-ka", 1], # a-chung below: the long vowel
    ["ཀཾ་ཀ", "kaṅ-ka", 1], # anusvāra read ṅ
    ["ཀ་ཀ་རང", "ka-ka-ráṅ", 1],
    ["ཀ་ཀོ་ལ", "ka-ko-la", 1],
    ["ཀ་ཁ", "ka-k̔á", 1],                   # the aspiration spiritus
    ["ཀ་ཁོལ་མ", "ka-k̔ól-ma", 1],
    ["ཀ་ཅ", "ká-c̀a", 1],                   # the palatal grave
    ["ཀ་ཏ་ཡ", "ká-ta-ya", 1],
    ["ཀ་ཏུ", "ka-tu", 1],
    ["ཀ་ཏོ་ར", "ka-tó-ra", 1],
    ["ཀ་ཐ་ར", "ka-t̔a-ra", 1],
    ["ཀ་དག", "ka-dág", 1],
    ["ཀ་དར", "ka-dár", 1],
    ["ཀ་པཱ་ལ", "ka-pā-la", 1],
    ["ཀ་པི་ཏ", "ka-pi-ta", 1],
    ["ཀཾ་པོ་རྩེ", "kam-po-rtse", 1],        # anusvāra read m; the r-headed stack
    ["ཀ་བ", "ká-ba", 1],
    ["ཀ་བེད", "ka-béd", 2],
    ["ཀ་མ་རུ", "ka-ma-ru", 2],
    ["ཀ་མ་ལ་ཤི་ལ", "ka-ma-la-s̀i-la", 2], # as the Corrections (p. 669) restore it
    ["ཀ་རྩམ", "ka-rtsam", 2],
    ["ཀྭ་ཡེ", "kwa-ye", 2], # the wa-zur, in the entry's parenthesis
    ["ཀ་ར", "ká-ra", 2],
    ["ཀ་ལཱ་པ", "ka-lā-pa", 2],
    ["ཀ་ལ་པིང་ཀ", "ka-la-piṅ-ka", 2],
    ["ཀ་ལ་ཤ", "ka-la-s̀a", 2],
    ["ཀ་ལག", "ká-lag", 2],
    ["ཀ་ལན་ཏ་ཀ", "ka-lan-taka", 2], # printed without the last hyphen
    ["ཀ་ལི", "ka-lí", 2],
    ["ཀ་ལིང་ག", "ka-liṅ-ga", 2],
    ["ཀ་ལིབ", "ka-líb", 2],
    ["ཀ་ལེ", "ka-lé", 2],
    ["ཀཱ་ཤ", "kā-s̀a", 2],
    ["ཀ་ཤི་ཀ", "ka-s̀i-ka", 2],
    ["ཀ་ས", "ká-sa", 2],
    ["ཀག་གིས", "kág-gis", 2],
    ["ཀག་མ", "kág-ma", 2],
    ["ཀང་ཀ", "kaṅ-ka", 2], # the same romanisation, spelt with ང
    ["ཀང་དང་ཀིང", "kaṅ-daṅ-kiṅ", 2],
    ["ཀད", "kad", 2],
    ["ཀན", "kan", 2],
    ["ཀན་མ", "kán-ma", 2]
  ].freeze

  # Print irregularities the oracle must FLAG (the pair disagrees) —
  # exactly what a transcription cross-check exists to catch.
  IRREGULAR_PAIRS = [
    ["ཀ་མ་ལ་ཤི་ལ", "ka-ma-la-si-la", "p. 2 misprint: the grave is missing (Corrections p. 669: read ka-ma-la-s̀i-la)"],
    ["ཀ་ཚིགས་ཆེན་པོ", "ka-tsigs-c̀̔én-po", "p. 2: the spiritus of ts̔ is not printed"],
    ["ཀ་ལི", "kā-li", "p. 2: the macron has no a-chung in the script"],
    ["ཀྭ", "ka", "p. 1: the headword romanisation omits the wa-zur (the entry's parenthesis has kva)"]
  ].freeze

  def test_every_verified_pair_agrees
    VERIFIED_PAIRS.each do |tibetan, roman, page|
      assert J.agree?(tibetan: tibetan, roman: roman), "p. #{page}: #{roman} ⇄ #{tibetan} " \
                                                       "(got #{J.to_tibetan(roman).inspect})"
    end
  end

  def test_the_native_reading_comes_first
    VERIFIED_PAIRS.reject { |tibetan, _| tibetan.include?("ཾ") }.each do |tibetan, roman, page|
      assert_equal tibetan, J.to_tibetan(roman).first, "p. #{page}: #{roman}"
    end
  end

  def test_every_verified_pair_round_trips_from_the_script
    VERIFIED_PAIRS.each do |tibetan, roman, page|
      assert_includes J.from_tibetan(tibetan).map { |r| r.delete("-") }, J.fold(roman).delete("-"),
                      "p. #{page}: #{tibetan}"
    end
  end

  def test_print_irregularities_are_flagged_not_absorbed
    IRREGULAR_PAIRS.each do |tibetan, roman, why|
      refute J.agree?(tibetan: tibetan, roman: roman), why
    end
  end

  # --- the ambiguities: alternatives, never a guess ------------------------

  def test_a_closing_ng_or_m_may_be_the_anusvara
    assert_equal %w[ཀང་ཀ ཀཾ་ཀ], J.to_tibetan("kaṅ-ka")
    assert_equal %w[ཀམ་པོ་རྩེ ཀཾ་པོ་རྩེ], J.to_tibetan("kam-po-rtse")
    assert_equal 8, J.to_tibetan("kaṅ-daṅ-kiṅ").size
    refute J.unambiguous?("kaṅ-ka")
  end

  def test_the_anusvara_reads_back_both_ways
    assert_equal %w[kaṅ-ka kam-ka], J.from_tibetan("ཀཾ་ཀ")
  end

  def test_ai_and_au_may_be_the_particle_or_the_vowel_sign
    assert_equal %w[ཀའི ཀཻ], J.to_tibetan("kai")
    assert_equal %w[ཀའུ ཀཽ], J.to_tibetan("kau")
    assert_equal %w[ཀའོ], J.to_tibetan("kao")
  end

  def test_a_closed_coda_without_n_or_m_is_unambiguous
    assert J.unambiguous?("ka-dág")
    assert_equal ["ཀ་དག"], J.to_tibetan("ka-dág")
  end

  # --- the system's marks ----------------------------------------------------

  def test_the_aspirates_take_the_spiritus
    assert_equal ["ཁ"], J.to_tibetan("k̔a")
    assert_equal ["ཆ"], J.to_tibetan("c̀̔a")
    assert_equal ["ཐ"], J.to_tibetan("t̔a")
    assert_equal ["ཕ"], J.to_tibetan("p̔a")
    assert_equal ["ཚ"], J.to_tibetan("ts̔a")
  end

  def test_the_palatals_take_the_grave
    assert_equal ["ཅ"], J.to_tibetan("c̀a")
    assert_equal ["ཇ"], J.to_tibetan("j̀a")
    assert_equal ["ཤ"], J.to_tibetan("s̀a")
    assert_equal ["ཞ"], J.to_tibetan("z̀a")
    assert_equal ["ས"], J.to_tibetan("sa")
    assert_equal ["ཟ"], J.to_tibetan("za")
  end

  def test_gamma_is_the_prefixed_g
    assert_equal ["གཅིག"], J.to_tibetan("γc̀ig")
    assert_equal ["གཡག"], J.to_tibetan("γyag")
    assert_equal ["གྱག"], J.to_tibetan("gyag")
    assert_equal ["གཉིས"], J.to_tibetan("γnyis")
  end

  def test_the_ring_is_the_a_chung
    assert_equal ["འབྲངས"], J.to_tibetan("˳bráṅs")
    assert_equal ["འོ"], J.to_tibetan("˳o")
  end

  def test_a_prefixed_open_syllable_takes_the_closing_a_chung
    assert_equal ["དགའ"], J.to_tibetan("dga")
    assert_equal ["བཀའ"], J.to_tibetan("bka")
    assert_equal ["དགུ"], J.to_tibetan("dgu")
  end

  def test_stacks_prefixes_and_subscripts_parse_by_the_orthography
    assert_equal ["བརྒྱད"], J.to_tibetan("brgyad")
    assert_equal ["བསྐྱེད"], J.to_tibetan("bskyed")
    assert_equal ["དབྱངས"], J.to_tibetan("dbyaṅs")
    assert_equal ["སྒྲ"], J.to_tibetan("sgra")
    assert_equal ["ལྷ"], J.to_tibetan("lha")
    assert_equal ["ཟླ"], J.to_tibetan("zla")
    assert_equal ["མཁའ"], J.to_tibetan("mk̔a")
  end

  def test_long_vowels_and_vowel_initials
    assert_equal ["ཀཱི"], J.to_tibetan("kī")
    assert_equal ["ཨ་མ"], J.to_tibetan("a-ma")
    assert_equal ["ཨོ"], J.to_tibetan("o")
  end

  def test_retroflex_letters_take_the_dot_below
    assert_equal ["ཀ་ཊོ་ར"], J.to_tibetan("ka-ṭo-ra")
    assert_equal ["ཎ"], J.to_tibetan("ṇa")
  end

  def test_the_parenthesis_spelling_kva_reads_the_wa_zur
    assert_equal ["ཀྭ"], J.to_tibetan("kva")
  end

  def test_unhyphenated_runs_split_onset_first
    assert_equal ["ཀ་ར་ཤིང"], J.to_tibetan("kara-s̀iṅ").take(1)
  end

  # --- fold: the search key ----------------------------------------------------

  def test_fold_strips_stress_and_unifies_the_mark_variants
    assert_equal J.fold("ka-k̔á"), J.fold("ka-k'a")
    assert_equal J.fold("ká-c̀a"), J.fold("ka-ča")
    assert_equal J.fold("ka-ma-la-s̀i-la"), J.fold("ka-ma-la-śi-la")
    assert_equal J.fold("ka-ma-la-s̀i-la"), J.fold("ka-ma-la-ši-la")
    assert_equal J.fold("˳bráṅs"), J.fold("°brāṅs".tr("ā", "a"))
    assert_equal "kā-ka", J.fold("Kā-ka")
    assert J.fold("ka-ká").unicode_normalized?(:nfc)
  end

  def test_to_ewts_bridges_to_the_house_tibetan_fold
    assert_equal ["ka rtse"], J.to_ewts("ka-rtse")
    assert_equal ["bka'"], J.to_ewts("bka")
  end

  def test_unreadable_input_raises_a_typed_error
    assert_raises(Nabu::Jaschke::Error) { J.to_tibetan("kaq") }
    assert_raises(Nabu::Jaschke::Error) { J.to_tibetan("") }
  end
end
