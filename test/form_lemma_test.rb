# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::FormLemma (P51-W6) — the Sanskrit form→lemma table read back off
# Nabu's OWN publication (nabu-data san/form-lemma), the two-way loop
# closed: given a query form (IAST or its ASCII fold), the lemma candidates
# with Lemma_ID and summed attestation counts. Exercised against a real
# trimmed slice of the published CSV (test/fixtures/nabu-data/README.md).
class FormLemmaTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("nabu-data")

  def table
    @table ||= Nabu::FormLemma.load(FIXTURES)
  end

  # --- lookup (published rows, verbatim) -------------------------------------

  # THE tier-2 case (D48-a): an s-stem instrumental the P48-r1 stem rule
  # cannot generate — only the table knows tapasā → tapas.
  def test_an_instrumental_the_stem_rule_cannot_reach_maps_to_its_lemma
    candidates = table.lookup("tapasā")
    assert_equal ["tapas"], candidates.map(&:lemma)
    tapas = candidates.first
    assert_equal "96401", tapas.lemma_id
    assert_equal "NOUN", tapas.pos
    assert_equal 1153, tapas.count, "tapasā (1,151) + the tapasa row (2) share the fold key"
  end

  def test_the_ascii_fold_reaches_the_same_candidates
    assert_equal table.lookup("tapasā"), table.lookup("tapasa"),
                 "IAST and its ASCII fold are the same key (the house san fold, both sides)"
  end

  # THE multi-lemma form: published rows map tapa to three lemmas (tapas
  # NOUN via sandhi, tap VERB, tapa NOUN) — all returned, count-descending.
  def test_a_multi_lemma_form_returns_every_candidate_count_descending
    candidates = table.lookup("tapa")
    assert_equal([%w[tapas 96401], %w[tap 157174], %w[tapa 96352]],
                 candidates.map { |c| [c.lemma, c.lemma_id] })
    assert_equal [118, 22, 13], candidates.map(&:count)
    assert_equal %w[NOUN VERB NOUN], candidates.map(&:pos)
  end

  # An Unsandhied ≠ Form row indexes BOTH spellings: tapo (surface sandhi)
  # and tapaḥ (the unsandhied analysis) each reach tapas.
  def test_unsandhied_and_surface_spellings_both_reach_the_lemma
    assert_equal "tapas", table.lookup("tapo").first.lemma
    tapah = table.lookup("tapaḥ")
    assert_equal "tapas", tapah.first.lemma
    assert_equal 1921, tapah.first.count, "every row whose Form or Unsandhied folds to tapah, summed"
  end

  def test_a_nominative_the_rule_also_gets_still_resolves_here
    candidates = table.lookup("bodhisattvaḥ")
    assert_equal ["bodhisattva"], candidates.map(&:lemma).uniq
    assert_equal "149046", candidates.first.lemma_id
    assert_equal candidates, table.lookup("bodhisattvah"), "ASCII visarga fold, same key"
  end

  # The 2,988 published rows with an empty Form and `_` Unsandhied are
  # lemma-only occurrences — they index nothing (honestly unreachable), so
  # the lemma-only tapas count (6) never inflates a form key.
  def test_lemma_only_rows_index_nothing
    assert_empty table.lookup("")
    assert_empty table.lookup("_")
    assert_equal 953, table.lookup("tapas").first.count,
                 "tapas + tapaś Form rows (735+151+66+1) — never the lemma-only row's 6"
  end

  # The upstream mis-encoding quirk (DCS carries kﾱp with U+FFB1 where kḷp
  # is meant): such rows take the slow fold path and stay reachable via
  # their own verbatim spellings.
  def test_the_mis_encoded_upstream_rows_stay_reachable_verbatim
    candidates = table.lookup("acīkﾱpatām")
    assert_equal ["kﾱp"], candidates.map(&:lemma)
    assert_equal "156176", candidates.first.lemma_id
  end

  def test_unknown_forms_are_empty_and_do_not_grow_the_index
    size = table.size
    assert_empty table.lookup("λόγος")
    assert_empty table.lookup("zzzznotaword")
    assert_equal size, table.size, "a miss must never memoize a key into the index"
  end

  # --- the fold contract -----------------------------------------------------

  # The fast tr path must be byte-identical to the house san fold — proven
  # over the full published file at trim time; pinned here on the fixture's
  # own spellings (regression guard for either side drifting).
  def test_fold_matches_the_house_sanskrit_fold_on_fixture_spellings
    %w[tapasā tapaḥ bodhisattvaḥ bodhisattvāḥ tapāṃsy 'tapās acīkﾱpatām].each do |form|
      assert_equal Nabu::Normalize.search_form(form, language: "san"), Nabu::FormLemma.fold(form),
                   "#{form}: FormLemma.fold must equal Normalize.search_form(san)"
    end
  end

  # --- loading shapes --------------------------------------------------------

  def test_a_missing_dataset_file_loads_empty
    Dir.mktmpdir do |dir|
      empty = Nabu::FormLemma.load(dir)
      assert_equal 0, empty.size
      assert_empty empty.lookup("tapasā")
    end
  end

  def test_load_default_feature_detects_the_canonical_tree
    Dir.mktmpdir do |root|
      config = Nabu::Config.new(canonical_dir: File.join(root, "canonical"),
                                db_dir: File.join(root, "db"),
                                sources_path: File.join(root, "sources.yml"), config_path: "(test)")
      assert_nil Nabu::FormLemma.load_default(config: config),
                 "no canonical/nabu-data tree -> nil (the lila/cldf-spine posture)"
      dest = File.join(root, "canonical", "nabu-data")
      FileUtils.mkdir_p(dest)
      FileUtils.cp_r(Dir[File.join(FIXTURES, "*")], dest)
      live = Nabu::FormLemma.load_default(config: config)
      refute_nil live
      assert_equal "tapas", live.lookup("tapasā").first.lemma
    end
  end
end
