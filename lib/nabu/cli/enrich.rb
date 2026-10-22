# frozen_string_literal: true

# Nabu::CLI — enrichment lanes: lemma-enrich, silver-dates, embed. Carved out
# of lib/nabu/cli.rb, the registry that loads it.
module Nabu
  class CLI < Thor
    desc "lemma-enrich LANGUAGE", "Run the silver-lemma enricher over the uncovered slice (P84-1)"
    long_desc <<~HELP, wrap: false
      The silver-lemma lane (P84-1): a local CPU lemmatizer (venv-managed
      Stanza; la:ittb for the Latin wave) runs over every live passage of
      LANGUAGE that has NO lemma coverage, and the raw model output lands
      on the local-lemmas shelf (local/shelves/local-lemmas/<language>/,
      through the Nabu::LemmaShelf gateway — model output costs hours of
      compute, so the derivability law homes it in a shelf, never db/).
      The shelf projects into passage_lemmas as tier-silver rows ONLY on
      the owner's word (owner-ruled 2026-08-29): --index after a campaign, or
      --index-only any time. A full rebuild never projects it (it announces
      the shelf and names this command); routine source syncs maintain
      already-projected slices but never arm a clean index. Gold rows are
      never touched: a passage with ANY existing lemma coverage is skipped.

      RESUMABLE: the campaign checkpoints at every shard flush — re-fire
      the same command after any interruption and it continues where the
      shelf left off. LANGUAGE accepts the catalog code or common aliases
      (lat/la). Wave-1 is Latin only; grc is measured but deliberately
      parked for its own wave.

      One-time setup: the venv (python + stanza + the la model) is an
      owner-run bootstrap — docs/manual/silver-lemma-venv.md. The default
      home is ~/.nabu/venvs/stanza (override: --venv or $NABU_STANZA_VENV).

      Modes:
        nabu lemma-enrich lat --dry-run        census + honest ETA, nothing runs
        nabu lemma-enrich lat                  the campaign (hours; resumable)
        nabu lemma-enrich lat --limit 100      bounded smoke run
        nabu lemma-enrich lat --index          campaign, then project the shelf
        nabu lemma-enrich lat --index-only     project the shelf, run nothing
        nabu lemma-enrich lat --spot-check 250 the P79-4 gold protocol: sample
                                               gold-annotated passages, score
                                               folded-lemma accuracy per source
    HELP
    option :dry_run, type: :boolean, default: false,
                     desc: "Census the uncovered slice and print the ETA; run nothing"
    option :limit, type: :numeric, banner: "N", desc: "Stop after N passages (smoke runs)"
    option :venv, type: :string, banner: "DIR",
                  desc: "The stanza venv (default ~/.nabu/venvs/stanza or $NABU_STANZA_VENV)"
    option :batch_size, type: :numeric, default: Nabu::LemmaEnrich::DEFAULT_BATCH,
                        desc: "Passages per model request (default #{Nabu::LemmaEnrich::DEFAULT_BATCH})"
    option :shard_size, type: :numeric, default: Nabu::LemmaEnrich::DEFAULT_SHARD,
                        desc: "Records per shelf shard / checkpoint stride " \
                              "(default #{Nabu::LemmaEnrich::DEFAULT_SHARD})"
    option :index, type: :boolean, default: false,
                   desc: "After the run, project the shelf into passage_lemmas (tier silver) now " \
                         "instead of waiting for the next rebuild/sync"
    option :index_only, type: :boolean, default: false,
                        desc: "Only project the existing shelf into passage_lemmas; run no model"
    option :spot_check, type: :numeric, banner: "N",
                        desc: "Score the model against N gold-annotated passages; writes nothing"
    def lemma_enrich(language_name)
      config = Nabu::Config.load
      language = Nabu::LemmaEnrich.resolve_language(language_name)
      shelf = Nabu::LemmaShelf.new(dir: Nabu::LemmaShelf.dir(config))
      return lemma_index_only(config, shelf) if options[:index_only]

      catalog = Nabu::Store.connect(config.catalog_path, readonly: true)
      fulltext = Nabu::Store.connect_fulltext(config.fulltext_path, readonly: true)
      begin
        enricher = Nabu::LemmaEnrich.new(
          catalog: catalog, fulltext: fulltext, shelf: shelf, language: language,
          worker_argv: options[:dry_run] ? nil : lemma_worker_argv(language),
          batch_size: options[:batch_size].to_i, shard_size: options[:shard_size].to_i,
          limit: options[:limit]&.to_i, progress: progress_reporter
        )
        return lemma_spot_check(enricher) if options[:spot_check]

        census = enricher.census
        say "silver lemmas (#{language}): #{commas(census.total)} live passages — " \
            "#{commas(census.covered)} covered, #{commas(census.shelved)} shelved, " \
            "#{commas(census.uncovered)} uncovered"
        say "  estimated #{Nabu::Eta.format_seconds(census.eta_seconds)} single-process " \
            "at the measured #{Nabu::LemmaEnrich::TRIAL_RATE.to_i} passages/s (P79-4)"
        return if options[:dry_run]

        result = enricher.run!
        finish_progress
        say "lemmatized #{commas(result.processed)} passages in " \
            "#{Nabu::Eta.format_seconds(result.elapsed_seconds)} " \
            "(#{format('%.1f', result.rate)}/s) — #{result.shards_written} shard(s) shelved; " \
            "skipped: #{commas(result.skipped_covered)} covered, " \
            "#{commas(result.skipped_shelved)} shelved, #{commas(result.skipped_empty)} empty"
        say "  model: #{result.model} #{result.model_version} (#{result.package})"
        say "  shelf: #{shelf.language_dir(language)}"
      ensure
        catalog.disconnect
        fulltext.disconnect
      end
      lemma_index_only(config, shelf) if options[:index]
    rescue Nabu::Error => e
      raise Thor::Error, e.message
    end

    desc "silver-dates", "The local-dates shelf: import date estimates, project them as silver dates (P122-1)"
    long_desc <<~HELP, wrap: false
      The silver-date lane (P122-1, the silver-lemma mold at document
      grain): model- or tool-emitted date ESTIMATES are non-derivable
      output, so they live on the local-dates shelf
      (local/shelves/local-dates/, JSONL shards written only through the
      Nabu::DateShelf gateway) — never in db/.

      --import FILE shelves one batch: a JSONL file, one estimate per line —
        {"urn": "urn:…", "not_before": -300, "not_after": -200,
         "basis": "model", "estimator": "chronos", "estimator_version": "0.3",
         "confidence": 0.8, "note": "…"}
      Signed historical years (BCE negative, no year 0; either bound may be
      null = open). Every urn must name a live document the catalog holds
      (--force shelves estimates for material not yet held). A later
      estimate for the same urn supersedes the earlier one.

      --project is the OWNER's gate: it arms the shelf and projects the
      latest estimate per live document into the timeline as SILVER rows
      (date_class "silver", precision "estimate", the estimator named in
      the date string). Once armed, every rebuild flavor, builders:refresh
      and sync re-projects behind the timeline — the lane survives `nabu
      rebuild`. --retract disarms the shelf and drops the projected rows
      (the shelf itself is untouched). Both re-derive the lemma/curve
      rollups, which bucket by date.

      Honesty: a silver date never answers a filter that promises
      upstream dates (`search --from/--to`, `vocab --by-century`, source
      date coverage, lect date inference, published nabu-data dates). It
      is the primary date only where no upstream date exists, and then
      renders labeled ("[silver — model estimate …]" on the card,
      date_class silver in exports); `search --date-basis silver` finds
      exactly those documents.

      Examples:
        nabu silver-dates                          census: shelf, arm state, projected rows
        nabu silver-dates --import estimates.jsonl
        nabu silver-dates --project
        nabu silver-dates --retract
    HELP
    option :import, type: :string, banner: "FILE", desc: "Shelve a JSONL batch of date estimates"
    option :force, type: :boolean, default: false,
                   desc: "With --import: shelve estimates for urns the catalog does not hold"
    option :project, type: :boolean, default: false,
                     desc: "Arm the shelf and project it into the timeline as silver dates (owner's gate)"
    option :retract, type: :boolean, default: false,
                     desc: "Disarm the shelf and drop the projected silver dates"
    def silver_dates
      modes = %i[import project retract].select { |mode| options[mode] }
      raise Thor::Error, "silver-dates: one of --import/--project/--retract at a time" if modes.size > 1
      raise Thor::Error, "silver-dates: --force only accompanies --import" if options[:force] && !options[:import]

      config = Nabu::Config.load
      shelf = Nabu::DateShelf.new(dir: Nabu::DateShelf.dir(config))
      case modes.first
      when :import then silver_dates_import(config, shelf)
      when :project then silver_dates_project(config, shelf)
      when :retract then silver_dates_retract(config, shelf)
      else silver_dates_census(config, shelf)
      end
    rescue Nabu::Error => e
      raise Thor::Error, "silver-dates: #{e.message}"
    end

    desc "model-budget", "The monthly paid-model spend table: show it, or set a month's cap"
    long_desc <<~HELP, wrap: false
      The model-output convention's budget table (architecture §16):
      local/config/model_budget.yml, one row per month (YYYY-MM) with the
      spend booked from every paid model call's real usage and the cap
      the owner allows. Every paid-model lane checks it AFTER its cache
      lookup and BEFORE each call; a month without a cap refuses every
      paid call (fail-closed — a cap is the owner's act, never a default).

      Bare: print the table. --cap USD sets the cap for --month (default:
      the current UTC month); spend is never reset by a cap change.

      Examples:
        nabu model-budget
        nabu model-budget --cap 20
        nabu model-budget --cap 50 --month 2026-11
    HELP
    option :cap, type: :numeric, banner: "USD", desc: "Set the month's spend cap in US dollars"
    option :month, type: :string, banner: "YYYY-MM", desc: "The month --cap applies to (default: this UTC month)"
    def model_budget
      raise Thor::Error, "model-budget: --month only accompanies --cap" if options[:month] && options[:cap].nil?

      budget = Nabu::ModelBudget.new(path: Nabu::Config.load.model_budget_path)
      if options[:cap]
        month = options[:month] || Nabu::ModelBudget.month
        budget.set_cap!(month: month, cap_usd: options[:cap])
        say format("model budget %<m>s: cap $%<c>.2f (written to %<p>s)", m: month, c: options[:cap], p: budget.path)
      end
      model_budget_table(budget)
    rescue Nabu::Error => e
      raise Thor::Error, "model-budget: #{e.message}"
    end

    desc "embed", "Build/refresh the semantic vectors over the embed-flagged sources (P93-4)"
    long_desc <<~HELP, wrap: false
      The semantic-vector build lane (owner-ruled after the P79-5 trial): encodes every
      live passage of the embed-flagged sources (registry
      `embed_index: true` — the literary core; the trial priced the full
      library as a measured NO) with the trial's model
      (multilingual-e5-base, venv worker) into db/vectors.sqlite3 — the
      store `search --similar` reads.

      INCREMENTAL BY CONSTRUCTION (the ruling's design constraint): rows
      key on (model, urn) plus the sha of the exact text embedded, never
      passage ids — so a rebuild invalidates nothing, and every run is a
      delta: the first is the priced ~22 h build (batches commit as they
      land; interrupt and re-fire freely), later runs re-embed only new
      or revised text, usually seconds. Only a deliberate MODEL change
      re-embeds everything, beside the old rows, never over them.

      Pointed Hebrew/Aramaic embeds a marks-stripped variant (the trial's
      finding: the pointed text carries zero signal for this model
      class); the stored passage text is untouched.

      One-time setup: the venv (python + sentence-transformers + the
      model) is an owner-run network bootstrap — docs/manual/embed-venv.md.
      Default home ~/.nabu/venvs/embed (override: --venv or
      $NABU_EMBED_VENV).

      Modes:
        nabu embed --status       census (fresh/stale/missing) + honest ETA, nothing runs
        nabu embed                the campaign (delta; first run ~22 h, resumable)
        nabu embed --limit 500    bounded smoke run
    HELP
    option :status, type: :boolean, default: false,
                    desc: "Census the scope (fresh/stale/missing) and print the ETA; run nothing"
    option :limit, type: :numeric, banner: "N", desc: "Stop after N passages (smoke runs)"
    option :venv, type: :string, banner: "DIR",
                  desc: "The embed venv (default ~/.nabu/venvs/embed or $NABU_EMBED_VENV)"
    option :batch_size, type: :numeric, default: Nabu::Embed::DEFAULT_BATCH,
                        desc: "Passages per model request (default #{Nabu::Embed::DEFAULT_BATCH})"
    def embed
      config = Nabu::Config.load
      registry = Nabu::SourceRegistry.load(config.sources_path)
      slugs = registry.embed_slugs
      raise Thor::Error, "no sources flagged embed_index: true in config/sources.yml" if slugs.empty?

      catalog = Nabu::Store.connect(config.catalog_path, readonly: true)
      vectors = Nabu::Store.connect(config.vectors_path)
      begin
        embedder = Nabu::Embed.new(
          catalog: catalog, vectors: vectors, slugs: slugs,
          worker_argv: options[:status] ? nil : Nabu::Embed.worker_argv(venv: options[:venv]),
          batch_size: options[:batch_size].to_i, limit: options[:limit]&.to_i,
          progress: progress_reporter
        )
        census = embedder.census
        say "embed scope: #{slugs.size} sources, #{commas(census.total)} live passages — " \
            "#{commas(census.fresh)} fresh, #{commas(census.stale)} stale, " \
            "#{commas(census.missing)} missing"
        say "  owed: #{commas(census.stale + census.missing)} passages, estimated " \
            "#{Nabu::Eta.format_seconds(census.eta_seconds)} at the measured " \
            "#{Nabu::Embed::TRIAL_RATE.round(1)} passages/s (P79-5)"
        return if options[:status]

        result = embedder.run!
        say "embedded #{commas(result.embedded)} passages in " \
            "#{Nabu::Eta.format_seconds(result.elapsed_seconds)} " \
            "(#{result.rate.round(1)}/s); skipped: #{commas(result.skipped_fresh)} fresh, " \
            "#{commas(result.skipped_empty)} empty"
        say "  model: #{result.model} dim #{result.dim} (worker #{result.worker_version})"
        say "  store: #{config.vectors_path}"
      ensure
        catalog.disconnect
        vectors.disconnect
      end
    rescue Nabu::Error => e
      raise Thor::Error, e.message
    end

    no_commands do
      # -- lemma-enrich helpers (P84-1) ------------------------------------

      def lemma_worker_argv(language)
        Nabu::LemmaEnrich.worker_argv(language: language, venv: options[:venv])
      end

      # Project the shelf into passage_lemmas now (tier silver,
      # insert-if-absent, frequencies delta'd) — the same pass every
      # rebuild/sync runs, fired standalone so a finished campaign is
      # searchable without waiting for one.
      def lemma_index_only(config, shelf)
        raise Thor::Error, "no local-lemmas shelf at #{shelf.dir} — run a campaign first" \
          if shelf.languages.empty?

        registry = Nabu::SourceRegistry.load(config.sources_path)
        catalog = Nabu::Store.connect(config.catalog_path, readonly: true)
        fulltext = Nabu::Store.connect_fulltext(config.fulltext_path)
        begin
          # P87-2: the apply rides the projection cache — the
          # fold/group work runs once per shelf state; a valid cache makes
          # this pass resolution+insert only. An UNARMED index (no silver
          # anywhere — the post-rebuild case) gets the bare-table window:
          # indexes drop, the bulk lands, each index rebuilds sorted.
          cache = Nabu::Store::SilverLemmaCache.new(
            path: Nabu::Store::SilverLemmaCache.default_path(config)
          )
          progress_reporter.stage("silver lemmas: fingerprinting the shelf")
          fingerprint = shelf.fingerprint
          cache.build!(shelf: shelf, progress: progress_reporter) unless cache.valid_for?(fingerprint)
          armed = Nabu::Store::Indexer.silver_armed?(fulltext)
          apply = lambda do
            Nabu::Store::SilverLemmaIndexer.apply_cached!(
              catalog: catalog, fulltext: fulltext, cache: cache,
              dictionary_filter_slugs: registry.lemma_filter_slugs,
              update_frequencies: true, progress: progress_reporter
            )
          end
          progress_reporter.stage("silver lemmas: projecting the cache into passage_lemmas" \
                                  "#{' (bare-table window — indexes cycle)' unless armed}")
          result = if armed
                     apply.call
                   else
                     Nabu::Store::Indexer.cycle_lemma_indexes(fulltext) { apply.call }
                   end
          finish_progress
          say "indexed #{commas(result.passages_indexed)} passages " \
              "(#{commas(result.rows_inserted)} silver rows) — skipped: " \
              "#{commas(result.skipped_covered)} already covered, " \
              "#{commas(result.skipped_missing)} missing/withdrawn, " \
              "#{commas(result.skipped_mismatch)} language-drifted; " \
              "#{commas(result.filtered_lemmas)} lemmas dictionary-filtered"
        ensure
          catalog.disconnect
          fulltext.disconnect
        end
        refresh_lemma_rollup(config)
      end

      # P121-2: the projection just moved silver passage_lemmas rows, so
      # the lemma attestation rollup re-derives in the same breath — the
      # `lemma` desk never serves a pre-projection silver curve.
      def refresh_lemma_rollup(config)
        catalog = Nabu::Store.connect(config.catalog_path)
        rows = Nabu::Store::LemmaRollup.refresh_lemmas!(catalog: catalog, fulltext_path: config.fulltext_path)
        say "lemma rollup re-derived: #{commas(rows)} rows"
      ensure
        catalog&.disconnect
      end

      # -- silver-dates (P122-1) --------------------------------------------

      def silver_dates_import(config, shelf)
        records = Nabu::DateShelf.read_import(options[:import])
        catalog = open_catalog(config) unless options[:force]
        raise Thor::Error, "silver-dates: no catalog to resolve urns against — run nabu sync, or --force" \
          if catalog.nil? && !options[:force]

        resolver = catalog && ->(urn) { !catalog[:documents].where(urn: urn, withdrawn: false).empty? }
        path = Nabu::DateShelf.new(dir: shelf.dir, resolver: resolver)
                              .append_batch!(records: records, force: options[:force])
        say "shelved #{commas(records.size)} estimate(s) → #{path}"
        say "  not yet on the timeline — `nabu silver-dates --project` projects the shelf" unless shelf.armed?
        say "  the shelf is armed — re-project now with `nabu silver-dates --project`" if shelf.armed?
      ensure
        catalog&.disconnect
      end

      def silver_dates_project(config, shelf)
        raise Thor::Error, "silver-dates: the local-dates shelf at #{shelf.dir} is empty — --import first" \
          if shelf.shard_paths.empty?

        catalog = open_or_create_catalog(config)
        shelf.arm!
        report = Nabu::Store::SilverDates.project!(catalog: catalog, shelf: shelf)
        say "projected #{commas(report.projected)} silver date(s) — " \
            "#{commas(report.unresolved)} estimate(s) name no live document, " \
            "#{commas(report.superseded)} superseded by a later estimate"
        say "  armed: every rebuild, builders:refresh and sync now re-projects the shelf"
        refresh_date_rollups(config, catalog)
      ensure
        catalog&.disconnect
      end

      def silver_dates_retract(config, shelf)
        shelf.disarm!
        catalog = open_catalog(config)
        removed = catalog ? Nabu::Store::SilverDates.retract!(catalog: catalog) : 0
        say "retracted #{commas(removed)} silver date(s); the shelf is disarmed (its estimates stay shelved)"
        refresh_date_rollups(config, catalog) if catalog
      ensure
        catalog&.disconnect
      end

      def silver_dates_census(config, shelf)
        records = 0
        shelf.each_record { records += 1 }
        say "local-dates shelf: #{shelf.dir}"
        say "  #{commas(records)} estimate(s) in #{commas(shelf.shard_paths.size)} shard(s), " \
            "#{commas(shelf.latest_by_urn.size)} document urn(s)"
        say "  #{shelf.armed? ? 'ARMED — projected at every rebuild/refresh/sync' : 'not armed — never projected'}"
        catalog = open_catalog(config)
        return unless catalog&.table_exists?(:document_axes)

        rows = catalog[:document_axes].where(axis_source: Nabu::Store::SilverDates::AXIS_SOURCE).count
        say "  #{commas(rows)} silver date row(s) on the timeline"
      ensure
        catalog&.disconnect
      end

      # The lemma/curve rollups bucket documents by date, so a moved
      # silver lane re-derives them in the same breath (the desks never
      # lag a projection — the lemma-enrich --index-only precedent).
      def refresh_date_rollups(config, catalog)
        return say("  lemma rollups: not in this catalog (migrate, then rake builders:refresh)") \
          unless Nabu::Store::LemmaRollup.available?(catalog)

        summary = Nabu::Store::LemmaRollup.rebuild!(catalog: catalog, fulltext_path: config.fulltext_path)
        say "  lemma rollups re-derived: #{commas(summary.lemma_rows)} lemma, #{commas(summary.curve_rows)} curve rows"
      end

      def model_budget_table(budget)
        table = budget.table
        if table.empty?
          say "no model budget rows — paid model calls are refused until a cap is set (nabu model-budget --cap USD)"
          return
        end
        say "month       spend_usd      cap_usd"
        table.each do |month, row|
          cap = row[:cap_usd] ? format("%.2f", row[:cap_usd]) : "(none)"
          say format("%<m>-8s %<s>12.4f %<c>12s", m: month, s: row[:spend_usd], c: cap)
        end
      end

      def lemma_spot_check(enricher)
        report = enricher.spot_check(sample: options[:spot_check].to_i)
        finish_progress
        say "gold spot-check (folded-lemma agreement on LCS-aligned tokens):"
        report.sort_by { |_slug, row| -row[:accuracy] }.each do |slug, row|
          say format("  %<slug>-18s gold_tokens=%<gold>-7d aligned=%<aligned>-7d folded=%<acc>.1f%%",
                     slug: slug, gold: row[:gold_tokens], aligned: row[:aligned], acc: row[:accuracy])
        end
        say "  (P79-4 bands: ~99% in-domain ITTB; 75–89% cross-domain — investigate a fall below them)"
      end
    end
  end
end
