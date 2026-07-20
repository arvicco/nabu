# frozen_string_literal: true

require "test_helper"

class NormalizeTest < Minitest::Test
  # 2026-07-20 incident regression: the owner's many-hour kanripo sync died
  # at the FIRST parse-time nfc call with LoadError on the stdlib's lazy
  # `require "unicode_normalize/normalize"` (String#unicode_normalize defers
  # it to first use; under late-run resource exhaustion, require's load-path
  # probe fails and masquerades as "cannot load such file"). The stdlib must
  # therefore be loaded EAGERLY when nabu/normalize loads — long syncs may
  # never depend on a first-use require surviving hours into a run.
  def test_unicode_normalize_stdlib_is_loaded_eagerly_not_on_first_use
    # A fresh interpreter, nabu loaded, NO nfc call made — the stdlib must
    # already be in $LOADED_FEATURES (in-process assertion would be vacuous:
    # this suite has long since triggered the lazy path).
    lib = File.expand_path("../lib", __dir__)
    out = Nabu::Shell.run(
      RbConfig.ruby, "-I", lib, "-r", "nabu",
      "-e", 'puts $LOADED_FEATURES.any? { |f| f.include?("unicode_normalize/normalize") }'
    )
    assert_equal "true", out.strip,
                 "unicode_normalize/normalize must be required at load time by lib/nabu/normalize.rb"
  end

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

  def test_ocs_titlo_and_palatalization_strip_and_the_skeleton_crosses_scripts
    # Real TOROT zogr fixture forms: дх҃омь (U+0483 titlo), огн҄емь (U+0484
    # palatalization), ст҃ъꙇмь (titlo + the ꙇ letterform). Since P27-2 the chu
    # form is the CROSS-SCRIPT skeleton (Cyrl neutralization → generic fold):
    # marks still strip, and the letters land on the Latin-diplomatic side of
    # the damaskini bridge (ꙇ → i by the censused letterform table — the §9
    # "letterform variants" open question, answered by the cross-script fold).
    assert_equal "dxomь", form("дх҃омь", "chu")
    assert_equal "ognemь", form("огн҄емь", "chu")
    assert_equal "stъimь", form("ст҃ъꙇмь", "chu")
  end

  def test_old_east_slavic_folds_to_the_same_skeleton
    # й maps to j in the Cyrl table (scholarly practice, нашей → našej) —
    # before P27-2 it fell to the generic breve strip (и).
    assert_equal "vsjakij", form("всякий", "orv")
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

  def test_coptic_strips_editorial_marks_but_keeps_letters
    # P17-1 (conventions.md §9): the ⳿ morphological divider (U+2CFF, Po —
    # the one non-Mn editorial mark in the diplomatic layer) deletes; the
    # supralinear strokes and overlines (U+FE24–26 half marks, combining
    # dot/diaeresis) are Mn and fall to the generic strip. All words are
    # real Coptic Scriptorium fixture surface forms (besa.letters).
    assert_equal "ⲙⲏⲣ", form("ⲙⲏⲣ⳿", "cop")
    assert_equal "ⲧⲉⲧⲛ", form("ⲧⲉⲧ︤ⲛ︥", "cop")
    assert_equal "ⲉⲡⲟⲩⲟⲧⲟⲩⲉⲧ", form("ⲉⲡⲟⲩⲟⲧⲟⲩⲉⲧ⳿", "cop")
    assert_equal "ⲁⲩⲱ", form("Ⲁⲩⲱ̇", "cop") # downcase + dot-above strip
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

  def test_reconstruction_shelves_fold_modifier_letters_to_ascii
    # P14-10 (conventions.md §9): the phonetic superscripts ʰ (U+02B0) → h and
    # ʷ (U+02B7) → w — the ONLY Unicode modifier letters (Lm) in the three
    # reconstruction extracts' 13,053 headwords (census: ʰ ×516, ʷ ×193, no
    # other). They survive the generic fold (Lm, not the stripped Mn), so an
    # ASCII typist's "bhewgh"/"gwhew" could never reach *bʰewgʰ-/*gʷʰew-
    # without this rule. Combining marks over the base letters (the é acute
    # here) still fall to the generic strip.
    assert_equal "bhewgh-", form("bʰewgʰ-", "ine-pro")
    assert_equal "gwhew-", form("gʷʰew-", "ine-pro")
    assert_equal "medhyos", form("médʰyos", "ine-pro")
    assert_equal "bogъ", form("bogъ", "sla-pro"), "no modifier letters — the jer stays"
    assert_equal "þunraz", form("þunraz", "gem-pro"), "þ is a base letter, kept"
    assert_equal "guda", form("gudą", "gem-pro"), "the ogonek is combining — generic strip"
    # Scoped to the reconstruction pseudo-languages: an attested code (no
    # corpus carries a collective code) keeps the superscripts.
    assert_equal "bʰewgʰ", form("bʰewgʰ", "chu")
  end

  def test_p17_3_proto_fold_extensions_for_the_new_shelves
    # P17-3 (conventions.md §9): the four new extracts add ˢ (U+02E2) → s,
    # ᶻ (U+1DBB) → z (Proto-Indo-Iranian sibilant clusters; ˢ×12 ᶻ×9
    # measured) and ˀ (U+02C0) → dropped (Proto-Balto-Slavic laryngeal
    # notation, ×310 in headwords — a 1→0 gsub, fold_with_map-safe). The
    # itc/iir primary subtags join the shared proto lambda; ine-bsl-pro
    # already folds under "ine"; gmw-pro carries NO modifier letters
    # (measured) and deliberately has no key.
    assert_equal "adzdhah", form("adᶻdʰáH", "iir-pro")
    assert_equal "witstas", form("witˢtás", "iir-pro")
    assert_equal "kwis", form("kʷis", "itc-pro")
    assert_equal "warna", form("wárˀnāˀ", "ine-bsl-pro"), "ˀ drops entirely under the ine key"
    assert_equal "hlaib", form("hlaib", "gmw-pro"), "gmw: generic fold only, nothing to do"
    # fold_with_map stays byte-identical to search_form under the 1→0 drop.
    folded, map = Nabu::Normalize.fold_with_map("wárˀnāˀ", language: "ine-bsl-pro")
    assert_equal "warna", folded
    assert_equal folded.length, map.length
  end

  def test_egyptological_transliteration_folds_to_ascii
    # P28-1 (conventions.md §9): the Egyptological alef ꜣ (U+A723) and ain ꜥ
    # (U+A725) are base letters with NO decomposition — the generic fold
    # leaves them — and ʾ (U+02BE MODIFIER LETTER RIGHT HALF RING) is Lm,
    # untouched exactly like the proto superscripts. Census over all 35,052
    # AED headwords: ꜣ ×12,753 (+Ꜣ ×284), ꜥ ×6,451 (+Ꜥ ×357), ʾ ×1,036 are
    # the only letters the generic fold cannot reach; every dotted/lined
    # consonant (ḥ ḫ ẖ š ṯ ḏ ṱ) decomposes and falls to the Mn strip. All
    # words are real AED fixture headwords.
    assert_equal "aj.wj", form("ꜣj.wj", "egy")
    assert_equal "aa", form("ꜥꜣ", "egy")
    assert_equal "hap-r", form("ḥꜣp-rʾ", "egy"), "ʾ drops entirely — no ASCII typist spells it"
    assert_equal "abd", form("Ꜣbḏ", "egy"), "downcase maps Ꜣ→ꜣ (U+A722→U+A723) before the rule"
    assert_equal "hai", form("ḥꜣi̯", "egy"), "the semivowel breve (U+032F) is Mn — generic strip"
    assert_equal "hw.t-ka", form("ḥw.t-kꜣ", "egy"), "compound punctuation is text, kept"
    # fold_with_map stays byte-identical to search_form under the 1→0 ʾ drop.
    folded, map = Nabu::Normalize.fold_with_map("ḥꜣp-rʾ", language: "egy")
    assert_equal "hap-r", folded
    assert_equal folded.length, map.length
  end

  def test_unknown_language_gets_the_generic_fold
    assert_equal "cafe", form("Café", "xx")
  end

  def test_search_form_is_nfc_utf8
    folded = form("ᾠδαῖς", "grc")
    assert_equal Encoding::UTF_8, folded.encoding
    assert folded.unicode_normalized?(:nfc)
  end

  # -- the per-language NFC exemption (P26-3, owner ruling 2026-07-18) -------

  def test_nfc_exempt_names_hebrew_and_biblical_aramaic_only
    assert Nabu::Normalize.nfc_exempt?("hbo")
    assert Nabu::Normalize.nfc_exempt?("arc")
    assert Nabu::Normalize.nfc_exempt?("hbo-Hebr"), "primary-subtag scoping, like LANGUAGE_FOLDS"
    refute Nabu::Normalize.nfc_exempt?("grc")
    refute Nabu::Normalize.nfc_exempt?("he"), "the exemption names the ancient codes the corpus uses"
    refute Nabu::Normalize.nfc_exempt?(nil)
  end

  def test_hebrew_search_form_folds_nfc_unstable_wlc_bytes_to_bare_letters
    # Upstream WLC bytes (Ruth 1:1 בִּימֵי֙): dagesh U+05BC precedes hiriq
    # U+05B4 — NOT NFC (canonical order swaps them). The SEARCH side folds
    # through NFC + mark strip regardless, so lookups are unaffected by the
    # byte-verbatim storage exemption.
    wlc = "\u05D1\u05BC\u05B4\u05D9\u05DE\u05B5\u05D9\u0599"
    refute wlc.unicode_normalized?(:nfc)
    assert_equal "בימי", Nabu::Normalize.search_form(wlc, language: "hbo")
    # fold-both-sides: a pointed query reaches the same bare-letter form.
    assert_includes Nabu::Normalize.query_forms(wlc), "בימי"
    assert_equal "בראשית", Nabu::Normalize.search_form("בְּרֵאשִׁ֖ית", language: "hbo"),
                 "an unpointed modern query meets pointed Masoretic text"
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
    # P14-10: the proto rule (gem/ine/sla share one lambda) adds an ASCII
    # variant when a superscript is present; a typed-ASCII form needs none.
    assert_equal %w[bʰewgʰ bhewgh], Nabu::Normalize.query_forms("bʰewgʰ")
    assert_equal ["bhewgh"], Nabu::Normalize.query_forms("bhewgh")
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
     "дх҃омь ст҃ъꙇмь", "jah qiþands", "þeáh-hwæðere and ǽg-ðer",
     "ⲙ︤ⲛ︥ⲛⲉⲧⲙⲏⲣ⳿ ⲉⲧⲉⲛⲉⲧⲙⲟⲕ︤ϩ︥"].each do |text|
      %w[grc grc lat chu got ang cop].each do |language|
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

  # -- script neutralization (P27-2): cross-script fold, both sides ----------

  # OWNER REPRO (2026-07-18a): `search 'धर्मन्'` was a silent miss while
  # `search dharman` hit — query_forms stripped the virāma (Mn) before any
  # transcode could see it. The neutralization runs Deva→IAST FIRST, on both
  # sides, so the Devanagari spelling and the IAST spelling are ONE form.
  def test_search_form_neutralizes_devanagari_before_the_virama_strip
    assert_equal "dharman", Nabu::Normalize.search_form("धर्मन्", language: "san")
    assert_equal Nabu::Normalize.search_form("dharman", language: "san"),
                 Nabu::Normalize.search_form("धर्मन्", language: "san")
  end

  def test_query_forms_covers_the_devanagari_spelling
    assert_includes Nabu::Normalize.query_forms("धर्मन्"), "dharman",
                    "the reflex-render Devanagari form pasted into search --lemma must fold to the DCS lemma form"
  end

  # OWNER REPRO (2026-07-18b): `search vъsta` (damaskini's Latin-diplomatic
  # surface) and `search въста` (the Cyrillic shelves) returned DISJOINT
  # result sets for the same word. Both spellings now fold to one skeleton,
  # in the index (search_form) and in the query union (query_forms).
  def test_slavic_search_forms_cross_the_script_boundary
    %w[chu orv bul].each do |language|
      assert_equal Nabu::Normalize.search_form("vъsta", language: language),
                   Nabu::Normalize.search_form("въста", language: language),
                   "#{language}: one word, one skeleton"
    end
    %w[vъsta въста].each do |spelling|
      variants = Nabu::Normalize.query_forms(spelling)
      assert_includes variants, Nabu::Normalize.search_form("vъsta", language: "chu"),
                      "query_forms(#{spelling}) must cover the indexed skeleton"
    end
  end

  def test_slavic_neutralization_folds_real_torot_bytes_to_the_skeleton
    assert_equal "tъ vasъ krьstitъ dxomь stъimь i ognemь·",
                 Nabu::Normalize.search_form("тъ васъ крьститъ дх҃омь ст҃ъꙇмь ꙇ огн҄емь·", language: "chu")
  end

  def test_slavic_neutralization_is_symmetric_on_the_u_digraph_widening
    # veles "oubi" (Latin) = оуби (Cyrillic); upstream's own lemma is ubija.
    assert_equal Nabu::Normalize.search_form("oubi", language: "chu"),
                 Nabu::Normalize.search_form("оуби", language: "chu")
    assert_includes Nabu::Normalize.query_forms("оуби"), "ubi"
  end

  # The round-trip property, both neutralized scripts: a query spelled the
  # way the source spells it folds — on some variant — to exactly the
  # indexed form. (The §9 union invariant, extended to neutralization.)
  def test_query_forms_covers_every_neutralized_document_form
    samples = {
      "san" => ["धर्मन्", "नारायणं नमस्कृत्य", "kṛṣṇa"],
      "chu" => %w[крьститъ vъsta щедроты oubi],
      "orv" => %w[Петрушъка нашей],
      "bul" => %w[světъ поучение]
    }
    samples.each do |language, texts|
      texts.each do |text|
        assert_includes Nabu::Normalize.query_forms(text),
                        Nabu::Normalize.search_form(text, language: language),
                        "query_forms(#{text.inspect}) must cover the #{language} document form"
      end
    end
  end

  # Unaffected languages keep their exact pre-P27-2 forms — neutralization is
  # scoped by primary subtag, never a global rewrite.
  def test_neutralization_leaves_other_languages_untouched
    assert_equal "μηνισ", Nabu::Normalize.search_form("μῆνις", language: "grc")
    assert_equal "бимь", Nabu::Normalize.search_form("бимь", language: "sl"),
                 "Cyrillic bytes under a NON-neutralized language stay Cyrillic"
  end

  def test_fold_with_map_equality_extends_to_neutralized_languages
    { "धर्मः पुरुषस्य" => "san", "тъ васъ крьститъ дх҃омь" => "chu",
      "slnce to kolkoto ima světъ" => "bul", "и оуби нашей ѿ" => "orv" }.each do |text, language|
      folded, map = Nabu::Normalize.fold_with_map(text, language: language)
      assert_equal Nabu::Normalize.search_form(text, language: language), folded
      assert_equal folded.length, map.length
    end
  end

  # Mapping correctness across the script boundary: a match located in the
  # Latin skeleton points back at the pristine CYRILLIC span (KWIC honesty).
  def test_fold_with_map_maps_a_skeleton_match_back_to_the_cyrillic_span
    text = "тъ васъ крьститъ"
    folded, map = Nabu::Normalize.fold_with_map(text, language: "chu")
    index = folded.index("krьstitъ")
    refute_nil index
    start = map[index]
    finish = map[index + "krьstitъ".length - 1] + 1
    assert_equal "крьститъ", Nabu::Normalize.nfc(text).chars[start...finish].join
  end

  # -- the Han variant fold (P37-2) ------------------------------------------

  # The §9 contract for lzh: trad/simp/z spellings of one character index as
  # ONE traditional skeleton — 說 (stored by kanripo/cbeta), 説 (z-variant
  # glyph in Japanese-transmitted editions), 说 (what a modern typist types).
  def test_lzh_search_form_folds_variants_to_the_traditional_skeleton
    assert_equal "不亦說乎", Nabu::Normalize.search_form("不亦說乎", language: "lzh")
    assert_equal "不亦說乎", Nabu::Normalize.search_form("不亦説乎", language: "lzh")
    assert_equal "不亦說乎", Nabu::Normalize.search_form("不亦说乎", language: "lzh")
  end

  # och dictionary headwords (Baxter-Sagart, TLS) fold by the same table, so
  # a simplified-typed lookup reaches the traditional headword's entry.
  def test_och_headwords_fold_like_lzh
    assert_equal "說", Nabu::Normalize.search_form("说", language: "och")
    assert_equal "馬", Nabu::Normalize.search_form("马", language: "och")
  end

  # The union invariant extends to the Han fold: a query spelled in ANY of
  # the variant forms covers the indexed lzh/och skeleton.
  def test_query_forms_covers_the_han_variant_spellings
    %w[不亦說乎 不亦説乎 不亦说乎].each do |query|
      variants = Nabu::Normalize.query_forms(query)
      %w[lzh och].each do |language|
        assert_includes variants, form(query, language),
                        "query_forms(#{query.inspect}) must cover the #{language} document form"
      end
    end
  end

  # Refusals hold at the fold boundary: self-listing characters are their own
  # traditional words (时/了/台), and semantic variants never fold (㐀/丘) —
  # the conservative line, censused on Nabu::Ops::HaniFoldBuilder.
  def test_lzh_search_form_leaves_refused_characters_alone
    assert_equal "时了台㐀丘", Nabu::Normalize.search_form("时了台㐀丘", language: "lzh")
  end

  # Other languages are byte-unchanged: the fold is keyed lzh/och only.
  # Japanese keeps its shinjitai (値段 stays; 呉 would fold under lzh), and
  # the unihan shelf's zho headwords stay literal on both spellings.
  def test_han_fold_leaves_other_languages_untouched
    # (mark-free text: the GENERIC fold already strips kana dakuten as \p{Mn},
    # pre-P37-2 behavior — the pin here is about Han codepoints only)
    assert_equal "値段の学問", Nabu::Normalize.search_form("値段の学問", language: "ja")
    assert_equal "说文解字", Nabu::Normalize.search_form("说文解字", language: "zho")
    assert_equal "呉音", Nabu::Normalize.search_form("呉音", language: "jpn")
    assert_equal "μηνισ", Nabu::Normalize.search_form("μῆνις", language: "grc")
  end

  # fold_with_map equality extends to the Han fold (per-codepoint 1→1), and
  # a skeleton match points back at the pristine variant-glyph span.
  def test_fold_with_map_equality_extends_to_lzh
    %w[不亦説乎 子曰學而時習之 说文解字注].each do |text|
      folded, map = Nabu::Normalize.fold_with_map(text, language: "lzh")
      assert_equal Nabu::Normalize.search_form(text, language: "lzh"), folded
      assert_equal folded.length, map.length
    end
  end

  def test_fold_with_map_maps_a_han_skeleton_match_back_to_the_pristine_span
    text = "不亦説乎"
    folded, map = Nabu::Normalize.fold_with_map(text, language: "lzh")
    index = folded.index("說")
    refute_nil index
    assert_equal "説", Nabu::Normalize.nfc(text).chars[map[index]]
  end
end
