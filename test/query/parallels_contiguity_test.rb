# frozen_string_literal: true

require "test_helper"

module Query
  # Nabu::Query::ContiguityBonus — the contiguity bonus (architecture §13
  # "Measuring the engine", the third measured borrowing). The corpora
  # below are hand-built on purpose: they test the SCORER (contiguous vs
  # scattered shared grams, verbatim runs vs damage-bridged spans), not
  # an upstream format. The rig is ParallelsTest's: in-memory catalog +
  # fulltext, the real Indexer, so every probe runs over the true FTS index.
  class ParallelsContiguityTest < Minitest::Test
    include StoreTestDB

    Contiguous = Nabu::Query::ParallelsContiguous

    ANCHOR = "alpha beta gamma delta epsilon zeta eta theta iota kappa"

    def setup
      @catalog = store_test_db
      @fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
      @source = Nabu::Store::Source.create(slug: "open", name: "Open", adapter_class: "TestAdapter",
                                           license_class: "open")
      @seq = 0
    end

    def teardown
      @fulltext.disconnect
    end

    # One single-passage document per text; returns the passage urn.
    def text(name, body)
      document = Nabu::Store::Document.create(source_id: @source.id, urn: "urn:t:#{name}", title: name,
                                              language: "lat", content_sha256: "x", revision: 1)
      Nabu::Store::Passage.create(document_id: document.id, urn: "urn:t:#{name}:1", sequence: (@seq += 1),
                                  language: "lat", text: body,
                                  text_normalized: Nabu::Normalize.search_form(body, language: "lat"),
                                  content_sha256: "x", revision: 1)
      "urn:t:#{name}:1"
    end

    def rebuild! = Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext)

    def exact = Nabu::Query::Parallels.new(catalog: @catalog, fulltext: @fulltext)

    def hit(result, name) = result.hits.find { |h| h.urn == "urn:t:#{name}:1" }

    def ranking(result) = result.hits.map { |h| [h.urn, h.score] }

    # Two candidates sharing TWO anchor 4-grams each at equal rarity: one
    # as a single 5-token phrase (grams 0 and 1, side by side), one
    # scattered (grams 0 and 6, apart). df: gram 0 = 3 (anchor + both),
    # grams 1 and 6 = 2 — so the exact engine scores them EQUAL.
    def equal_count_corpus
      anchor = text("anchor", ANCHOR)
      text("scattered", "alpha beta gamma delta lorem ipsum eta theta iota kappa")
      text("zcontiguous", "alpha beta gamma delta epsilon dolor sit")
      rebuild!
      anchor
    end

    # -- contiguous vs scattered, equal gram count ----------------------------

    def test_the_exact_engine_cannot_tell_a_contiguous_run_from_scattered_grams
      result = exact.run(equal_count_corpus, echoes: false)
      assert_equal hit(result, "scattered").score, hit(result, "zcontiguous").score
      assert_equal 2, hit(result, "scattered").shared_gram_count
      assert_equal 2, hit(result, "zcontiguous").shared_gram_count
      assert_equal "urn:t:scattered:1", result.hits.first.urn, "a tie, broken by urn"
    end

    def test_the_bonus_ranks_the_contiguous_run_above_scattered_grams_of_equal_count
      result = Contiguous.new(catalog: @catalog, fulltext: @fulltext).run(equal_count_corpus, echoes: false)
      assert_equal %w[urn:t:zcontiguous:1 urn:t:scattered:1], result.hits.map(&:urn)
      assert_in_delta (1 / 3.0) + (1 / 2.0), hit(result, "scattered").score, 1e-4, "scattered grams count once"
      assert_in_delta (1 / 3.0) + (2 * (1 / 2.0)), hit(result, "zcontiguous").score, 1e-4,
                      "the continuing gram (df 2) counts (1 + W) = 2 times"
      assert_equal [5, 5], hit(result, "zcontiguous").to_h.values_at(:longest_run, :bridged_span)
      assert_equal [4, 4], hit(result, "scattered").to_h.values_at(:longest_run, :bridged_span),
                   "a three-token anchor gap is no damage bridge"
    end

    def test_the_bonus_scales_with_the_weight
      result = Contiguous.new(catalog: @catalog, fulltext: @fulltext, contiguity_weight: 0.5)
                         .run(equal_count_corpus, echoes: false)
      assert_in_delta (1 / 3.0) + (1.5 * (1 / 2.0)), hit(result, "zcontiguous").score, 1e-4
    end

    def test_adjacent_anchor_grams_held_apart_in_the_candidate_earn_no_bonus
      anchor = text("anchor", ANCHOR)
      text("apart", "alpha beta gamma delta nu beta gamma delta epsilon")
      rebuild!
      base = hit(exact.run(anchor, echoes: false), "apart")
      result = hit(Contiguous.new(catalog: @catalog, fulltext: @fulltext).run(anchor, echoes: false), "apart")
      assert_equal 2, base.shared_gram_count, "grams 0 and 1 both present…"
      assert_equal base.score, result.score, "…but never side by side in the candidate: no continuation"
      assert_equal [4, 4], result.to_h.values_at(:longest_run, :bridged_span)
    end

    def test_at_gram_size_one_a_shared_phrase_outranks_the_same_words_scattered
      anchor = text("anchor", "dis manibus gaio caecinae")
      text("phrase", "gaio caecinae filio")
      text("bag", "caecinae uxor gaio")
      rebuild!
      base = exact.run(anchor, echoes: false, gram_size: 1)
      assert_equal hit(base, "bag").score, hit(base, "phrase").score, "two shared words each, same rarity"
      result = Contiguous.new(catalog: @catalog, fulltext: @fulltext).run(anchor, echoes: false, gram_size: 1)
      assert_equal "urn:t:phrase:1", result.hits.first.urn
      assert_equal [2, 2], hit(result, "phrase").to_h.values_at(:longest_run, :bridged_span)
      assert_equal [1, 1], hit(result, "bag").to_h.values_at(:longest_run, :bridged_span)
    end

    # -- the two figures: a damage-bridged span is not a contiguous run -------

    def test_a_damage_bridged_span_and_a_true_contiguous_run_report_different_figures
      anchor = text("anchor", "alpha beta gamma delta epsilon zeta eta theta iota")
      text("damaged", "alpha beta gamma delta lacuna zeta eta theta iota")
      text("intact", "alpha beta gamma delta epsilon zeta eta")
      text("far", "alpha beta gamma delta foo bar baz zeta eta theta iota")
      rebuild!
      result = Contiguous.new(catalog: @catalog, fulltext: @fulltext).run(anchor, echoes: false)
      damaged = hit(result, "damaged")
      assert_equal 4, damaged.longest_run, "two verbatim 4-token runs, broken by the damaged token"
      assert_equal 9, damaged.bridged_span, "one substituted token bridged: the whole line, damage included"
      intact = hit(result, "intact")
      assert_equal [7, 7], intact.to_h.values_at(:longest_run, :bridged_span), "no damage: the figures agree"
      assert_equal [4, 4], hit(result, "far").to_h.values_at(:longest_run, :bridged_span),
                   "a three-token candidate gap is no bridge"
    end

    def test_a_bridged_span_earns_no_bonus
      anchor = text("anchor", "alpha beta gamma delta epsilon zeta eta theta iota")
      text("damaged", "alpha beta gamma delta lacuna zeta eta theta iota")
      rebuild!
      base = hit(exact.run(anchor, echoes: false), "damaged")
      bonus = hit(Contiguous.new(catalog: @catalog, fulltext: @fulltext).run(anchor, echoes: false), "damaged")
      assert_equal base.score, bonus.score, "scored as the exact engine scores it — the damage is bridged in the report"
    end

    def test_a_lost_token_on_one_side_is_bridged_too
      anchor = text("anchor", "alpha beta gamma delta epsilon zeta eta theta iota")
      text("lost", "alpha beta gamma delta zeta eta theta iota")
      rebuild!
      lost = hit(Contiguous.new(catalog: @catalog, fulltext: @fulltext).run(anchor, echoes: false), "lost")
      assert_equal [4, 9], lost.to_h.values_at(:longest_run, :bridged_span)
    end

    # -- the switch: off is today's engine, byte for byte ---------------------

    def test_weight_zero_reports_the_figures_with_scoring_identical_to_the_exact_engine
      anchor = equal_count_corpus
      off = Contiguous.new(catalog: @catalog, fulltext: @fulltext, contiguity_weight: 0)
                      .run(anchor, echoes: false)
      base = exact.run(anchor, echoes: false)
      assert_equal ranking(base), ranking(off)
      assert_equal(base.hits.map(&:to_h), off.hits.map { |h| h.to_h.except(:longest_run, :bridged_span) })
      assert_equal base.gram_count, off.gram_count
      assert_equal 5, hit(off, "zcontiguous").longest_run
    end

    def test_a_negative_or_non_numeric_weight_is_refused
      assert_raises(ArgumentError) { Contiguous.new(catalog: @catalog, fulltext: @fulltext, contiguity_weight: -1) }
      assert_raises(ArgumentError) { Contiguous.new(catalog: @catalog, fulltext: @fulltext, contiguity_weight: "1") }
    end

    # -- composition -------------------------------------------------------------

    def test_with_the_fuzzy_fallback_a_short_anchor_keeps_its_fuzzy_answer
      anchor = text("a", "dis manibus gaio")
      text("b", "dis lacuna gaio")
      rebuild!
      fuzzy = Nabu::Query::ParallelsFuzzy.new(catalog: @catalog, fulltext: @fulltext).run(anchor, echoes: false)
      both = Nabu::Query::ParallelsFuzzyContiguous.new(catalog: @catalog, fulltext: @fulltext)
                                                  .run(anchor, echoes: false)
      assert_equal ranking(fuzzy), ranking(both), "no exact gram, no run: the fuzzy answer stands"
      assert_equal [0, 0], both.hits.first.to_h.values_at(:longest_run, :bridged_span)
    end

    def test_every_tier_combination_carries_the_bonus
      anchor = equal_count_corpus
      [Nabu::Query::ParallelsFuzzyContiguous, Nabu::Query::ParallelsHubContiguous,
       Nabu::Query::ParallelsFuzzyHubContiguous].each do |klass|
        result = klass.new(catalog: @catalog, fulltext: @fulltext).run(anchor, echoes: false)
        assert_equal "urn:t:zcontiguous:1", result.hits.first.urn, klass.name
      end
    end

    # -- the persisted-scope guard --------------------------------------------

    def test_the_bonus_sits_outside_the_batch_miners_stamp_closure
      closure = Nabu::LinkStamps.code_files("parallels").map { |file| File.basename(file) }
      assert_includes closure, "parallels.rb"
      refute_includes closure, "parallels_contiguity.rb", "switching the bonus must never re-mine a persisted scope"
    end
  end
end
