# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module Ops
  # Nabu::Ops::ParallelsBench — the recall@K harness (architecture §13
  # "Measuring the engine"). Arithmetic and gold loading run on small
  # in-memory stores with a stub producer; the BASELINE runs the real
  # engine over the real edh/edr fixture pairs (two editions of one stone)
  # and pins its recall.
  class ParallelsBenchTest < Minitest::Test
    include StoreTestDB

    Bench = Nabu::Ops::ParallelsBench

    # A producer answering fixed ranked document lists.
    class StubProducer
      def initialize(lists) = @lists = lists
      def name = "stub"
      def params = { "kind" => "stub" }

      def candidates(query, grain:, limit:)
        @seen ||= []
        @seen << [query, grain, limit]
        @lists.fetch(query, []).first(limit)
      end

      attr_reader :seen
    end

    def setup
      @catalog = store_test_db
      @links = Nabu::Store::LinksJournal.migrate!(Nabu::Store::LinksJournal.connect("sqlite::memory:"))
      @source = Nabu::Store::Source.create(slug: "t", name: "T", adapter_class: "TestAdapter", license_class: "open")
    end

    def teardown
      @links.disconnect
    end

    def doc(urn, language: "lat", passages: 1)
      document = Nabu::Store::Document.create(source_id: @source.id, urn: urn, title: urn, language: language,
                                              content_sha256: "x", revision: 1)
      passages.times do |i|
        Nabu::Store::Passage.create(document_id: document.id, urn: "#{urn}:#{i + 1}", sequence: i,
                                    language: language, text: "t", text_normalized: "t",
                                    content_sha256: "x", revision: 1)
      end
      document
    end

    def edges(producer, kind, pairs, details: {})
      run = Nabu::Store::LinksJournal.record_run!(@links, producer: producer, scope: producer, params: {},
                                                          code_version: "test")
      pairs.each do |from, to|
        Nabu::Store::LinksJournal.write_edge!(@links, from_urn: from, to_urn: to, kind: kind, score: nil,
                                                      run_id: run, detail: details[[from, to]])
      end
    end

    def bench = Bench.new(links: @links, catalog: @catalog, clock: -> { 0.0 })

    # -- gold loading ----------------------------------------------------------

    def test_pair_mode_loads_an_undirected_gold_set_with_its_filter
      edges("trismegistos", "reference", [%w[urn:a urn:b], %w[urn:a tm:1], %w[urn:c urn:d]],
            details: { %w[urn:a urn:b] => "same text (Trismegistos 1)", %w[urn:a tm:1] => "Trismegistos concordance",
                       %w[urn:c urn:d] => "same text (Trismegistos 2)" })
      gold = bench.gold_set(Bench.recipe("tm-same-text"))
      assert_equal 2, gold.pairs
      assert_equal Set["urn:b"], gold.adjacency["urn:a"]
      assert_equal Set["urn:a"], gold.adjacency["urn:b"], "undirected"
      refute gold.adjacency.key?("tm:1"), "the concordance edges are not same-text gold"
    end

    def test_hub_mode_pairs_co_members_and_censuses_singletons_and_oversized_hubs
      big = (1..26).map { |i| ["urn:nabu:cdli:p9#{i.to_s.rjust(5, '0')}", "urn:nabu:cdli:q000009"] }
      edges("cdli", "reference",
            [%w[urn:nabu:cdli:p000001 urn:nabu:cdli:q000001], %w[urn:nabu:cdli:p000002 urn:nabu:cdli:q000001],
             %w[urn:nabu:cdli:p000003 urn:nabu:cdli:q000001], %w[urn:nabu:cdli:p000004 urn:nabu:cdli:q000002],
             %w[urn:nabu:cdli:p000005 etcsl:1.1]] + big)
      gold = bench.gold_set(Bench.recipe("cdli-composite"))
      assert_equal 3, gold.pairs, "one 3-member hub → 3 pairs"
      assert_equal({ edges: 30, hubs: 3, hubs_used: 1, hubs_singleton: 1, hubs_over_cap: 1, max_hub: 25,
                     gold_pairs: 3, gold_urns: 3 }, gold.census)
    end

    def test_same_language_recipes_drop_cross_language_pairs
      doc("urn:nabu:suttacentral:sn1.1", language: "pli")
      doc("urn:nabu:suttacentral:sa1", language: "lzh")
      doc("urn:nabu:suttacentral:sa2", language: "lzh")
      edges("suttacentral", "reference", [%w[urn:nabu:suttacentral:sn1.1 urn:nabu:suttacentral:sa1],
                                          %w[urn:nabu:suttacentral:sa1 urn:nabu:suttacentral:sa2]])
      gold = bench.gold_set(Bench.recipe("suttacentral"))
      assert_equal 1, gold.pairs
      assert_equal 1, gold.census[:cross_language_or_unheld]
    end

    # -- the arithmetic -----------------------------------------------------------

    def test_recall_at_k_micro_macro_hit_and_precision_lower_bound
      %w[urn:a urn:b urn:c urn:d urn:e urn:x].each { |urn| doc(urn) }
      edges("trismegistos", "reference", [%w[urn:a urn:b], %w[urn:a urn:c], %w[urn:d urn:e]],
            details: Hash.new("same text (Trismegistos 1)"))
      gold = bench.gold_set(Bench.recipe("tm-same-text"))
      producer = StubProducer.new(
        "urn:a" => %w[urn:x urn:b urn:c], # 1 of 2 at K=2… both at K=3
        "urn:b" => %w[urn:a],
        "urn:c" => %w[urn:x],             # miss
        "urn:d" => %w[urn:e],
        "urn:e" => []                     # zero candidates
      )
      report = bench.run(gold: gold, producer: producer, ks: [1, 3], sample: nil)
      k1, k3 = report.rows
      assert_equal 5, report.census[:evaluated]
      assert_equal 1, report.census[:no_candidates]
      # K=1: found a?0 b:1 c:0 d:1 e:0 = 2 of 6 gold partner slots
      assert_in_delta 2 / 6.0, k1[:recall_micro]
      assert_in_delta (0 + 1 + 0 + 1 + 0) / 5.0, k1[:recall_macro]
      assert_in_delta 2 / 5.0, k1[:hit_rate]
      assert_in_delta 2 / 4.0, k1[:precision_lower_bound], 1e-9, "4 candidates returned at K=1"
      # K=3: a finds both
      assert_in_delta 4 / 6.0, k3[:recall_micro]
      assert_in_delta (1 + 1 + 0 + 1 + 0) / 5.0, k3[:recall_macro]
      assert_equal [3, :document], producer.seen.first.values_at(2, 1), "asked for max K at the gold grain"
    end

    def test_unheld_urns_are_censused_never_scored
      doc("urn:a")
      doc("urn:b")
      edges("trismegistos", "reference", [%w[urn:a urn:b], %w[urn:a urn:ghost], %w[urn:ghost2 urn:b]],
            details: Hash.new("same text (Trismegistos 1)"))
      report = bench.run(gold: bench.gold_set(Bench.recipe("tm-same-text")),
                         producer: StubProducer.new("urn:a" => %w[urn:b], "urn:b" => %w[urn:a]), ks: [1], sample: nil)
      assert_equal 2, report.census[:unheld_queries]
      assert_equal 2, report.census[:unheld_targets]
      assert_in_delta 1.0, report.rows.first[:recall_micro], 1e-9, "a ghost partner is not a miss"
    end

    def test_sampling_is_deterministic_by_seed
      urns = (1..40).map { |i| "urn:q#{i.to_s.rjust(2, '0')}" }
      urns.each { |urn| doc(urn) }
      edges("trismegistos", "reference", urns.each_slice(2).to_a, details: Hash.new("same text (Trismegistos 1)"))
      gold = bench.gold_set(Bench.recipe("tm-same-text"))
      seen = lambda do |seed|
        producer = StubProducer.new({})
        bench.run(gold: gold, producer: producer, ks: [1], sample: 10, seed: seed)
        producer.seen.map(&:first)
      end
      assert_equal seen.call(7), seen.call(7)
      refute_equal seen.call(7), seen.call(8)
      assert_equal 10, seen.call(7).size
    end

    def test_a_gold_set_cannot_grade_itself
      edges("trismegistos", "reference", [%w[urn:a urn:b]], details: Hash.new("same text (Trismegistos 1)"))
      gold = bench.gold_set(Bench.recipe("tm-same-text"))
      producer = Bench::JournalProducer.new(links: @links, catalog: @catalog, producer: "trismegistos",
                                            kind: "reference")
      assert_raises(Bench::Error) { bench.run(gold: gold, producer: producer) }
    end

    def test_a_persisted_layer_is_measurable_as_a_producer
      %w[urn:a urn:b urn:c].each { |urn| doc(urn, passages: 2) }
      edges("trismegistos", "reference", [%w[urn:a urn:b]], details: Hash.new("same text (Trismegistos 1)"))
      run = Nabu::Store::LinksJournal.record_run!(@links, producer: "parallels", scope: "t", params: {},
                                                          code_version: "test")
      { %w[urn:a:1 urn:c:1] => 0.5, %w[urn:b:2 urn:a:2] => 0.9 }.each do |(from, to), score|
        Nabu::Store::LinksJournal.write_edge!(@links, from_urn: from, to_urn: to, kind: "parallel", score: score,
                                                      run_id: run)
      end
      producer = Bench::JournalProducer.new(links: @links, catalog: @catalog, producer: "parallels", kind: "parallel")
      assert_equal %w[urn:b urn:c], producer.candidates("urn:a", grain: :document, limit: 5),
                   "passage edges lift to documents, best score first"
      report = bench.run(gold: bench.gold_set(Bench.recipe("tm-same-text")), producer: producer, ks: [1],
                         sample: nil)
      assert_in_delta 1.0, report.rows.first[:recall_micro], 1e-9
    end

    # -- output ---------------------------------------------------------------------

    def test_the_table_and_the_sidecar_are_honest
      %w[urn:a urn:b].each { |urn| doc(urn) }
      edges("trismegistos", "reference", [%w[urn:a urn:b]], details: Hash.new("same text (Trismegistos 1)"))
      report = bench.run(gold: bench.gold_set(Bench.recipe("tm-same-text")),
                         producer: StubProducer.new("urn:a" => %w[urn:b]), ks: [1, 5], sample: nil)
      table = Bench.render(report)
      assert_match(/gold tm-same-text \(document grain\) × producer stub/, table)
      assert_match(/precision@K is a LOWER BOUND/, table)
      assert_match(/^\s+1\s+50\.0%\s+50\.0%\s+50\.0%\s+100\.0%\s+0\.50$/, table)
      Dir.mktmpdir do |dir|
        path = Bench.write_sidecar(report, Bench.default_sidecar(db_dir: dir, report: report))
        assert_equal File.join(dir, "bench", "parallels-tm-same-text-stub-nall-s1.json"), path
        data = JSON.parse(File.read(path))
        assert_equal "nabu.parallels-bench/1", data["schema"]
        assert_equal [1, 5], data["ks"]
        assert_equal 0.5, data["results"].first["recall_micro"]
        assert_equal 2, data["census"]["evaluated"]
      end
    end

    def test_the_census_renders_every_recipe
      edges("edh-edr-same-artifact", "same-artifact", [%w[urn:a urn:b]])
      rows = bench.census
      assert_equal(Bench::RECIPES.keys, rows.map { |row| row[:name] })
      edh = rows.find { |row| row[:name] == "edh-edr" }
      assert_equal 1, edh[:gold_pairs]
      text = Bench.render_census(rows)
      assert_match(/edh-edr\s+document\s+1 pairs over\s+2 urns/, text)
      assert_match(/cdli-composite .* hubs=0/, text)
    end

    def test_env_options_and_the_producer_they_name
      options = Bench.options_from_env("GOLD" => "edh-edr", "K" => "1,10", "SAMPLE" => "all", "SEED" => "3",
                                       "PROFILE" => "latin", "GRAM_SIZE" => "2")
      assert_equal [[1, 10], nil, 3], [options.ks, options.sample, options.seed]
      fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
      engine = Bench.producer_for(options, catalog: @catalog, fulltext: fulltext, links: @links)
      latin = Nabu::ReuseProfiles.default.fetch("latin")
      assert_equal({ "profile" => "latin", "gram_size" => 2, "lang" => latin.lang, "min_score" => latin.min_score },
                   engine.params.slice("profile", "gram_size", "lang", "min_score"),
                   "a profile supplies knobs; an explicit GRAM_SIZE overrides its own")
      journal_options = Bench.options_from_env("GOLD" => "census", "PRODUCER" => "journal:parallels:parallel")
      journal = Bench.producer_for(journal_options, catalog: @catalog, fulltext: fulltext, links: @links)
      assert_equal "journal:parallels:parallel", journal.name
      assert_raises(Bench::Error) { Bench.options_from_env("GOLD" => "nope") }
      assert_raises(Bench::Error) { Bench.options_from_env("GOLD" => "edh-edr", "PRODUCER" => "bm25") }
      assert_raises(Bench::Error) { Bench.options_from_env("GOLD" => "edh-edr", "K" => "x") }
      assert_nil options.fuzzy, "the fuzzy tier is off unless asked for"
      assert_equal({ "fuzzy" => nil }, engine.params.slice("fuzzy"))
    ensure
      fulltext&.disconnect
    end

    def test_the_fuzzy_tier_is_a_named_switchable_knob
      fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
      %w[fallback all].each do |scope|
        options = Bench.options_from_env("GOLD" => "edh-edr", "FUZZY" => scope)
        assert_equal scope.to_sym, options.fuzzy
        engine = Bench.producer_for(options, catalog: @catalog, fulltext: fulltext, links: @links)
        assert_equal scope, engine.params["fuzzy"], "the sidecar records which tier ran"
      end
      assert_nil Bench.options_from_env("GOLD" => "edh-edr", "FUZZY" => "off").fuzzy
      assert_raises(Bench::Error) { Bench.options_from_env("GOLD" => "edh-edr", "FUZZY" => "sometimes") }
    ensure
      fulltext&.disconnect
    end

    def test_hub_demotion_is_a_named_switchable_knob
      fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
      off = Bench.options_from_env("GOLD" => "edh-edr")
      refute off.hub, "hub demotion is off unless asked for"
      assert_equal({ "hub" => nil, "hub_df" => nil },
                   Bench.producer_for(off, catalog: @catalog, fulltext: fulltext, links: @links)
                        .params.slice("hub", "hub_df"))
      on = Bench.options_from_env("GOLD" => "edh-edr", "HUB" => "on", "HUB_DF" => "200")
      engine = Bench.producer_for(on, catalog: @catalog, fulltext: fulltext, links: @links)
      assert_equal({ "hub" => "on", "hub_df" => 200 }, engine.params.slice("hub", "hub_df"),
                   "the sidecar records which tier ran, at which cutoff")
      both = Bench.options_from_env("GOLD" => "edh-edr", "HUB" => "on", "FUZZY" => "fallback")
      assert_equal({ "hub" => "on", "fuzzy" => "fallback" },
                   Bench.producer_for(both, catalog: @catalog, fulltext: fulltext, links: @links)
                        .params.slice("hub", "fuzzy"))
      assert_raises(Bench::Error) { Bench.options_from_env("GOLD" => "edh-edr", "HUB" => "maybe") }
      assert_raises(Bench::Error) { Bench.options_from_env("GOLD" => "edh-edr", "HUB_DF" => "lots") }
    ensure
      fulltext&.disconnect
    end

    def test_the_contiguity_bonus_is_a_named_switchable_knob
      fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
      off = Bench.options_from_env("GOLD" => "edh-edr")
      refute off.contiguity, "the contiguity bonus is off unless asked for"
      plain = Bench.producer_for(off, catalog: @catalog, fulltext: fulltext, links: @links)
      assert_equal Nabu::Query::Parallels, plain.engine_class, "switch off: today's engine, untouched"
      assert_equal({ "contiguity" => nil, "contiguity_weight" => nil },
                   plain.params.slice("contiguity", "contiguity_weight"))
      on = Bench.options_from_env("GOLD" => "edh-edr", "CONTIGUITY" => "on")
      engine = Bench.producer_for(on, catalog: @catalog, fulltext: fulltext, links: @links)
      assert_equal Nabu::Query::ParallelsContiguous, engine.engine_class
      assert_equal({ "contiguity" => "on", "contiguity_weight" => 1.0 },
                   engine.params.slice("contiguity", "contiguity_weight"), "the sidecar records the weight that ran")
      swept = Bench.options_from_env("GOLD" => "edh-edr", "CONTIGUITY" => "on", "CONTIGUITY_WEIGHT" => "0.25",
                                     "FUZZY" => "fallback", "HUB" => "on")
      all = Bench.producer_for(swept, catalog: @catalog, fulltext: fulltext, links: @links)
      assert_equal Nabu::Query::ParallelsFuzzyHubContiguous, all.engine_class
      assert_equal({ "contiguity" => "on", "contiguity_weight" => 0.25, "fuzzy" => "fallback", "hub" => "on" },
                   all.params.slice("contiguity", "contiguity_weight", "fuzzy", "hub"))
      assert_equal Nabu::Query::ParallelsFuzzyHub,
                   Bench.producer_for(Bench.options_from_env("GOLD" => "edh-edr", "FUZZY" => "fallback", "HUB" => "on"),
                                      catalog: @catalog, fulltext: fulltext, links: @links).engine_class
      assert_raises(Bench::Error) { Bench.options_from_env("GOLD" => "edh-edr", "CONTIGUITY" => "yes") }
      assert_raises(Bench::Error) { Bench.options_from_env("GOLD" => "edh-edr", "CONTIGUITY_WEIGHT" => "heavy") }
    ensure
      fulltext&.disconnect
    end

    # -- the pinned baseline: the real engine over real edh/edr editions -------

    # The trimmed-real fixture editions are SHORT (one- to three-token
    # lines: EDH "uicimus" ↔ EDR "uicimus", "caecina" ↔ "gai caecinae
    # […]"), which is exactly the epigraphic reality the harness exists to
    # expose: the engine's 4-gram shingles yield NO gram from a line under
    # four tokens, so at the default gram size it finds nothing (0 of 6
    # partner slots); at gram size 1 the identical "uicimus" pair is found
    # both ways (2 of 6) while the inflected/lacunose pairs stay misses
    # (no fuzzy matching). Pinned 2026-10-22 — a technique that moves
    # these numbers moves them deliberately.
    BASELINE = { 4 => { 1 => [0, 6], 5 => [0, 6] }, 1 => { 1 => [2, 6], 5 => [2, 6] } }.freeze

    # The fuzzy 2-of-3 positional gram tier (Query::ParallelsFuzzy) over
    # the same editions, both scopes, at the default gram size — pinned
    # 2026-10-22 beside the off-state above. It moves NOTHING here, and
    # that is the measured finding, not a defect: a 2-of-3 window needs
    # two agreeing TOKENS, and these lines carry one ("caecina",
    # "uicimus", "artemo") or two that their partner never shares ("gai
    # caecinae", "ius eros"); what separates the misses is character-level
    # damage ("[…]rtemo") and inflection ("caecina" / "caecinae"), below
    # the token grain the tier works at.
    FUZZY_PIN = { fallback: { 1 => [0, 6], 5 => [0, 6] }, all: { 1 => [0, 6], 5 => [0, 6] } }.freeze

    # Hub demotion (Query::HubDemotion) at its default cutoff over the
    # same editions, at both pinned gram sizes — pinned 2026-10-27 beside
    # the off-state. It moves NOTHING here, by construction: no fixture
    # gram reaches a df of ten (two editions per stone), so there is no
    # hub mass to demote and the answer is the exact engine's.
    HUB_PIN = { 4 => { 1 => [0, 6], 5 => [0, 6] }, 1 => { 1 => [2, 6], 5 => [2, 6] } }.freeze

    # The contiguity bonus (Query::ContiguityBonus) at its default weight
    # over the same editions, at both pinned gram sizes — pinned
    # 2026-10-28 beside the off-state. It moves NOTHING here: at gram size
    # 4 the one- to three-token lines yield no gram (no run to reward);
    # at gram size 1 each found partner shares ONE token ("uicimus"), and
    # a run needs two — the bonus re-orders near-ties among multi-token
    # matches, it cannot reach a pair the exact tier never scores.
    CONTIGUITY_PIN = { 4 => { 1 => [0, 6], 5 => [0, 6] }, 1 => { 1 => [2, 6], 5 => [2, 6] } }.freeze

    def test_engine_baseline_over_the_edh_edr_fixture_editions
      fulltext = load_edh_edr_fixture_editions
      gold = bench.gold_set(Bench.recipe("edh-edr"))
      assert_equal 3, gold.pairs
      measured = BASELINE.keys.to_h do |gram_size|
        producer = Bench::EngineProducer.new(catalog: @catalog, fulltext: fulltext, gram_size: gram_size)
        report = bench.run(gold: gold, producer: producer, ks: [1, 5], sample: nil)
        assert_equal 6, report.census[:evaluated], "both editions of each stone query"
        [gram_size, report.rows.to_h { |row| [row[:k], row.values_at(:found, :gold)] }]
      end
      assert_equal BASELINE, measured, "the engine's recall over the fixture editions moved — re-measure deliberately"
    ensure
      fulltext&.disconnect
    end

    def test_fuzzy_tier_over_the_edh_edr_fixture_editions
      fulltext = load_edh_edr_fixture_editions
      gold = bench.gold_set(Bench.recipe("edh-edr"))
      measured = FUZZY_PIN.keys.to_h do |scope|
        producer = Bench::EngineProducer.new(catalog: @catalog, fulltext: fulltext, fuzzy: scope)
        report = bench.run(gold: gold, producer: producer, ks: [1, 5], sample: nil)
        [scope, report.rows.to_h { |row| [row[:k], row.values_at(:found, :gold)] }]
      end
      assert_equal FUZZY_PIN, measured, "the fuzzy tier's recall over the fixture editions moved — re-measure"
    ensure
      fulltext&.disconnect
    end

    def test_hub_demotion_over_the_edh_edr_fixture_editions
      fulltext = load_edh_edr_fixture_editions
      gold = bench.gold_set(Bench.recipe("edh-edr"))
      measured = HUB_PIN.keys.to_h do |gram_size|
        producer = Bench::EngineProducer.new(catalog: @catalog, fulltext: fulltext, gram_size: gram_size, hub: true)
        report = bench.run(gold: gold, producer: producer, ks: [1, 5], sample: nil)
        [gram_size, report.rows.to_h { |row| [row[:k], row.values_at(:found, :gold)] }]
      end
      assert_equal HUB_PIN, measured, "hub demotion's recall over the fixture editions moved — re-measure"
      assert_equal BASELINE, HUB_PIN, "no fixture gram is a hub: the on-state is the off-state"
    ensure
      fulltext&.disconnect
    end

    def test_contiguity_bonus_over_the_edh_edr_fixture_editions
      fulltext = load_edh_edr_fixture_editions
      gold = bench.gold_set(Bench.recipe("edh-edr"))
      measured = CONTIGUITY_PIN.keys.to_h do |gram_size|
        producer = Bench::EngineProducer.new(catalog: @catalog, fulltext: fulltext, gram_size: gram_size,
                                             contiguity: true)
        report = bench.run(gold: gold, producer: producer, ks: [1, 5], sample: nil)
        [gram_size, report.rows.to_h { |row| [row[:k], row.values_at(:found, :gold)] }]
      end
      assert_equal CONTIGUITY_PIN, measured, "the bonus's recall over the fixture editions moved — re-measure"
    ensure
      fulltext&.disconnect
    end

    private

    def load_edh_edr_fixture_editions
      root = Nabu::TestSupport.fixtures("edh_edr_same_artifact")
      fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
      { "edh" => Nabu::Adapters::Edh, "edr" => Nabu::Adapters::Edr }.each do |slug, klass|
        source = Nabu::Store::Source.create(slug: slug, name: slug, adapter_class: klass.name,
                                            license_class: "attribution")
        Nabu::Store::Loader.new(db: @catalog, source: source).load_from(klass.new, workdir: File.join(root, slug))
      end
      Nabu::Store::TimelineBuilder.rebuild!(catalog: @catalog, canonical_dir: root)
      Nabu::EdhEdrSameArtifact.new(catalog: @catalog, journal: @links).run("edr")
      Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: fulltext)
      fulltext
    end
  end
end
