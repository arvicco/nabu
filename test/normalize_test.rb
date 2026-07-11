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

  def test_akkadian_folds_cuneiform_transliteration_to_bare_sign_readings
    # P10-1 (conventions.md §9): sign-join punctuation (./-) and determinative
    # braces open to spaces — each sign reading becomes its own searchable
    # token — and subscript index digits normalize to ASCII. Double/trailing
    # spaces are deliberate (the rule is per-codepoint so fold_with_map stays
    # exact); the FTS tokenizer collapses separator runs anyway.
    assert_equal "du un nu um ki ", form("du-un-nu-um{ki}", "akk")
    assert_equal "zi3", form("ZI₃", "akk")
    assert_equal " d en zu se mi", form("{d}EN.ZU-še-mi", "akk")
    # š/ṣ/ṭ and vowel macrons fall to the generic mark strip, not this rule
    assert_equal "gesbun", form("GEŠBUN", "akk")
    assert_equal "situ", form("ṣītu", "akk")
    assert_equal "qemu", form("qēmu", "akk")
  end

  def test_sumerian_shares_the_cuneiform_rule
    assert_equal " d amar  d suen", form("{d}amar-{d}suen", "sux")
    assert_equal "urim5 ki  ma", form("urim₅{ki}-ma", "sux")
  end

  def test_old_english_folds_ash_thorn_and_eth_to_ascii
    # P12-3 (conventions.md §9): æ→ae, þ→th, ð→th — the transliterations a
    # user types, and B-T's own alphabetization (its <sort> field folds æ to
    # "ae" and buckets ð/þ identically: æðele → "aetþele", þing → "tþing").
    # All words are real Bosworth-Toller fixture headwords.
    assert_equal "aethele", form("æðele", "ang")
    assert_equal "thing", form("þing", "ang")
    assert_equal "th", form("Þ", "ang") # downcase runs before the rule
    assert_equal "aethelbald", form("Æðelbald", "ang")
    assert_equal "theahhwaethere", form("þeáhhwæðere", "ang")
    # vowel length (acute, macron) falls to the generic mark strip, not this rule
    assert_equal "ac", form("ác", "ang")
    assert_equal "ae", form("ǣ", "ang")
  end

  def test_slovene_folds_bohoric_long_s_to_s
    # P13-9 (conventions.md §9): ſ→s. The long s survives the generic fold
    # (plain downcase does not apply Unicode full case folding, which maps
    # U+017F ſ → s), so Bohorič-print words would be unfindable by any
    # modern query. All words are real goo300k fixture surface forms
    # (Dalmatin 1584); haček letters fall to the generic mark strip.
    assert_equal "svoje", form("ſvoje", "sl")
    assert_equal "dvanajst", form("dvanajſt", "sl")
    assert_equal "oblast", form("oblaſt", "sl")
    # generic strip handles the modern diacritics; ſ-free words untouched
    assert_equal "cez", form("čez", "sl")
    assert_equal "studente", form("študente", "sl")
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
    assert_equal %w[þing thing], Nabu::Normalize.query_forms("þing")
    assert_equal ["aurora"], Nabu::Normalize.query_forms("aurora")
    # the akk/sux rule shares one lambda, so its variant appears once
    assert_equal ["a-na", "a na"], Nabu::Normalize.query_forms("a-na")
    assert_equal ["zi₃", "zi3"], Nabu::Normalize.query_forms("ZI₃")
  end

  # THE union invariant that makes every per-language document form findable:
  # for any query and any language rule L, search_form(query, L) is among
  # query_forms(query) — so a query spelled the way the source spells it
  # always folds (on some variant) to exactly the indexed form.
  def test_query_forms_covers_every_language_rule
    samples = ["ἀοιδῆς", "Arma Virumque", "jah", "дх҃омь", "kṛṣṇa", "Café", "du-un-nu-um{ki}", "ZI₃", "æðele"]
    languages = %w[grc lat chu orv got san akk sux ang xx]
    samples.each do |sample|
      variants = Nabu::Normalize.query_forms(sample)
      languages.each do |language|
        assert_includes variants, form(sample, language),
                        "query_forms(#{sample.inspect}) must cover the #{language} document form"
      end
    end
  end

  # -- fold_with_map: char-aligned fold for KWIC (P8-3) ----------------------

  # THE equality the concordance rests on: the char-by-char fold must produce
  # byte-identically what search_form produces, so a query folded via
  # search_form is found in the fold_with_map output.
  def test_fold_with_map_folded_string_equals_search_form
    ["μῆνιν ἄειδε θεά", "ἄρχε δ’ ἀοιδῆς", "Arma Virumque Iustitiam",
     "дх҃омь ст҃ъꙇмь", "jah qiþands", "þeáh-hwæðere and ǽg-ðer"].each do |text|
      %w[grc grc lat chu got ang].each do |language|
        folded, = Nabu::Normalize.fold_with_map(text, language: language)
        assert_equal Nabu::Normalize.search_form(text, language: language), folded
      end
    end
  end

  # THE mapping-correctness test: locate the folded keyword in a Greek passage
  # carrying combining marks and map back to the PRISTINE accented span. The
  # fold is not length-preserving, so a naive index would slice the wrong span.
  def test_fold_with_map_maps_a_folded_match_back_to_the_pristine_span
    text = "θεὰ μῆνιν ἄειδε"
    folded, map = Nabu::Normalize.fold_with_map(text, language: "grc")
    index = folded.index("μηνιν")
    start = map[index]
    finish = map[index + "μηνιν".length - 1] + 1
    assert_equal "μῆνιν", Nabu::Normalize.nfc(text).chars[start...finish].join
  end

  # A combining mark that folds away entirely contributes nothing to the map,
  # keeping every surviving index exact even when the source is decomposed.
  def test_fold_with_map_handles_a_stripped_combining_mark
    nfd = "άειδε" # alpha + combining acute + ειδε → "αειδε"
    folded, map = Nabu::Normalize.fold_with_map(nfd, language: "grc")
    assert_equal "αειδε", folded
    assert_equal folded.length, map.length
    # nfc collapses α+acute into ά (one char), so every folded char maps in range.
    assert(map.all? { |i| i < Nabu::Normalize.nfc(nfd).chars.length })
  end
end
