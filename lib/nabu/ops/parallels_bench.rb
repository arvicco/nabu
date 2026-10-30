# frozen_string_literal: true

require "fileutils"
require "json"
require_relative "../errors"
require_relative "../query/parallels_hub"
require_relative "../query/parallels_contiguity"
require_relative "../query/parallels_novelty"

module Nabu
  module Ops
    # The parallels recall@K harness (`rake bench:parallels`; architecture
    # §13 "Measuring the engine"): the measuring stick candidate-parallels
    # techniques must clear BEFORE admission. Given a GOLD set — pairs the
    # library already holds as upstream- or curator-asserted ground truth
    # (the links journal's own reference/reuse/same-artifact edges) — and a
    # candidate PRODUCER (the live intertext engine, or a persisted mined
    # layer), it asks for each sampled query urn the producer's top-K
    # documents and reports how many of the query's gold partners came
    # back: recall@K (micro and per-query macro), hit@K, and — as CONTEXT,
    # never a score — precision@K against the gold set, a LOWER BOUND
    # (gold sets are incomplete: an unlisted true parallel reads as a miss).
    #
    # == Grain
    #
    # The engine ranks DOCUMENTS (one hit per document, Query::Parallels
    # rider ii), so every comparison happens at document grain: gold
    # targets lift to their document, producer candidates likewise. A
    # document-grain gold set queries with a whole document — every live
    # passage up to +max_anchors+ (urn sequence order) is probed and the
    # candidate documents' scores SUM across anchors (a partner sharing
    # many passages outranks one sharing a single line). A passage-grain
    # set queries with its passage alone and earns DOCUMENT credit (the
    # target passage's document came back) — stated in every report.
    #
    # == Determinism
    #
    # Queries are the gold set's urns in sorted order; a SAMPLE draws from
    # them with Random.new(seed), so a (gold, sample, seed) triple names
    # the same queries on the same catalog every time. Ties in a
    # producer's ranking break by urn.
    #
    # Read-only on every store; the one write is the JSON sidecar (a
    # deterministic function of its inputs — derived, deletable).
    class ParallelsBench
      DEFAULT_KS = [1, 5, 10, 15].freeze
      DEFAULT_SAMPLE = 200
      DEFAULT_SEED = 1
      DEFAULT_MAX_ANCHORS = 50
      SIDECAR_SCHEMA = "nabu.parallels-bench/1"

      class Error < Nabu::Error; end

      # One gold-set recipe over the links union. +mode+ :pair takes each
      # edge as one gold pair; :hub groups the edges' FROM urns by their
      # shared TO urn (a composite, a work) and takes every pair of
      # co-members — hubs above +max_hub+ members are censused and left
      # out (an O(n²) series would swamp the set). +same_language+ keeps
      # only pairs whose two documents share a language (a surface-gram
      # engine cannot cross languages; the rest are censused).
      Recipe = Data.define(:name, :producer, :kind, :grain, :mode, :detail_like, :to_like,
                           :max_hub, :same_language, :meaning) do
        def self.build(name:, producer:, kind:, grain:, meaning:, mode: :pair, detail_like: nil, to_like: nil,
                       max_hub: nil, same_language: false)
          new(name: name, producer: producer, kind: kind, grain: grain, mode: mode, detail_like: detail_like,
              to_like: to_like, max_hub: max_hub, same_language: same_language, meaning: meaning)
        end
      end

      # The held ground-truth sets (census 2026-10-22, architecture §13).
      RECIPES = [
        Recipe.build(name: "edh-edr", producer: "edh-edr-same-artifact", kind: "same-artifact", grain: :document,
                     meaning: "two editions (EDH, EDR) of ONE inscribed object, joined on the Trismegistos " \
                              "number — near-verbatim Latin; the floor any surface engine should clear"),
        Recipe.build(name: "tm-same-text", producer: "trismegistos", kind: "reference", grain: :document,
                     detail_like: "same text%",
                     meaning: "the same text held by two sources (the Trismegistos TexRelations " \
                              "concordance) — editions of one text, mostly epigraphic"),
        Recipe.build(name: "cdli-composite", producer: "cdli", kind: "reference", grain: :document, mode: :hub,
                     to_like: "urn:nabu:cdli:q%", max_hub: 25,
                     meaning: "exemplars of one composite text (CDLI Q-number, catalog composite_id / >>Q " \
                              "links) — witnesses of a composition, often fragmentary, overlapping in part; " \
                              "not physical joins (CDLI join_information is prose, eBL's joins field is empty)"),
        Recipe.build(name: "suttacentral", producer: "suttacentral", kind: "reference", grain: :document,
                     same_language: true,
                     meaning: "SuttaCentral's curated parallels (full or partial, expert-asserted) — only " \
                              "same-language pairs are reachable by surface grams; cross-language ones censused"),
        Recipe.build(name: "kitab-passages", producer: "kitab", kind: "reuse", grain: :passage,
                     meaning: "KITAB passim alignments at milestone grain (upstream machine alignment, the " \
                              "field's reference reuse data) — passage queries, document credit"),
        Recipe.build(name: "kitab-books", producer: "kitab-reuse", kind: "reuse", grain: :document,
                     meaning: "KITAB release statistics: OpenITI book pairs with >= 2 aligned reuse instances " \
                              "(upstream passim, machine-computed) — large; sample it")
      ].to_h { |recipe| [recipe.name, recipe] }.freeze

      def self.recipe(name)
        RECIPES.fetch(name) { raise Error, "unknown gold set #{name.inspect} — one of #{RECIPES.keys.join(', ')}" }
      end

      # A loaded gold set: +adjacency+ { query urn => Set of partner urns }
      # (undirected); +census+ the counts behind it.
      GoldSet = Data.define(:recipe, :adjacency, :census) do
        def name = recipe.name
        def pairs = adjacency.sum { |_urn, partners| partners.size } / 2
      end

      Report = Data.define(:gold, :grain, :meaning, :producer, :params, :ks, :sample, :seed, :census,
                           :rows, :elapsed) do
        def to_h
          { "schema" => SIDECAR_SCHEMA, "gold" => gold, "grain" => grain.to_s, "meaning" => meaning,
            "producer" => producer, "params" => params, "ks" => ks, "sample" => sample, "seed" => seed,
            "census" => census.transform_keys(&:to_s),
            "results" => rows.map { |row| row.transform_keys(&:to_s) },
            "elapsed_seconds" => elapsed.round(3) }
        end
      end

      # +links+ the links union (Store::LinkLayers); +catalog+ for the
      # document lift and the language filter.
      def initialize(links:, catalog:, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
        @links = links
        @catalog = catalog
        @clock = clock
      end

      # Load +recipe+'s gold set (lifted to documents where the recipe's
      # grain is :document; passage-grain sets keep passage queries).
      def gold_set(recipe)
        pairs, census = raw_pairs(recipe)
        pairs, census = language_filter(pairs, census) if recipe.same_language
        adjacency = Hash.new { |hash, key| hash[key] = Set.new }
        pairs.each do |a, b|
          next if a == b

          adjacency[a] << b
          adjacency[b] << a
        end
        adjacency.default_proc = nil
        GoldSet.new(recipe: recipe, adjacency: adjacency,
                    census: census.merge(gold_pairs: adjacency.sum { |_u, p| p.size } / 2,
                                         gold_urns: adjacency.size))
      end

      # The census deliverable: every recipe's loaded size, one row each.
      def census
        RECIPES.values.map do |recipe|
          { name: recipe.name, grain: recipe.grain, meaning: recipe.meaning }.merge(gold_set(recipe).census)
        end
      end

      # Run +producer+ against +gold+ (a GoldSet). Returns a Report.
      def run(gold:, producer:, ks: DEFAULT_KS, sample: DEFAULT_SAMPLE, seed: DEFAULT_SEED) # rubocop:disable Naming/MethodParameterName -- "K" is the metric's own name
        ks = ks.sort.uniq
        raise Error, "K values must be positive integers" unless ks.all? { |k| k.is_a?(Integer) && k.positive? }
        if producer.respond_to?(:gold_producer) && producer.gold_producer == gold.recipe.producer
          raise Error, "circular: the producer IS the gold set's producer (#{gold.recipe.producer})"
        end

        started = @clock.call
        queries = sample_queries(gold.adjacency.keys.sort, sample: sample, seed: seed)
        lift = document_lift(queries + queries.flat_map { |urn| gold.adjacency.fetch(urn).to_a })
        tallies = ks.to_h { |k| [k, { found: 0, gold: 0, retrieved: 0, hits: 0, recall_sum: 0.0 }] }
        census = gold.census.merge(sampled_queries: queries.size, evaluated: 0, unheld_queries: 0,
                                   unheld_targets: 0, no_reachable_targets: 0, no_candidates: 0)
        queries.each do |query|
          evaluate(query, gold: gold, producer: producer, lift: lift, ks: ks, tallies: tallies, census: census)
        end
        Report.new(gold: gold.name, grain: gold.recipe.grain, meaning: gold.recipe.meaning,
                   producer: producer.name, params: producer.params, ks: ks, sample: sample, seed: seed,
                   census: census, rows: ks.map { |k| row(k, tallies.fetch(k), census.fetch(:evaluated)) },
                   elapsed: @clock.call - started)
      end

      # The rake task's knobs, parsed from ENV (`rake bench:parallels`):
      # GOLD (a recipe name, or "census"), PRODUCER ("engine", or
      # "journal:<producer>:<kind>" for a persisted layer), K ("1,5,10,15"),
      # SAMPLE (an integer or "all"), SEED, and the engine knobs PROFILE
      # (a config/reuse_profiles.yml name), GRAM_SIZE, LANG, MIN_SCORE,
      # MAX_ANCHORS, FUZZY (off | fallback | all — the fuzzy 2-of-3
      # positional gram tier, Query::ParallelsFuzzy; off by default), HUB
      # (off | on — hub demotion, Query::HubDemotion; off by default) and
      # HUB_DF (an absolute hub cutoff overriding the corpus-relative one),
      # CONTIGUITY (off | on — the contiguity bonus, Query::ContiguityBonus;
      # off by default) and CONTIGUITY_WEIGHT (its bonus weight W, default
      # 1.0; 0 = figures only, scoring unchanged), NOVELTY (off | on —
      # novelty weighting, Query::NoveltyWeighting; off by default) and
      # NOVELTY_WEIGHT (its demotion weight W, default 1.0; 0 = scoring
      # unchanged); OUT names the sidecar (default under db/bench/).
      Options = Data.define(:gold, :producer, :ks, :sample, :seed, :profile, :gram_size, :lang, :min_score,
                            :max_anchors, :fuzzy, :hub, :hub_df, :contiguity, :contiguity_weight,
                            :novelty, :novelty_weight, :out)

      def self.options_from_env(env)
        gold = env.fetch("GOLD") { raise Error, "GOLD=<#{RECIPES.keys.join('|')}|census> is required" }
        recipe(gold) unless gold == "census"
        producer = env.fetch("PRODUCER", "engine")
        unless producer == "engine" || producer.match?(/\Ajournal:[^:]+:[^:]+\z/)
          raise Error, "PRODUCER must be engine or journal:<producer>:<kind>, got #{producer.inspect}"
        end

        sample = env.fetch("SAMPLE", DEFAULT_SAMPLE.to_s)
        Options.new(gold: gold, producer: producer,
                    ks: env.fetch("K", DEFAULT_KS.join(",")).split(",").map { |k| Integer(k.strip, 10) },
                    sample: sample == "all" ? nil : Integer(sample, 10),
                    seed: Integer(env.fetch("SEED", DEFAULT_SEED.to_s), 10),
                    profile: env["PROFILE"], gram_size: env["GRAM_SIZE"]&.then { |v| Integer(v, 10) },
                    lang: env["LANG_FILTER"], min_score: env["MIN_SCORE"]&.then { |v| Float(v) },
                    max_anchors: Integer(env.fetch("MAX_ANCHORS", DEFAULT_MAX_ANCHORS.to_s), 10),
                    fuzzy: fuzzy_scope(env.fetch("FUZZY", "off")), hub: hub_switch(env.fetch("HUB", "off")),
                    hub_df: env["HUB_DF"]&.then { |v| Integer(v, 10) },
                    contiguity: switch("CONTIGUITY", env.fetch("CONTIGUITY", "off")),
                    contiguity_weight: env["CONTIGUITY_WEIGHT"]&.then { |v| Float(v) },
                    novelty: switch("NOVELTY", env.fetch("NOVELTY", "off")),
                    novelty_weight: env["NOVELTY_WEIGHT"]&.then { |v| Float(v) }, out: env["OUT"])
      rescue ArgumentError => e
        raise Error, "bench:parallels: #{e.message}"
      end

      def self.fuzzy_scope(value)
        return nil if value == "off"

        scopes = Nabu::Query::ParallelsFuzzy::SCOPES
        return value.to_sym if scopes.map(&:to_s).include?(value)

        raise Error, "FUZZY must be off or one of #{scopes.join(', ')}, got #{value.inspect}"
      end
      private_class_method :fuzzy_scope

      def self.hub_switch(value) = switch("HUB", value)
      private_class_method :hub_switch

      def self.switch(name, value)
        return value == "on" if %w[on off].include?(value)

        raise Error, "#{name} must be off or on, got #{value.inspect}"
      end
      private_class_method :switch

      # Build the producer +options+ name. A PROFILE supplies its knobs;
      # explicit GRAM_SIZE / LANG_FILTER / MIN_SCORE override them.
      def self.producer_for(options, catalog:, fulltext:, links:)
        if options.producer.start_with?("journal:")
          _, producer, kind = options.producer.split(":", 3)
          return JournalProducer.new(links: links, catalog: catalog, producer: producer, kind: kind)
        end

        profile = options.profile && Nabu::ReuseProfiles.default.fetch(options.profile)
        EngineProducer.new(catalog: catalog, fulltext: fulltext, max_anchors: options.max_anchors,
                           lang: options.lang || profile&.lang, gram_size: options.gram_size || profile&.gram_size,
                           stop_tokens: profile&.stop_tokens, candidate_pool: profile&.candidate_pool,
                           min_score: options.min_score || profile&.min_score, profile: options.profile,
                           fuzzy: options.fuzzy, hub: options.hub, hub_df: options.hub_df,
                           contiguity: options.contiguity, contiguity_weight: options.contiguity_weight,
                           novelty: options.novelty, novelty_weight: options.novelty_weight)
      end

      # The honest table.
      def self.render(report)
        lines = []
        lines << "parallels recall@K — gold #{report.gold} (#{report.grain} grain) × producer #{report.producer}"
        lines << "  gold: #{report.meaning}"
        lines << "  params: #{JSON.generate(report.params)}"
        c = report.census
        lines << format("  queries: %<e>d evaluated of %<s>d sampled (seed %<seed>s) from %<u>d gold urns / " \
                        "%<p>d gold pairs; unheld queries %<uq>d, unheld targets %<ut>d, " \
                        "no reachable target %<nr>d, zero-candidate %<z>d",
                        e: c[:evaluated], s: c[:sampled_queries], seed: report.seed, u: c[:gold_urns],
                        p: c[:gold_pairs], uq: c[:unheld_queries], ut: c[:unheld_targets],
                        nr: c[:no_reachable_targets], z: c[:no_candidates])
        header = %w[K recall(micro) recall(macro) hit@K precision@K(lb) mean_cands]
        lines << "  #{header.map { |cell| cell.rjust(16) }.join}"
        report.rows.each do |row|
          cells = [row[:k].to_s, pct(row[:recall_micro]), pct(row[:recall_macro]), pct(row[:hit_rate]),
                   pct(row[:precision_lower_bound]), format("%.2f", row[:mean_candidates])]
          lines << "  #{cells.map { |cell| cell.rjust(16) }.join}"
        end
        lines << "  precision@K is a LOWER BOUND (gold sets are incomplete); " \
                 "#{'passage queries earn DOCUMENT credit; ' if report.grain == :passage}" \
                 "elapsed #{report.elapsed.round(1)}s"
        lines.join("\n")
      end

      # The census table (GOLD=census).
      def self.render_census(rows)
        lines = ["parallels ground-truth census — the held gold sets"]
        rows.each do |row|
          extras = row.except(:name, :grain, :meaning, :gold_pairs, :gold_urns).map { |k, v| "#{k}=#{v}" }.join(" ")
          lines << format("  %<n>-15s %<g>-8s %<p>9d pairs over %<u>8d urns  (%<x>s)",
                          n: row[:name], g: row[:grain], p: row[:gold_pairs], u: row[:gold_urns], x: extras)
          lines << "  #{' ' * 15} #{row[:meaning]}"
        end
        lines.join("\n")
      end

      def self.pct(value) = value.nil? ? "—" : format("%.1f%%", value * 100)
      private_class_method :pct

      # Write the machine-readable sidecar; returns the path.
      def self.write_sidecar(report, path)
        FileUtils.mkdir_p(File.dirname(path))
        tmp = "#{path}.tmp"
        File.write(tmp, "#{JSON.pretty_generate(report.to_h)}\n")
        File.rename(tmp, path)
        path
      end

      # The default sidecar path under db/bench/ (derived output).
      def self.default_sidecar(db_dir:, report:)
        slug = report.producer.gsub(/[^A-Za-z0-9._-]/, "_")
        File.join(db_dir, "bench", "parallels-#{report.gold}-#{slug}-n#{report.sample || 'all'}-s#{report.seed}.json")
      end

      private

      def evaluate(query, gold:, producer:, lift:, ks:, tallies:, census:) # rubocop:disable Naming/MethodParameterName
        query_doc = lift[query]
        if query_doc.nil?
          census[:unheld_queries] += 1
          return
        end
        partners = gold.adjacency.fetch(query)
        census[:unheld_targets] += partners.count { |urn| lift[urn].nil? }
        # A partner inside the query's own document is unreachable by
        # construction (the engine excludes the anchor's document).
        target_docs = partners.filter_map { |urn| lift[urn]&.fetch(:document) }.to_set
        target_docs.delete(query_doc[:document])
        if target_docs.empty?
          census[:no_reachable_targets] += 1
          return
        end

        census[:evaluated] += 1
        ranked = producer.candidates(query, grain: gold.recipe.grain, limit: ks.max)
        ranked = ranked.reject { |doc| doc == query_doc[:document] }.uniq
        census[:no_candidates] += 1 if ranked.empty?
        ks.each do |k|
          top = ranked.first(k)
          found = top.count { |doc| target_docs.include?(doc) }
          tally = tallies.fetch(k)
          tally[:found] += found
          tally[:gold] += target_docs.size
          tally[:retrieved] += top.size
          tally[:hits] += 1 if found.positive?
          tally[:recall_sum] += found.fdiv(target_docs.size)
        end
      end

      def row(cutoff, tally, evaluated)
        { k: cutoff, recall_micro: ratio(tally[:found], tally[:gold]),
          recall_macro: evaluated.zero? ? nil : tally[:recall_sum] / evaluated,
          hit_rate: ratio(tally[:hits], evaluated),
          precision_lower_bound: ratio(tally[:found], tally[:retrieved]),
          mean_candidates: evaluated.zero? ? 0.0 : tally[:retrieved].fdiv(evaluated),
          found: tally[:found], gold: tally[:gold] }
      end

      def ratio(num, den) = den.zero? ? nil : num.fdiv(den)

      def sample_queries(urns, sample:, seed:)
        return urns if sample.nil? || sample >= urns.size

        urns.sample(sample, random: Random.new(seed)).sort
      end

      # Gold edges of +recipe+, as [a, b] urn pairs, with the census.
      def raw_pairs(recipe)
        edges = @links[:links].join(:link_runs, id: :run_id)
                              .where(Sequel[:link_runs][:producer] => recipe.producer,
                                     Sequel[:links][:kind] => recipe.kind)
        edges = edges.where(Sequel.like(Sequel[:links][:detail], recipe.detail_like)) if recipe.detail_like
        edges = edges.where(Sequel.like(Sequel[:links][:to_urn], recipe.to_like)) if recipe.to_like
        rows = edges.select_map([Sequel[:links][:from_urn], Sequel[:links][:to_urn]])
        return [rows, { edges: rows.size }] unless recipe.mode == :hub

        hub_pairs(rows, recipe.max_hub)
      end

      def hub_pairs(rows, max_hub)
        hubs = rows.group_by(&:last).transform_values { |members| members.map(&:first).uniq.sort }
        kept = hubs.select { |_hub, members| members.size.between?(2, max_hub) }
        pairs = kept.values.flat_map { |members| members.combination(2).to_a }
        [pairs, { edges: rows.size, hubs: hubs.size, hubs_used: kept.size,
                  hubs_singleton: hubs.count { |_h, m| m.size < 2 },
                  hubs_over_cap: hubs.count { |_h, m| m.size > max_hub }, max_hub: max_hub }]
      end

      def language_filter(pairs, census)
        lift = document_lift(pairs.flatten.uniq)
        kept = pairs.select do |a, b|
          lift[a] && lift[b] && lift[a][:language] && lift[a][:language] == lift[b][:language]
        end
        [kept, census.merge(cross_language_or_unheld: pairs.size - kept.size)]
      end

      # urn → { document:, language: } for every urn the catalog holds as a
      # live passage (its document) or a live document; absent otherwise.
      def document_lift(urns)
        result = {}
        urns.uniq.each_slice(500) do |slice|
          @catalog[:passages].join(:documents, id: Sequel[:passages][:document_id])
                             .where(Sequel[:passages][:urn] => slice, Sequel[:passages][:withdrawn] => false)
                             .select(Sequel[:passages][:urn].as(:urn), Sequel[:documents][:urn].as(:document),
                                     Sequel[:documents][:language].as(:language))
                             .each { |row| result[row[:urn]] = { document: row[:document], language: row[:language] } }
          @catalog[:documents].where(urn: slice - result.keys, withdrawn: false)
                              .select(:urn, :language)
                              .each { |row| result[row[:urn]] = { document: row[:urn], language: row[:language] } }
        end
        result
      end

      # The first subject: the live intertext engine (Query::Parallels),
      # surface grams only (the batch producer's echoes: false), with any
      # reuse-profile knobs. +min_score+ drops hits below the floor (the
      # batch persistence rule) — nil keeps every hit. +fuzzy+ (a
      # Query::ParallelsFuzzy scope; nil = off) adds the fuzzy 2-of-3
      # positional gram tier, named in the params so a sidecar says so;
      # +hub+ (true = on) adds hub demotion (Query::HubDemotion) at the
      # corpus-relative cutoff, or at +hub_df+ when given; +contiguity+
      # (true = on) adds the contiguity bonus (Query::ContiguityBonus) at
      # weight +contiguity_weight+ (nil = its default); +novelty+ (true =
      # on) adds novelty weighting (Query::NoveltyWeighting) at weight
      # +novelty_weight+ (nil = its default), acting last. Every switch off
      # is the plain Query::Parallels engine.
      class EngineProducer
        # [fuzzy?, hub?, contiguity?, novelty?] → the engine class carrying them.
        ENGINES = {
          [false, false, false, false] => Nabu::Query::Parallels,
          [true, false, false, false] => Nabu::Query::ParallelsFuzzy,
          [false, true, false, false] => Nabu::Query::ParallelsHub,
          [true, true, false, false] => Nabu::Query::ParallelsFuzzyHub,
          [false, false, true, false] => Nabu::Query::ParallelsContiguous,
          [true, false, true, false] => Nabu::Query::ParallelsFuzzyContiguous,
          [false, true, true, false] => Nabu::Query::ParallelsHubContiguous,
          [true, true, true, false] => Nabu::Query::ParallelsFuzzyHubContiguous,
          [false, false, false, true] => Nabu::Query::ParallelsNovel,
          [true, false, false, true] => Nabu::Query::ParallelsFuzzyNovel,
          [false, true, false, true] => Nabu::Query::ParallelsHubNovel,
          [true, true, false, true] => Nabu::Query::ParallelsFuzzyHubNovel,
          [false, false, true, true] => Nabu::Query::ParallelsContiguousNovel,
          [true, false, true, true] => Nabu::Query::ParallelsFuzzyContiguousNovel,
          [false, true, true, true] => Nabu::Query::ParallelsHubContiguousNovel,
          [true, true, true, true] => Nabu::Query::ParallelsFuzzyHubContiguousNovel
        }.freeze

        def initialize(catalog:, fulltext:, max_anchors: DEFAULT_MAX_ANCHORS, lang: nil, gram_size: nil,
                       stop_tokens: nil, candidate_pool: nil, min_score: nil, profile: nil, fuzzy: nil,
                       hub: false, hub_df: nil, contiguity: false, contiguity_weight: nil, novelty: false,
                       novelty_weight: nil)
          @catalog = catalog
          @fuzzy = fuzzy
          @hub = hub
          @hub_df = hub ? hub_df : nil
          @contiguity = contiguity
          @contiguity_weight = contiguity ? contiguity_weight || Nabu::Query::ContiguityBonus::CONTIGUITY_WEIGHT : nil
          @novelty = novelty
          @novelty_weight = novelty ? novelty_weight || Nabu::Query::NoveltyWeighting::NOVELTY_WEIGHT : nil
          @engine = build_engine(catalog, fulltext)
          @max_anchors = max_anchors
          @knobs = { lang: lang, gram_size: gram_size || Nabu::Query::Parallels::GRAM_SIZE,
                     stop_tokens: stop_tokens, candidate_pool: candidate_pool }
          @min_score = min_score
          @profile = profile
        end

        def name = "engine"

        # The engine class this producer runs (the switch pin's handle).
        def engine_class = @engine.class

        def params
          { "engine" => "query-parallels", "profile" => @profile, "max_anchors" => @max_anchors,
            "lang" => @knobs[:lang], "gram_size" => @knobs[:gram_size],
            "stop_tokens" => @knobs[:stop_tokens]&.size, "candidate_pool" => @knobs[:candidate_pool],
            "min_score" => @min_score, "fuzzy" => @fuzzy&.to_s, "hub" => (@hub ? "on" : nil),
            "hub_df" => @hub_df, "contiguity" => (@contiguity ? "on" : nil),
            "contiguity_weight" => @contiguity_weight, "novelty" => (@novelty ? "on" : nil),
            "novelty_weight" => @novelty_weight,
            "aggregation" => "sum of per-anchor document scores" }
        end

        # Ranked candidate DOCUMENT urns for +query+.
        def candidates(query, grain:, limit:)
          anchors = grain == :passage ? [query] : anchor_passages(query)
          scores = Hash.new(0.0)
          anchors.each do |urn|
            result = @engine.run(urn, limit: limit, echoes: false, **@knobs)
            (result&.hits || []).each do |hit|
              next if @min_score && hit.score < @min_score

              scores[hit.urn] += hit.score
            end
          end
          by_document(scores).sort_by { |doc, score| [-score, doc] }.map(&:first).first(limit)
        end

        private

        def build_engine(catalog, fulltext)
          base = { catalog: catalog, fulltext: fulltext }
          base[:scope] = @fuzzy if @fuzzy
          base[:hub_df] = @hub_df if @hub
          base[:contiguity_weight] = @contiguity_weight if @contiguity
          base[:novelty_weight] = @novelty_weight if @novelty
          switches = [!@fuzzy.nil?, @hub ? true : false, @contiguity ? true : false, @novelty ? true : false]
          ENGINES.fetch(switches).new(**base)
        end

        def anchor_passages(document_urn)
          @catalog[:passages].join(:documents, id: Sequel[:passages][:document_id])
                             .where(Sequel[:documents][:urn] => document_urn, Sequel[:passages][:withdrawn] => false)
                             .order(Sequel[:passages][:sequence], Sequel[:passages][:urn])
                             .limit(@max_anchors)
                             .select_map(Sequel[:passages][:urn])
        end

        # Hit passage urns → their documents, scores summed.
        def by_document(scores)
          return {} if scores.empty?

          docs = @catalog[:passages].join(:documents, id: Sequel[:passages][:document_id])
                                    .where(Sequel[:passages][:urn] => scores.keys)
                                    .select_hash(Sequel[:passages][:urn].as(:passage_urn),
                                                 Sequel[:documents][:urn].as(:document_urn))
          scores.each_with_object(Hash.new(0.0)) { |(urn, score), acc| acc[docs.fetch(urn, urn)] += score }
        end
      end

      # A persisted layer as the producer: the edges +producer+ minted with
      # +kind+, neighbors of the query ranked by score (unscored last, then
      # urn), lifted to documents. Measuring a mined layer against a gold
      # set is the point; measuring a gold set against ITSELF is refused.
      class JournalProducer
        def initialize(links:, catalog:, producer:, kind:)
          @links = links
          @catalog = catalog
          @producer = producer
          @kind = kind
        end

        def name = "journal:#{@producer}:#{@kind}"
        def gold_producer = @producer
        def params = { "producer" => @producer, "kind" => @kind }

        def candidates(query, grain:, limit:)
          probe = grain == :passage ? [query] : [query] + passages_of(query)
          edges = @links[:links].join(:link_runs, id: :run_id)
                                .where(Sequel[:link_runs][:producer] => @producer, Sequel[:links][:kind] => @kind)
                                .where(Sequel.expr(Sequel[:links][:from_urn] => probe) |
                                       Sequel.expr(Sequel[:links][:to_urn] => probe))
                                .select_map([Sequel[:links][:from_urn], Sequel[:links][:to_urn],
                                             Sequel[:links][:score]])
          probe_set = probe.to_set
          ranked = edges.map { |from, to, score| [probe_set.include?(from) ? to : from, score] }
                        .sort_by { |urn, score| [score.nil? ? 1 : 0, -(score || 0), urn] }
          lift_documents(ranked.map(&:first)).uniq.first(limit)
        end

        private

        def passages_of(document_urn)
          @catalog[:passages].join(:documents, id: Sequel[:passages][:document_id])
                             .where(Sequel[:documents][:urn] => document_urn)
                             .select_map(Sequel[:passages][:urn])
        end

        def lift_documents(urns)
          return [] if urns.empty?

          docs = @catalog[:passages].join(:documents, id: Sequel[:passages][:document_id])
                                    .where(Sequel[:passages][:urn] => urns.uniq)
                                    .select_hash(Sequel[:passages][:urn].as(:passage_urn),
                                                 Sequel[:documents][:urn].as(:document_urn))
          urns.map { |urn| docs.fetch(urn, urn) }
        end
      end
    end
  end
end
