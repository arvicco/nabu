# frozen_string_literal: true

require "test_helper"

class NormalizeTest < Minitest::Test
  # NFD-decomposed polytonic Greek "andra" (ἄνδρα), built from explicit
  # codepoints so the fixture stays decomposed regardless of how the editor or
  # filesystem stores the file bytes:
  #   alpha U+03B1 + psili U+0313 + oxia U+0301 + nu + delta + rho + alpha
  NFD_ANDRA = "ἄνδρα"
  # Precomposed NFC form: U+1F04 (alpha with psili and oxia) + nu + delta + rho + alpha
  NFC_ANDRA = "ἄνδρα"

  def test_decomposed_greek_normalizes_to_precomposed
    refute_equal NFC_ANDRA, NFD_ANDRA, "fixture must actually be decomposed"
    assert_equal NFC_ANDRA, Nabu::Normalize.nfc(NFD_ANDRA)
  end

  def test_already_nfc_round_trips_unchanged
    assert_equal NFC_ANDRA, Nabu::Normalize.nfc(NFC_ANDRA)
  end

  def test_result_is_utf8
    assert_equal Encoding::UTF_8, Nabu::Normalize.nfc(NFD_ANDRA).encoding
  end

  def test_invalid_utf8_bytes_raise_nabu_error
    invalid = "\xC3(".b # truncated 2-byte sequence: not valid UTF-8
    assert_raises(Nabu::Error) { Nabu::Normalize.nfc(invalid) }
  end

  def test_bytes_tagged_utf8_but_ill_formed_raise
    invalid = "abc\xFF".dup.force_encoding("UTF-8")
    assert_raises(Nabu::Error) { Nabu::Normalize.nfc(invalid) }
  end

  def test_plain_ascii_round_trips
    assert_equal "hello", Nabu::Normalize.nfc("hello")
  end

  # -- fold_diacritics (P4-1 search form) ----------------------------------

  def test_fold_strips_polytonic_greek_accents_and_breathings
    # μῆνιν (perispomeni), ἄνδρα (breathing+oxia), ᾠδή (iota subscript),
    # ῥαψῳδία (rough breathing + iota subscript) → bare letters.
    assert_equal "μηνιν", Nabu::Normalize.fold_diacritics("μῆνιν")
    assert_equal "ανδρα", Nabu::Normalize.fold_diacritics("ἄνδρα")
    assert_equal "ωδη", Nabu::Normalize.fold_diacritics("ᾠδή")
    assert_equal "ραψωδια", Nabu::Normalize.fold_diacritics("ῥαψῳδία")
  end

  def test_fold_strips_latin_diacritics
    assert_equal "cafe", Nabu::Normalize.fold_diacritics("café")
  end

  def test_fold_leaves_undecorated_text_unchanged
    assert_equal "μηνιν", Nabu::Normalize.fold_diacritics("μηνιν")
    assert_equal "hello", Nabu::Normalize.fold_diacritics("hello")
  end

  def test_fold_result_is_nfc_utf8
    folded = Nabu::Normalize.fold_diacritics("μῆνιν")
    assert_equal Encoding::UTF_8, folded.encoding
    assert_equal folded, folded.unicode_normalize(:nfc)
  end

  # -- search_form: the per-language rule table (P6-4, conventions.md §9) ----

  def form(text, language) = Nabu::Normalize.search_form(text, language: language)

  def test_greek_folds_marks_case_and_final_sigma
    # Real fixture text: Homeric Hymn 13.1 has "Δημήτηρ’", 13.3 ends "ἀοιδῆς."
    assert_equal "δημητηρ", form("Δημήτηρ", "grc")
    assert_equal "αοιδησ", form("ἀοιδῆς", "grc"), "final ς must normalize to σ"
    # Ruby's #downcase maps Σ→σ unconditionally, so all-caps input converges too.
    assert_equal "λογοσ", form("ΛΟΓΟΣ", "grc")
  end

  def test_greek_iota_subscript_is_stripped_as_a_combining_mark
    # ᾳ is NFD alpha + U+0345 ypogegrammeni (category Mn): the generic mark
    # strip removes it. Adscript iota spelled as a full letter (αι) is NOT
    # folded — documented open question in conventions.md §9.
    assert_equal "ωδη", form("ᾠδή", "grc")
    assert_equal "α", form("ᾳ", "grc")
    assert_equal "α", form("ᾼ", "grc")
  end

  def test_greek_script_subtag_uses_the_greek_rule
    assert_equal "αοιδησ", form("ἀοιδῆς", "grc-Grek")
  end

  def test_latin_folds_v_to_u_and_j_to_i
    # PHI/Perseus practice: Latin search does not distinguish u/v or i/j.
    assert_equal "arma uirumque cano", form("Arma Virumque cano", "lat")
    assert_equal "iulius", form("Julius", "lat")
    assert_equal "iuuenemque", form("iuvenemque", "lat") # Perseus Ausonius fixture word
  end

  def test_ocs_titlo_and_palatalization_strip_but_letterforms_survive
    # Real TOROT zogr fixture forms: дх҃омь (U+0483 titlo), огн҄емь (U+0484
    # palatalization), ст҃ъꙇмь (titlo + the ꙇ letterform, which must survive —
    # letterform normalization is deliberately NOT done, conventions.md §9).
    assert_equal "дхомь", form("дх҃омь", "chu")
    assert_equal "огнемь", form("огн҄емь", "chu")
    assert_equal "стъꙇмь", form("ст҃ъꙇмь", "chu")
  end

  def test_old_east_slavic_gets_the_generic_fold_only
    # й is NFD и + U+0306 breve (Mn), so it folds to и — a documented side
    # effect of the generic mark strip, not a letterform rule.
    assert_equal "всякии", form("всякий", "orv")
  end

  def test_gothic_and_sanskrit_get_the_generic_fold_only
    # Gothic romanization uses j as a real letter: it must NOT be folded to i.
    assert_equal "jah qiþands", form("jah qiþands", "got")
    # Vedic Sanskrit (UD fixture, IAST): diacritics strip; they are phonemic,
    # which is the documented price of diacritic-insensitive search.
    assert_equal "krsna", form("kṛṣṇa", "san")
    assert_equal "samdihya", form("saṃdihya", "san")
  end

  def test_unknown_language_gets_the_generic_fold
    assert_equal "cafe", form("Café", "xx")
  end

  def test_search_form_is_nfc_utf8
    folded = form("ᾠδαῖς", "grc")
    assert_equal Encoding::UTF_8, folded.encoding
    assert folded.unicode_normalized?(:nfc)
  end

  # -- query_forms: the query-side union (P6-4) ------------------------------

  def test_query_forms_returns_the_generic_form_first
    assert_equal ["cafe"], Nabu::Normalize.query_forms("Café")
  end

  def test_query_forms_adds_variants_only_when_they_differ
    assert_equal %w[μηνις μηνισ], Nabu::Normalize.query_forms("μῆνις")
    assert_equal %w[jah iah], Nabu::Normalize.query_forms("jah")
    assert_equal ["aurora"], Nabu::Normalize.query_forms("aurora")
  end

  # THE union invariant that makes every per-language document form findable:
  # for any query and any language rule L, search_form(query, L) is among
  # query_forms(query) — so a query spelled the way the source spells it
  # always folds (on some variant) to exactly the indexed form.
  def test_query_forms_covers_every_language_rule
    samples = ["ἀοιδῆς", "Arma Virumque", "jah", "дх҃омь", "kṛṣṇa", "Café"]
    languages = %w[grc lat chu orv got san xx]
    samples.each do |sample|
      variants = Nabu::Normalize.query_forms(sample)
      languages.each do |language|
        assert_includes variants, form(sample, language),
                        "query_forms(#{sample.inspect}) must cover the #{language} document form"
      end
    end
  end
end
