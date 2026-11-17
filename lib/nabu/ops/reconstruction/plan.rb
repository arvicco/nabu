# frozen_string_literal: true

require_relative "source_class"
require_relative "../rail_plan"
require_relative "../../eta"
require_relative "../../tool_bootstrap"
require_relative "../../store/stage_timings"

module Nabu
  module Ops
    module Reconstruction
      # `nabu reconstruct plan`: the ordered bootstrap plan from a bare
      # clone, each step estimated from the box's OWN history where it can
      # answer and labeled "unmeasured" where it cannot — never a guess.
      #
      #   1. tools        — the ToolBootstrap tasks (no timing).
      #   2. modules      — kind: module registry rows, fetched first; each
      #                     estimate is its last succeeded sync run
      #                     (Eta.last_sync — an incremental re-sync may
      #                     understate a cold fetch; the ledger keeps no
      #                     other per-source fetch figure).
      #   3. sources      — wired corpus sources bucketed by SourceClass
      #                     verdict; per bucket the summed last-sync seconds
      #                     and the unmeasured count. Syncs run parallel
      #                     across sources, so the sum is COMPUTE, the
      #                     longest single source the wall-clock floor.
      #      rail_paced   — the cone math instead: slice time per
      #                     Ops::RailPlan (the newest complete fetch→load
      #                     step), the cone off each lane's persisted
      #                     last_slice (census / remaining ÷ slice size),
      #                     and the OBSERVED cadence (fetch steps per day
      #                     over the sync stage-timing history). From a bare
      #                     clone the whole cone re-crawls.
      #   4. rebuild      — the governing stage_timings row of every
      #                     (scope, stage) under kind "rebuild", summed.
      #   5. enrichments  — the capability registry's enrichment-produced
      #                     layers, each with its command; mined_links
      #                     reads the mined store's per-layer measured
      #                     seconds, the others any stage_timings kind named
      #                     by the command's verb.
      #
      # READ-ONLY by construction: every input is handed in already open
      # (or nil = absent → unmeasured). The backup-critical set — local/
      # layers no command regenerates, plus atticked canonical bytes — is
      # listed, never "planned".
      class Plan
        TIMED_CLASSES = %i[public_stable manual granted restricted].freeze

        Timed = Data.define(:slug, :seconds) do
          def measured? = !seconds.nil?
        end

        Bucket = Data.define(:klass, :sources) do
          def measured = sources.select(&:measured?)
          def measured_seconds = measured.sum(&:seconds)
          def unmeasured = sources.count { |source| !source.measured? }
          def longest = measured.max_by(&:seconds)
        end

        Rail = Data.define(:slug, :cap, :slice_seconds, :remaining_steps, :full_steps, :steps_per_day) do
          def remaining_days = days(remaining_steps)
          def full_days = days(full_steps)
          def full_compute_seconds = slice_seconds && full_steps && (full_steps * slice_seconds)

          def days(steps)
            steps && steps_per_day&.positive? ? steps / steps_per_day : nil
          end
        end

        Rebuild = Data.define(:corpus_seconds, :source_seconds, :stages) do
          def seconds = corpus_seconds + source_seconds
        end

        Enrichment = Data.define(:layer, :command, :seconds, :basis)

        Report = Data.define(:tools, :modules, :classes, :unwired, :rails, :rebuild, :enrichments,
                             :backup, :attic, :local_dir, :local_present)

        # The ToolBootstrap tasks, one rake line each (bang methods are the
        # tasks; a keyword parameter becomes the task's bracket argument).
        def self.tool_tasks
          ToolBootstrap.public_instance_methods(false).grep(/!\z/).sort.map do |name|
            params = ToolBootstrap.instance_method(name).parameters.map { |(_, param)| param.to_s.upcase }
            task = "bundle exec rake tools:#{name.to_s.delete_suffix('!')}"
            params.empty? ? task : "#{task}[#{params.join(',')}]"
          end
        end

        def initialize(registry:, verdicts:, ledger:, capabilities:, canonical_dir:, local_dir:, mined_layers: [])
          @registry = registry
          @verdicts = verdicts.to_h { |verdict| [verdict.slug, verdict] }
          @ledger = ledger
          @layers = capabilities.fetch("layers", {})
          @canonical_dir = canonical_dir
          @local_dir = local_dir
          @mined_layers = mined_layers
        end

        def build
          Report.new(tools: self.class.tool_tasks, modules: modules, classes: classes, unwired: unwired,
                     rails: rails, rebuild: rebuild, enrichments: enrichments, backup: backup,
                     attic: @verdicts.values.select(&:attic).map(&:slug).sort,
                     local_dir: @local_dir, local_present: File.directory?(@local_dir.to_s))
        end

        def self.render(report)
          Render.new(report).to_s
        end

        private

        def entries = @registry.each_source.to_a

        def timed(slug)
          Timed.new(slug: slug, seconds: Eta.last_sync(@ledger, slug: slug)&.seconds)
        end

        def modules
          entries.select(&:feature_module?).map { |entry| timed(entry.slug) }
        end

        def corpus = entries.select { |entry| entry.source? && entry.wired }

        def classes
          TIMED_CLASSES.to_h do |klass|
            slugs = corpus.map(&:slug).select { |slug| @verdicts[slug]&.klass == klass }
            [klass, Bucket.new(klass: klass, sources: slugs.map { |slug| timed(slug) })]
          end
        end

        def unwired = entries.select { |entry| entry.source? && !entry.wired }.map(&:slug)

        def rails
          slugs = corpus.map(&:slug).select { |slug| @verdicts[slug]&.klass == :rail_paced }
          return [] if slugs.empty?

          measured = RailPlan.new(registry: @registry, ledger: @ledger).plan.all_sources.to_h do |source|
            [source.slug, source]
          end
          slugs.map do |slug|
            source = measured[slug]
            remaining, full = cone(slug)
            Rail.new(slug: slug, cap: source&.cap, slice_seconds: source&.slice_seconds,
                     remaining_steps: remaining, full_steps: full, steps_per_day: cadence(slug))
          end
        end

        # [remaining steps, full-cone steps] off each lane's persisted last
        # slice (one sync step runs every lane a slice, so the slowest lane
        # governs); [nil, nil] when no lane has ever reported.
        def cone(slug)
          adapter = @registry[slug].build_adapter
          return [nil, nil] unless adapter.respond_to?(:paced_crawls) && @canonical_dir

          reports = adapter.paced_crawls(File.join(@canonical_dir, slug)).values.filter_map(&:last_slice)
          reports = reports.select { |last| last["slice"].to_i.positive? }
          return [nil, nil] if reports.empty?

          steps = ->(key) { reports.map { |last| (key.call(last).to_i / last["slice"].to_f).ceil }.max }
          [steps.call(->(last) { last.dig("remaining", "after") }), steps.call(->(last) { last["census"] })]
        rescue Nabu::Error
          [nil, nil]
        end

        # Fetch steps per day over the source's sync stage-timing history;
        # nil below two steps (no span to measure a rate over).
        def cadence(slug)
          return nil unless Store::StageTimings.table?(@ledger)

          stamps = @ledger[Store::StageTimings::TABLE].where(kind: "sync", scope: slug, stage: "fetch")
                                                      .order(:id).select_map(:finished_at)
          return nil if stamps.size < 2

          span_days = (stamps.last - stamps.first) / 86_400.0
          span_days.positive? ? (stamps.size - 1) / span_days : nil
        end

        def rebuild
          rows = Store::StageTimings.latest_per_stage(@ledger, kind: "rebuild")
          return nil if rows.empty?

          corpus, sources = rows.partition { |row| row[:scope] == "corpus" }
          Rebuild.new(corpus_seconds: corpus.sum { |row| row[:seconds].to_f },
                      source_seconds: sources.sum { |row| row[:seconds].to_f }, stages: rows.size)
        end

        def enrichments
          @layers.select { |_, layer| layer["producer"] == "enrichment" }.sort.map do |name, layer|
            seconds, basis = name == "mined_links" ? mined_estimate : verb_estimate(layer["command"].to_s)
            Enrichment.new(layer: name, command: layer["command"], seconds: seconds, basis: basis)
          end
        end

        def mined_estimate
          timed = @mined_layers.reject { |layer| layer.seconds.nil? }
          return [nil, nil] if timed.empty?

          basis = timed.map { |layer| "#{layer.label} #{Eta.format_seconds(layer.seconds)}" }.join(", ")
          [timed.sum(&:seconds), "mined layers: #{basis}"]
        end

        # A stage_timings kind named by the command's verb ("nabu embed" →
        # kind "embed"), summed over its governing rows.
        def verb_estimate(command)
          verb = command[/\Anabu ([a-z][a-z-]*)/, 1]
          rows = verb ? Store::StageTimings.latest_per_stage(@ledger, kind: verb) : []
          return [nil, nil] if rows.empty?

          [rows.sum { |row| row[:seconds].to_f }, "stage timings (kind #{verb}, #{rows.size} stages)"]
        end

        # [[layer, home]] for every local/ layer no command regenerates: the
        # non-enrichment ones, plus enrichments whose product came from
        # outside (an imported file, paid model output) — re-running their
        # command needs the very input that is lost.
        def backup
          @layers.select { |_, layer| layer["home"].to_s.start_with?("local/") && irreplaceable?(layer) }
                 .sort.map { |name, layer| [name, layer["home"]] }
        end

        def irreplaceable?(layer)
          layer["producer"] != "enrichment" || %w[acquired paid].include?(layer["cost"])
        end

        # The card's text (Plan.render).
        class Render
          def initialize(report)
            @report = report
          end

          def to_s
            lines = ["reconstruct plan — the bootstrap from a bare clone, in order " \
                     "(estimates from this box's own history; approximate)"]
            lines.concat(tools, modules, sources, rails, rebuild, enrichments, headline)
            "#{lines.join("\n")}\n"
          end

          private

          def fmt(seconds) = seconds ? Eta.format_seconds(seconds) : "unmeasured"

          def tools
            ["", "1. tools (external bootstraps, idempotent; no timing)"] +
              @report.tools.map { |task| "   #{task}" }
          end

          def modules
            rows = @report.modules
            measured = rows.select(&:measured?)
            ["", "2. sister/module sources — fetch first (#{rows.size} modules; " \
                 "#{fmt(measured.sum(&:seconds))} summed, #{rows.size - measured.size} unmeasured)"] +
              rows.map { |row| format("   %-24<s>s %<t>s", s: row.slug, t: fmt(row.seconds)) }
          end

          def sources
            lines = ["", "3. sources by reconstruction class (estimate = each source's last successful sync)"]
            @report.classes.each_value do |bucket|
              longest = bucket.longest
              floor = longest ? "; longest #{longest.slug} #{fmt(longest.seconds)}" : ""
              lines << format("   %-14<k>s %4<n>d sources  %<sum>s summed compute, %<u>d unmeasured%<f>s",
                              k: bucket.klass, n: bucket.sources.size, sum: fmt(bucket.measured_seconds),
                              u: bucket.unmeasured, f: floor)
            end
            lines << "   (syncs run parallel across sources: the sum is compute; wall-clock is parallel, " \
                     "floored by the longest source)"
            lines << "   unwired (never synced by the plan): #{@report.unwired.size}" unless @report.unwired.empty?
            lines
          end

          def rails
            return [] if @report.rails.empty?

            lines = ["   rail_paced     #{@report.rails.size} sources — paced crawls, the cone re-crawls whole " \
                     "(approximate: measured slice × cone ÷ observed cadence)"]
            @report.rails.each { |rail| lines << "     #{rail_line(rail)}" }
            lines
          end

          def rail_line(rail)
            return "#{rail.slug}: cone unknown (no persisted slice) — unmeasured" if rail.full_steps.nil?

            cone = "#{rail.slug}: full cone #{rail.full_steps} slice(s) (#{rail.remaining_steps} still to go)"
            compute = if rail.slice_seconds
                        "#{fmt(rail.slice_seconds)}/slice → #{fmt(rail.full_compute_seconds)} " \
                          "compute"
                      else
                        "slice time unmeasured"
                      end
            wall = if rail.full_days
                     "≈#{months(rail.full_days)} wall at the observed #{rail.steps_per_day.round(2)} slices/day " \
                       "(cap #{rail.cap}/phase)"
                   else
                     "cadence unmeasured (cap #{rail.cap}/phase)"
                   end
            "#{cone}; #{compute}; #{wall}"
          end

          def months(days)
            days >= 60 ? "#{(days / 30.4).round(1)} months" : "#{days.round(1)} days"
          end

          def rebuild
            rebuild = @report.rebuild
            return ["", "4. the owner-fired rebuild — unmeasured (no rebuild stage timings)"] if rebuild.nil?

            ["", "4. the owner-fired rebuild — ~#{fmt(rebuild.seconds)} summed over #{rebuild.stages} recorded stages",
             "   corpus stages #{fmt(rebuild.corpus_seconds)} + per-source loads #{fmt(rebuild.source_seconds)} " \
             "(each stage's latest recorded run)"]
          end

          def enrichments
            lines = ["", "5. enrichments (separate commands, never the rebuild — the cost law)"]
            @report.enrichments.each do |row|
              basis = row.basis ? " (#{row.basis})" : ""
              lines << format("   %-14<l>s %-32<c>s %<t>s%<b>s", l: row.layer, c: row.command, t: fmt(row.seconds),
                                                                 b: basis)
            end
            lines
          end

          # Measured compute OUTSIDE the rails (their compute is politeness-
          # bound wall time, stated apart).
          def measured_seconds
            r = @report
            [r.modules.select(&:measured?).sum(&:seconds), r.classes.values.sum(&:measured_seconds),
             r.rebuild&.seconds.to_f, r.enrichments.filter_map(&:seconds).sum].sum
          end

          def unmeasured_steps
            r = @report
            r.modules.count { |row| !row.measured? } + r.classes.values.sum(&:unmeasured) +
              r.rails.count { |rail| rail.full_compute_seconds.nil? } + (r.rebuild ? 0 : 1) +
              r.enrichments.count { |row| row.seconds.nil? }
          end

          def headline
            ["", "headline: ~#{fmt(measured_seconds)} of summed measured compute outside the rails (modules, " \
                 "sources, rebuild, enrichments; syncs parallelize across sources, so wall-clock is far " \
                 "shorter); #{unmeasured_steps} unmeasured step(s) carry no estimate; #{rail_headline}.",
             "NOT reconstructed by any step — the backup-critical set: local/ " \
             "(rulings, grants, shelves, the ledger) and atticked canonical bytes.", local_line] +
              @report.backup.map { |name, home| format("   %-18<n>s %<h>s", n: name, h: home) } +
              attic_lines
          end

          def rail_headline
            rails = @report.rails
            rail_days = rails.filter_map(&:full_days).max
            return "no rail wall-clock is measured" unless rail_days

            "the rails add ~#{fmt(rails.filter_map(&:full_compute_seconds).sum)} of slice compute, paced: the " \
              "longest re-crawl runs ≈#{months(rail_days)} of wall-clock at its observed cadence"
          end

          def local_line
            return "   local/ at #{@report.local_dir}:" if @report.local_present

            "   no local/ at #{@report.local_dir} — a bare clone: nothing instance-held exists to back up yet"
          end

          def attic_lines
            return [] if @report.attic.empty?

            ["   attic (upstream-deleted bytes, backup-only): #{@report.attic.size} sources — " \
             "#{@report.attic.join(', ')}"]
          end
        end
      end
    end
  end
end
