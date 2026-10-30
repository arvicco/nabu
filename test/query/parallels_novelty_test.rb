# frozen_string_literal: true

require "test_helper"

module Query
  # Nabu::Query::NoveltyWeighting — novelty weighting (architecture §13
  # "Measuring the engine", the fourth measured borrowing). The corpora
  # below are hand-built on purpose: they test the SCORER (a gram the
  # anchor's own document repeats vs a distinctive line at equal df), not
  # an upstream format. The rig is ParallelsTest's: in-memory catalog +
  # fulltext, the real Indexer, so every probe runs over the true FTS index.
  class ParallelsNoveltyTest < Minitest::Test
    include StoreTestDB

    Novel = Nabu::Query::ParallelsNovel

    # Gram 0 ("evam me sutam ekam") is the anchor document's own framing
    # formula; gram 6 ("viharati tatra kho bhikkhave") its distinctive line.
    ANCHOR = "evam me sutam ekam samayam bhagava viharati tatra kho bhikkhave"

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

    # One document holding +bodies+ as consecutive passages; returns the
    # passage urns.
    def document(name, *bodies)
      doc = Nabu::Store::Document.create(source_id: @source.id, urn: "urn:t:#{name}", title: name,
                                         language: "pli", content_sha256: "x", revision: 1)
      bodies.each_with_index.map do |body, i|
        Nabu::Store::Passage.create(document_id: doc.id, urn: "urn:t:#{name}:#{i + 1}", sequence: (@seq += 1),
                                    language: "pli", text: body,
                                    text_normalized: Nabu::Normalize.search_form(body, language: "pli"),
                                    content_sha256: "x", revision: 1)
        "urn:t:#{name}:#{i + 1}"
      end
    end

    def rebuild! = Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext)

    def exact = Nabu::Query::Parallels.new(catalog: @catalog, fulltext: @fulltext)

    def novel(**) = Novel.new(catalog: @catalog, fulltext: @fulltext, **)

    def hit(result, name) = result.hits.find { |h| h.urn == "urn:t:#{name}:1" }

    def ranking(result) = result.hits.map { |h| [h.urn, h.score] }

    # The anchor's document repeats its framing formula in +repeats+ more
    # passages. "aecho" shares only the formula gram; "bline" only the
    # distinctive line. Both grams sit at df 3 + (repeats − 1) … so the
    # line is padded by "cline" (and fillers) to the SAME df — equal
    # rarity, equal exact score.
    def formula_corpus(repeats: 1)
      anchor, = document("sutta", ANCHOR, *Array.new(repeats) { |i| "evam me sutam ekam aliud#{i}" })
      document("aecho", "evam me sutam ekam alia verba")
      document("bline", "viharati tatra kho bhikkhave nunc")
      document("cline", "et viharati tatra kho bhikkhave")
      (repeats - 1).times { |i| document("dfill#{i}", "iti viharati tatra kho bhikkhave #{'x' * (i + 1)}") }
      rebuild!
      anchor
    end

    # -- the case the technique exists for ------------------------------------

    def test_the_exact_engine_cannot_tell_an_intra_work_formula_from_a_distinctive_line
      result = exact.run(formula_corpus, echoes: false)
      assert_equal hit(result, "aecho").score, hit(result, "bline").score, "both grams at df 3"
      assert_equal "urn:t:aecho:1", result.hits.first.urn, "a tie, broken by urn"
    end

    def test_novelty_ranks_the_distinctive_line_above_the_anchors_own_formula
      result = novel.run(formula_corpus, echoes: false)
      assert_equal %w[urn:t:bline:1 urn:t:cline:1 urn:t:aecho:1], result.hits.map(&:urn)
      assert_in_delta 1 / 3.0, hit(result, "bline").score, 1e-4, "a gram the anchor's document never repeats: 1/df"
      assert_in_delta (1 / 3.0) / 2, hit(result, "aecho").score, 1e-4,
                      "one other anchor-document passage holds it: 1/df · 1/(1 + W·1)"
      assert_equal 1, hit(result, "aecho").shared_gram_count, "demoted, never dropped; evidence untouched"
      assert_equal ["evam me sutam ekam"], hit(result, "aecho").evidence
    end

    def test_the_demotion_grows_with_the_formulas_recurrence_in_the_anchors_document
      result = novel.run(formula_corpus(repeats: 3), echoes: false)
      assert_in_delta (1 / 5.0) / 4, hit(result, "aecho").score, 1e-4, "three repeats: 1/(1 + 3)"
      assert_in_delta 1 / 5.0, hit(result, "bline").score, 1e-4
    end

    def test_the_demotion_scales_with_the_weight
      result = novel(novelty_weight: 3).run(formula_corpus, echoes: false)
      assert_in_delta (1 / 3.0) / 4, hit(result, "aecho").score, 1e-4, "1/(1 + 3·1)"
    end

    def test_a_candidate_sharing_both_keeps_its_distinctive_mass_whole
      anchor, = document("sutta", ANCHOR, "evam me sutam ekam aliud")
      document("both", "evam me sutam ekam et viharati tatra kho bhikkhave")
      document("bline", "viharati tatra kho bhikkhave nunc")
      rebuild!
      base = hit(exact.run(anchor, echoes: false), "both")
      result = hit(novel.run(anchor, echoes: false), "both")
      assert_in_delta (1 / 3.0) + (1 / 3.0), base.score, 1e-4
      assert_in_delta ((1 / 3.0) / 2) + (1 / 3.0), result.score, 1e-4, "only the formula gram's share is demoted"
    end

    def test_a_formula_pervasive_only_in_other_documents_is_left_to_the_rarity_weight
      anchor, = document("sutta", ANCHOR)
      document("aecho", "evam me sutam ekam alia verba")
      document("bother", "evam me sutam ekam aliud")
      document("bline", "viharati tatra kho bhikkhave nunc")
      rebuild!
      assert_equal ranking(exact.run(anchor, echoes: false)), ranking(novel.run(anchor, echoes: false)),
                   "novelty is anchor-relative: cross-document formulae are 1/df's (and hub demotion's) concern"
    end

    def test_the_anchor_document_cache_follows_the_anchor
      first = formula_corpus
      other, = document("other", "evam me sutam ekam samayam bhagava viharati tatra kho bhikkhave iti")
      rebuild!
      engine = novel
      engine.run(first, echoes: false)
      result = engine.run(other, echoes: false)
      assert_equal ranking(exact.run(other, echoes: false)), ranking(result),
                   "a single-passage anchor document repeats nothing: nothing demoted"
    end

    # -- the switch: off is today's engine, byte for byte ---------------------

    def test_weight_zero_scores_byte_identically_to_the_exact_engine
      anchor = formula_corpus(repeats: 2)
      off = novel(novelty_weight: 0).run(anchor, echoes: false)
      base = exact.run(anchor, echoes: false)
      assert_equal base.hits.map(&:to_h), off.hits.map(&:to_h)
      assert_equal base.gram_count, off.gram_count
    end

    def test_without_an_intra_document_formula_the_on_state_is_byte_identical_too
      anchor, = document("solo", ANCHOR)
      document("aecho", "evam me sutam ekam alia verba")
      document("bline", "viharati tatra kho bhikkhave nunc")
      rebuild!
      assert_equal exact.run(anchor, echoes: false).hits.map(&:to_h), novel.run(anchor, echoes: false).hits.map(&:to_h)
    end

    def test_a_negative_or_non_numeric_weight_is_refused
      assert_raises(ArgumentError) { novel(novelty_weight: -1) }
      assert_raises(ArgumentError) { novel(novelty_weight: "1") }
      assert_raises(ArgumentError) { novel(novelty_weight: Float::INFINITY) }
    end

    # -- composition -------------------------------------------------------------

    def test_every_tier_combination_carries_novelty
      anchor = formula_corpus
      [Nabu::Query::ParallelsFuzzyNovel, Nabu::Query::ParallelsHubNovel, Nabu::Query::ParallelsFuzzyHubNovel,
       Nabu::Query::ParallelsContiguousNovel, Nabu::Query::ParallelsFuzzyContiguousNovel,
       Nabu::Query::ParallelsHubContiguousNovel, Nabu::Query::ParallelsFuzzyHubContiguousNovel].each do |klass|
        result = klass.new(catalog: @catalog, fulltext: @fulltext).run(anchor, echoes: false)
        assert_equal "urn:t:bline:1", result.hits.first.urn, klass.name
        assert_in_delta (1 / 3.0) / 2, hit(result, "aecho").score, 1e-4, klass.name
      end
    end

    def test_novelty_scales_the_final_score_of_the_tier_beneath_it
      anchor, = document("sutta", "alpha beta gamma delta epsilon zeta", "alpha beta gamma delta epsilon aliud")
      document("run", "alpha beta gamma delta epsilon nunc")
      rebuild!
      contiguous = hit(Nabu::Query::ParallelsContiguous.new(catalog: @catalog, fulltext: @fulltext)
                                                       .run(anchor, echoes: false), "run")
      both = hit(Nabu::Query::ParallelsContiguousNovel.new(catalog: @catalog, fulltext: @fulltext)
                                                      .run(anchor, echoes: false), "run")
      assert_in_delta contiguous.score / 2, both.score, 1e-4,
                      "every exact gram is the anchor document's formula (s = 1): the bonused score halves"
      assert_equal contiguous.longest_run, both.longest_run, "the contiguity figures ride through"
    end

    # -- the persisted-scope guard --------------------------------------------

    def test_novelty_sits_outside_the_batch_miners_stamp_closure
      closure = Nabu::LinkStamps.code_files("parallels").map { |file| File.basename(file) }
      assert_includes closure, "parallels.rb"
      refute_includes closure, "parallels_novelty.rb", "switching novelty must never re-mine a persisted scope"
    end
  end
end
