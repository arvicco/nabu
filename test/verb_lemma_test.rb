# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::VerbLemma (P54-3) — the Tibetan verb stem→lemma table read back off
# Nabu's OWN publication (nabu-data xct/verb-lemma), the second consume-back
# seam: given a queried tense stem (Tibetan script or Wylie), the paradigm
# lemma candidates with tense and grammarian attribution, disagreements
# deliberately uncollapsed. Exercised against a real trimmed slice of the
# published CSV (test/fixtures/nabu-data/README.md).
class VerbLemmaTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("nabu-data")

  def table
    @table ||= Nabu::VerbLemma.load(FIXTURES)
  end

  # --- lookup (published rows, verbatim) -------------------------------------

  # THE payoff case: a past stem no headword lookup could reach — only the
  # table knows བཀོངས is the past of ཀོང. And the SAME form also belongs
  # to the བཀོང paradigm (KN's analysis, line 60): both lemmas return.
  def test_a_past_stem_maps_to_every_lemma_that_claims_it
    candidates = table.lookup("བཀོངས")
    assert_equal([%w[ཀོང Past GT], %w[བཀོང Past KN]],
                 candidates.map { |c| [c.lemma, c.tense, c.analysis_source] })
  end

  def test_a_suppletive_past_reaches_its_lemma
    candidates = table.lookup("སོང")
    assert_equal ["འགྲོ"], candidates.map(&:lemma).uniq
    assert_equal ["Imperative"], candidates.map(&:tense).uniq
    assert_equal %w[GT KN PH TDC], candidates.map(&:analysis_source).sort
  end

  # --- the bracket notation (censused; class doc) ----------------------------

  # `ཀེར༼ད༽` (GT's Past/Imperative): BOTH the bracket-stripped base and the
  # suffix-applied variant are indexed, and they reach the same lemma.
  def test_an_optional_suffix_cell_indexes_base_and_suffixed_variants
    suffixed = table.lookup("ཀེརད")
    assert_equal([%w[ཀེར Past GT], %w[ཀེར Imperative GT]],
                 suffixed.map { |c| [c.lemma, c.tense, c.analysis_source] })
    base = table.lookup("ཀེར")
    assert_equal ["ཀེར"], base.map(&:lemma).uniq
    assert_operator base.map(&:tense).uniq.sort, :==, %w[Future Imperative Past Present],
                    "the bare spelling carries the base variant of every bracketed cell too"
  end

  # `སྐྱོལ༼ད༽༼སྐྱོལ༽` (two groups: optional suffix + alternate form):
  # all three concrete spellings reach the སྐྱེལ paradigm.
  def test_a_two_group_cell_expands_suffix_and_alternate
    assert_equal([%w[སྐྱེལ Imperative GT]],
                 table.lookup("སྐྱོལད").map { |c| [c.lemma, c.tense, c.analysis_source] })
    imperatives = table.lookup("སྐྱོལ")
    assert_equal ["སྐྱེལ"], imperatives.map(&:lemma).uniq
    assert_equal %w[GT KN PH TDC], imperatives.map(&:analysis_source).sort
  end

  # `འཆོར༼ད༽༼ཤོར༼ད༽༽` (a NESTED group — the alternate carries its own
  # optional suffix): ཤོརད reaches the lemma, whose published spelling is
  # itself bracketed (འཆོར༼ཤོར༽) and stays verbatim on the candidate.
  def test_a_nested_group_expands_and_the_lemma_stays_verbatim
    candidates = table.lookup("ཤོརད")
    assert_equal ["འཆོར༼ཤོར༽"], candidates.map(&:lemma).uniq,
                 "the published Lemma spelling, brackets and all — display honesty"
    assert_equal %w[Imperative Past], candidates.map(&:tense).sort
  end

  # --- multi-source honesty --------------------------------------------------

  # ཀེར appears in THREE rows (GT/TDC/PH — different grammarians'
  # analyses, deliberately uncollapsed upstream): all analyses return.
  def test_a_multi_source_lemma_returns_all_analyses_uncollapsed
    presents = table.lookup("ཀེར").select { |c| c.tense == "Present" }
    assert_equal %w[GT PH TDC], presents.map(&:analysis_source).sort,
                 "every grammarian's analysis stays visible — no tier laundering, no collapsing"
  end

  # --- the fold contract -----------------------------------------------------

  # The index key IS the house xct fold (EWTS transcode) — the same key
  # define's query side produces, so Wylie and script queries agree.
  def test_wylie_and_script_spellings_are_the_same_key
    assert_equal table.lookup("བཀོངས"), table.lookup("bkongs")
    assert_equal table.lookup("ཀེརད"), table.lookup("kerd")
    %w[བཀོངས ཀེར སྐྱོལ phyin].each do |form|
      assert_equal Nabu::Normalize.search_form(form, language: "xct"), Nabu::VerbLemma.fold(form),
                   "#{form}: VerbLemma.fold must equal Normalize.search_form(xct)"
    end
  end

  def test_unknown_forms_are_empty_and_do_not_grow_the_index
    size = table.size
    assert_empty table.lookup("ཟོག")
    assert_empty table.lookup("zzzznotastem")
    assert_empty table.lookup("")
    assert_equal size, table.size, "a miss must never memoize a key into the index"
  end

  # --- the bracket expander (the census shapes, pinned) ----------------------

  def test_expand_covers_the_censused_notation_shapes
    assert_equal %w[ཀེར], Nabu::VerbLemma.expand("ཀེར")
    assert_equal %w[ཀེར ཀེརད], Nabu::VerbLemma.expand("ཀེར༼ད༽")
    assert_equal %w[སྐྱོལ སྐྱོལད], Nabu::VerbLemma.expand("སྐྱོལ༼ད༽༼སྐྱོལ༽")
    assert_equal %w[འཆོར འཆོརད ཤོར ཤོརད], Nabu::VerbLemma.expand("འཆོར༼ད༽༼ཤོར༼ད༽༽")
    assert_equal %w[འཆོར ཤོར], Nabu::VerbLemma.expand("འཆོར༼ཤོར༽")
  end

  # --- loading shapes --------------------------------------------------------

  def test_a_missing_dataset_file_loads_empty
    Dir.mktmpdir do |dir|
      empty = Nabu::VerbLemma.load(dir)
      assert_equal 0, empty.size
      assert_empty empty.lookup("བཀོངས")
    end
  end

  def test_load_default_feature_detects_the_canonical_tree
    Dir.mktmpdir do |root|
      config = Nabu::Config.new(canonical_dir: File.join(root, "canonical"),
                                db_dir: File.join(root, "db"),
                                sources_path: File.join(root, "sources.yml"), config_path: "(test)")
      assert_nil Nabu::VerbLemma.load_default(config: config),
                 "no canonical/nabu-data tree -> nil (the lila/cldf-spine posture)"
      dest = File.join(root, "canonical", "nabu-data")
      FileUtils.mkdir_p(dest)
      FileUtils.cp_r(Dir[File.join(FIXTURES, "*")], dest)
      live = Nabu::VerbLemma.load_default(config: config)
      refute_nil live
      assert_equal "ཀོང", live.lookup("བཀོངས").first.lemma
    end
  end
end
