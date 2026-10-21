# frozen_string_literal: true

# Nabu::CLI — the `nabu data` subcommand family (DataCLI). Carved out of
# lib/nabu/cli.rb, the registry that loads it.
module Nabu
  # The `nabu data` command family (P50-W1, architecture §17): the production
  # rail for the public nabu-data repository. `list` is the self-documentation
  # surface (every registered feature with rationale and recommended
  # maintenance — the owner ruling); `build` runs an available feature's
  # builder and writes the dataset directory into the owner's nabu-data
  # working clone. The rail writes FILES there and never runs git operations —
  # publishing the data repo is the owner's explicit act.
  class DataCLI < Thor
    include DurationFormat

    # Thor 1.5's inherited built-ins (`tree`) render under the class
    # auto-namespace ("data_c_l_i") without this — listed in help yet not
    # invocable. The explicit namespace keeps banners truthful.
    namespace "data"

    def self.exit_on_failure?
      true
    end

    desc "list", "Document every dataset the rail can produce (rationale + maintenance included)"
    long_desc <<~HELP, wrap: false
      The rail's own documentation: one block per registered feature — slug,
      status (available | planned), title, language, tier, license,
      anchoring kind, input sources, the rationale for the dataset's
      existence, and the recommended maintenance/periodicity. Planned
      features are listed too: the census is the roadmap, and `data build`
      refuses them by name.
    HELP
    def list
      features = Nabu::DataBuild.features
      say "nabu-data build rail — #{features.size} registered feature(s):"
      features.each do |feature|
        inputs = feature.inputs.empty? ? "(own authorship)" : feature.inputs.join(", ")
        say ""
        say "#{feature.slug} — #{feature.status}"
        say "  #{feature.title}"
        say "  language: #{feature.language_code} (#{feature.language.name})   tier: #{feature.tier}   " \
            "license: #{feature.license}   anchoring: #{feature.anchoring}   inputs: #{inputs}"
        say "  rationale: #{feature.rationale}"
        say "  maintenance: #{feature.maintenance}"
        # Owner ruling 2026-07-29: the maintenance prose alone gives no
        # copy-paste path — print the exact sequence. Input syncs lead (the
        # stale-ingest guard makes them mandatory), the build closes.
        if feature.available?
          syncs = feature.inputs.map { |slug| "nabu sync #{slug} && " }.join
          say "  commands: #{syncs}nabu data build #{feature.slug} --into #{clone_hint}"
        end
      end
      say ""
      say "Planned features refuse to build until their builder lands; the census is the roadmap."
    end

    desc "build [SLUG]", "Build one dataset — or every available one with --all (files only — never git)"
    long_desc <<~HELP, wrap: false
      Runs the feature's builder and writes the complete dataset directory —
      CSVs, languages.csv, sources.bib, datapackage.json (Frictionless Data
      Package v2 + the nabu derivation block), README.md — under
      --into PATH/<lang>/<feature>/. PATH is your nabu-data development
      clone; the command writes files, prints an honest summary (rows,
      paths, fingerprint), and stops. It NEVER runs git operations there —
      review, commit, and push yourself.

      With --all, every AVAILABLE feature builds in registry order; planned
      features are skipped by name; a failing feature is reported and the
      sweep continues (census-and-continue) — the exit is nonzero if any
      failed. The stale-ingest guard applies per feature as always.

      Canonical inputs are named honestly: a git-backed cone must be clean
      (its HEAD sha is recorded); a dirty tree is refused, not misdescribed.

      Examples:
        nabu data build san/form-lemma --into ~/Dev/nabu-data
        nabu data build --all --into ~/Dev/nabu-data
    HELP
    option :into, type: :string, required: true, banner: "PATH",
                  desc: "Your nabu-data working clone — files are written under PATH/<lang>/<feature>/; " \
                        "git is never touched"
    option :all, type: :boolean, default: false,
                 desc: "Build every available feature in registry order (planned skipped by name)"
    option :verbose, type: :boolean, default: false, desc: Nabu::Ops::StageGuide::OPTION_DESC
    def build(slug = nil)
      # XOR gate: exactly one of slug / --all.
      raise Thor::Error, "data build: give either a slug or --all (see nabu data list)" if options[:all] == !slug.nil?

      verbose_narrator&.intro(:data_build)
      return build_all if options[:all]

      feature = Nabu::DataBuild.feature(slug)
      if feature.nil?
        raise Thor::Error, "data build: unknown feature #{slug.inspect}. Registered: " \
                           "#{Nabu::DataBuild.features.map(&:slug).join(', ')} (see nabu data list)"
      end
      if feature.planned?
        raise Thor::Error, "data build: #{feature.slug} is planned — its builder has not landed yet. " \
                           "#{available_features_hint}"
      end

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      explain_feature(feature)
      summary = build_runner.run(feature: feature, into: options[:into])
      print_build_summary(summary, seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
      refresh_readme_index(options[:into])
      say "No git operations were performed in #{options[:into]} — review, commit, and push there yourself."
    rescue Nabu::Error => e
      raise Thor::Error, "data build: #{e.message}"
    end

    no_commands do
      # Copy-paste honesty: name the real clone when it is where the docs
      # say it lives; otherwise an unambiguous placeholder beats a wrong path.
      def clone_hint
        File.directory?(File.expand_path("~/Dev/nabu-data")) ? "~/Dev/nabu-data" : "<your-nabu-data-clone>"
      end

      # --verbose: green narration on stderr (Ops::StageGuide).
      def verbose_narrator
        return nil unless options[:verbose]

        @verbose_narrator ||= Nabu::Ops::StageGuide::Narrator.new(io: $stderr)
      end

      # A feature's explanation is its own registry title (DataBuild
      # REGISTRY, beside its builder) — never a second string table.
      def explain_feature(feature)
        verbose_narrator&.line("#{feature.slug}: #{feature.title}")
      end

      def build_runner
        config = Nabu::Config.load
        registry = Nabu::SourceRegistry.load(config.sources_path)
        catalog = File.exist?(config.catalog_path) ? Nabu::Store.connect(config.catalog_path, readonly: true) : nil
        Nabu::DataBuild::Runner.new(config: config, registry: registry, catalog: catalog)
      end

      def print_build_summary(summary, seconds: nil)
        elapsed = seconds ? " (#{format_duration(seconds)})" : ""
        say "Built #{summary.slug} → #{summary.out_dir}#{elapsed}"
        summary.files.each do |path, rows|
          if rows.nil?
            say "  #{path}"
          else
            say format("  %-18<path>s %<rows>d row%<plural>s", path: path, rows: rows, plural: rows == 1 ? "" : "s")
          end
        end
        say "#{summary.rows} data row(s) total; derivation fingerprint #{summary.fingerprint[0, 12]}"
      end

      # `data build --all` (owner ask 2026-07-29): every available feature in
      # registry order, census-and-continue — one failure never aborts the
      # sweep; the grand total names built/skipped/failed and the exit is
      # honest (nonzero iff any failed).
      def build_all
        runner = build_runner
        built = 0
        failed = []
        skipped = []
        all_started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        Nabu::DataBuild.features.each do |feature|
          if feature.planned?
            skipped << feature.slug
            say "skipped (planned): #{feature.slug}", :yellow
            next
          end
          begin
            started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            explain_feature(feature)
            summary = runner.run(feature: feature, into: options[:into])
            print_build_summary(summary,
                                seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
            built += 1
          rescue Nabu::Error => e
            failed << feature.slug
            say "FAILED #{feature.slug}: #{e.message}", :red
          end
        end
        say "#{built} dataset(s) built, #{skipped.size} skipped (planned), #{failed.size} failed " \
            "in #{format_duration(Process.clock_gettime(Process::CLOCK_MONOTONIC) - all_started)}"
        refresh_readme_index(options[:into])
        say "No git operations were performed in #{options[:into]} — review, commit, and push there yourself."
        raise Thor::Error, "data build --all: failed: #{failed.join(', ')}" unless failed.empty?
      end

      # The repository README's dataset table regenerates after every build
      # (ReadmeIndex — owner correction 2026-10-17: the hand table had gone
      # a release stale). A scratch --into dir with no README is a silent
      # no-op; a clone README missing the markers raises loudly.
      def refresh_readme_index(into)
        return unless File.exist?(File.join(into, "README.md"))

        features = Nabu::DataBuild.features
        dates = Nabu::DataBuild::ReadmeIndex.published_dates(
          out_dir: into, slugs: features.select(&:available?).map(&:slug)
        )
        result = Nabu::DataBuild::ReadmeIndex.refresh!(features: features, out_dir: into,
                                                       published_dates: dates)
        say "README dataset table regenerated — #{result.listed} dataset(s) listed" \
            "#{" (not yet built here: #{result.missing.join(', ')})" unless result.missing.empty?}"
      end

      def available_features_hint
        available = Nabu::DataBuild.features.select(&:available?).map(&:slug)
        if available.empty?
          "No builders have shipped yet — nabu data list documents the roadmap."
        else
          "Available now: #{available.join(', ')} (nabu data list documents the roadmap)."
        end
      end
    end
  end
end
