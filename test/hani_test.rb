# frozen_string_literal: true

require "test_helper"

# Nabu::Hani (P37-2): the COMMITTED generated table — these tests pin the
# artifact the suite actually ships, not the generator (which has its own
# tests in test/ops/hani_fold_builder_test.rb). Every character pinned here
# is real Unihan 17.0.0 data; if a future `rake fold:hani` regeneration
# changes one of these verdicts, that is a REAL fold change (the §9
# rebuild-storm caveat) and the pin must be re-argued, not weakened.
class HaniTest < Minitest::Test
  def test_provenance_names_the_held_unihan_version
    assert_equal "17.0.0", Nabu::Hani::UNIHAN_VERSION
    assert_equal "2025-07-24", Nabu::Hani::UNIHAN_DATE
  end

  def test_the_flagship_cluster_folds_to_one_traditional_skeleton
    # 說 (traditional) / 説 (z-variant glyph) / 说 (simplified) — the packet's
    # own example: one indexed skeleton, canonical = 說 (what kanripo/cbeta
    # store, and the lowest codepoint of the 說/説 z-cluster).
    assert_equal "說說說", Nabu::Hani.fold("說説说")
  end

  def test_direct_simplified_to_traditional_pairs
    assert_equal "亞", Nabu::Hani::TABLE["亚"]
    assert_equal "愛", Nabu::Hani::TABLE["爱"]
    assert_equal "馬", Nabu::Hani::TABLE["马"]
  end

  def test_z_cluster_members_fold_to_the_cluster_canonical
    assert_equal "吳", Nabu::Hani::TABLE["吴"] # simplified, self-listing, z-warranted
    assert_equal "吳", Nabu::Hani::TABLE["呉"] # Japanese glyph, same cluster
    assert_equal "値", Nabu::Hani::TABLE["值"] # anchorless z-pair → lowest codepoint
    assert_equal "悅", Nabu::Hani::TABLE["悦"] # mutual kZVariant + trad/simp pair
  end

  def test_the_one_cycle_resolves_to_the_lowest_codepoint
    # 奨 (U+5968) ↔ 奬 (U+596C) is the sole cycle in 17.0.0's three fields:
    # both resolve to 奨, and the chain from simplified 奖 lands there too.
    assert_equal "奨", Nabu::Hani::TABLE["奬"]
    assert_equal "奨", Nabu::Hani::TABLE["奖"]
    assert_nil Nabu::Hani::TABLE["奨"]
  end

  def test_self_listing_characters_are_their_own_traditional_words_and_stay
    # Each lists ITSELF among its kTraditionalVariant targets — it is a
    # traditional character in its own right (了 vs 瞭, 台 in 天台 vs 臺):
    # folding would merge distinct words. Conservative refusal, censused.
    %w[了 台 体 单 么 乐 时].each do |char|
      assert_nil Nabu::Hani::TABLE[char], "#{char} must not fold (self-listing traditional word)"
    end
  end

  def test_cross_cluster_ambiguity_is_refused
    # 发 → 發 (emit) / 髮 (hair): two different traditional words — picking
    # one would be a guess. Neither direction folds.
    assert_nil Nabu::Hani::TABLE["发"]
    assert_nil Nabu::Hani::TABLE["發"]
    assert_nil Nabu::Hani::TABLE["髮"]
  end

  def test_semantic_variants_are_not_folded_the_refusal_pin
    # 㐀 kSemanticVariant 丘, 㐫 kSemanticVariant 凶 (mutual, and ONLY
    # semantic) — different WORDS meaning the same thing; the owner-agreed
    # line: folding them is a lie. The fields never enter the graph.
    assert_nil Nabu::Hani::TABLE["㐀"]
    assert_nil Nabu::Hani::TABLE["㐫"]
    assert_nil Nabu::Hani::TABLE["凶"]
    assert_equal "㐀丘㐫凶", Nabu::Hani.fold("㐀丘㐫凶")
  end

  def test_every_pair_is_single_codepoint_and_every_value_a_fixed_point
    Nabu::Hani::TABLE.each do |from, to|
      assert_equal 1, from.length
      assert_equal 1, to.length
      refute Nabu::Hani::TABLE.key?(to),
             "#{to.inspect} is a fold target but also a key — chains must resolve to fixed points"
    end
  end

  def test_table_scale_matches_the_generation_census
    # 6,050 pairs from Unihan 17.0.0 (5,973 direct + 8 cluster-resolved +
    # 70 z-members, minus identities). A regeneration that moves this number
    # changed the fold — re-argue the pins above.
    assert_equal 6050, Nabu::Hani::TABLE.size
  end

  def test_fold_is_per_codepoint_so_char_by_char_equals_whole_string
    # The fold_with_map safety property (Normalize composes the fold per
    # character for KWIC maps).
    text = "不亦説乎，学而时习之"
    whole = Nabu::Hani.fold(text)
    per_char = text.each_char.map { |c| Nabu::Hani.fold(c) }.join
    assert_equal whole, per_char
  end
end
