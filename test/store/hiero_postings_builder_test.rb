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
      assert_equal summary.rows, @catalog[:hiero_postings].where(code: nil).sum(:signs)
      assert_equal summary.rows + summary.code_signs, @catalog[:hiero_postings].sum(:signs)

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

  # The finer attestation grain the stand-off files carry beside the
  # flat tally: WORD tokens (<w corresp="src:tla…">) attesting the
  # glyph, and occurrences read inside <unclear> (damaged). Expected
  # values counted by hand-script over the glyph-bearing fixture.
  def test_records_word_grain_and_damaged_occurrences
    with_canonical do |dir|
      Nabu::Store::HieroPostingsBuilder.rebuild!(catalog: @catalog, canonical_dir: dir)
      r = @catalog[:hiero_postings].first(glyph: "𓂋")
      assert_equal [42, 39, 2], [r[:signs], r[:words], r[:unclear]],
                   "𓂋: 42 occurrences over 39 word tokens, 2 of them damaged"
      n = @catalog[:hiero_postings].first(glyph: "𓈖")
      assert_equal [67, 62, 4], [n[:signs], n[:words], n[:unclear]]
      ankh = @catalog[:hiero_postings].first(glyph: "𓋹")
      assert_equal [1, 1, 1], [ankh[:signs], ankh[:words], ankh[:unclear]],
                   "the sign attested only inside <unclear> is wholly damaged"
      assert_operator @catalog[:hiero_postings].where { words > signs }.count, :zero?
    end
  end

  # Signs without a codepoint ride as <w><note>Keine Entsprechung in
  # Unicode für D31A-A1</note></w>: the Gardiner-coded payloads tally
  # into CODE-keyed rows beside the glyph rows. Expected values counted
  # by hand-script over the glyph-bearing fixture's 51 notes (42 coded,
  # 2 of those inside <unclear>; 9 "diese Graphien").
  def test_tallies_gardiner_coded_notes_into_code_rows
    with_canonical do |dir|
      summary = Nabu::Store::HieroPostingsBuilder.rebuild!(catalog: @catalog, canonical_dir: dir)
      codes = @catalog[:hiero_postings].exclude(code: nil)
      assert_equal 56, codes.count, "56 distinct Gardiner codes posted"
      assert_equal 111, codes.sum(:signs), "111 coded sign occurrences"
      assert_equal 12, codes.sum(:unclear), "12 of them inside <unclear>-wrapped notes"
      assert_equal 56, summary.codes
      assert_equal 111, summary.code_signs
      assert codes.all? { |row| row[:glyph].nil? }, "a code row never stuffs the code into glyph"
      assert(@catalog[:hiero_postings].where(code: nil).all? { |row| row[:glyph] })

      # A hyphen-joined spelling posts every member: X1 recurs in 8 notes.
      assert_equal [1, 8, 8, 0], code_grain("X1")
      # Repeats inside one spelling: 3 occurrences, ONE word (S38-N29 ×3).
      assert_equal [1, 3, 1, 0], code_grain("S38")
      # "D31A-A1" sits inside <unclear>: damaged; A1 also posts undamaged.
      assert_equal [1, 1, 1, 1], code_grain("D31A")
      assert_equal [1, 4, 4, 1], code_grain("A1")
      # Damage brackets strip: "[[-I9-]]" ×2 → I9.
      assert_equal [1, 2, 2, 0], code_grain("I9")
      # "O50-2" ×5: the code posts; the numeral is screened.
      assert_equal [1, 5, 5, 0], code_grain("O50")
      assert_equal [1, 2, 2, 0], code_grain("V32B")
      assert_equal [1, 1, 1, 0], code_grain("P112")
      refute @catalog[:hiero_postings].first(code: "2"), "a bare numeral is never a code row"
      assert_operator codes.where { words > signs }.count, :zero?
    end
  end

  # The untalliable remainder is censused, never silently dropped:
  # "für diese Graphien" notes and grammar-failing tokens.
  def test_censuses_the_untalliable_remainder
    with_canonical do |dir|
      summary = Nabu::Store::HieroPostingsBuilder.rebuild!(catalog: @catalog, canonical_dir: dir)
      assert_equal 51, summary.remainder.notes, "every Keine-Entsprechung note seen"
      assert_equal 9, summary.remainder.graphien, "9 'diese Graphien' notes (all inside <unclear>)"
      assert_equal({ "2" => 7, "3" => 2 }, summary.remainder.screened,
                   "numeral tokens (O50-2, T22-W24-2, Aa1-D52-X1-3…) screened out")
    end
  end

  def test_the_gardiner_grammar_mirrors_the_sign_card
    assert_equal Nabu::Query::HieroCard::CODE, Nabu::Store::HieroPostingsBuilder::CODE
  end

  def test_the_key_is_exactly_one_of_glyph_or_code
    assert_raises(Sequel::ConstraintViolation) do
      @catalog[:hiero_postings].insert(glyph: "𓂋", code: "D21", texts: 1, signs: 1)
    end
    assert_raises(Sequel::ConstraintViolation) do
      @catalog[:hiero_postings].insert(texts: 1, signs: 1)
    end
    @catalog[:hiero_postings].insert(code: "D21", texts: 1, signs: 1)
    assert_raises(Sequel::UniqueConstraintViolation) do
      @catalog[:hiero_postings].insert(code: "D21", texts: 1, signs: 1)
    end
  end

  def test_rebuild_is_drop_and_reproject
    with_canonical do |dir|
      Nabu::Store::HieroPostingsBuilder.rebuild!(catalog: @catalog, canonical_dir: dir)
      first = @catalog[:hiero_postings].count
      coded = code_grain("X1")
      Nabu::Store::HieroPostingsBuilder.rebuild!(catalog: @catalog, canonical_dir: dir)
      assert_equal first, @catalog[:hiero_postings].count, "re-running never accretes"
      assert_equal coded, code_grain("X1"), "code rows reproject identically"
    end
  end

  def code_grain(code)
    @catalog[:hiero_postings].first(code: code).values_at(:texts, :signs, :words, :unclear)
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
