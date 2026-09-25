# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Store::HieroPostingsBuilder (P103-2): the canonical/aed per-text
# hieroglyph walk tallied into the precompiled hiero_postings table —
# per glyph, distinct texts + total occurrences; glyphs inside
# <unclear> count (attested-but-damaged); an absent cone is the honest
# empty table.
class HieroPostingsBuilderTest < Minitest::Test
  include StoreTestDB

  FIXTURES = File.join(Nabu::TestSupport::FIXTURES_ROOT, "aed", "files")

  def setup
    @catalog = store_test_db
  end

  def with_canonical(&)
    Dir.mktmpdir do |dir|
      files = File.join(dir, "aed", "files")
      FileUtils.mkdir_p(files)
      Dir.glob(File.join(FIXTURES, "*_hiero.xml")).each { |f| FileUtils.cp(f, files) }
      yield dir
    end
  end

  def test_tallies_glyphs_per_text_and_occurrence
    with_canonical do |dir|
      summary = Nabu::Store::HieroPostingsBuilder.rebuild!(catalog: @catalog, canonical_dir: dir)
      assert_equal 2, summary.texts, "both fixture texts scanned"
      assert_operator summary.glyphs, :>, 50, "the glyph-bearing fixture attests many distinct signs"
      assert_equal summary.rows, @catalog[:hiero_postings].sum(:signs)

      # 𓂋 (r, D21) appears in the glyph-bearing fixture; the all-unclear
      # fixture contributes nothing — so texts=1 for every glyph here.
      row = @catalog[:hiero_postings].first(glyph: "𓂋")
      refute_nil row, "a known sign of the run has its row"
      assert_equal 1, row[:texts]
      assert_operator row[:signs], :>=, 2, "𓂋 recurs within the text"

      unclear_glyph = @catalog[:hiero_postings].first(glyph: "𓋹")
      refute_nil unclear_glyph,
                 "glyphs inside <unclear> still count — attested-but-damaged is attested"
    end
  end

  def test_rebuild_is_drop_and_reproject
    with_canonical do |dir|
      Nabu::Store::HieroPostingsBuilder.rebuild!(catalog: @catalog, canonical_dir: dir)
      first = @catalog[:hiero_postings].count
      Nabu::Store::HieroPostingsBuilder.rebuild!(catalog: @catalog, canonical_dir: dir)
      assert_equal first, @catalog[:hiero_postings].count, "re-running never accretes"
    end
  end

  def test_absent_cone_is_the_honest_empty_table
    Dir.mktmpdir do |dir|
      summary = Nabu::Store::HieroPostingsBuilder.rebuild!(catalog: @catalog, canonical_dir: dir)
      assert_equal 0, summary.texts
      assert_equal 0, @catalog[:hiero_postings].count
    end
    summary = Nabu::Store::HieroPostingsBuilder.rebuild!(catalog: @catalog, canonical_dir: nil)
    assert_equal 0, summary.texts
  end
end
