# frozen_string_literal: true

require "test_helper"

module Query
  # Nabu::Query::ParallelsHub — hub demotion (architecture §13 "Measuring
  # the engine", the second admissible borrowing). The corpora below are
  # hand-built on purpose: they test the SCORER (how ubiquitous shared
  # grams weigh against a distinctive one), not an upstream format. The
  # rig is ParallelsTest's: in-memory catalog + fulltext, the real
  # Indexer, so every probe runs over the true FTS index.
  class ParallelsHubTest < Minitest::Test
    include StoreTestDB

    Hub = Nabu::Query::ParallelsHub

    # A 16-token stock formula: 13 shared 4-grams wherever it recurs.
    FORMULA = "in nomine domini dei nostri iesu christi amen anno ab incarnatione eiusdem " \
              "millesimo centesimo regnante rege"

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
    def charter(name, text)
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

    # The anchor: the stock formula, then a distinctive clause. Five more
    # charters carry the formula (df 6 with the anchor — a hub at
    # hub_df 5); one carries the distinctive clause and nothing else, and
    # two unrelated charters share that clause's phrase too (df 4).
    def formulaic_corpus
      anchor = charter("anchor", "#{FORMULA} donamus ecclesiae sancti petri molendinum")
      (1..5).each { |i| charter("hub#{i}", "#{FORMULA} vendidit #{%w[agrum uineam domum pratum siluam][i - 1]}") }
      charter("true", "ego comes donamus ecclesiae sancti petri molendinum in fluuio")
      charter("other1", "et donamus ecclesiae sancti petri terram")
      charter("other2", "quod donamus ecclesiae sancti petri omnia")
      rebuild!
      anchor
    end

    # -- the drowning the technique exists for ------------------------------

    def test_ubiquitous_formula_grams_drown_a_distinctive_overlap_in_the_exact_engine
      anchor = formulaic_corpus
      exact = Nabu::Query::Parallels.new(catalog: @catalog, fulltext: @fulltext).run(anchor, echoes: false)
      assert_equal "urn:t:true:1", hit_urns(exact).last(3).first,
                   "baseline: the five formula hubs (13 grams at df 6 ≈ 2.2) outrank the true echo (≈ 1.0)"
      assert(hit_urns(exact).first(5).all? { |urn| urn.start_with?("urn:t:hub") })
    end

    def test_hub_demotion_lets_the_distinctive_overlap_outrank_the_formula
      anchor = formulaic_corpus
      result = engine.run(anchor, echoes: false)
      assert_equal "urn:t:true:1", hit_urns(result).first
      hubs = result.hits.select { |hit| hit.urn.start_with?("urn:t:hub") }
      assert_equal 5, hubs.size, "demoted, never dropped"
      assert(hubs.all? { |hit| hit.score < 1.0 / 5 }, "a pure-hub candidate's mass stays under one hub_df gram")
    end

    def test_evidence_spans_still_name_the_formula
      anchor = formulaic_corpus
      hub = engine.run(anchor, echoes: false).hits.find { |hit| hit.urn == "urn:t:hub1:1" }
      assert_equal [FORMULA], hub.evidence
      assert_equal 13, hub.shared_gram_count
    end

    def test_demotion_preserves_order_among_pure_hub_candidates
      words = FORMULA.split
      anchor = charter("anchor", FORMULA)
      (1..5).each { |i| charter("full#{i}", "#{FORMULA} x#{i}") }
      charter("half", words.first(8).join(" "))
      rebuild!
      ranked = hit_urns(engine.run(anchor, echoes: false))
      assert_equal "urn:t:half:1", ranked.last, "five shared grams still rank under thirteen"
    end

    def test_with_no_gram_at_the_hub_df_the_answer_is_the_exact_engines
      anchor = formulaic_corpus
      exact = Nabu::Query::Parallels.new(catalog: @catalog, fulltext: @fulltext).run(anchor, echoes: false)
      assert_equal exact, engine(hub_df: 7).run(anchor, echoes: false), "df 6 < 7: nothing is a hub"
    end

    def test_the_hub_cutoff_scales_with_the_corpus_and_floors_at_the_tuning_value
      anchor = formulaic_corpus
      engine = Hub.new(catalog: @catalog, fulltext: @fulltext)
      engine.run(anchor, echoes: false)
      assert_equal Hub::HUB_GRAM_DF, engine.hub_gram_df, "a tiny corpus binds the absolute floor"
    end

    def test_a_non_positive_hub_df_is_refused
      assert_raises(ArgumentError) { engine(hub_df: 0) }
      assert_raises(ArgumentError) { engine(hub_df: "5") }
    end

    # -- composition with the fuzzy tier --------------------------------------

    def test_with_the_fuzzy_fallback_a_short_anchor_keeps_its_fuzzy_answer
      anchor = charter("a", "dis manibus gaio")
      charter("b", "dis lacuna gaio")
      rebuild!
      fuzzy = Nabu::Query::ParallelsFuzzy.new(catalog: @catalog, fulltext: @fulltext).run(anchor, echoes: false)
      both = Nabu::Query::ParallelsFuzzyHub.new(catalog: @catalog, fulltext: @fulltext, hub_df: 5)
                                           .run(anchor, echoes: false)
      assert_equal fuzzy, both, "no exact score — the fallback fires and demotion has nothing to act on"
    end

    def test_with_the_fuzzy_fallback_a_long_anchor_is_hub_demoted
      anchor = formulaic_corpus
      both = Nabu::Query::ParallelsFuzzyHub.new(catalog: @catalog, fulltext: @fulltext, hub_df: 5)
                                           .run(anchor, echoes: false)
      assert_equal engine.run(anchor, echoes: false), both
    end

    # -- the persisted-scope guard --------------------------------------------

    def test_the_tier_sits_outside_the_batch_miners_stamp_closure
      closure = Nabu::LinkStamps.code_files("parallels").map { |file| File.basename(file) }
      assert_includes closure, "parallels.rb"
      refute_includes closure, "parallels_hub.rb", "switching hub demotion must never re-mine a persisted scope"
    end

    private

    def engine(hub_df: 5) = Hub.new(catalog: @catalog, fulltext: @fulltext, hub_df: hub_df)
  end
end
