# frozen_string_literal: true

require "test_helper"

# Nabu::Cyrl (P27-2): the shared Cyrillic ↔ scholarly-Latin table behind
# (a) the chu/orv/bul cross-script search fold (Normalize neutralization)
# and (b) the `--display translit` rendering for Cyrillic shelves.
#
# The table is CENSUS-BUILT, not assumed: the Latin side is damaskini's own
# ingested diplomatic layer (conllu FORM/lemma columns — š ž č ě ę ъ x, "ou"
# for оу, "št" for щ, j-iotation), the Cyrillic side the TOROT/UD-orv/
# wiktionary-cu fixture inventory. Sample strings below are real fixture
# bytes.
class CyrlTest < Minitest::Test
  # TOROT zogr 75108, exactly as stored (titlo U+0483, palatalization U+0484).
  ZOGR = "тъ васъ крьститъ дх҃омь ст҃ъꙇмь ꙇ огн҄емь·"

  # damaskini conllu berlinski.1 — the ingested Latin-diplomatic surface.
  BERLINSKI = "slnce to kolkoto ima světъ"

  # -- neutralize: the search skeleton (lowercase input) ---------------------

  def test_neutralize_maps_the_owner_incident_pair_to_one_skeleton
    # The 2026-07-18 incident: vъsta (damaskini Latin-diplomatic) vs въста
    # (Cyrillic shelves) — the same word, one skeleton.
    assert_equal Nabu::Cyrl.neutralize("vъsta"), Nabu::Cyrl.neutralize("въста")
  end

  def test_neutralize_passes_latin_diplomatic_text_through_where_it_is_the_skeleton
    assert_equal BERLINSKI, Nabu::Cyrl.neutralize(BERLINSKI)
  end

  def test_neutralize_transliterates_real_torot_bytes
    # Combining marks (titlo/palatalization) ride through on their letters —
    # the generic fold strips them later; neutralization never does.
    assert_equal "tъ vasъ krьstitъ dx҃omь st҃ъimь i ogn҄emь·",
                 Nabu::Cyrl.neutralize(ZOGR)
  end

  def test_neutralize_widens_shta_and_the_sht_digraph_to_one_skeleton
    # щ ≡ шт ≡ "št" (damaskini berlinski.4 "šte"; the widening, not a guess).
    assert_equal Nabu::Cyrl.neutralize("щедроты"), Nabu::Cyrl.neutralize("штедроты")
    assert_equal "štedroty", Nabu::Cyrl.neutralize("щедроты")
  end

  def test_neutralize_widens_ou_digraphs_both_scripts_to_u
    # veles conllu "oubi" (= оуби), upstream's own lemma "ubija"; Cyrillic оу
    # and plain у likewise. Symmetric widening — a genuine o+u hiatus
    # (поучение) collapses identically on both sides.
    assert_equal "ubi", Nabu::Cyrl.neutralize("oubi")
    assert_equal "ubi", Nabu::Cyrl.neutralize("оуби")
    assert_equal "ubi", Nabu::Cyrl.neutralize("уби")
    assert_equal Nabu::Cyrl.neutralize("поучение"), Nabu::Cyrl.neutralize("poučenie")
  end

  def test_neutralize_maps_jotated_vowels_and_short_i_to_j_forms
    assert_equal "ljubovь", Nabu::Cyrl.neutralize("любовь")
    assert_equal "ja", Nabu::Cyrl.neutralize("я")
    assert_equal "ję", Nabu::Cyrl.neutralize("ѩ")
    assert_equal "jǫ", Nabu::Cyrl.neutralize("ѭ")
    assert_equal "našej", Nabu::Cyrl.neutralize("нашей")
  end

  def test_neutralize_maps_yat_yuses_and_yery_variants
    assert_equal "světъ", Nabu::Cyrl.neutralize("свѣтъ")
    assert_equal "pęt", Nabu::Cyrl.neutralize("пѧт")
    assert_equal "rǫka", Nabu::Cyrl.neutralize("рѫка")
    assert_equal "y", Nabu::Cyrl.neutralize("ы")
    assert_equal "y", Nabu::Cyrl.neutralize("ꙑ")
  end

  def test_neutralize_maps_letterform_variants_by_fixture_census
    assert_equal "i", Nabu::Cyrl.neutralize("ꙇ"), "zogr's ꙇ (A647)"
    assert_equal "i", Nabu::Cyrl.neutralize("і")
    assert_equal "u", Nabu::Cyrl.neutralize("ꙋ"), "ud-orv monograph uk"
    assert_equal "ot", Nabu::Cyrl.neutralize("ѿ"), "ud-orv ot-ligature"
    assert_equal "o", Nabu::Cyrl.neutralize("ѡ")
    assert_equal "v", Nabu::Cyrl.neutralize("ѵ"), "izhitsa as damaskini's own diplomatic renders it (Paraskevi)"
    assert_equal "dz", Nabu::Cyrl.neutralize("ѕ")
    assert_equal "ks", Nabu::Cyrl.neutralize("ѯ")
    assert_equal "ps", Nabu::Cyrl.neutralize("ѱ")
  end

  def test_neutralize_keeps_the_jers_distinct
    # No ingested layer attests an ambiguous apostrophe-jer (kól'koto lives
    # only in the NON-ingested accented TSV column) — so the fold stays
    # narrow: ъ and ь are distinct skeleton letters, never conflated.
    refute_equal Nabu::Cyrl.neutralize("vъ"), Nabu::Cyrl.neutralize("vь")
  end

  def test_neutralize_keeps_shared_literal_residues_untouched
    # ѳ/ћ/џ ride literal in BOTH layers (damaskini keeps them in its Latin
    # text); identity is the honest cross-script mapping. The th/f readings
    # of ѳ are not widenable and are deliberately not guessed.
    assert_equal "ѳ", Nabu::Cyrl.neutralize("ѳ")
    assert_equal "ћ", Nabu::Cyrl.neutralize("ћ")
  end

  def test_neutralize_decomposes_unlisted_precomposed_cyrillic
    # torot's ӑ (а + breve, precomposed): the base letter maps, the mark
    # rides through for the generic fold to strip.
    assert_equal "ă", Nabu::Cyrl.neutralize("ӑ")
  end

  def test_neutralize_with_map_points_every_skeleton_char_at_its_source
    neutral, map = Nabu::Cyrl.neutralize_with_map("оуби щ")
    assert_equal "ubi št", neutral
    assert_equal neutral.length, map.length
    assert_equal 0, map[0], "u ← оу attributes to the digraph's first char"
    assert_equal 2, map[1], "b ← б"
    assert_equal 4, map[3], "space maps through"
    assert_equal [5, 5], map[4, 2], "š and t both ← щ"
  end

  def test_neutralize_with_map_is_byte_identical_to_neutralize
    [ZOGR, BERLINSKI, "oubi", "поучение", "ѿ ꙋ ѕѣло"].each do |text|
      neutral, map = Nabu::Cyrl.neutralize_with_map(text)
      assert_equal Nabu::Cyrl.neutralize(text), neutral
      assert_equal neutral.length, map.length
    end
  end

  # -- to_translit: the --display translit rendering -------------------------

  def test_to_translit_renders_cyrillic_case_aware_and_leaves_latin_alone
    assert_equal "Tъ vasъ krьstitъ", Nabu::Cyrl.to_translit("Тъ васъ крьститъ")
    assert_equal BERLINSKI, Nabu::Cyrl.to_translit(BERLINSKI),
                 "damaskini's own Latin surface is already the transliteration — render-only honesty"
  end

  def test_to_translit_does_not_apply_the_latin_side_search_widenings
    # ou→u is a SEARCH widening; the display transliteration never rewrites
    # Latin text the source wrote.
    assert_equal "oubi", Nabu::Cyrl.to_translit("oubi")
    assert_equal "ubi", Nabu::Cyrl.to_translit("оуби"), "Cyrillic оу renders u — deterministic, scholarly"
  end

  def test_to_translit_renders_scholarly_values_with_diacritics
    assert_equal "světъ", Nabu::Cyrl.to_translit("свѣтъ")
    assert_equal "Št", Nabu::Cyrl.to_translit("Щ"), "digraph capitals render title-case"
    assert_equal "rǫka", Nabu::Cyrl.to_translit("рѫка")
  end

  def test_to_translit_keeps_combining_marks_on_their_letters
    # Titla are the default display MODE's business (strip lists), never the
    # transcoder's: translit output keeps every mark the stored bytes carry.
    assert_equal "dx҃omь", Nabu::Cyrl.to_translit("дх҃омь")
  end
end
