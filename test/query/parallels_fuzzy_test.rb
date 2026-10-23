# frozen_string_literal: true

require "test_helper"

module Query
  # Nabu::Query::ParallelsFuzzy — the fuzzy 2-of-3 positional gram tier
  # (architecture §13 "Measuring the engine", the first admissible
  # borrowing). The corpora below are hand-built on purpose: they test the
  # MATCHER (which positional windows agree), not an upstream format.
  # The rig is ParallelsTest's: in-memory catalog + fulltext, the real
  # Indexer, so every probe runs over the true FTS index.
  class ParallelsFuzzyTest < Minitest::Test
    include StoreTestDB

    Fuzzy = Nabu::Query::ParallelsFuzzy

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
    def inscription(name, text)
      document = Nabu::Store::Document.create(source_id: @source.id, urn: "urn:t:#{name}", title: name,
                                              language: "lat", content_sha256: "x", revision: 1)
      Nabu::Store::Passage.create(document_id: document.id, urn: "urn:t:#{name}:1", sequence: (@seq += 1),
                                  language: "lat", text: text,
                                  text_normalized: Nabu::Normalize.search_form(text, language: "lat"),
                                  content_sha256: "x", revision: 1)
      "urn:t:#{name}:1"
    end

    def rebuild! = Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext)

    def hit_urns(result) = result.hits.map(&:urn)

    # -- the blind spot the tier exists for --------------------------------

    def test_a_short_anchor_below_the_exact_gram_size_is_invisible_to_the_exact_engine
      anchor = inscription("a", "dis manibus gaio")
      inscription("b", "dis manibus gaio")
      rebuild!
      exact = Nabu::Query::Parallels.new(catalog: @catalog, fulltext: @fulltext).run(anchor, echoes: false)
      assert_equal 0, exact.gram_count, "three tokens yield no 4-gram"
      assert_empty exact.hits
      assert_equal ["urn:t:b:1"], hit_urns(engine.run(anchor, echoes: false))
    end

    # -- the three 2-of-3 masks --------------------------------------------

    def test_a_damaged_middle_slot_still_matches_on_the_gap_mask
      anchor = inscription("a", "dis manibus gaio")
      inscription("b", "dis lacuna gaio")
      rebuild!
      result = engine.run(anchor, echoes: false)
      assert_equal ["urn:t:b:1"], hit_urns(result)
      assert_includes result.hits.first.evidence, "~dis _ gaio", "the tolerated slot is marked"
    end

    def test_a_damaged_edge_slot_still_matches_on_an_adjacent_mask
      anchor = inscription("a", "dis manibus gaio")
      inscription("b", "dis manibus lucio")
      inscription("c", "titus manibus gaio")
      rebuild!
      result = engine.run(anchor, echoes: false)
      assert_equal %w[urn:t:b:1 urn:t:c:1], hit_urns(result).sort
      assert_includes result.hits.find { |hit| hit.urn == "urn:t:b:1" }.evidence, "~dis manibus"
    end

    def test_one_agreeing_slot_is_not_a_match
      anchor = inscription("a", "dis manibus gaio")
      inscription("b", "dis lacuna lucio")
      inscription("c", "titus lacuna gaio")
      rebuild!
      assert_empty engine.run(anchor, echoes: false).hits
    end

    def test_the_gap_mask_is_positional_not_mere_proximity
      anchor = inscription("a", "dis manibus gaio")
      inscription("b", "gaio lacuna dis") # both tokens, one apart — but reversed
      inscription("c", "dis una duo gaio") # right order, two apart
      rebuild!
      assert_empty engine.run(anchor, echoes: false).hits
    end

    def test_a_full_window_outscores_a_two_of_three_window
      anchor = inscription("a", "dis manibus gaio")
      inscription("b", "dis manibus gaio")
      inscription("c", "dis lacuna gaio")
      rebuild!
      ranked = engine.run(anchor, echoes: false).hits
      assert_equal %w[urn:t:b:1 urn:t:c:1], ranked.map(&:urn)
      assert_operator ranked.first.score, :>, ranked.last.score
    end

    def test_a_two_token_anchor_matches_as_a_window_with_one_lost_slot
      anchor = inscription("a", "gai caecinae")
      inscription("b", "lucius gai caecinae libertus")
      rebuild!
      assert_equal ["urn:t:b:1"], hit_urns(engine.run(anchor, echoes: false))
    end

    def test_a_one_token_anchor_has_no_two_slots_to_agree
      anchor = inscription("a", "uicimus")
      inscription("b", "uicimus")
      rebuild!
      result = engine.run(anchor, echoes: false)
      assert_empty result.hits
      assert_equal 0, result.gram_count
    end

    # -- scope: fallback is the default; all always adds the tier ----------

    def test_fallback_scope_leaves_an_anchor_the_exact_tier_scores_untouched
      anchor = inscription("a", "arma uirumque cano troiae qui primus")
      inscription("b", "arma uirumque cano troiae")
      inscription("c", "lacuna uirumque cano lacuna") # 2-of-3 windows only
      rebuild!
      exact = Nabu::Query::Parallels.new(catalog: @catalog, fulltext: @fulltext).run(anchor, echoes: false)
      fallback = engine.run(anchor, echoes: false)
      assert_equal exact.hits, fallback.hits, "the exact tier scored — fallback adds nothing"
      assert_includes hit_urns(engine(scope: :all).run(anchor, echoes: false)), "urn:t:c:1"
    end

    def test_stop_token_pairs_are_neither_probed_nor_scored
      anchor = inscription("a", "et in gaio")
      inscription("b", "et in lucio")
      rebuild!
      assert_empty engine.run(anchor, echoes: false, stop_tokens: %w[et in]).hits
      refute_empty engine.run(anchor, echoes: false).hits
    end

    def test_an_unknown_scope_is_refused
      assert_raises(ArgumentError) { engine(scope: :sometimes) }
    end

    private

    def engine(scope: :fallback) = Fuzzy.new(catalog: @catalog, fulltext: @fulltext, scope: scope)
  end
end
