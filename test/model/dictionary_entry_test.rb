# frozen_string_literal: true

require "test_helper"

# DictionaryEntry + DictionaryReflex (P14-1): the reconstruction shelf adds
# machine-readable descendant edges (reflexes) to dictionary entries — the
# citation pattern exactly: a validated value the parser mints and the
# loader persists, resolved at query time only.
class DictionaryEntryTest < Minitest::Test
  def reflex(**overrides)
    Nabu::DictionaryReflex.new(
      lang_code: "cu", language: "chu", word: "богъ",
      roman: nil, word_folded: "богъ", roman_folded: nil, **overrides
    )
  end

  def entry(**overrides)
    Nabu::DictionaryEntry.new(
      entry_id: "bogъ:noun", key_raw: "bogъ", language: "sla-pro",
      headword: "bogъ", headword_folded: "bogъ", body: "god", **overrides
    )
  end

  # --- DictionaryReflex ---------------------------------------------------------

  def test_reflex_carries_upstream_code_mapped_language_and_folds
    r = reflex
    assert_equal "cu", r.lang_code
    assert_equal "chu", r.language
    assert_equal "богъ", r.word
    assert_equal "богъ", r.word_folded
    assert_nil r.roman
    assert_nil r.roman_folded
  end

  def test_reflex_roman_and_its_fold_travel_together
    r = reflex(lang_code: "got", language: "got", word: "𐌲𐌿𐌸",
               roman: "guþ", word_folded: "𐌲𐌿𐌸", roman_folded: "guþ")
    assert_equal "guþ", r.roman
    assert_equal "guþ", r.roman_folded
  end

  def test_reflex_requires_word_and_codes
    assert_raises(Nabu::ValidationError) { reflex(word: "") }
    assert_raises(Nabu::ValidationError) { reflex(lang_code: nil) }
    assert_raises(Nabu::ValidationError) { reflex(language: "Not A Code") }
  end

  # --- DictionaryEntry#reflexes ---------------------------------------------------

  def test_entry_reflexes_default_empty_and_frozen
    assert_equal [], entry.reflexes
    assert entry.reflexes.frozen?
  end

  def test_entry_accepts_reflexes_and_rejects_non_reflex_values
    e = entry(reflexes: [reflex])
    assert_equal ["богъ"], e.reflexes.map(&:word)
    assert e.reflexes.frozen?

    assert_raises(Nabu::ValidationError) { entry(reflexes: ["not a reflex"]) }
    assert_raises(Nabu::ValidationError) { entry(reflexes: nil) }
  end

  def test_reconstruction_language_codes_pass_validation
    %w[sla-pro ine-pro gem-pro].each do |code|
      assert_equal code, entry(language: code).language
    end
  end

  # --- the hbo/arc NFC exemption on the dictionary surface (P30-2) ---------------

  # Masoretic pointing is not NFC-stable (dagesh ccc 21 written before vowel
  # points ccc 10-19); the P26-3 owner ruling stores hbo/arc bytes verbatim.
  # Passage already routes exempt text through verbatim validation — the
  # dictionary surface must too, or no pointed Hebrew headword could ever
  # construct. בֹּהוּ below is a real SDBH lemma in upstream byte order.
  BOHU = "בֹּהוּ"

  def test_exempt_language_entries_accept_non_nfc_hebrew_byte_verbatim
    refute BOHU.unicode_normalized?(:nfc), "the fixture premise: upstream mark order is not NFC"
    e = entry(language: "hbo", headword: BOHU, key_raw: BOHU,
              headword_folded: "בהו", body: "glosses: emptiness #{BOHU}")
    assert_equal BOHU, e.headword, "bytes exactly as upstream shipped them"
    assert_includes e.body, BOHU
    assert e.headword_folded.unicode_normalized?(:nfc), "the search form keeps the NFC contract"
  end

  def test_exempt_language_gloss_is_verbatim_too
    e = entry(language: "arc", gloss: BOHU)
    assert_equal BOHU, e.gloss
  end

  def test_non_exempt_languages_still_reject_non_nfc_text
    assert_raises(Nabu::ValidationError) { entry(language: "grc", headword: BOHU) }
    assert_raises(Nabu::ValidationError) { entry(language: "grc", body: BOHU) }
  end

  def test_exempt_entries_still_reject_empty_and_invalid_text
    assert_raises(Nabu::ValidationError) { entry(language: "hbo", headword: "") }
    assert_raises(Nabu::ValidationError) { entry(language: "hbo", body: "") }
    assert_raises(Nabu::ValidationError) { entry(language: "hbo", headword: "\xC3".b) }
  end
end
