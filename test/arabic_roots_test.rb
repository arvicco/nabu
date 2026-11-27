# frozen_string_literal: true

require "test_helper"
require "nabu/arabic_roots"

# Nabu::ArabicRoots — the Arabic root crosswalk: Buckwalter and DMG roots
# onto Arabic script, and the comparison key whose rules apply identically
# to Lane's headings and to a Quranic token's root.
class ArabicRootsTest < Minitest::Test
  R = Nabu::ArabicRoots

  # The 28 consonants + hamza of the Arabic alphabet.
  CONSONANTS = %w[ء ب ت ث ج ح خ د ذ ر ز س ش ص ض ط ظ ع غ ف ق ك ل م ن ه و ي].freeze

  # Every character the live QAC ROOT column carries (census 2026-11-27,
  # 1,642 distinct roots) and every consonant Corpus Coranicum's root
  # column carries (1,697 distinct; its vowel-bearing non-root analyses
  # are clean misses, pinned below).
  QAC_ROOT_CHARS = %w[l r w A b n y m E q k d s h f H j x t $ S * D z g T v Z].freeze
  CORAN_ROOT_CHARS = %w[l r w b m n y ʾ ʿ q k s d f ḥ ǧ ḫ t š ṣ h ḏ ḍ z ġ ṭ ṯ ẓ].freeze

  # -- the tables -------------------------------------------------------------

  def test_tables_are_one_to_one
    R::TABLES.each do |scheme, table|
      assert_equal table.size, table.values.uniq.size, "#{scheme}: two keys share an Arabic letter"
      table.each_key { |key| assert_equal 1, key.length, "#{scheme}: #{key.inspect} is not one character" }
    end
  end

  def test_both_tables_cover_every_consonant
    R::TABLES.each do |scheme, table|
      missing = CONSONANTS - table.values
      assert_empty missing, "#{scheme} lacks #{missing.join(' ')}"
    end
  end

  def test_buckwalter_covers_the_standard_marks_and_seats
    %w[ء آ أ ؤ إ ئ ا ة ى ـ ٱ].each { |letter| assert_includes R::BUCKWALTER.values, letter }
    (0x064B..0x0652).map { |cp| cp.chr(Encoding::UTF_8) }.push("ٰ").each do |mark|
      assert_includes R::BUCKWALTER.values, mark
    end
  end

  def test_dmg_is_consonants_only
    assert_equal 28, R::DMG.size
    assert_empty R::DMG.values - CONSONANTS
  end

  # The loud census: an inventory character a table cannot map fails here.
  def test_every_live_inventory_character_maps
    assert_empty R.unmapped(QAC_ROOT_CHARS.join, scheme: :buckwalter)
    assert_empty R.unmapped(CORAN_ROOT_CHARS.join, scheme: :dmg)
  end

  def test_transliterates_known_roots
    assert_equal "رحم", R.to_arabic("rHm", scheme: :buckwalter)
    assert_equal "ءمن", R.to_arabic("Amn".tr("A", "'"), scheme: :buckwalter)
    assert_equal "امن", R.to_arabic("Amn", scheme: :buckwalter)
    assert_equal "شيء", R.to_arabic("$y'", scheme: :buckwalter)
    assert_equal "ذكر", R.to_arabic("*kr", scheme: :buckwalter)
    assert_equal "رحم", R.to_arabic("rḥm", scheme: :dmg)
    assert_equal "ءمن", R.to_arabic("ʾmn", scheme: :dmg)
    assert_equal "جعل", R.to_arabic("ǧʿl", scheme: :dmg)
    assert_equal "كتب", R.to_arabic("كتب", scheme: :arabic)
  end

  def test_dmg_input_is_nfc_folded
    decomposed = "rḥm" # h + combining dot below
    assert_equal "رحم", R.to_arabic(decomposed, scheme: :dmg)
  end

  # Runtime: an unmapped character is a clean miss, never a guess.
  def test_unmapped_character_is_a_clean_miss
    assert_nil R.to_arabic("ʾūl", scheme: :dmg)
    assert_nil R.to_arabic("ḥelpinġVowel", scheme: :dmg)
    assert_nil R.to_arabic("r-m", scheme: :buckwalter)
    assert_nil R.keys("kum", scheme: :dmg)
    assert_nil R.to_arabic("", scheme: :dmg)
    assert_equal %w[ū], R.unmapped("ʾūl", scheme: :dmg)
  end

  def test_unknown_scheme_is_an_error
    assert_raises(ArgumentError) { R.to_arabic("ktb", scheme: :ipa) }
  end

  def test_detect_scheme
    assert_equal :arabic, R.detect_scheme("كتب")
    assert_equal :dmg, R.detect_scheme("rḥm")
    assert_equal :dmg, R.detect_scheme("ktb") # shared letters: same Arabic either way
    assert_equal :buckwalter, R.detect_scheme("rHm")
    assert_equal :buckwalter, R.detect_scheme("$y'")
    assert_equal R.to_arabic("ktb", scheme: :dmg), R.to_arabic("ktb", scheme: :buckwalter)
  end

  # -- rule 1 -----------------------------------------------------------------

  def test_strip_vowels
    assert_equal "أكر", R.strip_vowels("أَكَرَ")
    assert_equal "جهل", R.strip_vowels("جَهِلَ")
    assert_equal "ثفا", R.strip_vowels("ثفاً")
    assert_equal "ربّ", R.strip_vowels("رَبّ"), "shadda is rule 2's"
  end

  def test_fold_seats
    assert_equal "ءمن", R.fold_seats("أمن")
    assert_equal "ءمن", R.fold_seats("امن")
    assert_equal "ءمن", R.fold_seats("إمن")
    assert_equal "سءل", R.fold_seats("سأل")
    assert_equal "بءس", R.fold_seats("بئس")
    assert_equal "لءم", R.fold_seats("لؤم")
    assert_equal "ءمن", R.fold_seats("آمن")
    assert_equal "كفي", R.fold_seats("كفى"), "alif maqsura is the y radical"
  end

  # -- rule 2 -----------------------------------------------------------------

  def test_expand_shadda
    assert_equal "ربب", R.expand_shadda("ربّ")
    assert_equal "قمم", R.expand_shadda("قمّ")
    assert_equal "رب", R.expand_shadda("ّرب"), "a leading stray shadda drops"
  end

  def test_collapse_geminate
    assert_equal "رب", R.collapse_geminate("ربب")
    assert_equal "رب", R.collapse_geminate("رب")
    assert_equal "ردد", R.collapse_geminate("رددد"), "one collapse, final pair only"
    assert_equal "مد", R.collapse_geminate("مدد")
    assert_equal "كتب", R.collapse_geminate("كتب")
  end

  # -- rule 3 -----------------------------------------------------------------

  def test_fold_weak
    assert_equal "دءر", R.fold_weak("دير")
    assert_equal "دءر", R.fold_weak("دور")
    assert_equal "ءجل", R.fold_weak("وجل")
    assert_equal "كتب", R.fold_weak("كتب")
  end

  # -- rule 4 -----------------------------------------------------------------

  def test_collapse_reduplication
    assert_equal "زل", R.collapse_reduplication("زلزل")
    assert_equal "وس", R.collapse_reduplication("وسوس")
    assert_equal "زلزال", R.collapse_reduplication("زلزال")
    assert_equal "ربب", R.collapse_reduplication("ربب")
  end

  # -- the keys: identical on both sides --------------------------------------

  def test_strict_key_joins_the_known_classes
    assert_equal R.strict_key("أمن"), R.keys("Amn", scheme: :buckwalter).first
    assert_equal R.strict_key("ربّ"), R.keys("rbb", scheme: :buckwalter).first
    assert_equal R.strict_key("رب"), R.keys("rbb", scheme: :buckwalter).first
    assert_equal R.strict_key("كفى"), R.keys("kfy", scheme: :buckwalter).first
    assert_equal R.strict_key("حيى"), R.keys("Hyy", scheme: :buckwalter).first
    assert_equal R.strict_key("أَكَرَ"), R.keys("Akr", scheme: :buckwalter).first
    assert_equal R.strict_key("رحم"), R.keys("rḥm", scheme: :dmg).first
    assert_equal R.keys("rHm", scheme: :buckwalter), R.keys("rḥm", scheme: :dmg)
  end

  def test_strict_key_keeps_weak_radicals_apart
    refute_equal R.strict_key("قول"), R.strict_key("قيل")
    refute_equal R.strict_key("زل"), R.keys("zlzl", scheme: :buckwalter).first
  end

  def test_loose_key_joins_weak_and_reduplicated
    assert_equal R.loose_key("دير"), R.keys("dwr", scheme: :buckwalter).last
    assert_equal R.loose_key("اجل"), R.keys("wjl", scheme: :buckwalter).last
    assert_equal R.loose_key("زل"), R.keys("zlzl", scheme: :buckwalter).last
    assert_equal R.loose_key("وس"), R.keys("wsws", scheme: :buckwalter).last
    assert_equal R.loose_key("لأ"), R.keys("lAlA", scheme: :buckwalter).last
  end

  def test_strict_key_drops_punctuation_and_empties_to_nil
    assert_equal "شع", R.strict_key("شع.")
    assert_nil R.strict_key("...")
    assert_nil R.strict_key(nil)
  end

  # -- Lane headings ----------------------------------------------------------

  def test_unvocalized_multi_root_heading_splits
    assert_equal %w[كتع كتف كتل], R.heads("كتع كتف كتل")
    assert_equal %w[قلم قلو قلى قمّ], R.heads("قلم قلو قلى قمّ")
    assert_equal [%w[قلم قلم], %w[قلو قلء], %w[قلي قلء], %w[قم قم]], R.heading_keys("قلم قلو قلى قمّ")
  end

  def test_vocalized_heading_with_space_stays_one_head
    assert_equal ["مَشَقَ الخَطَّ"], R.heads("مَشَقَ الخَطَّ")
    assert_equal ["كتب"], R.heads("كتب")
  end
end
