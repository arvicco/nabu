# frozen_string_literal: true

require "test_helper"

# Nabu::Jpn (P38-4): the COMMITTED generated kyūjitai↔shinjitai fold — these
# tests pin the artifact the suite ships, not the generator (which has its own
# tests in test/ops/jpn_fold_builder_test.rb). Every character pinned here is
# real Unihan 17.0.0 kJinmeiyoKanji data; if a future `rake fold:jpn`
# regeneration changes one of these verdicts, that is a REAL fold change (the
# §9 rebuild-storm caveat) and the pin must be re-argued, not weakened.
class JpnTest < Minitest::Test
  def test_provenance_names_the_held_unihan_version
    assert_equal "17.0.0", Nabu::Jpn::UNIHAN_VERSION
    assert_equal "2025-07-24", Nabu::Jpn::UNIHAN_DATE
  end

  def test_the_census_scale_matches_the_generation_report
    # 230 raw kJinmeiyoKanji pointers − 57 NFC-identity (compat ideographs) =
    # 173 reform pairs and 173 fold entries. Moving this number is a real fold
    # change — re-argue the pins below.
    assert_equal 173, Nabu::Jpn::NEW_TO_OLD.size
    assert_equal 173, Nabu::Jpn::TABLE.size
    assert_equal 173, Nabu::Jpn::OLD_TO_NEW.size
  end

  def test_flagship_shinjitai_fold_to_their_kyujitai_skeleton
    # The workhorse reform pairs — modern form folds to the old/traditional
    # skeleton so a query for either finds both.
    assert_equal "國", Nabu::Jpn.fold("国")
    assert_equal "廣", Nabu::Jpn.fold("広")
    assert_equal "圓", Nabu::Jpn.fold("円")
    assert_equal "眞", Nabu::Jpn.fold("真")
    assert_equal "藝", Nabu::Jpn.fold("芸")
    assert_equal "惠", Nabu::Jpn.fold("恵")
  end

  def test_reform_pairs_cross_reference_both_directions
    # NEW_TO_OLD / OLD_TO_NEW back the char card's kyūjitai↔shinjitai note.
    assert_equal "國", Nabu::Jpn.old_form("国")
    assert_equal "国", Nabu::Jpn.new_form("國")
    assert_nil Nabu::Jpn.old_form("學"), "not a shinjitai — no reform pointer"
    assert_nil Nabu::Jpn.new_form("学"), "學/学 is not a jinmeiyō pair (out of scope)"
  end

  def test_composition_with_hani_lands_on_one_shared_skeleton
    # The composition rule: jpn's canonical == Hani.fold(kyūjitai), so a
    # Japanese new/old form and the Chinese trad/simp forms index identically.
    assert_equal Nabu::Hani.fold("國"), Nabu::Jpn.fold("国")
    assert_equal Nabu::Hani.fold("国"), Nabu::Jpn.fold("国")
    assert_equal "國", Nabu::Hani.fold("國")
  end

  def test_the_hani_composed_pairs_fold_the_old_form_not_the_new
    # The 奨↔奬 cycle family: Unihan makes the shinjitai (揺/奨) the traditional
    # skeleton, so Hani.fold(搖)=揺. Composition means the OLD form folds onto
    # the new, and the pair is still recorded new=揺 / old=搖.
    assert_equal "揺", Nabu::Jpn.fold("搖")
    assert_equal "揺", Nabu::Jpn.fold("揺")
    assert_equal "搖", Nabu::Jpn.old_form("揺")
    assert_equal "揺", Nabu::Jpn.new_form("搖")
  end

  def test_reform_merges_are_refused_not_invented
    # The famous many-to-one reform merges (辨/瓣/辯 → 弁, 豫/預) are absent
    # from kJinmeiyoKanji AND the builder refuses to synthesise them: 弁 is
    # never a fold key, and no merged-away traditional is a fold target.
    assert_nil Nabu::Jpn::TABLE["弁"]
    refute Nabu::Jpn::NEW_TO_OLD.key?("弁"), "弁 must have no single 'the' kyūjitai"
    %w[辨 瓣 辯 豫].each do |merged|
      refute_includes Nabu::Jpn::TABLE.values, merged, "#{merged} must never be a fold target"
    end
  end

  def test_the_documented_coverage_bound_non_name_kyujitai_are_out_of_scope
    # kJinmeiyoKanji only covers kyūjitai that are registered name-kanji, so
    # the highest-frequency non-name reform pairs (學/学, 體/体, 醫/医, 觀/観)
    # are deliberately NOT folded — honest scope, pinned so it stays honest.
    %w[学 体 医 観].each do |shinjitai|
      assert_equal shinjitai, Nabu::Jpn.fold(shinjitai),
                   "#{shinjitai} is out of scope (kyūjitai not a name-kanji)"
    end
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
    text = "国の廣さと圓い眞珠"
    whole = Nabu::Jpn.fold(text)
    per_char = text.each_char.map { |c| Nabu::Jpn.fold(c) }.join
    assert_equal whole, per_char
  end
end
