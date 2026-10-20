# frozen_string_literal: true

require "test_helper"

module Query
  # Nabu::Query::ParallelsExplain — the parallels explain surface. Same rig
  # as ParallelsTest (fresh in-memory catalog + fulltext, the real Indexer).
  #
  # score = Σ over the anchor's grams of (positions × 1/df) for the grams the
  # hit SHARES. Every anchor gram is a row — gram → document frequency →
  # rarity weight → contribution — and the rows sum to the served score
  # EXACTLY (decimal-exact at the score's 4-place grain); grams that add
  # nothing are explicit zero rows naming why.
  class ParallelsExplainTest < Minitest::Test
    include StoreTestDB

    def setup
      @catalog = store_test_db
      @fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
      @open = Nabu::Store::Source.create(
        slug: "open", name: "Open", adapter_class: "TestAdapter", license_class: "open"
      )
    end

    def teardown
      @fulltext.disconnect
    end

    def make_passage(urn:, text:)
      document = Nabu::Store::Document.create(
        source_id: @open.id, urn: urn, title: urn, language: "lat", content_sha256: "x", revision: 1
      )
      Nabu::Store::Passage.create(
        document_id: document.id, urn: "#{urn}:1", sequence: 0, language: "lat",
        text: text, text_normalized: Nabu::Normalize.search_form(text, language: "lat"),
        annotations_json: "{}", content_sha256: "x", revision: 1
      )
    end

    def rebuild!
      Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext)
    end

    def engine(klass = Nabu::Query::ParallelsExplain)
      klass.new(catalog: @catalog, fulltext: @fulltext)
    end

    # Fillers make the dfs uneven (df 4 · 6 · 3 · 8 · 2 across the five
    # anchor grams), so contributions are repeating decimals and a naive
    # per-row rounding would drift off the score — the invariant bites.
    def seed_explain_corpus
      make_passage(urn: "urn:ex:a", text: "alpha beta gamma delta epsilon zeta eta theta")
      make_passage(urn: "urn:ex:q", text: "dixit alpha beta gamma delta epsilon zeta")
      make_passage(urn: "urn:ex:p", text: "gamma delta epsilon zeta eta theta finis")
      { "alpha beta gamma delta" => 2, "beta gamma delta epsilon" => 4, "delta epsilon zeta eta" => 6 }
        .each do |phrase, copies|
          copies.times { |i| make_passage(urn: "urn:ex:f:#{phrase.split.first}:#{i}", text: "nunc #{phrase} tunc") }
        end
      rebuild!
    end

    # The served float's shortest decimal rendering, read back exactly.
    def decimal(value) = Rational(value.to_s)

    def assert_exact_decomposition(hit)
      rows = hit.contributions
      refute_nil rows, "the explain engine attaches the contribution rows"
      assert_equal decimal(hit.score), rows.sum { |row| decimal(row.contribution) },
                   "contributions sum to the served score exactly (#{hit.urn})"
      assert_equal (hit.score * 10_000).round, rows.sum { |row| (row.contribution * 10_000).round },
                   "and in integer 1e-4 units"
    end

    def test_contributions_sum_to_the_score_exactly_on_every_hit
      seed_explain_corpus
      result = engine.run("urn:ex:a:1")
      assert_operator result.hits.size, :>=, 3
      result.hits.each { |hit| assert_exact_decomposition(hit) }
    end

    def test_the_engine_is_unchanged_hits_and_scores_match_the_plain_run
      seed_explain_corpus
      plain = Nabu::Query::Parallels.new(catalog: @catalog, fulltext: @fulltext).run("urn:ex:a:1")
      explained = engine.run("urn:ex:a:1")
      assert_equal(plain.hits.map(&:to_h), explained.hits.map { |hit| hit.to_h.except(:contributions) })
      assert_equal plain.gram_count, explained.gram_count
    end

    def test_rows_carry_gram_df_weight_and_status_with_explicit_zeros
      seed_explain_corpus
      hit = engine.run("urn:ex:a:1").hits.find { |h| h.urn == "urn:ex:q:1" }
      rows = hit.contributions.to_h { |row| [row.gram, row] }
      assert_equal 5, rows.size, "every distinct anchor gram is a row (8 tokens → 5 grams)"

      opening = rows.fetch("alpha beta gamma delta")
      assert_equal ["shared", 1, 4], [opening.status, opening.positions, opening.df],
                   "df counts the anchor, the quoter, and the two fillers"
      assert_in_delta 0.25, opening.weight, 1e-9

      tail = rows.fetch("epsilon zeta eta theta")
      assert_equal ["not_shared", 2, 0.0], [tail.status, tail.df, tail.contribution],
                   "a gram the quoter lacks is an explicit zero row (df: anchor + partial)"
      assert_equal(hit.shared_gram_count, rows.values.count { |row| row.status == "shared" })
      assert_equal rows.values.sort_by { |row| [-row.contribution, row.position] }.map(&:gram),
                   hit.contributions.map(&:gram), "rows ordered by contribution, then anchor position"
    end

    def test_too_common_and_stop_grams_are_named_zero_rows
      seed_explain_corpus
      # Pin the common-gram cutoff at 5 so the df-6 and df-8 grams cross it.
      low_cutoff = Class.new(Nabu::Query::ParallelsExplain) do
        private

        def relative_cutoff(*) = 5
      end
      result = engine(low_cutoff).run("urn:ex:a:1", stop_tokens: %w[eta theta epsilon zeta])
      hit = result.hits.find { |h| h.urn == "urn:ex:q:1" }
      rows = hit.contributions.to_h { |row| [row.gram, row] }
      common = rows.fetch("delta epsilon zeta eta")
      assert_equal ["too_common", 5, 0.0, 0.0], [common.status, common.df, common.weight, common.contribution],
                   "df reads as the cutoff floor the probe stopped at"
      stop = rows.fetch("epsilon zeta eta theta")
      assert_equal ["stop", nil, 0.0], [stop.status, stop.df, stop.contribution],
                   "an all-stop gram is never probed — no df, an explicit zero"
      assert_exact_decomposition(hit)
    end

    # A gram repeated in the anchor contributes positions × weight.
    def test_a_repeated_anchor_gram_counts_every_position
      make_passage(urn: "urn:rp:a", text: "ora pro nobis ora pro nobis ora pro nobis")
      make_passage(urn: "urn:rp:b", text: "semper ora pro nobis ora amen")
      rebuild!
      hit = engine.run("urn:rp:a:1").hits.first
      rows = hit.contributions.to_h { |r| [r.gram, r] }
      assert_equal 3, rows.size, "6 grams, 3 distinct"
      shared = rows.fetch("ora pro nobis ora")
      assert_equal ["shared", 2, 2, 1.0], [shared.status, shared.positions, shared.df, shared.contribution],
                   "two anchor positions × 1/2"
      assert_equal "not_shared", rows.fetch("pro nobis ora pro").status
      assert_exact_decomposition(hit)
    end

    # Three grams at df 3 each: exact thirds summing to 1.0 — per-row
    # rounding would serve 0.3333 × 3 = 0.9999 against a score of 1.0.
    def test_repeating_thirds_apportion_onto_the_score_exactly
      %w[a q f].each { |tag| make_passage(urn: "urn:th:#{tag}", text: "unum duo tres quattuor quinque sex") }
      rebuild!
      hit = engine.run("urn:th:a:1").hits.first
      assert_in_delta 1.0, hit.score, 1e-12
      assert_equal [0.3334, 0.3333, 0.3333], hit.contributions.map(&:contribution)
      assert_exact_decomposition(hit)
    end

    # The apportionment law over arbitrary exact rows: integer units summing
    # to the target, each within one unit of its exact value, zeros kept.
    def test_apportionment_sums_to_the_target_for_any_rational_rows
      rng = Random.new(137)
      200.times do
        exact = Array.new(rng.rand(1..30)) { rng.rand < 0.3 ? 0 : Rational(rng.rand(1..5), rng.rand(1..499)) }
        target = (exact.sum.to_f.round(4) * 10_000).round
        units = engine.send(:apportion, exact, target: target)
        assert_equal target, units.sum
        units.each_with_index do |unit, i|
          assert_operator (unit - (exact[i] * 10_000)).abs, :<, 1, "row #{i} within one unit"
          assert_equal 0, unit if exact[i].zero?
        end
      end
    end

    # The batch miner's links stamp digests batch_parallels.rb's require
    # closure; the explain engine must stay OUTSIDE it, or adding it would
    # re-mine every persisted parallels scope for a change that alters no edge.
    def test_the_explain_engine_stays_outside_the_parallels_link_stamp_closure
      closure = Nabu::LinkStamps.code_files("parallels").map { |path| File.basename(path) }
      assert_includes closure, "parallels.rb"
      refute_includes closure, "parallels_explain.rb"
    end
  end
end
