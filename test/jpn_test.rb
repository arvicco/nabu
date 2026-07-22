# frozen_string_literal: true

require "test_helper"

# Nabu::Jpn (P38-4 / P38-r1): the COMMITTED generated kyūjitai↔shinjitai fold —
# these tests pin the artifact the suite ships, not the generator (which has its
# own tests in test/ops/jpn_fold_builder_test.rb). Every character pinned here is
# real held data (Unihan 17.0.0 kJinmeiyoKanji/kJoyoKanji + KANJIDIC2 2026-202
# variants); if a future `rake fold:jpn` regeneration changes one of these
# verdicts, that is a REAL fold change (the §9 rebuild-storm caveat) and the pin
# must be re-argued, not weakened.
class JpnTest < Minitest::Test
  def test_provenance_names_the_held_source_versions
    assert_equal "17.0.0", Nabu::Jpn::UNIHAN_VERSION
    assert_equal "2025-07-24", Nabu::Jpn::UNIHAN_DATE
    assert_equal "2026-202", Nabu::Jpn::KANJIDIC_VERSION
    assert_equal "2026-07-21", Nabu::Jpn::KANJIDIC_DATE
  end

  def test_the_census_scale_matches_the_generation_report
    # census: 744 fold entries, 2026-07-21 (173 jinmeiyō + 341 kanjidic 1:1 +
    # 79 merges over 185 old forms). NEW/OLD (the SEMANTIC kyūjitai relation)
    # stays the 173 authoritative jinmeiyō pairs — the kanjidic lane is fold-
    # only. 2 one-to-many olds refused, 0 jinmeiyō conflicts, 57 NFC dropped.
    # Moving any of these is a real fold change — re-argue the pins.
    assert_equal 173, Nabu::Jpn::NEW_TO_OLD.size
    assert_equal 173, Nabu::Jpn::OLD_TO_NEW.size
    assert_equal 744, Nabu::Jpn::TABLE.size
  end

  def test_flagship_shinjitai_fold_to_their_kyujitai_skeleton
    # The workhorse jinmeiyō-lane reform pairs — modern form folds to the
    # old/traditional skeleton so a query for either finds both.
    assert_equal "國", Nabu::Jpn.fold("国")
    assert_equal "廣", Nabu::Jpn.fold("広")
    assert_equal "圓", Nabu::Jpn.fold("円")
    assert_equal "眞", Nabu::Jpn.fold("真")
    assert_equal "惠", Nabu::Jpn.fold("恵")
  end

  def test_the_four_famous_non_name_reform_pairs_now_land_via_kanjidic
    # 學/学, 體/体, 醫/医, 觀/観 — the highest-frequency reform pairs whose old
    # form is NOT a name-kanji, so LANE 1 (jinmeiyō) could not reach them.
    # LANE 2 (kanjidic-jōyō) lands them: each pair is reachable through fold
    # equality (both spellings collapse to one skeleton).
    { "學" => "学", "體" => "体", "醫" => "医", "觀" => "観" }.each do |old, new|
      assert_equal Nabu::Jpn.fold(old), Nabu::Jpn.fold(new),
                   "#{old}/#{new} must be reachable through fold equality"
    end
    assert_equal "學", Nabu::Jpn.fold("学")
    assert_equal "學", Nabu::Jpn.fold("學"), "the skeleton is a fixed point"
  end

  def test_reform_merges_are_admitted_and_reachable_through_fold_equality
    # Owner ruling 2026-07-21: admit the merges (match modern reading habits).
    # 辨/瓣/辯 all fold together with 弁 onto 弁's skeleton, so a search for 弁
    # finds all three. The glyph-literal escape hatch is `nabu search --exact`.
    %w[辨 瓣 辯].each do |old|
      assert_equal Nabu::Jpn.fold("弁"), Nabu::Jpn.fold(old), "#{old} must fold with 弁"
    end
    assert_equal Nabu::Hani.fold("弁"), Nabu::Jpn.fold("辨"),
                 "the merge lands on 弁's own skeleton (Hani.fold(弁))"
    # 斈 (itaiji of 學) is admitted too, folding onto 学's skeleton.
    assert_equal Nabu::Jpn.fold("学"), Nabu::Jpn.fold("斈")
  end

  def test_the_chinese_lane_stays_distinct_the_merge_lives_only_in_jpn
    # The lzh/och Han fold must keep 辨/瓣/辯 apart — they are three live
    # distinct Chinese words. The Japanese merge is a jpn-only convenience.
    refute_equal Nabu::Hani.fold("辨"), Nabu::Hani.fold("瓣")
    refute_equal Nabu::Hani.fold("瓣"), Nabu::Hani.fold("辯")
  end

  def test_reform_pairs_cross_reference_stays_authoritative_jinmeiyo_only
    # NEW_TO_OLD / OLD_TO_NEW back the char card's kyūjitai↔shinjitai note and
    # stay the authoritative jinmeiyō pairs (国/國). The KANJIDIC2-mined pairs
    # (医/醫) and merges (弁) are FOLD-only — a kanjidic <variant> link is not a
    # reliable "old form", so they are absent from the semantic cross-reference.
    assert_equal "國", Nabu::Jpn.old_form("国")
    assert_equal "国", Nabu::Jpn.new_form("國")
    assert_nil Nabu::Jpn.old_form("医"), "kanjidic-mined pairs are fold-only, not semantic"
    assert_nil Nabu::Jpn.old_form("弁"), "a merge has no single 'the' kyūjitai"
  end

  def test_composition_with_hani_lands_on_one_shared_skeleton
    # jpn's canonical == Hani.fold(kyūjitai) for 1:1 pairs, so a Japanese
    # new/old form and the Chinese trad/simp forms index identically.
    assert_equal Nabu::Hani.fold("國"), Nabu::Jpn.fold("国")
    assert_equal "國", Nabu::Hani.fold("國")
  end

  def test_one_to_many_ambiguous_olds_stay_literal
    # 碕 is variant-linked to two jōyō forms (崎 AND 埼) → refused (never pick
    # arbitrarily), so it folds to nothing (stays itself).
    assert_equal "碕", Nabu::Jpn.fold("碕")
  end

  def test_every_pair_is_single_codepoint_and_every_value_a_fixed_point
    Nabu::Jpn::TABLE.each do |from, to|
      assert_equal 1, from.length
      assert_equal 1, to.length
      refute Nabu::Jpn::TABLE.key?(to),
             "#{to.inspect} is a fold target but also a key — must be a fixed point"
    end
  end

  def test_fold_is_per_codepoint_so_char_by_char_equals_whole_string
    # The fold_with_map safety property (Normalize composes the fold per
    # character for KWIC maps).
    text = "国の廣さと學び"
    whole = Nabu::Jpn.fold(text)
    per_char = text.each_char.map { |c| Nabu::Jpn.fold(c) }.join
    assert_equal whole, per_char
  end

  def test_gsub_fold_is_byte_identical_to_the_tr_translation
    # P39-3 replaced tr(FROM, TO) with gsub(FOLD_RE, TABLE) on the jpn lane
    # too (aozora folds every passage). The two must be BYTE-identical.
    from = Nabu::Jpn::FROM
    to = Nabu::Jpn::TO
    assert_equal from.tr(from, to), Nabu::Jpn.fold(from), "the whole FROM string"
    assert_equal to, Nabu::Jpn.fold(from), "…and the whole FROM folds to TO exactly"
    ["国の廣さと學び", "普通の日本語の文章です。", ""].each do |sample|
      assert_equal sample.tr(from, to), Nabu::Jpn.fold(sample), "byte-identity on #{sample.inspect}"
    end
  end
end
