# frozen_string_literal: true

require "test_helper"

# RebuildProfile (P36-0): the always-on per-source/per-stage wall-time collector
# behind `rebuild --profile`. A fake monotonic clock makes the timings exact, so
# these pin the arithmetic (stages present, sums, shares) rather than wall race.
class RebuildProfileTest < Minitest::Test
  # A clock that advances by a fixed tick on every read, so `measure` around an
  # empty block records exactly one tick — deterministic, no real sleeping.
  def clock(tick: 1.0)
    now = 0.0
    -> { now += tick }
  end

  def test_measure_records_the_block_delta_and_returns_the_block_value
    profile = Nabu::RebuildProfile.new(clock: clock(tick: 2.5))
    value = profile.measure(scope: "perseus", stage: :load) { :the_summary }

    assert_equal :the_summary, value
    assert_in_delta 2.5, profile.seconds(scope: "perseus", stage: :load), 1e-9
  end

  def test_add_folds_raw_deltas_for_the_per_document_accumulators
    profile = Nabu::RebuildProfile.new
    profile.add(scope: "papyri", stage: :parse, seconds: 1.0)
    profile.add(scope: "papyri", stage: :parse, seconds: 0.5)
    profile.add(scope: "papyri", stage: :insert, seconds: 3.0)

    assert_in_delta 1.5, profile.seconds(scope: "papyri", stage: :parse), 1e-9
    assert_equal({ parse: 1.5, insert: 3.0 }, profile.breakdown("papyri"))
  end

  def test_breakdown_is_nil_for_an_uninstrumented_source
    profile = Nabu::RebuildProfile.new
    profile.add(scope: "notes", stage: :load, seconds: 0.2)

    assert_nil profile.breakdown("notes"), "no parse/insert component was sampled"
  end

  def test_a_raising_block_records_nothing
    profile = Nabu::RebuildProfile.new(clock: clock)
    assert_raises(RuntimeError) { profile.measure(scope: "x", stage: :load) { raise "boom" } }

    assert_in_delta 0.0, profile.seconds(scope: "x", stage: :load), 1e-9
    assert_predicate profile, :empty?
  end

  # Sources are ordered heaviest-load first (the hotspot order).
  def test_source_scopes_are_sorted_by_load_desc
    profile = Nabu::RebuildProfile.new
    profile.add(scope: "small", stage: :load, seconds: 1.0)
    profile.add(scope: "big", stage: :load, seconds: 9.0)
    profile.add(scope: "mid", stage: :load, seconds: 4.0)

    assert_equal %w[big mid small], profile.source_scopes
  end

  # The grand total is source loads + corpus stages; parse/insert are COMPONENTS
  # of :load and must never be re-summed into it (the monotonic/sum invariant).
  def test_grand_total_sums_loads_and_corpus_stages_but_not_components
    profile = Nabu::RebuildProfile.new
    profile.add(scope: "src", stage: :load, seconds: 10.0)
    profile.add(scope: "src", stage: :parse, seconds: 6.0)  # component of :load
    profile.add(scope: "src", stage: :insert, seconds: 3.0) # component of :load
    profile.add(scope: Nabu::RebuildProfile::CORPUS, stage: :fts_lemma, seconds: 20.0)
    profile.add(scope: Nabu::RebuildProfile::CORPUS, stage: :trigram, seconds: 5.0)

    # 10 (load) + 20 (fts_lemma) + 5 (trigram) — NOT + parse + insert.
    assert_in_delta 35.0, profile.grand_total, 1e-9
    assert_in_delta 10.0, profile.load_total, 1e-9
    assert_in_delta 25.0, profile.index_total, 1e-9
    assert_in_delta 6.0, profile.parse_total, 1e-9
    assert_in_delta 3.0, profile.insert_total, 1e-9
  end

  # Components sit within their source's load: parse+insert ≲ load.
  def test_components_do_not_exceed_the_load_rollup
    profile = Nabu::RebuildProfile.new(clock: clock(tick: 1.0))
    # load rollup = 5 ticks; inside it parse=2 ticks + insert=2 ticks ≤ 5.
    profile.add(scope: "s", stage: :load, seconds: 5.0)
    profile.add(scope: "s", stage: :parse, seconds: 2.0)
    profile.add(scope: "s", stage: :insert, seconds: 2.0)
    b = profile.breakdown("s")

    assert_operator b[:parse] + b[:insert], :<=, profile.seconds(scope: "s", stage: :load) + 1e-9
  end

  # The rows view: heaviest-first, labelled, shares summing to ~1.0.
  def test_rows_are_heaviest_first_with_shares_summing_to_one
    profile = Nabu::RebuildProfile.new
    profile.add(scope: "src", stage: :load, seconds: 30.0)
    profile.add(scope: Nabu::RebuildProfile::CORPUS, stage: :fts_lemma, seconds: 60.0)
    profile.add(scope: Nabu::RebuildProfile::CORPUS, stage: :timeline, seconds: 10.0)

    rows = profile.rows
    labels = rows.map(&:first)

    assert_equal ["fts+lemma reindex", "src", "timeline"], labels
    assert_in_delta 1.0, rows.sum { |_, _, share| share }, 1e-9
    assert_in_delta 0.6, rows.first[2], 1e-9 # fts_lemma is 60/100
  end

  def test_corpus_stages_are_sorted_desc_and_labelled
    profile = Nabu::RebuildProfile.new
    profile.add(scope: Nabu::RebuildProfile::CORPUS, stage: :trigram, seconds: 2.0)
    profile.add(scope: Nabu::RebuildProfile::CORPUS, stage: :fts_lemma, seconds: 9.0)

    assert_equal %i[fts_lemma trigram], profile.corpus_stages
  end

  def test_empty_profile_reports_zero_and_no_rows
    profile = Nabu::RebuildProfile.new

    assert_predicate profile, :empty?
    assert_in_delta 0.0, profile.grand_total, 1e-9
    assert_empty profile.rows
  end
end
