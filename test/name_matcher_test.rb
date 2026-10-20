# frozen_string_literal: true

require "test_helper"
require_relative "support/legacy_name_scan"

# Nabu::NameMatcher — the Aho-Corasick multi-name substring matcher behind
# the place mine. Its contract is EQUIVALENCE with the bucket scan it
# replaced: the same distinct names per text, in the same order (first
# occurrence position, longer name first at a shared start). Every test
# here compares against the verbatim legacy oracle.
class NameMatcherTest < Minitest::Test
  def assert_equivalent(names, texts)
    matcher = Nabu::NameMatcher.new(names)
    buckets = LegacyNameScan.buckets(names)
    texts.each do |text|
      assert_equal LegacyNameScan.scan(text, buckets), matcher.scan(text),
                   "hit list (set AND order) differs from the legacy scan on #{text.inspect}"
    end
  end

  def test_overlapping_and_prefix_sharing_names
    names = %w[霸州 霸州城 州城 順天 順天府 天府 府尹 天府之國 之國]
    texts = %w[臣至霸州城見順天府尹 天府之國 霸州霸州城州城 順天府天府之國之國 府尹順天]
    assert_equivalent(names, texts)
  end

  def test_names_at_string_edges_and_whole_text
    names = %w[長安 安西 西州 長安西州]
    texts = %w[長安 長安西州 西州 安西州 長安西 州長安]
    assert_equivalent(names, texts + ["", "長", "安"])
  end

  def test_suffix_names_reported_through_failure_links
    # 甲乙丙丁 contains 乙丙丁 and 丙丁 as suffixes; 乙丙 as an inner name.
    names = %w[甲乙丙丁 乙丙丁 丙丁 乙丙 丁戊]
    texts = %w[甲乙丙丁戊 甲乙丙 乙丙丁戊 甲甲乙丙丁丁戊]
    assert_equivalent(names, texts)
  end

  def test_shared_first_character_bucket_collisions
    # one long bucket: many names opening with the same character, of
    # mixed lengths, only some of which match at each start.
    names = %w[東京 東平 東平府 東海 東海郡 東萊 東萊郡 東郡 東陽 東陽縣 平府 海郡 郡東]
    texts = ["東平府東海郡東萊郡東陽縣", "東郡東京東", "郡東平東海", "東" * 12]
    assert_equivalent(names, texts)
  end

  def test_repeated_occurrences_report_once
    names = %w[洛陽 陽洛]
    assert_equivalent(names, ["洛陽洛陽洛陽陽洛洛陽"])
  end

  def test_supplementary_plane_characters_and_mixed_scripts
    names = %w[𠀀𠀁 𠀁州 a州 州b]
    texts = %w[𠀀𠀁州b xa州b𠀀 𠀁𠀁州]
    assert_equivalent(names, texts)
  end

  def test_empty_name_set_matches_nothing
    assert_equal [], Nabu::NameMatcher.new([]).scan("霸州")
  end

  # The property sweep: a tiny alphabet forces dense overlaps, shared
  # prefixes and suffix chains far beyond the hand cases above.
  def test_randomized_equivalence_over_a_dense_alphabet
    rng = Random.new(20_261_020)
    alphabet = %w[州 府 東 西 天 長 安 𠀀]
    40.times do
      names = Array.new(rng.rand(1..60)) { Array.new(rng.rand(2..5)) { alphabet.sample(random: rng) }.join }.uniq
      texts = Array.new(50) { Array.new(rng.rand(0..40)) { alphabet.sample(random: rng) }.join }
      assert_equivalent(names, texts)
    end
  end
end
