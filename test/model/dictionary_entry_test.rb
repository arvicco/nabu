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

  # --- The P30-1 NFC exemption (Normalize::NFC_EXEMPT_LANGUAGES) ------------------

  # Upstream Masoretic bytes: bet + dagesh (ccc 21) BEFORE qamats (ccc 18) —
  # the mark order the WLC and the OSHB lexicon ship, which NFC would reorder
  # (the P26-3 owner ruling). Measured upstream: 4,053 LexicalIndex / 3,796
  # HebrewStrong / 4,720 BDB headwords are not NFC-normalized.
  # בָּרָא exactly as LexicalIndex.xml ships it: bet, dagesh, qamats, resh,
  # qamats, alef - spelled in escapes so no editor can silently reorder it.
  MASORETIC = "\u05D1\u05BC\u05B8\u05E8\u05B8\u05D0"

  def test_exempt_language_headword_gloss_and_body_stay_byte_verbatim
    refute MASORETIC.unicode_normalized?(:nfc), "the exemplar must exercise the exemption"
    %w[hbo arc].each do |language|
      e = entry(language: language, headword: MASORETIC, headword_folded: "ברא",
                gloss: MASORETIC, body: MASORETIC)
      assert_equal MASORETIC.bytes, e.headword.bytes, "#{language} headword must keep upstream byte order"
      assert_equal MASORETIC.bytes, e.gloss.bytes
      assert_equal MASORETIC.bytes, e.body.bytes
    end
  end

  def test_non_exempt_language_still_rejects_non_nfc_text
    assert_raises(Nabu::ValidationError) { entry(headword: MASORETIC) }
    assert_raises(Nabu::ValidationError) { entry(body: MASORETIC) }
    assert_raises(Nabu::ValidationError) { entry(gloss: MASORETIC) }
  end

  def test_exempt_language_headword_folded_stays_nfc_checked
    # The search form is minted NFC for every language (Normalize.search_form);
    # the exemption never widens to the folded lookup key.
    assert_raises(Nabu::ValidationError) do
      entry(language: "hbo", headword: MASORETIC, headword_folded: MASORETIC)
    end
  end
end
