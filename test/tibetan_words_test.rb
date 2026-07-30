# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::TibetanWords (P54-1) — Classical Tibetan word segmentation read back
# off Nabu's OWN publication (nabu-data xct/segmentation), the two-way loop
# closed: token counts over the published Form column train the promoted
# Nabu::TibetanSegmenter, and #segment splits running Tibetan text into
# words. Exercised against a real trimmed slice of the published CSV
# (test/fixtures/nabu-data/README.md); every expected split below is the
# published gold segmentation of the very rows in the slice.
class TibetanWordsTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("nabu-data")

  def words
    @words ||= Nabu::TibetanWords.load(FIXTURES)
  end

  # --- segmentation (published rows, verbatim) -------------------------------

  # The opening of buston:1 — rows 1-4 of the published CSV are exactly
  # these four tokens (Form and Offset columns, byte-verbatim): the seam
  # must reproduce its own gold on vocabulary it was trained from, clitic
  # splits included (བདེ་བར = བདེ་བ + terminative ར; གཤེགས་པའི = གཤེགས་པ +
  # genitive འི).
  def test_reproduces_the_published_gold_split_of_the_buston_opening
    tokens = words.segment("བདེ་བར་གཤེགས་པའི་")
    assert_equal %w[བདེ་བ ར་ གཤེགས་པ འི་], tokens.map(&:form)
    assert_equal [0, 5, 7, 14], tokens.map(&:offset)
  end

  # A clitic split through the seam on its own: the slice carries བདེ་བ
  # (count 1) and the terminative ར་ (count 10), so the split edge is
  # cheaper than two unknown tsheg-bars — deterministically.
  def test_a_terminative_clitic_splits_through_the_seam
    assert_equal %w[བདེ་བ ར་], words.segment("བདེ་བར་").map(&:form)
  end

  def test_tokens_are_the_segmenters_own_exact_substrings
    text = "བདེ་བར་གཤེགས་པའི་"
    tokens = words.segment(text)
    tokens.each do |token|
      assert_kind_of Nabu::TibetanSegmenter::Token, token
      assert_equal token.form, text[token.offset, token.form.length],
                   "every token must be the exact substring at its offset"
    end
  end

  # The slice census (300 gold rows, buston passages 1-4): 179 distinct
  # Form spellings feed the vocabulary. Pins the fixture's row set.
  def test_size_counts_the_distinct_published_forms
    assert_equal 179, words.size
  end

  # --- loading shapes --------------------------------------------------------

  # A missing dataset file loads empty (a partial tree stays honest): no
  # vocabulary, so the segmenter falls back to tsheg-bar grain — known
  # behavior pinned in the segmenter's own tests, visible through the seam.
  def test_a_missing_dataset_file_loads_empty_and_falls_back_to_tsheg_bars
    Dir.mktmpdir do |dir|
      empty = Nabu::TibetanWords.load(dir)
      assert_equal 0, empty.size
      assert_equal %w[བདེ་ བར་ གཤེགས་ པའི་], empty.segment("བདེ་བར་གཤེགས་པའི་").map(&:form)
    end
  end

  def test_load_default_feature_detects_the_canonical_tree
    Dir.mktmpdir do |root|
      config = Nabu::Config.new(canonical_dir: File.join(root, "canonical"),
                                db_dir: File.join(root, "db"),
                                sources_path: File.join(root, "sources.yml"), config_path: "(test)")
      assert_nil Nabu::TibetanWords.load_default(config: config),
                 "no canonical/nabu-data tree -> nil (the lila/cldf-spine posture)"
      dest = File.join(root, "canonical", "nabu-data")
      FileUtils.mkdir_p(dest)
      FileUtils.cp_r(Dir[File.join(FIXTURES, "*")], dest)
      live = Nabu::TibetanWords.load_default(config: config)
      refute_nil live
      assert_equal %w[བདེ་བ ར་], live.segment("བདེ་བར་").map(&:form)
    end
  end
end
