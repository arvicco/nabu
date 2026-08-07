# frozen_string_literal: true

require "thor"
require_relative "version"
require_relative "display"

module Nabu
  # The `nabu data` command family (P50-W1, architecture §17): the production
  # rail for the public nabu-data repository. `list` is the self-documentation
  # surface (every registered feature with rationale and recommended
  # maintenance — the owner ruling); `build` runs an available feature's
  # builder and writes the dataset directory into the owner's nabu-data
  # working clone. The rail writes FILES there and never runs git operations —
  # publishing the data repo is the owner's explicit act.
  class DataCLI < Thor
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
    def build(slug = nil)
      # XOR gate: exactly one of slug / --all.
      raise Thor::Error, "data build: give either a slug or --all (see nabu data list)" if options[:all] == !slug.nil?

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

      summary = build_runner.run(feature: feature, into: options[:into])
      print_build_summary(summary)
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

      def build_runner
        config = Nabu::Config.load
        registry = Nabu::SourceRegistry.load(config.sources_path)
        catalog = File.exist?(config.catalog_path) ? Nabu::Store.connect(config.catalog_path, readonly: true) : nil
        Nabu::DataBuild::Runner.new(config: config, registry: registry, catalog: catalog)
      end

      def print_build_summary(summary)
        say "Built #{summary.slug} → #{summary.out_dir}"
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
        Nabu::DataBuild.features.each do |feature|
          if feature.planned?
            skipped << feature.slug
            say "skipped (planned): #{feature.slug}", :yellow
            next
          end
          begin
            print_build_summary(runner.run(feature: feature, into: options[:into]))
            built += 1
          rescue Nabu::Error => e
            failed << feature.slug
            say "FAILED #{feature.slug}: #{e.message}", :red
          end
        end
        say "#{built} dataset(s) built, #{skipped.size} skipped (planned), #{failed.size} failed"
        say "No git operations were performed in #{options[:into]} — review, commit, and push there yourself."
        raise Thor::Error, "data build --all: failed: #{failed.join(', ')}" unless failed.empty?
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

  # The lect-assignment journal CLI (P58-1): the owner's hand on the
  # per-document overlay tier of Nabu::Lects#resolve. Every subcommand
  # operates on db/lects.sqlite3 (Store::LectJournal — rebuild never touches
  # it) and validates lect ids against the LIVE registry: an undefined tag
  # is refused loudly, never silently coerced (the registry's own rule).
  class LectCLI < Thor
    # The DataCLI namespace note applies here too (Thor 1.5 `tree`).
    namespace "lect"

    def self.exit_on_failure?
      true
    end

    desc "assign [URN LECT_ID]", "Rule that URN's use of a code means LECT_ID (journaled; survives rebuild)"
    long_desc <<~HELP, wrap: false
      The per-document tier of lect resolution — the highest-precedence seam,
      above per-source overrides and the universal codemap. One CURRENT
      assignment per (URN, code); re-assigning updates in place. The code
      being refined defaults to the document's own catalog language; pass
      --code when the catalog is absent or the document is polyglot.

      --from-file imports a ratified batch (TSV: urn, code, lect_id, then
      optional basis and note columns — exactly `lect list --format tsv`'s
      shape, so the flat export re-imports as a restore path). Comment (#)
      and blank lines skip. The whole batch is validated before ANY row is
      written: one bad line rejects the file.
    HELP
    option :code, banner: "CODE", desc: "the stored bare code the ruling refines"
    option :note, banner: "TEXT", desc: "the why, kept with the ruling"
    option :basis, default: "owner", banner: "owner|rule:<id>",
                   desc: "authorship of the ruling (rule bases are re-run-superseded wholesale)"
    option :from_file, banner: "FILE", desc: "bulk import a ratified TSV batch"
    def assign(urn = nil, lect_id = nil)
      config = Nabu::Config.load
      registry = require_lects_module!(config)
      check_basis!(options[:basis])
      if options[:from_file]
        import_batch!(config, registry, options[:from_file])
      else
        raise Thor::Error, "lect assign: URN and LECT_ID are required (or --from-file FILE)" unless urn && lect_id

        check_lect!(registry, lect_id)
        code = options[:code] || infer_code!(config, urn)
        journal = Nabu::Store::LectJournal.open!(config.lects_journal_path)
        verdict = Nabu::Store::LectJournal.assign!(journal, urn: urn, code: code, lect_id: lect_id,
                                                            basis: options[:basis], note: options[:note])
        say "#{verdict}  #{urn}  #{code} → #{lect_id}  (#{options[:basis]})"
        refresh_lect_facet(config, urn)
      end
    end

    desc "list", "The journaled assignments (--urn/--basis filters; --format tsv is the flat backup)"
    option :urn, banner: "URN"
    option :basis, banner: "owner|rule:<id>"
    option :format, banner: "tsv"
    # census: render cap only — the full journal is always in the tsv export;
    # truncation is announced (the house honesty vocabulary)
    option :limit, type: :numeric, default: 50
    def list
      config = Nabu::Config.load
      journal = Nabu::Store::LectJournal.open_readonly(config.lects_journal_path)
      unless journal
        return say "no lect assignments (#{config.lects_journal_path} absent) — " \
                   "nabu lect assign mints the first"
      end

      scope = journal[:lect_assignments].order(:urn, :code)
      scope = scope.where(urn: options[:urn]) if options[:urn]
      scope = scope.where(basis: options[:basis]) if options[:basis]
      if options[:format] == "tsv"
        scope.each { |row| say row.values_at(:urn, :code, :lect_id, :basis, :note).join("\t") }
      else
        render_table(journal, scope)
      end
    end

    desc "apply-rules", "Compile the ratified facet→lect rules into journal assignments (--dry-run first)"
    long_desc <<~HELP, wrap: false
      Reads config/lect_facet_rules.yml (owner-ratified document-group rules:
      a source's facet value names the stage of every document carrying it),
      censuses the live catalog, and writes one journal row per matched
      document with basis rule:<id>. A re-run supersedes exactly its own
      rows; an existing (urn, code) assignment — a hand ruling, another
      rule — is never overwritten (counted as skipped). --dry-run renders
      the full value → lect census, including unmatched values, and writes
      nothing: the owner reviews that report before any batch lands.
    HELP
    option :rule, banner: "ID", desc: "compile just this rule"
    option :dry_run, type: :boolean, default: false
    def apply_rules
      config = Nabu::Config.load
      registry = require_lects_module!(config)
      rules = Nabu::LectRules.load(config.lect_facet_rules_path)
      raise Thor::Error, "lect apply-rules: no rules file at #{config.lect_facet_rules_path}" unless rules

      begin
        rules.validate!(registry)
      rescue Nabu::Error => e
        raise Thor::Error, e.message
      end
      unless File.exist?(config.catalog_path)
        raise Thor::Error,
              "lect apply-rules: no catalog at #{config.catalog_path}"
      end

      catalog = Nabu::Store.connect(config.catalog_path)
      journal = options[:dry_run] ? nil : Nabu::Store::LectJournal.open!(config.lects_journal_path)
      # A compose rule's census reads the CURRENT journal even on --dry-run
      # (it buckets candidates by their existing stage rows); absent file →
      # nil → the census reports every candidate as rowless, honestly.
      census_journal = journal || Nabu::Store::LectJournal.open_readonly(config.lects_journal_path)
      selected_rules(rules).each { |rule| run_rule(rules, rule, catalog, journal, census_journal) }
      if options[:dry_run]
        say "dry run — nothing written (drop --dry-run to compile)"
      else
        materialize_lect_facets!(config, catalog: catalog)
      end
    end

    desc "infer-dates", "Infer stages from document dates × registry bands (--dry-run first)"
    long_desc <<~HELP, wrap: false
      The document grain for dated-but-unstaged holdings (Latin epigraphy
      above all): a document whose code resolves to a bare anchor, whose
      date interval is closed, and whose interval sits INSIDE EXACTLY ONE
      attested stage band, is assigned that stage (journal basis
      rule:date-band; the note carries the dating). Containment, never
      overlap — a date spanning two bands stays honestly bare, and every
      skip reason is tallied in the report. Same discipline as apply-rules:
      re-runs supersede their own basis, existing rulings always win,
      --dry-run writes nothing.
    HELP
    option :source, banner: "SLUG", desc: "scope to one source"
    option :lang, banner: "CODE", desc: "scope to one stored code"
    option :dry_run, type: :boolean, default: false
    def infer_dates
      config = Nabu::Config.load
      registry = require_lects_module!(config)
      unless File.exist?(config.catalog_path)
        raise Thor::Error,
              "lect infer-dates: no catalog at #{config.catalog_path}"
      end

      catalog = Nabu::Store.connect(config.catalog_path)
      dates = Nabu::LectDates.new(registry: registry)
      report = dates.census(catalog: catalog, source: options[:source], lang: options[:lang])
      report.assignable.sort_by { |_key, count| -count }.each do |(source, code, lect_id), count|
        say format("  %<source>-16s %<code>-6s → %<lect>-10s %<count>d",
                   source: source, code: code, lect: lect_id, count: count)
      end
      report.skipped.sort_by { |_reason, count| -count }.each do |reason, count|
        say "  (#{reason.to_s.tr('_', ' ')}: #{count})"
      end
      say "  assignable: #{report.candidates.size}"
      if options[:dry_run]
        say "dry run — nothing written (drop --dry-run to compile)"
      else
        journal = Nabu::Store::LectJournal.open!(config.lects_journal_path)
        outcome = dates.apply!(catalog: catalog, journal: journal,
                               source: options[:source], lang: options[:lang])
        suffix = outcome.skipped.positive? ? " (#{outcome.skipped} skipped — already ruled)" : ""
        say "  assigned #{outcome.assigned}#{suffix}"
        materialize_lect_facets!(config, catalog: catalog)
      end
    end

    desc "materialize", "Recompute the derived lect facet (document_facets 'lect') from the current resolution"
    long_desc <<~HELP, wrap: false
      Flattens the whole lect resolution — journal rulings, per-source
      overrides, universal codemap — into one document_facets row per
      document whose resolution differs from its bare code (no row means
      identity). `nabu rebuild` runs this automatically; the journal CLI
      refreshes single documents; this command is the manual full pass
      (e.g. after hand-editing config/lect_overrides.yml).
    HELP
    def materialize
      config = Nabu::Config.load
      require_lects_module!(config)
      unless File.exist?(config.catalog_path)
        raise Thor::Error,
              "lect materialize: no catalog at #{config.catalog_path}"
      end

      materialize_lect_facets!(config)
    end

    desc "suggest SLUG", "The front-door census: what could refine this source's lect posture (report-only)"
    long_desc <<~HELP, wrap: false
      Inspects ONE source's held metadata against the lect registry and
      reports what could refine it (P59-4): each language code with its
      current resolution and whether the anchor carries stages at all; the
      source's facet vocabulary (a small label set over a staged anchor is
      a rule candidate — a scaffold stanza is sketched for the best one);
      and the date-band inference census. REPORT-ONLY by design — adapters
      never write the journal; the owner (or a ruled rule in
      config/lect_facet_rules.yml) applies. The new-adapter checklist runs
      this at adapter-add time; the outcome lands as a rule, an override,
      or a config/postures.yml lect declaration (identity is an honest
      answer).
    HELP
    def suggest(slug = nil)
      slug = slug.to_s.strip
      raise Thor::Error, "lect suggest: give a source slug" if slug.empty?

      config = Nabu::Config.load
      registry = require_lects_module!(config)
      raise Thor::Error, "lect suggest: no catalog at #{config.catalog_path}" unless File.exist?(config.catalog_path)

      catalog = Nabu::Store.connect(config.catalog_path)
      report = Nabu::LectSuggest.new(catalog: catalog, registry: registry).run(slug)
      raise Thor::Error, "lect suggest: unknown source or no live documents: #{slug}" if report.nil?

      render_suggest_report(report)
    ensure
      catalog&.disconnect
    end

    desc "dossiers", "Accrete the registry stage ladder into existing language dossiers (idempotent)"
    long_desc <<~HELP, wrap: false
      The dossier stage section (P60 rider, the P58-6 deferral): every
      registry anchor with stages or registered varieties whose language
      dossier EXISTS (canonical/local-language/<code>.md) gains one
      structured "## stages (nabu-lects, DATE)" section through the
      sanctioned LanguageShelf gateway — registry facts only (tags, names,
      bands, the reconstructed asterisk), never live counts (the live card
      computes those fresh). Idempotent: unchanged ladders never re-write,
      so the section date moves only when the registry did. Anchors without
      a dossier are skipped, never skeletonized. After a write, run
      `bin/nabu sync local-language` to refresh the derived catalog records.
    HELP
    method_option :"dry-run", type: :boolean, default: false, desc: "Report without writing"
    def dossiers
      config = Nabu::Config.load
      registry = require_lects_module!(config)
      shelf = Nabu::LanguageShelf.new(dir: Nabu::LanguageShelf.dir(config.canonical_dir))
      report = Nabu::LectDossiers.new(lects: registry, shelf: shelf).run!(dry_run: options[:"dry-run"])
      verb = options[:"dry-run"] ? "would write" : "wrote"
      say "stage sections: #{verb} #{report.written.size} " \
          "(#{report.unchanged.size} unchanged, #{report.skipped.size} anchors without a dossier)"
      say "  #{verb}: #{report.written.join(', ')}" if report.written.any?
      say "next: bin/nabu sync local-language (derives the catalog records)" \
        unless options[:"dry-run"] || report.written.empty?
    end

    desc "check-dates", "The reverse audit: journal assignments whose document dates fall outside the stage band"
    def check_dates
      config = Nabu::Config.load
      registry = require_lects_module!(config)
      journal = Nabu::Store::LectJournal.open_readonly(config.lects_journal_path)
      return say "no lect journal — nothing to audit" unless journal
      unless File.exist?(config.catalog_path)
        raise Thor::Error,
              "lect check-dates: no catalog at #{config.catalog_path}"
      end

      catalog = Nabu::Store.connect(config.catalog_path)
      findings = Nabu::LectDates.new(registry: registry).check(catalog: catalog, journal: journal)
      if findings.empty?
        say "check-dates clean — no assignment contradicts its document's dates"
      else
        findings.each do |finding|
          say format("  %<urn>-42s %<lect>-12s dated %<nb>s..%<na>s outside band %<band>s (%<basis>s)",
                     urn: finding.urn, lect: finding.lect_id, nb: finding.not_before,
                     na: finding.not_after, band: finding.band.inspect, basis: finding.basis)
        end
        say "#{findings.size} finding#{'s' unless findings.size == 1} — a ruling or a dating is wrong; " \
            "review before trusting either"
      end
    end

    desc "withdraw URN", "Remove URN's assignment(s) — all codes, or just --code"
    option :code, banner: "CODE"
    def withdraw(urn)
      config = Nabu::Config.load
      journal = Nabu::Store::LectJournal.open_readonly(config.lects_journal_path)
      raise Thor::Error, "lect withdraw: no journal at #{config.lects_journal_path}" unless journal

      journal.disconnect
      writable = Nabu::Store::LectJournal.open!(config.lects_journal_path)
      count = Nabu::Store::LectJournal.withdraw!(writable, urn: urn, code: options[:code])
      say "withdrew #{count} assignment#{'s' unless count == 1}  #{urn}#{" #{options[:code]}" if options[:code]}"
      refresh_lect_facet(config, urn)
    end

    no_commands do
      def require_lects_module!(config)
        registry = Nabu::Lects.load_default(config: config, overlay: {})
        raise Thor::Error, "lect: the nabu-lects module is not synced (canonical/nabu-lects)" unless registry

        registry
      end

      def check_lect!(registry, lect_id, where: nil)
        return if registry.lect(lect_id)

        raise Thor::Error, "lect: #{lect_id.inspect}#{where} is not defined in the registry " \
                           "(an undefined tag is never silently coerced)"
      end

      def check_basis!(basis, where: nil)
        return if basis == "owner" || basis.match?(/\Arule:[a-z0-9][a-z0-9-]*\z/)

        raise Thor::Error, "lect: basis must be owner or rule:<id>, got #{basis.inspect}#{where}"
      end

      def infer_code!(config, urn)
        unless File.exist?(config.catalog_path)
          raise Thor::Error, "lect assign: no catalog to read the document's language from — pass --code"
        end

        db = Nabu::Store.connect(config.catalog_path)
        language = db[:documents].where(urn: urn).get(:language)
        db.disconnect
        return language unless language.to_s.strip.empty?

        raise Thor::Error, "lect assign: #{urn} is not in the catalog (or carries no language) — pass --code"
      end

      # Parse + validate the WHOLE file, then write — one bad line rejects
      # the batch before any row lands (a ratified batch is one decision).
      def import_batch!(config, registry, path)
        raise Thor::Error, "lect assign: no such file #{path}" unless File.file?(path)

        rows = parse_batch!(registry, path)
        journal = Nabu::Store::LectJournal.open!(config.lects_journal_path)
        verdicts = rows.map { |row| Nabu::Store::LectJournal.assign!(journal, **row) }
        say "#{verdicts.size} assignments (#{verdicts.count(:inserted)} inserted, " \
            "#{verdicts.count(:updated)} updated) from #{path}"
        rows.map { |row| row[:urn] }.uniq.each { |row_urn| refresh_lect_facet(config, row_urn) }
      end

      # The single-document facet refresh after a hand ruling — a fresh
      # load_default carries the just-written journal state; no catalog or
      # no module is a clean skip (nothing to refresh into).
      def refresh_lect_facet(config, urn)
        return unless File.exist?(config.catalog_path)

        registry = Nabu::Lects.load_default(config: config)
        return unless registry

        catalog = Nabu::Store.connect(config.catalog_path)
        Nabu::Store::LectFacets.refresh_document!(catalog: catalog, registry: registry, urn: urn)
        catalog.disconnect
      end

      # The suggest render (P59-4): codes → facets → dating, each with the
      # honest posture verdict inline; a scaffold stanza for the best rule
      # candidate (small vocabulary over a staged anchor), values capped at
      # LectSuggest::TOP_VALUES with the cap announced.
      def render_suggest_report(report)
        say "lect suggest #{report.slug} — report only; apply via rules/overrides/posture"
        say "  codes:"
        report.codes.each do |row|
          verdict = if row.resolution != row.code then "resolved — machine posture exists"
                    elsif row.stages.any? then "IDENTITY, but the anchor has stages: #{row.stages.join(' ')}"
                    else
                      "identity — no minted stages (declare posture: identity)"
                    end
          say format("    %<code>-12s %<docs>6d docs → %<res>-14s %<verdict>s",
                     code: row.code, docs: row.docs, res: row.resolution, verdict: verdict)
        end
        say "  facets:"
        say "    (none — no rule material)" if report.facets.empty?
        report.facets.each do |row|
          candidate = row.distinct <= Nabu::LectSuggest::RULE_CANDIDATE_DISTINCT ? " ← rule candidate" : ""
          say "    #{row.facet}: #{row.distinct} distinct over #{row.docs} rows#{candidate}"
          row.top.each { |value, count| say format("      %<value>-40s %<count>d", value: value, count: count) }
          if row.distinct > row.top.size
            say "      … #{row.distinct - row.top.size} more values (census caps at " \
                "#{Nabu::LectSuggest::TOP_VALUES})"
          end
        end
        render_suggest_dating(report.dating)
        render_suggest_scaffold(report)
        render_suggest_layers(report)
      end

      # P61-2: the dating/places/script layer sections — the posture
      # sweep's evidence, one block per layer, sniff caps announced.
      def render_suggest_layers(report)
        dating = report.dating_layer
        say "  dating layer: #{dating.dated}/#{dating.total} docs carry bounds"
        if dating.candidates.any?
          keys = dating.candidates.first(6).map { |key, count| "#{key} (#{count})" }.join(", ")
          say "    pending sniff — date-shaped metadata keys on undated docs: #{keys} " \
              "(sampled ≤#{Nabu::LectSuggest::SNIFF_SAMPLE})"
        end
        places = report.places_layer
        say "  places layer: #{places.linked} ref-linked · #{places.named} named · " \
            "#{places.total} docs#{" · #{places.latent} LATENT refs in raw metadata" if places.latent.positive?}"
        if report.script_layer.any?
          say "  script layer (suffixed codes, byte-checked surface):"
          report.script_layer.each do |row|
            surface = row.surface ? "#{row.surface} #{(row.share * 100).round}%" : "no script-bearing bytes"
            say format("    %<code>-22s %<docs>6d docs → surface %<surface>s",
                       code: row.code, docs: row.docs, surface: surface)
          end
        else
          say "  script layer: no suffixed codes — script-implied (declare posture: implied)"
        end
      end

      def render_suggest_dating(dating)
        say "  dating:"
        if dating.is_a?(String)
          say "    #{dating}"
        elsif dating.assignable.empty?
          say "    no date-band material (undated, band-less anchors, or spans)"
        else
          dating.assignable.sort_by { |_k, v| -v }.first(8).each do |(_src, code, lect_id), count|
            say format("    %<code>-8s → %<lect>-14s %<count>d docs assignable by date-band inference",
                       code: code, lect: lect_id, count: count)
          end
        end
      end

      def render_suggest_scaffold(report)
        staged = report.codes.select { |row| row.stages.any? && row.resolution == row.code }
        facet = report.facets.find { |row| row.distinct <= Nabu::LectSuggest::RULE_CANDIDATE_DISTINCT }
        return if staged.empty? || facet.nil?

        code = staged.first
        say "  scaffold (config/lect_facet_rules.yml — every target needs an owner ruling):"
        say "    - id: #{report.slug}-#{code.code}-#{facet.facet}"
        say "      tier: TODO(certain|approximation)"
        say "      sources: [#{report.slug}]"
        say "      code: #{code.code}"
        say "      facet: #{facet.facet}"
        say "      map:"
        facet.top.map(&:first).each { |value| say "        #{value.inspect}: \"#{code.code}:TODO\"" }
      end

      # The wholesale recompute after a bulk compile (apply-rules,
      # infer-dates) or on demand (materialize). Pending migrations run
      # first (idempotent — the open_or_create_catalog stance) so the
      # lect_stats census table exists on a catalog last touched by an
      # older binary.
      def materialize_lect_facets!(config, catalog: nil)
        registry = Nabu::Lects.load_default(config: config)
        catalog ||= Nabu::Store.connect(config.catalog_path)
        Nabu::Store.migrate!(catalog)
        count = Nabu::Store::LectFacets.rebuild!(catalog: catalog, registry: registry)
        say "lect facet: #{count} rows materialized"
      end

      def parse_batch!(registry, path)
        File.readlines(path).each_with_index.filter_map do |line, index|
          text = line.chomp
          next if text.strip.empty? || text.lstrip.start_with?("#")

          urn, code, lect_id, basis, note = text.split("\t", 5)
          where = " (#{File.basename(path)} line #{index + 1})"
          raise Thor::Error, "lect assign: urn/code/lect_id required#{where}" if lect_id.to_s.strip.empty?

          check_lect!(registry, lect_id, where: where)
          basis = options[:basis] if basis.to_s.strip.empty?
          check_basis!(basis, where: where)
          { urn: urn, code: code, lect_id: lect_id, basis: basis, note: note }
        end
      end

      def selected_rules(rules)
        return rules.rules unless options[:rule]

        rule = rules.find(options[:rule])
        unless rule
          raise Thor::Error, "lect apply-rules: unknown rule #{options[:rule].inspect} — " \
                             "the file defines: #{rules.rules.map(&:id).join(', ')}"
        end
        [rule]
      end

      def run_rule(rules, rule, catalog, journal, census_journal = journal)
        report = rules.census(rule, catalog: catalog, journal: census_journal)
        say "rule #{rule.id} (#{rule.tier}; facet #{rule.facet}, code #{rule.code}, " \
            "sources #{rule.sources.join(' ')})"
        report.matched.sort_by { |_pair, count| -count }.each do |(value, lect_id), count|
          say format("  %<value>-28s → %<lect>-10s %<count>d", value: value, lect: lect_id, count: count)
        end
        report.unmatched.sort_by { |_value, count| -count }.each do |value, count|
          say format("  %<value>-28s   (unmatched) %<count>d", value: value, count: count)
        end
        say "  assignable: #{report.assignable}"
        return unless journal

        outcome = rules.apply!(rule, catalog: catalog, journal: journal)
        suffix = outcome.skipped.positive? ? " (#{outcome.skipped} skipped — already ruled)" : ""
        say "  assigned #{outcome.assigned}#{suffix}"
      end

      def render_table(journal, scope)
        rows = scope.limit(options[:limit] + 1).all
        shown = rows.first(options[:limit])
        shown.each do |row|
          note = row[:note].to_s.empty? ? "" : "  # #{row[:note]}"
          say format("%<urn>-42s %<code>-8s %<lect>-14s %<basis>s%<note>s",
                     urn: row[:urn], code: row[:code], lect: row[:lect_id], basis: row[:basis], note: note)
        end
        total = scope.count
        say "… #{total - shown.size} more (--limit, or --format tsv for all)" if total > shown.size
        census = Nabu::Store::LectJournal.counts_by_basis(journal)
                                         .map { |basis, count| "#{basis} #{count}" }.join(", ")
        say "#{total} assignment#{'s' unless total == 1} — #{census}"
      end
    end
  end

  # `nabu layer` (P61-2): the core-layers front door. One command today —
  # the generalized suggest census (lect + dating + places + script
  # sections, all rendered by LectCLI#suggest, which `nabu lect suggest`
  # keeps aliasing). New layer-wide commands land here, not on LectCLI.
  class LayerCLI < Thor
    namespace "layer"

    desc "suggest SLUG", "The core-layers census: lect, dating, places and script postures in one report"
    def suggest(slug = nil)
      LectCLI.new.suggest(slug)
    end

    desc "artifacts", "Re-derive the artifact-script lane from config/artifact_scripts.yml (idempotent)"
    long_desc <<~HELP, wrap: false
      Compiles the owner-ruled artifact-script rows (source → code → the
      ARTIFACT's script where it differs from the held surface, D60-b) into
      document_axes under the "artifact-script" lane — wholesale supersede,
      a pure function of stored codes + config, also re-derived by rebuild.
    HELP
    def artifacts
      config = Nabu::Config.load
      raise Thor::Error, "layer artifacts: no catalog at #{config.catalog_path}" unless File.exist?(config.catalog_path)

      catalog = Nabu::Store.connect(config.catalog_path)
      report = Nabu::Store::ArtifactScripts.derive!(
        catalog, config_path: config.artifact_scripts_path,
                 registry: Nabu::Lects.load_default(config: config)
      )
      say "artifact-script lane: #{report.minted} rows (#{report.sources.join(', ')})"
    ensure
      catalog&.disconnect
    end
  end

  # Command-line entry point. Only `version` is functional in Phase 0; the
  # ingest/query subcommands are stubs that report "not implemented" and exit 1
  # so scripts and CI can rely on the failure signal before the real work lands.
  class CLI < Thor
    # The DataCLI namespace note applies at the root too: without it Thor
    # 1.5's `tree` labels its root with the class auto-namespace ("nabu:c_l_i").
    namespace "nabu"

    # The tag-semantics note the axis-grouped surfaces (`list --axis`,
    # `status --axis`, P35-1) state ONCE: axes are TAGS over the source list,
    # so a source appears under every axis it serves — never a folder owning it.
    AXIS_TAG_NOTE = "Axes are tags, not folders — a source appears under every desk it serves."

    # Raise Thor::Error (rather than aborting the process abruptly) so failures
    # surface a clean stderr message and a non-zero exit status.
    def self.exit_on_failure?
      true
    end

    # `nabu search --help` (owner report 2026-07-18): this Thor build does
    # not intercept a help flag AFTER a command name, so "--help" reached
    # FTS5 as the literal query. Route `nabu CMD --help|-h` to `nabu help
    # CMD` for every known command; a literal "--help" stays searchable via
    # quoting inside a longer query (the fts literal fallback).
    def self.start(given_args = ARGV, config = {})
      if Thor::HELP_MAPPINGS.include?(given_args[1]) &&
         all_commands.key?(normalize_command_name(given_args.first.to_s))
        given_args = ["help", given_args.first]
      end
      # P44-i1b: a ^C is an OPERATOR DECISION, not a crash — one honest line
      # and the conventional 130, never a thread-backtrace storm. (Open3's
      # internal reader threads also die noisily at interrupt; bin/nabu turns
      # their report_on_exception chatter off.) State safety is the atomic
      # fetchers' job — an interrupted acquisition leaves staging debris the
      # next run sweeps, announced.
      super
    rescue Interrupt
      warn "\ninterrupted — partial work is staged safely; the next run cleans up and starts fresh."
      exit 130
    end

    # The --display flag, shared by every command that renders passage text to
    # the terminal (P27-0: show, align, search, concord, parallels, cognates).
    # Modes come from the Nabu::Display registry so sibling packets can add
    # modes (reading, …) without touching this declaration.
    def self.display_option
      option :display, type: :string, default: Nabu::Display::DEFAULT_MODE, banner: "MODE",
                       desc: "Display mode: default (config/display.yml policies), " \
                             "full (every stored byte, no transforms), plain (strip all " \
                             "defined mark classes), reading (edition apparatus simplified, " \
                             "qere read), diplomatic (edition marks as stored), " \
                             "translit (romanized rendering), " \
                             "mono (default without token colors) — see docs/display.md"
    end

    desc "version", "Print the Nabu version"
    def version
      say Nabu::VERSION
    end

    desc "data SUBCOMMAND ...ARGS", "The nabu-data production rail: document and build publishable derived datasets"
    subcommand "data", DataCLI

    desc "lect SUBCOMMAND ...ARGS", "Per-document lect rulings: the journaled overlay tier of lect resolution"
    subcommand "lect", LectCLI

    # P61-2: `nabu layer` is the core-layers front door — today one
    # command, `suggest`, the generalized census (lect + dating + places +
    # script sections). `nabu lect suggest` stays as the historical alias;
    # both run the same report.
    desc "layer SUBCOMMAND ...ARGS", "Core-layer postures: the generalized suggest front door"
    subcommand "layer", LayerCLI

    desc "sync [SOURCE]", "Fetch and load a source, an axis's members, or --all live sources"
    long_desc <<~HELP, wrap: false
      Fetch and load into the store. The positional NAME resolves EXACT SLUG
      FIRST, then axis: a source slug syncs that one source (the explicit
      request — a disabled source syncs anyway, with a note); a name that is
      not a slug but IS a research axis (config/axes.yml) expands to the
      axis's members. Axis names can never equal source slugs (a load-time
      guarantee), so the resolution is unambiguous.

      Axis expansion is PURE fan-out onto the per-source path: each member
      syncs exactly as `sync <slug>` would, per-source report lines
      byte-unchanged, under a one-line axis header. The asymmetry to know:
      an axis expansion is NOT an explicit per-source request, so DISABLED
      members are SKIPPED — reported by name on one `skipped (unwired): …`
      line, never silently — whereas `sync <disabled-slug>` (explicit) still
      syncs. `--axis a,b` selects several axes and prints one group each, in
      order. `--all` is a flat batch (enabled + live sources), never grouped.

      Examples:
        nabu sync sblgnt          # one source (explicit; disabled syncs anyway)
        nabu sync celtic          # the celtic axis's enabled members
        nabu sync --axis celtic,italic --parse-only
        nabu sync --all
    HELP
    option :all, type: :boolean, default: false,
                 desc: "Sync every enabled kind: source with sync_policy: auto"
    option :axis, type: :string, banner: "NAME[,NAME...]",
                  desc: "Sync the enabled members of one or more research axes (config/axes.yml), " \
                        "grouped; disabled members are skipped by name (an axis is not an explicit request)"
    option :parse_only, type: :boolean, default: false,
                        desc: "Skip fetch; re-parse the snapshot already on disk"
    option :force, type: :boolean, default: false,
                   desc: "Override the >20% withdrawal circuit breaker"
    option :redownload, type: :boolean, default: false,
                        desc: "Wipe the source's canonical snapshot (attic preserved) and re-acquire " \
                              "from scratch, regardless of any resumable/partial state"
    option :grant_acknowledged, type: :boolean, default: false,
                                desc: "Acknowledge a grant-required source's terms non-interactively " \
                                      "(scripted use); records the acknowledgment, then syncs. Single-source only."
    option :review, type: :string, banner: "CMD",
                    desc: "Pipe a JSON sync brief to CMD's stdin at sync end (advisory; " \
                          "the hook's exit status is reported, never fails the sync). " \
                          "Example: --review script/review-sync-claude. Single-source sync only."
    def sync(slug = nil)
      # --redownload refusals up front (P44-i1): contradictory with
      # --parse-only (nothing to re-download if we skip fetch), and
      # per-source by design (a wipe is an explicit, named decision).
      if options[:redownload]
        raise Thor::Error, "sync: --redownload contradicts --parse-only" if options[:parse_only]
        raise Thor::Error, "sync: --redownload is per-source — name one slug" if options[:all] || options[:axis]
      end
      config = Nabu::Config.load
      registry = Nabu::SourceRegistry.load(config.sources_path)
      # Ledger FIRST: open_or_create_ledger lifts a pre-P7-1 catalog's history
      # before open_or_create_catalog migrates the moved tables away.
      ledger = open_or_create_ledger(config)
      db = open_or_create_catalog(config)
      runner = Nabu::SyncRunner.new(config: config, registry: registry, db: db, ledger: ledger)
      run_sync(runner, registry, slug, db, ledger, enabled: sync_enabled_slugs(config, registry, db))
    rescue Nabu::Error => e
      # Unknown slug (ValidationError), fetch failure (FetchError), ... all
      # surface as a clean stderr message and exit 1.
      raise Thor::Error, e.message
    ensure
      db&.disconnect
      ledger&.disconnect
    end

    # -- quickstart (P18-2): the starter shelf --------------------------------

    # One starter source: its registry slug, its measured canonical footprint
    # (du -sh of the live tree, git history included), and what it unlocks.
    StarterSource = Data.define(:slug, :size, :blurb)

    # The curated starter shelf: the smallest set of real sources that delivers
    # the library's three signature surfaces in minutes — align "MARK 2.3"
    # (seven witnesses: sblgnt + the five PROIEL NT texts + the ISWOC
    # West-Saxon Mark), search --lemma (PROIEL gold annotations), and
    # define λόγος / virtus (LSJ + Lewis & Short). Sizes measured 2026-07-13.
    # vulgate/eng-web were weighed and excluded: each is a full open-bibles
    # clone (357 MB) for one USFX file — the first "grow the library" step
    # instead. Order: quick wins first, the big dictionary clone last.
    STARTER_SOURCES = [
      StarterSource.new(slug: "sblgnt", size: "~11 MB",
                        blurb: "SBL Greek New Testament — the align hub's second Greek witness (CC BY)"),
      StarterSource.new(slug: "proiel", size: "~175 MB",
                        blurb: "PROIEL treebank — NT in Greek, Latin, Gothic, Armenian, OCS; gold lemmas (nc)"),
      StarterSource.new(slug: "iswoc", size: "~30 MB",
                        blurb: "ISWOC treebank — the West-Saxon gospels, Old English (nc)"),
      StarterSource.new(slug: "lexica", size: "~480 MB",
                        blurb: "LSJ + Lewis & Short — the dictionary shelf (CC BY-SA)")
    ].freeze
    # The whole shelf on disk (sum of the measured sizes above).
    STARTER_TOTAL = "~690 MB"

    # Class-method accessor so tests can pin a fixture-backed starter list
    # (the Config.load swap pattern) without touching the shipped constant.
    def self.starter_sources = STARTER_SOURCES

    desc "quickstart", "Sync the starter shelf (#{STARTER_SOURCES.map(&:slug).join(' → ')}) " \
                       "and print what to try first"
    long_desc <<~HELP, wrap: false
      The zero-to-first-marvel path for a fresh clone: sync the curated STARTER
      SHELF — four small sources, #{STARTER_TOTAL} canonical on disk (measured
      2026-07-13), minutes on an ordinary connection — then print the first
      three commands to try:

        sblgnt   ~11 MB    SBL Greek New Testament (CC BY)
        proiel   ~175 MB   PROIEL treebank: the NT in Greek, Latin, Gothic,
                           Armenian, and Old Church Slavonic, with gold
                           lemma/morphology annotations (nc)
        iswoc    ~30 MB    ISWOC treebank: the West-Saxon gospels — Old
                           English as an alignment witness (nc)
        lexica   ~480 MB   LSJ + Lewis & Short, the dictionary shelf (CC BY-SA)

      Together they light the three signature surfaces: `align "MARK 2.3"`
      (one verse across seven witnesses), `search --lemma λέγω`
      (dictionary-form search over the gold treebanks — λέγουσι, εἶπας,
      εἰπεῖν all found), and `define λόγος` / `define virtus` (the full
      dictionary entries, citations resolved into your own catalog).

      Each source syncs through its NORMAL path (fetch → load → index), so
      the command is idempotent — a re-run is an ordinary re-sync — and one
      source's failure never stops the rest: failures are reported at the
      end, and the exit status is 1 if any source failed. --list prints the
      set (with sizes) and exits without touching the network.

      Examples:
        nabu quickstart          # sync the starter shelf, then try the printed commands
        nabu quickstart --list   # what would be synced, and why

      Use cases: a new install's first minutes; the README/site Quickstart's
      one command; rebuilding a demo box.
    HELP
    option :list, type: :boolean, default: false,
                  desc: "Print the starter set (slugs, sizes, what each unlocks) and exit without syncing"
    def quickstart
      return print_starter_list if options[:list]

      config = Nabu::Config.load
      registry = Nabu::SourceRegistry.load(config.sources_path)
      # Ledger FIRST, as in sync: open_or_create_ledger lifts a pre-P7-1
      # catalog's history before open_or_create_catalog migrates it away.
      ledger = open_or_create_ledger(config)
      db = open_or_create_catalog(config)
      runner = Nabu::SyncRunner.new(config: config, registry: registry, db: db, ledger: ledger)
      # P44-r3c: quickstart ENABLES its set before syncing — additive into
      # the enablement config (never overwriting an existing profile's
      # entries), so the sync gate passes deterministically and a fresh
      # box's profile is written explicitly rather than by migration grace.
      enable_starter_set(config)
      failures = run_starter_syncs(runner)
      print_quickstart_epilogue(failures)
      unless failures.empty?
        raise Thor::Error, "quickstart: #{failures.size} of #{self.class.starter_sources.size} starter " \
                           "sources failed — re-run bin/nabu quickstart, or sync each by name (bin/nabu sync <slug>)"
      end
    rescue Nabu::Error => e
      raise Thor::Error, e.message
    ensure
      db&.disconnect
      ledger&.disconnect
    end

    desc "ingest FILE|URL...", "File your own PDFs, scans and articles into the local-library shelf"
    long_desc <<~HELP, wrap: false
      The intake front door for canonical memory (architecture §16): copy
      files (never move — your originals stay put) into
      canonical/local-library/<collection>/, categorize them, append one
      manifest entry each, then run the shelf's ordinary sync and print the
      minted urns. This is the ONE sanctioned write path onto the library
      shelf; after it, the files are searchable, showable, linkable corpus
      members like everything else.

      Arguments may be http(s) URLs: the file is DOWNLOADED first (redirect
      chains followed — archive.org's mirror hop included), then flows
      through the exact same intake as a local file, and the manifest
      entry additionally records the URL you gave in a source_url: lane
      (mirror-node URLs rotate; yours is the stable identity — it also
      prefills the provenance candidate). A failed download is one honest
      FAILED line naming the HTTP status — and aborts the batch (below).

      Candidate metadata is derived mechanically first — PDF Info metadata
      and a first-page text sample via mutool (degrading gracefully to
      filename heuristics where mutool is absent), the sha256 always — then
      categorized in one of three modes:

        interactive (TTY default)  one prompt per field, candidates
                                   prefilled; Enter keeps the [default],
                                   '-' clears a field. license_class
                                   DEFAULTS to research_private (never
                                   served or redistributed) — stated at
                                   the prompt; raise it per item only for
                                   genuinely open material.
        --assist CMD               pipe a JSON brief (nabu.ingest-assist/1:
                                   derived candidates + text sample) to
                                   CMD's stdin, parse a suggested entry
                                   from its stdout, and PREFILL the
                                   interactive prompts with it — AI
                                   suggests, you confirm; nothing lands
                                   unreviewed unless you also pass --yes.
                                   Bundled example:
                                   script/ingest-assist-claude (claude -p
                                   with the nabu MCP tools).
        --yes                      scripted: accept the candidates plus
                                   any --title/--creator/--year/--languages/
                                   --tags/--related/--provenance/
                                   --license-class flags, no prompts —
                                   for bulk drops.

      The default collection is "#{Nabu::Ingest::DEFAULT_COLLECTION}" — pass
      --collection for anything you want shelved by topic. Mind that the
      collection is part of the minted urn (frozen forever), so file
      deliberately: a later re-file is honestly a new document.

      Atomicity and honesty: the batch lands WHOLE or not at all —
      everything fallible (downloads, existence and no-executables checks,
      categorization, validation against the manifest's own rules) runs
      BEFORE any write, so a defect anywhere is one named FAILED line per
      problem, the other files say "aborted", canonical/ stays untouched,
      exit 1. A file whose bytes are already catalogued anywhere in the
      shelf is a no-op with a message; the same NAME with new bytes
      replaces the copy and the sync records an ordinary revision.

      --shelf language CODE scaffolds a language DOSSIER instead — the same
      front door for all canonical memory: prompts (same three modes; flags
      --name/--family/--context) for the front matter and a context line,
      writes canonical/local-language/CODE.md through the shelf's gateway,
      and syncs. A scaffold, not an editor: an existing dossier is a no-op
      pointing at the file.

      --shelf source SLUG scaffolds a SOURCE dossier the same way (P24-0):
      prompts (flags --description/--themes/--key-works) with the
      description prefilled from the registered source's name, writes
      canonical/local-source/SLUG.md through Nabu::SourceShelf, and syncs.
      SLUG must be registered in config/sources.yml — dossiers describe
      held shelves.

      Examples:
        nabu ingest ~/scans/vaillant-1950-manuel.pdf --collection slavistics
        nabu ingest https://archive.org/download/handbuchderaltbu00lesk/handbuchderaltbu00lesk.pdf
        nabu ingest paper.pdf --assist script/ingest-assist-claude
        nabu ingest notes.txt --yes --title "Reading notes" --languages eng \\
          --related urn:nabu:ccmh:mar:mt --license-class open
        nabu ingest --shelf language zle-ort
        nabu ingest --shelf source edh --themes epigraphy,prosopography
    HELP
    option :collection, type: :string, banner: "NAME",
                        desc: "Target collection under canonical/local-library/ " \
                              "(default #{Nabu::Ingest::DEFAULT_COLLECTION}; becomes part of the urn)"
    option :assist, type: :string, banner: "CMD",
                    desc: "AI-assist hook: JSON brief to CMD's stdin, suggested entry from its stdout " \
                          "(prefills the prompts; example: script/ingest-assist-claude)"
    option :yes, type: :boolean, default: false,
                 desc: "No prompts: accept the derived/assist/flag values (scripted bulk drops)"
    option :title, type: :string, desc: "Title (one file only)"
    option :creator, type: :string, desc: "Creator/author"
    option :year, type: :numeric, desc: "Publication year"
    option :languages, type: :string, banner: "chu,deu", desc: "Language codes, comma-separated"
    option :tags, type: :string, banner: "grammar,ocs", desc: "Tags, comma-separated"
    option :related, type: :string, banner: "URN,CODE",
                     desc: "Related urns/language codes, comma-separated (urns become links-journal edges)"
    option :provenance, type: :string, desc: "Where this copy came from"
    option :license_class, type: :string, banner: "CLASS",
                           desc: "License class (default research_private — never served or redistributed)"
    option :shelf, type: :string, banner: "language|source",
                   desc: "Ingest into another local shelf: `--shelf language CODE` / `--shelf source SLUG` " \
                         "scaffolds a dossier"
    option :name, type: :string, desc: "With --shelf language: the language's name"
    option :family, type: :string, desc: "With --shelf language: the family lane"
    option :context, type: :string, desc: "With --shelf language: one context line (free prose)"
    option :description, type: :string,
                         desc: "With --shelf source: the 1–3 sentence content description (the load-bearing lane)"
    option :themes, type: :string, banner: "epigraphy,onomastics",
                    desc: "With --shelf source: themes, comma-separated"
    option :key_works, type: :string, banner: "URN,URN",
                       desc: "With --shelf source: key works as catalog urns, comma-separated"
    def ingest(*paths)
      config = Nabu::Config.load
      return ingest_shelf(config, paths) if options[:shelf]

      if paths.empty?
        raise Thor::Error, "ingest: give at least one file or url (or --shelf language CODE / " \
                           "--shelf source SLUG)"
      end

      %w[name family context description themes key_works].each do |flag|
        raise Thor::Error, "ingest: --#{flag.tr('_', '-')} only applies with --shelf language/source" if options[flag]
      end
      raise Thor::Error, "ingest: --title names one file's title — ingest that file alone" \
        if options[:title] && paths.size > 1

      outcomes = build_ingest_engine(config).add_files(
        paths, collection: options[:collection] || Nabu::Ingest::DEFAULT_COLLECTION
      )
      outcomes.each { |outcome| print_ingest_outcome(outcome) }
      if outcomes.any? { |outcome| %i[added revised].include?(outcome.status) }
        run_shelf_sync(config, Nabu::LibraryShelf::SLUG)
        print_ingest_epilogue(outcomes)
      end
      failed = outcomes.reject(&:ok?)
      raise Thor::Error, "ingest: #{failed.size} of #{outcomes.size} file(s) failed — see above" unless failed.empty?
    rescue Nabu::Error => e
      raise Thor::Error, e.message
    end

    desc "status [SOURCE]", "Show per-source sync status and passage counts (`nabu list` shows what is held)"
    long_desc <<~HELP, wrap: false
      The SYNC-STATE view. Bare `nabu status` is the COMPACT table (P40-s):
      one dense row per registered source, grouped by kind — a fused
      kind/enablement/cadence column, a SILENT liveness cell that speaks only
      to flag an exception (OLD/DOWN/?REPROBE/UNPROBED), one humanized
      holdings column, and the last run's stamp + zero-suppressed delta. Its
      sibling is `nabu list`, the WHAT-IS-HELD view (content census, per-shelf
      cards): status answers "should I sync?", list answers "what does the
      library hold?".

      `nabu status SOURCE` is one source's full labeled detail block: kind,
      enabled, cadence, the liveness verdict (healthy states included), exact
      thousands-separated counts, license class, the full timestamp/delta, and
      the last run's status. `nabu status --long` is that extended detail as a
      labeled table for EVERY row.

      --remote probes every upstream first (the same code path as
      `health --remote`, persisting each verdict) and renders the fresh
      drift column — the one-command informed-update flow.
    HELP
    option :remote, type: :boolean, default: false,
                    desc: "Probe every upstream first (same as health --remote), persist, then show fresh drift"
    option :long, type: :boolean, default: false,
                  desc: "The full labeled detail (verbose liveness, exact counts, license, full delta) for every row"
    option :axis, type: :string, banner: "[NAME[,NAME…]]", lazy_default: "",
                  desc: "Group the status table under the research axes (config/axes.yml): bare = all in " \
                        "ratified order, NAME[,NAME…] = those axes only. A source appears under each axis it serves"
    option :all, type: :boolean, default: false,
                 desc: "Ignore the focus profile: show every row (modules + unfocused sources included)"
    option :disabled, type: :boolean, default: false,
                      desc: "The complement view: ONLY the rows nabu enable would add " \
                            "(shelves are always enabled and never appear)"
    def status(slug = nil)
      refuse_all_with_disabled!("status")
      slug = slug.to_s.strip
      config = Nabu::Config.load
      registry = Nabu::SourceRegistry.load(config.sources_path)
      # --remote (P14-12): the one-command informed-update flow — run the live
      # upstream probe inline (the SAME code path as `health --remote`, which
      # persists each verdict into the ledger cache), then render the up= column
      # from that fresh cache. Bare `status` is read-only and shows the cached
      # verdicts as-is (with their age).
      ledger = options[:remote] ? probe_upstreams(config, registry) : open_ledger(config)
      db = open_catalog(config)
      # `status SOURCE` is the detail block — UNSCOPED (explicit naming is
      # explicit intent; any source, focused or not). The bare/--long/--axis
      # tables scope to the focus profile (P40-f).
      view = focus_view(config, registry, catalog: db)
      if slug.empty?
        warn_focus_drift(view)
        # An EMPTY --disabled complement renders no table (the "No sources
        # registered." banner belongs to a truly empty registry, not to an
        # exhausted menu — the stderr footer carries the all-enabled state).
        say status_report(view.registry, db, ledger, slug) unless view.disabled && view.registry.slugs.empty?
        # `status --axis` is SCOPED (P44-r1 addendum): the grouped table, then an
        # enable hint for the axes' not-yet-enabled members — never the
        # whole-library `enabled:` footer. Bare status keeps that footer.
        if options[:axis]
          print_axis_enable_hint(view, registry, selected_axes(registry.axes))
        else
          print_focus_note(view, view.registry_hidden_slugs)
        end
      else
        say status_report(registry, db, ledger, slug)
        print_source_enable_hint(view, registry, slug)
      end
    ensure
      db&.disconnect
      ledger&.disconnect
    end

    desc "list [SOURCE]", "What the library holds: the shelf census, or one source's card " \
                          "(`nabu status` shows sync state)"
    long_desc <<~HELP, wrap: false
      The WHAT-IS-HELD view — the contents sibling of `nabu status` (which
      answers "should I sync?"; list answers "what does the library hold?").

      Bare `nabu list` is the content census: one line per catalog source —
      live document/passage counts, dictionary entry counts, the languages
      held (codes when few, a count when many), the effective license-class
      mix (document overrides included), and withdrawn/retired counts when
      nonzero (zero fields are suppressed, the house rule).

      `nabu list SOURCE` is one shelf's card: identity (name, adapter,
      registry sync policy + enabled), the shelf's dossier description
      when the local-source shelf carries one (canonical/local-source,
      architecture §16 — seed the shelf once with
      --export-source-dossiers), license class(es) with the source's
      credit line when it carries one, counts, a per-language passage
      breakdown, its dictionaries (dictionary shelves), timeline coverage
      (dated docs + year range) when present, genre-facet and collection
      summaries when present. A card, not a dump — the enumerations below
      go deeper. `nabu list --long` adds each source's description line to
      the census.

      `nabu list --sources` is the one-page onboarding map: every source on
      one line (slug — the first sentence of its dossier description, ~100
      chars, honest ellipsis), grouped under family headers (Greek & Latin ·
      Biblical & Near Eastern · Slavic · Celtic · Indic & Iranian · Egyptian
      & Coptic · Germanic & Old English · Reference & dictionaries · Your
      shelves · Other). Groups are DERIVED from the census languages'
      family lanes (the language-dossier shelf); an optional owner-curated
      `group:` front-matter key in a source dossier overrides the
      derivation. Disabled sources stay visible with an (off) tag; a source
      without a dossier description shows the honest stub hint. Composes
      with nothing — it IS the whole-library view.

      `nabu list --axis` groups the census under the research axes (the
      owner's desks, config/axes.yml): each axis leads with its persona
      line, then the same census rows, indented. Axes are TAGS, not folders
      — a source appears under every axis it serves (stated once). Bare
      --axis shows every axis in the ratified order; `--axis slavic` one
      axis; `--axis a,b` those axes only. An unknown axis names the known
      set. The bare (ungrouped) census is unchanged.

      A bare `nabu list SOURCE --lang CODE` (no enumeration flag) IMPLIES the
      natural mode by the shelf's content kind — a dictionary shelf lists its
      entries in that language, a text shelf its documents — and a header
      announces the implication. Name --documents/--entries explicitly to
      override. (--lang still needs a SOURCE, and does not compose with the
      --collections/--loans census grains.)

      Enumerations (one per invocation, each honoring --limit, default 50,
      0 = all, with an honest "… N more" tail):
        --documents    every document: urn — title [lang] license, urn order,
                       withdrawn/retired flagged inline. Filters: --lang,
                       --license, --withdrawn (ONLY withdrawn/retired — the
                       stewardship lens), --from/--to/--century (the
                       timeline, as in search).
        --entries      a dictionary shelf's entries: headword [dict] — gloss.
                       Filters: --lang (dictionary language), --prefix STR
                       (folded headword prefix — bh finds *bʰer-, the define
                       contract). A passage shelf misses honestly, exit 0.
        --collections  collection → document count for shelves whose urns
                       carry a manifest collection segment (local-library);
                       an honest miss elsewhere, exit 0.
        --loans [CODE] the language-contact lens (P34-2, the stored P17-1
                       per-passage loan-token counts — no reparse). Bare:
                       the census, one row per loan-origin code (tokens/
                       passages/docs, token order). With CODE: the documents
                       carrying such loan tokens, most-saturated first,
                       honoring --limit. An honest miss on shelves without
                       the layer, exit 0.

      Examples:
        nabu list                                # the census, every shelf
        nabu list --sources                      # the one-page grouped map
        nabu list --axis                         # the census, grouped by desk
        nabu list --axis slavic                  # one desk's shelves
        nabu list ccmh                           # one shelf's card
        nabu list local-library --documents      # what did I ingest?
        nabu list local-library --collections    # …and how is it filed?
        nabu list lexica --entries --prefix log  # λόγος and its neighbors
        nabu list iecor --lang xcl               # entries implied (a dictionary shelf)
        nabu list papyri-ddbdp --documents --century 6 --limit 5
        nabu list shelf --documents --withdrawn  # the stewardship lens
        nabu list coptic-scriptorium --loans     # the loan-origin census
        nabu list coptic-scriptorium --loans grc --limit 10
                                                 # the most Greek-saturated books

      Use cases: enumerate a shelf without sqlite3 one-liners; a license
      audit before an export; eyeballing what an ingest actually filed.
    HELP
    option :documents, type: :boolean, default: false,
                       desc: "Enumerate the source's documents (urn order, withdrawn/retired flagged)"
    option :entries, type: :boolean, default: false,
                     desc: "Enumerate a dictionary source's entries (headword + gloss)"
    option :collections, type: :boolean, default: false,
                         desc: "Collection → document count for manifest-collection shelves"
    option :loans, type: :string, banner: "[CODE]", lazy_default: "",
                   desc: "The loan-origin census (bare), or the documents carrying CODE loan tokens, " \
                         "most-saturated first (P17-1 annotations — Coptic Scriptorium)"
    option :sources, type: :boolean, default: false,
                     desc: "The one-page grouped map: every source's description under family headers"
    option :limit, type: :numeric, default: Nabu::Query::List::DEFAULT_LIMIT,
                   desc: "Maximum rows per enumeration (default #{Nabu::Query::List::DEFAULT_LIMIT}; 0 = all)"
    option :prefix, type: :string, banner: "STR",
                    desc: "With --entries: folded headword prefix (bh finds *bʰer-)"
    option :lang, type: :string,
                  desc: "Restrict to one language; bare `list SOURCE --lang CODE` implies the natural " \
                        "mode (dictionary → entries, text → documents)"
    option :license, type: :string,
                     desc: "With --documents: restrict to an exact effective license class"
    option :withdrawn, type: :boolean, default: false,
                       desc: "With --documents: ONLY withdrawn/retired documents (the stewardship lens)"
    option :from, type: :numeric, banner: "YEAR",
                  desc: "With --documents: earliest date on the timeline (negative = BCE)"
    option :to, type: :numeric, banner: "YEAR", desc: "With --documents: latest date on the timeline"
    option :century, type: :numeric, banner: "N",
                     desc: "With --documents: one century's --from/--to shorthand (6, -2)"
    option :long, type: :boolean, default: false,
                  desc: "Census only: add each source's dossier description line (the local-source shelf)"
    option :axis, type: :string, banner: "[NAME[,NAME…]]", lazy_default: "",
                  desc: "Group the census under the research axes (config/axes.yml): bare = all in " \
                        "ratified order, NAME[,NAME…] = those axes only. A source appears under each " \
                        "axis it serves"
    option :"export-source-dossiers", type: :boolean, default: false,
                                      desc: "Owner one-shot: scaffold a canonical/local-source dossier for " \
                                            "EVERY registered source, descriptions seeded from existing " \
                                            "prose (idempotent; existing dossiers untouched)"
    option :"dry-run", type: :boolean, default: false,
                       desc: "With --export-source-dossiers: report without writing"
    option :all, type: :boolean, default: false,
                 desc: "Ignore the focus profile: census every source (--sources map is always whole-library)"
    option :disabled, type: :boolean, default: false,
                      desc: "The complement view: ONLY the rows nabu enable would add " \
                            "(shelves are always enabled and never appear)"
    def list(slug = nil)
      refuse_all_with_disabled!("list")
      slug = slug.to_s.strip
      validate_list_flags!(slug)
      validate_license!(options[:license])
      from, to = date_window
      config = Nabu::Config.load
      return export_source_dossiers(config) if options[:"export-source-dossiers"]

      catalog = open_catalog(config)
      raise Thor::Error, "no catalog — run nabu sync or nabu rebuild" unless catalog

      require_timeline!(catalog) if from || to
      query = Nabu::Query::List.new(catalog: catalog)
      # Bare `list SOURCE --lang X` (P44-r1): with no explicit enumeration
      # flag, --lang IMPLIES the natural mode by the shelf's content kind —
      # a dictionary shelf lists entries, a text shelf documents — and the
      # header announces the implication so it stays legible.
      implied = implied_list_mode(query, slug)
      if options[:axis]
        registry = Nabu::SourceRegistry.load(config.sources_path)
        view = focus_view(config, registry, catalog: catalog)
        warn_focus_drift(view)
        rows = scoped_census(query.census, view)
        axes = selected_axes(registry.axes)
        print_census_by_axis(rows, axes, registry)
        # A SCOPED request (P44-r1 addendum): no whole-library `enabled:`
        # footer — just an enable hint for THIS axis's not-yet-enabled members.
        print_axis_enable_hint(view, registry, axes)
      elsif options[:sources]
        print_source_map(query.source_groups, Nabu::SourceRegistry.load(config.sources_path))
      elsif slug.empty?
        registry = Nabu::SourceRegistry.load(config.sources_path)
        view = focus_view(config, registry, catalog: catalog)
        warn_focus_drift(view)
        rows = scoped_census(query.census, view)
        if view.disabled
          print_disabled_census(view, rows)
        else
          print_census(rows, options[:long] ? query.descriptions : nil)
        end
        # The hidden side here is CENSUS rows the view dropped (catalog-backed,
        # so orphan slugs the registry no longer carries still count).
        print_focus_note(view, query.census.map(&:slug) - rows.map(&:slug))
      elsif options[:documents] || implied == :documents
        say implied_mode_header(:documents, slug, options[:lang]) if implied
        print_list_documents(query.documents(slug, lang: options[:lang], license: options[:license],
                                                   withdrawn_only: options[:withdrawn], from: from, to: to,
                                                   limit: options[:limit].to_i, prefix: options[:prefix]))
      elsif options[:entries] || implied == :entries
        say implied_mode_header(:entries, slug, options[:lang]) if implied
        print_list_entries(slug, query.entries(slug, prefix: options[:prefix], lang: options[:lang],
                                                     limit: options[:limit].to_i))
      elsif options[:collections] then print_list_collections(slug, query.collections(slug))
      elsif options[:loans]
        code = options[:loans].strip
        if code.empty? then print_list_loans_census(slug, query.loans_census(slug))
        else
          print_list_loan_documents(code, query.loan_documents(slug, code: code, limit: options[:limit].to_i))
        end
      else
        registry = Nabu::SourceRegistry.load(config.sources_path)
        print_list_card(query.card(slug), registry[slug])
        # A named SOURCE is a scoped request too: hint the enable on-ramp only
        # when that source is not yet enabled (silence otherwise).
        print_source_enable_hint(focus_view(config, registry, catalog: catalog), registry, slug)
      end
    rescue Nabu::Query::List::Error => e
      # Unknown source slug: a clean stderr line naming the valid slugs.
      raise Thor::Error, e.message
    ensure
      catalog&.disconnect
    end

    desc "rebuild", "Rebuild the derived db/ from canonical/ (parse-only; no fetch)"
    option :dry_run, type: :boolean, default: false,
                     desc: "Print what would happen and change nothing"
    option :profile, type: :boolean, default: false,
                     desc: "Print the per-source/per-stage timing table after the rebuild (P36-0)"
    option :incremental, type: :boolean, default: false,
                         desc: "Keep the catalog; re-derive only fingerprint-dirty sources " \
                               "(full rebuild remains the reference)"
    def rebuild
      config = Nabu::Config.load
      registry = Nabu::SourceRegistry.load(config.sources_path)
      # db/ is derived data by design (architecture §1); dropping it is the whole
      # point, so a real run needs no confirmation. An empty registry has nothing
      # to replay.
      return say("Nothing to rebuild: no sources registered.") if registry.empty?
      return rebuild_incremental(config, registry) if options[:incremental]

      rebuilder = Nabu::Rebuild.new(config: config, registry: registry)
      if options[:dry_run]
        # --profile implies nothing extra on a dry run: there is no run to time.
        print_plan(rebuilder.plan)
      else
        result = rebuilder.run(progress: progress_reporter)
        finish_progress
        print_result(result)
        print_profile(result.profile) if options[:profile]
      end
    end

    desc "verify", "Re-hash canonical files against the catalog (bitrot/tamper check; cronnable)"
    def verify
      config = Nabu::Config.load
      registry = Nabu::SourceRegistry.load(config.sources_path)
      catalog = open_catalog(config)
      raise Thor::Error, "no catalog — run nabu sync or nabu rebuild" unless catalog

      result = Nabu::Verify.new(config: config, registry: registry, db: catalog).run
      print_verify(result)
      # A clean run returns normally (exit 0); any mismatch/missing/unparseable
      # exits 1 via the shared Thor::Error path, the report already on stdout.
      raise Thor::Error, verify_failure_summary(result) unless result.clean?
    ensure
      catalog&.disconnect
    end

    desc "health", "Source health checks (run-history trends + live golden replay; --remote for the upstream probe)"
    option :remote, type: :boolean, default: false,
                    desc: "Probe every registered upstream (git ls-remote + license drift); no cloning, no corpus fetch"
    option :backfill_pins, type: :boolean, default: false,
                           desc: "Record ledger pins for pre-ledger sources from local clones / state files; no network"
    option :all, type: :boolean, default: false,
                 desc: "Ignore the focus profile: check every source (modules + unfocused sources included)"
    option :accept_creep, type: :string, banner: "SLUG",
                          desc: "Record owner acceptance of SLUG's current quarantine baseline " \
                                "(quiets the creep alarm; it re-arms past the accepted level)"
    option :note, type: :string,
                  desc: "Optional rationale recorded with --accept-creep"
    def health
      # Bare `health` is the local, no-network P5-5 check (run-history trends +
      # live golden replay). --remote is the P5-3 upstream probe.
      # --backfill-pins (P15-7) is the one-shot pin recovery. --accept-creep
      # (P43-0) books a reviewed creep anomaly durably in the ledger. Each
      # keeps its own helper, db lifetime, and exit-code raise.
      return run_backfill_pins if options[:backfill_pins]
      return run_accept_creep(options[:accept_creep]) if options[:accept_creep]

      options[:remote] ? run_remote_health : run_local_health
    end

    desc "search QUERY", "Full-text search the corpus (FTS5 over folded text)"
    long_desc <<~HELP, wrap: false
      Full-text search over every live passage, bm25-ranked. Matching is
      diacritic- and case-insensitive on BOTH sides: μηνιν finds μῆνιν,
      ΜΗΝΙΝ finds both — type without accents, breathings, or iota
      subscripts and still hit the polytonic editions. The fold also matches
      modern Japanese reading habits: 学 finds 學, 弁 finds 辨/瓣/辯.

      EXACT (--exact): glyph-literal match — the query must appear in the
      passage's stored text exactly as typed (NFC-normalized, but nothing
      else: no diacritic strip, no case fold, no reform fold). Use it to tell a
      literal 弁 apart from the default's 弁/辨/瓣/辯. It runs the normal folded
      search for candidates, then keeps only glyph-literal hits — so it does
      not combine with --fuzzy/--near/--lemma/--morph or the character filters.

      WHOLE-WORD (--word): keep only hits where the query lands on a WORD
      BOUNDARY in the stored text — a fold-aware whole-word match. ἦ finds the
      standalone particle ἦ but NOT ἦμαρ (the query sits mid-word there); 学
      still folds to 學 but only as a whole word. A boundary is the start/end
      of the text or a non-letter (whitespace, punctuation — combining marks
      are word-internal, so accents never break a word). --word composes with
      --exact (word-AND-glyph exact: ἦ finds ἦ, not ἦμαρ nor a folded ἠ) and,
      alone, with the plain fold; it does NOT combine with
      --fuzzy/--near/--lemma/--morph or the character filters. Spaceless scripts
      have no word boundaries: --word on a query containing Han or kana is
      REFUSED (use --exact for glyph-literal matching there). Hangul is
      space-delimited, so --word treats it like any alphabetic script.

      BROWSE (term-less): run search with NO query to LIST the corpus, but only
      when at least one CONTENT-NARROWING filter is present — a date window
      (--from/--to/--century), --place, a genre facet (--type/--province/
      --material), or --loans. The page is served in corpus order (no ranking),
      the standard hit rendering with a stored-text window per passage, --limit
      honored. --lang/--license/--source/--axis select whole shelves and are NOT
      sufficient on their own — a term-less listing of a whole language is a
      dump, not a browse — so combine them WITH a content filter to scope one
      (`--century 2 --axis epigraphy` lists the 2nd-c. inscriptions). The
      character-structure filters (--radical/--strokes/--char-component) are a
      separate term-less path of their own.

      Query syntax (SQLite FTS5 over the folded text):
        μηνιν αειδε          all words must appear in the passage (implicit AND)
        '"μηνιν αειδε"'      exact adjacent phrase — FTS quotes, so shell-quote them
        μηνι*                prefix match (μῆνιν, μηνίω, μήνιμα, …)
      Boolean OR/NOT are not supported: operators are folded to lowercase
      and become ordinary search terms.

      Each hit prints the passage urn, its language, and a folded snippet
      with the match in [brackets] (on an interactive terminal, RTL scripts
      highlight the match in reverse video instead — bracket glyphs do not
      survive bidi reordering; piped output keeps the brackets). The snippet is the SEARCH form, not the
      edition text — `nabu show <urn>` gives the pristine passage. DDbDP
      papyri render lost text as the […] gap marker.

      Filters (combinable):
        --lang     ISO-639-3 passage language: grc, lat, got, chu, orv, san, …
        --license  effective license class (document override beats source):
                   open, attribution, nc, research_private, restricted
        --source   one source slug (nabu list names them); composes with
                   every other filter, --lemma/--near/--fuzzy included
        --limit    maximum hits, default 20

      LEMMA SEARCH (--lemma FORM): exact dictionary-form lookup over the
      gold treebank annotations (UD, PROIEL, TOROT — the sources that carry
      per-token lemmas). One lemma finds every inflected attestation, even
      suppletive stems no text query can reach: --lemma λέγω hits λέγουσι,
      λέγοιεν, AND εἶπας/εἰπεῖν. Hits show the dictionary form, the surface
      form(s) that matched, and the pristine passage line. Diacritics are
      optional on the query, exactly as in text search (λεγω works; so does
      final-sigma-insensitive λόγος/λογοσ). --lemma REPLACES the text query
      (combining both is not supported); it composes with --lang, --limit,
      and --license. Passages outside the treebanks carry no lemma
      annotations and are honestly absent here.

      MORPH FACETS (--morph case=dat,number=pl): with --lemma, narrow to
      attestations whose morphology matches the given facets (comma-joined
      key=value, all required). The vocabulary is Universal Dependencies
      feature names — case, number, gender, person, tense, mood, voice,
      degree (values dat, pl/sg, masc, aor, opt, sub…); UD treebanks match on
      their `feats`, PROIEL/TOROT are decoded from their positional tag into
      the same names. Each hit shows the matching surface form(s) and the
      decoded morph evidence. --morph REQUIRES --lemma (bare morphology search
      is out of scope); ORACC carries no inflectional morphology, so
      inflectional facets never match it (honest absence). See conventions §6.1.

      PROXIMITY (A --near B [--window N]): keep only hits where B occurs
      within N words of A in the SAME passage — λόγος near θεός is John 1:1.
      Built on FTS5 NEAR over the folded search forms: --window N is the max
      words BETWEEN the two terms (default 10; 0 = immediately adjacent), and
      NEAR is order-independent (A…B and B…A both count). The window counts
      folded tokens, so for cuneiform (akk/sux), where sign-joins and
      determinatives fold to spaces, one transliterated word spans several
      tokens and the window reads tighter. --near composes with --lemma (the
      anchor then expands to the lemma's attested surface forms before the
      NEAR: --lemma λέγω --near κύριος finds εἶπε near κύριος too), and with
      --lang/--license/--limit. Cross-passage adjacency is OUT — the passage
      is the unit. --morph does not compose with --near (out of scope). Both
      matched terms are bracketed in the snippet, shown in the stored text
      (the pristine spelling, not the folded search form).

      FUZZY (--fuzzy): substring/fragment search for damaged texts — matches
      the fragment ANYWHERE in a passage, mid-word included, where normal
      search sees only whole words and prefixes. Type the fragment straight
      off the edition: editorial square brackets are stripped from the query
      before matching, so `']μηνιν αει['` works as typed. Built on a
      character-trigram index over the folded search form (same
      diacritic/case folding as plain search), so fragments need at least 3
      characters. Scope is DOCUMENTARY sources only (papyri-ddbdp, oracc,
      edh, open-etruscan, edr, elephantine — registry `fuzzy_index: true`):
      papyrus lines, tablets and damaged inscriptions are where fragment
      search earns its index bytes; every result footer names the
      live scope. For half-remembered LITERARY quotations use plain search
      or `nabu parallels` — the literary corpus is deliberately not
      trigram-indexed (it would grow the index 15×). Composes with --lang,
      --limit, --license, and --from/--to/--century/--place; --long prints
      the full folded passage instead of the windowed snippet. --fuzzy
      replaces the FTS query syntax: the fragment is matched literally
      (no AND/phrase/prefix operators) and does not combine with
      --lemma/--near/--morph.

      FACETS (--type / --province / --material): document-grained categorical
      filters over the facet table (P17-2 — EDH inscriptions seed it: 22
      EAGLE inscription types, 103 Roman provinces, materials). Patterns are
      case-insensitive and match the normalized term OR the upstream raw code
      (--type epitaph and --type titsep both work; % wildcards as in
      --place). They compose with the text query, --fuzzy, and every
      date/place filter — the epigraphist's slice is
      `--type epitaph --province "Pannonia inferior" --century 2`. A document
      with no facet row falls out under an active filter (honest absence:
      only faceted sources — inscriptions — can match). Like the date
      filters they do not combine with --lemma/--near. Facet rows land at
      `nabu rebuild` (like the timeline).

      LOANS (--loans CODE): the language-contact facet (P34-2, reading the
      P17-1 annotations) — keep only passages carrying at least one token
      the corpus tags as borrowed from CODE. Passage-grained and read
      straight off each passage's stored token annotations: no reparse, no
      rebuild step. Codes are the mapped origins grc / hbo / arc / lat /
      egy plus any verbatim upstream name (Akkadian, Arabic, Phoenician,
      Persian…), matched case-insensitively; an unattested code finds
      nothing, honestly. Today the Coptic Scriptorium shelf carries the
      layer (~56k of its passages bear Greek loan tokens). Unlike the
      document facets, --loans composes with EVERYTHING: the text query,
      --fuzzy, --lemma/--morph, --near, and all of --lang/--license/
      --source/date/place/facet filters — the loans corpus is
      gold-lemmatized, so `--lemma ⲛⲟⲩⲧⲉ --loans grc` is the designed
      move (attestations of a Coptic lemma in Greek-loan-bearing verses).
      `nabu list coptic-scriptorium --loans` is the census view.

      Sources ingesting parallel translations (registry `translations: true`,
      P7-4) make those English passages ordinary search hits; --lang eng
      scopes to them, --lang grc keeps them out. `show <hit> --parallel`
      jumps from either side to the aligned line in the other.

      Examples:
        nabu search μηνιν                          # finds μῆνιν, accents optional
        nabu search '"ανδρα μοι εννεπε"'           # Odyssey 1.1 — including the
                                                   #   papyri that quote it
        nabu search sapientia --lang lat           # Latin corpus only
        nabu search μηνι* --lang grc               # every derivative of the stem
        nabu search αγαπη --license attribution    # only freely re-usable hits
        nabu search "rich-haired" --lang eng       # the ingested translations
        nabu search --lemma λέγω --lang grc        # every attestation in the Greek
                                                   #   treebank: λέγουσι, εἶπας, εἰπεῖν…
        nabu search --lemma tu --lang lat          # te, tibi, tu across PROIEL Cicero
        nabu search --lemma λόγος --morph case=dat,number=pl
                                                   # only the dative-plural λόγοις
        nabu search λόγος --near θεός --window 5    # λόγος within 5 words of θεός
                                                   #   (John 1:1 and its kin)
        nabu search --lemma λέγω --near κύριος      # every inflection of λέγω
                                                   #   near κύριος: τάδε λέγει κύριος
        nabu search --fuzzy ']μηνιν αει['           # a damaged scrap, brackets and
                                                   #   all — infix match, papyri+oracc
        nabu search --fuzzy στρατηγ --century 6     # mid-word fragment, 6th c. papyri
        nabu search --century 2 --axis epigraphy    # term-less browse: the 2nd-c.
                                                   #   inscriptions, corpus order
        nabu search "dis manibus" --type epitaph --province "Germania superior"
                                                   # the D M formula on epitaphs of
                                                   #   one province (EDH facets)
        nabu search --fuzzy "votum solvit" --type "votive%" --material Sandstein
                                                   # V S L M on sandstone votives
        nabu search ⲡⲛⲟⲩⲧⲉ --loans grc --lang cop   # "God" in verses that carry
                                                   #   Greek loan tokens
        nabu search arma --meter H                  # hits restricted to scanned
                                                    #   hexameters (P44 meter layer:
                                                    #   pedecerto/hypotactic)
        nabu search --meter P --lang lat            # term-less browse: every scanned
                                                    #   pentameter line
        nabu search --lemma ⲕⲁϩ --loans grc         # a Coptic lemma's attestations
                                                   #   inside the Greek-contact zone

      Use cases: find a half-remembered line; concordance-style scans of a
      word across six corpora at once; checking which sources attest a term
      (and under what license) before an export.
    HELP
    option :lang, type: :string, desc: "Restrict to a passage language (e.g. grc, lat)"
    option :license, type: :string,
                     desc: "Restrict to an exact license class (open, attribution, nc, …)"
    option :source, type: :string, banner: "SLUG",
                    desc: "Restrict to one source (`nabu list` names the slugs)"
    option :axis, type: :string, banner: "NAME[,NAME...]",
                  desc: "Restrict to the members of one or more research axes (config/axes.yml) — the " \
                        "multi-source generalization of --source; composes with every path and filter"
    option :limit, type: :numeric, default: 20, desc: "Maximum number of hits"
    option :lemma, type: :string, banner: "FORM",
                   desc: "Exact-lemma search over the gold treebanks (replaces the text query)"
    option :morph, type: :string, banner: "FACETS",
                   desc: "Morphology facets (with --lemma), e.g. case=dat,number=pl"
    option :near, type: :string, banner: "TERM",
                  desc: "Proximity: keep only hits where TERM is within --window words of the query/lemma"
    option :window, type: :numeric, default: Nabu::Query::Proximity::DEFAULT_WINDOW,
                    desc: "Max words between the two --near terms (default " \
                          "#{Nabu::Query::Proximity::DEFAULT_WINDOW}; 0 = adjacent)"
    option :from, type: :numeric, banner: "YEAR",
                  desc: "Earliest date: signed historical year, negative = BCE (-300 = 300 BCE, no year 0)"
    option :to, type: :numeric, banner: "YEAR",
                desc: "Latest date: signed historical year (14 = 14 CE); composes with --from"
    option :century, type: :numeric, banner: "N",
                     desc: "Shorthand for one century's --from/--to (6 = 6th c. CE, -2 = 2nd c. BCE)"
    option :place, type: :string, banner: "PATTERN",
                   desc: "Provenance place LIKE filter (Oxyrhynchus, oxyrhynch%) — dated papyri"
    option :type, type: :string, banner: "PATTERN",
                  desc: "Inscription-type facet filter (epitaph, votive%, or the raw titsep code)"
    option :province, type: :string, banner: "PATTERN",
                      desc: "Roman-province facet filter (Germania inferior, pannonia%)"
    option :material, type: :string, banner: "PATTERN",
                      desc: "Material facet filter (Marmor, sandstein%)"
    option :loans, type: :string, banner: "CODE",
                   desc: "Loan-origin facet: only passages with ≥1 token borrowed from CODE " \
                         "(grc, hbo, arc, lat, egy — Coptic Scriptorium)"
    option :meter, type: :string, banner: "CODE",
                   desc: "Meter facet: only passages carrying a meter enrichment with this code " \
                         "(pedecerto codes H, P, …) or name (hypotactic 'dactylic hexameter'); " \
                         "case-insensitive; composes with a text query or stands alone as a browse"
    option :meter_pattern, type: :string, banner: "PATTERN",
                           desc: "Meter facet: exact foot/scansion pattern (pedecerto DSDS, " \
                                 "hypotactic '-u u -uu …'); composes with --meter or stands alone"
    option :radical, type: :numeric, banner: "N",
                     desc: "Character filter: KangXi radical number 1-214 (Unihan kRSUnicode); " \
                           "composes with --strokes/--char-component and a text query"
    option :strokes, type: :string, banner: "A-B",
                     desc: "Character filter: total-stroke range A-B (or a single N; Unihan kTotalStrokes)"
    option :char_component, type: :string, banner: "C",
                            desc: "Character filter: characters CONTAINING C anywhere in their " \
                                  "structure (KRADFILE ∪ BabelStone IDS transitive containment)"
    option :fuzzy, type: :boolean, default: false,
                   desc: "Substring/fragment search over the documentary trigram index (]μηνιν αει[)"
    option :long, type: :boolean, default: false,
                  desc: "With --fuzzy: print the full folded passage instead of the windowed snippet"
    option :gold_only, type: :boolean, default: false,
                       desc: "With --lemma: gold (verified) annotations only — exclude silver " \
                             "(automatic) lemmatization and equivalence (scholar-curated " \
                             "Classical-Latin equivalents on non-Latin passages)"
    option :exact, type: :boolean, default: false,
                   desc: "Glyph-literal match; the default fold matches modern reading habits " \
                         "(学 finds 學, 弁 finds 辨/瓣/辯) — --exact does not"
    option :word, type: :boolean, default: false,
                  desc: "Whole-word match: the query must land on a word boundary in the stored " \
                        "text (ἦ finds ἦ, not ἦμαρ); refuses spaceless CJK/kana"
    option :words, type: :boolean, default: false,
                   desc: "Tibetan word-grain match (P54-4): keep only hits whose matched span " \
                         "aligns with word boundaries (nabu-data xct/segmentation) — Tibetan is " \
                         "indexed at syllable grain, so a plain query also lands on accidental " \
                         "runs across word boundaries; non-Tibetan queries or an unsynced module " \
                         "degrade to plain search with a note"
    option :lect, type: :string, banner: "LECT-ID",
                  desc: "Lect filter (P57-4, nabu-lects module): keep only hits whose (language, " \
                        "source) resolves to this lect id or a more specific one under it " \
                        "(--lect lat matches lat:med; --lect lat:med matches lat:med and " \
                        "lat:med/xyz, not lat:cla). Text search or a term-less browse only, not " \
                        "--lemma/--near; errors if the nabu-lects module is not synced"
    display_option
    def search(query = nil)
      query = query.to_s.strip
      display_mode
      if (options[:from] || options[:to] || options[:century] || options[:place] || facet_filters) &&
         (options[:near] || options[:lemma])
        raise Thor::Error, "search: --from/--to/--century/--place/--type/--province/--material compose " \
                           "with text search only, not --lemma/--near (the dated/faceted corpus — " \
                           "papyri, inscriptions — is not lemmatized)"
      end
      if options[:fuzzy] && (options[:near] || options[:lemma] || options[:morph])
        raise Thor::Error, "search: --fuzzy is literal substring matching — it does not combine " \
                           "with --lemma/--near/--morph"
      end
      if (options[:meter] || options[:meter_pattern]) &&
         (options[:near] || options[:lemma] || options[:fuzzy] || char_filter_options?)
        raise Thor::Error, "search: --meter/--meter-pattern filter the meter enrichment layer and " \
                           "compose with plain text search or a term-less browse only — not " \
                           "--lemma/--near/--fuzzy or the character-structure filters"
      end
      if options[:gold_only] && (!options[:lemma] || options[:near])
        raise Thor::Error, "search: --gold-only filters the lemma tier — it requires --lemma " \
                           "(and does not compose with --near)"
      end
      if options[:exact] && (options[:fuzzy] || options[:near] || options[:lemma] || options[:morph])
        raise Thor::Error, "search: --exact is glyph-literal substring matching over the plain " \
                           "text query — it does not combine with --fuzzy/--near/--lemma/--morph"
      end
      if options[:exact] && char_filter_options?
        raise Thor::Error, "search: --exact is a word-level glyph-literal filter — it does not " \
                           "combine with the character-structure filters (--radical/--strokes/--char-component)"
      end
      if options[:word] && (options[:fuzzy] || options[:near] || options[:lemma] || options[:morph] ||
                            char_filter_options?)
        raise Thor::Error, "search: --word is a whole-word filter over the plain text query — it " \
                           "composes only with --exact, not --fuzzy/--near/--lemma/--morph or the " \
                           "character-structure filters"
      end
      if options[:word] && (msg = Nabu::Query::Search.word_refusal_for(query))
        raise Thor::Error, "search: #{msg}"
      end
      if options[:words] && (query.empty? || options[:fuzzy] || options[:near] || options[:lemma] ||
                             options[:morph] || options[:exact] || options[:word] || char_filter_options?)
        raise Thor::Error, "search: --words is the Tibetan word-grain filter over the plain text " \
                           "query — it needs a text query and does not combine with --exact/--word/" \
                           "--fuzzy/--near/--lemma/--morph or the character-structure filters"
      end
      if options[:lect] && (options[:near] || options[:lemma] || options[:fuzzy] || char_filter_options?)
        raise Thor::Error, "search: --lect filters the lect-resolution layer and composes with " \
                           "plain text search or a term-less browse only — not --lemma/--near/" \
                           "--fuzzy or the character-structure filters"
      end

      if char_filter_options?
        if options[:fuzzy] || options[:near] || options[:lemma] || options[:morph]
          raise Thor::Error, "search: the character filters (--radical/--strokes/--char-component) are " \
                             "character-level structure search — they do not combine with the word-level " \
                             "--lemma/--near/--fuzzy/--morph (they compose with a plain text query)"
        end
        return char_structured_search(query)
      end
      return fuzzy_search(query) if options[:fuzzy]
      return proximity_search(query) if options[:near]
      return lemma_search(query) if options[:lemma]
      raise Thor::Error, "search: --morph requires --lemma (bare morphology search is out of scope)" if options[:morph]
      return browse_search if query.empty?

      validate_license!(options[:license])
      from, to = date_window
      place = options[:place]
      facets = facet_filters
      loans = loans_filter
      config = Nabu::Config.load
      catalog = open_catalog(config)
      fulltext = open_fulltext(config)
      # Either half of the derived store missing means the corpus was never
      # built/indexed; a search cannot run.
      raise Thor::Error, "no index — run nabu sync or nabu rebuild" unless catalog && fulltext

      require_timeline!(catalog) if from || to || place
      require_facets!(catalog) if facets
      validate_source!(catalog, options[:source])
      axis_names, axis_slugs = axis_membership(command: "search", config: config)
      lects = require_lects!(config, options[:lect])

      searcher = Nabu::Query::Search.new(catalog: catalog, fulltext: fulltext, lects: lects || :auto)
      results = searcher.run(query, lang: options[:lang], license: options[:license],
                                    limit: options[:limit].to_i, from: from, to: to, place: place,
                                    facets: facets, source: options[:source], sources: axis_slugs,
                                    loans: loans, meter: options[:meter],
                                    meter_pattern: options[:meter_pattern],
                                    exact: options[:exact], word: options[:word], words: options[:words],
                                    lect: options[:lect])
      print_search_results(results, facets: facets, query: query, loans: loans, axis: axis_names,
                                    incomplete: searcher.incomplete_hint, exact: options[:exact],
                                    word: options[:word], rank_note: searcher.rank_note,
                                    meter_note: searcher.meter_note, words_note: searcher.words_note)
      print_display_footer
    ensure
      catalog&.disconnect
      fulltext&.disconnect
    end

    desc "concord QUERY", "Concordance (KWIC): keyword-in-context lines, one per hit"
    long_desc <<~HELP, wrap: false
      Keyword-in-context concordance: every hit as one line — left context, the
      matched keyword, right context — with the keyword aligned in a fixed
      column so you can scan a word's usage down the page. The keyword is
      located in the PRISTINE edition text (accents and all), not the folded
      search form: a concordance is for reading real usage.

      Matching is exactly `nabu search`: diacritic- and case-insensitive on both
      sides (μηνιν finds μῆνιν), implicit-AND multiple words, "quoted phrase",
      prefix* — and --lemma FORM for exact dictionary-form lookup over the gold
      treebanks (finds every inflected attestation). Rows come in CORPUS order
      (urn/citation), not relevance order — the point is scanning, not ranking.
      One row per passage: a passage with the keyword twice shows its first
      occurrence.

      Layout: left context is trimmed to --width cells per side (default 40)
      and right-justified so the keyword column lines up; the right context is
      trimmed to the same width; clipped context is marked with …. Each row
      ends with the passage urn and [language]. Alignment counts East-Asian
      display width (Nabu::Display.width), so a lzh/ojp Han line lines up its
      keyword column exactly where a grc line does — each ideograph two cells.

      Filters (as in search): --lang, --license, --limit (default 20).

      Examples:
        nabu concord μῆνιν                       # every attestation of μῆνιν, KWIC
        nabu concord μηνιν --width 30            # tighter context, accents optional
        nabu concord ἄειδε --lang grc --limit 50
        nabu concord --lemma λέγω --lang grc     # every inflection in context:
                                                 #   λέγουσι, εἶπας, εἰπεῖν…
        nabu concord sapientia --lang lat        # a Latin word across the corpus

      Use cases: see how a word is actually used across six corpora at once;
      spot collocations and formulae; build a hand concordance for a term before
      writing about it.
    HELP
    option :lang, type: :string, desc: "Restrict to a passage language (e.g. grc, lat)"
    option :license, type: :string,
                     desc: "Restrict to an exact license class (open, attribution, nc, …)"
    option :limit, type: :numeric, default: 20, desc: "Maximum number of KWIC lines"
    option :width, type: :numeric, default: Nabu::Query::Concord::DEFAULT_WIDTH,
                   desc: "Context characters per side (default #{Nabu::Query::Concord::DEFAULT_WIDTH})"
    option :lemma, type: :string, banner: "FORM",
                   desc: "Exact-lemma concordance over the gold treebanks (replaces the text query)"
    display_option
    def concord(query = nil)
      query = query.to_s.strip
      display_mode
      lemma = options[:lemma]
      if lemma
        raise Thor::Error, "concord: --lemma replaces the text query — give one or the other" unless query.empty?

        lemma = lemma.strip
        raise Thor::Error, "concord: --lemma needs a lemma" if lemma.empty?
      elsif query.empty?
        raise Thor::Error, "concord: give a query"
      end

      validate_license!(options[:license])
      config = Nabu::Config.load
      catalog = open_catalog(config)
      fulltext = open_fulltext(config)
      raise Thor::Error, "no index — run nabu sync or nabu rebuild" unless catalog && fulltext
      if lemma && !fulltext.table_exists?(Nabu::Store::Indexer::LEMMA_TABLE)
        raise Thor::Error, "no lemma index (the fulltext index predates lemma search) — " \
                           "run nabu sync or nabu rebuild"
      end

      rows = Nabu::Query::Concord.new(catalog: catalog, fulltext: fulltext).run(
        query.empty? ? nil : query, lemma: lemma, lang: options[:lang],
                                    license: options[:license], limit: options[:limit].to_i, width: options[:width].to_i
      )
      print_concord_rows(rows)
      print_display_footer
    ensure
      catalog&.disconnect
      fulltext&.disconnect
    end

    desc "parallels URN", "Find passages that quote or echo this one (intertext over the FTS index)"
    long_desc <<~HELP, wrap: false
      Passage-anchored intertext: point at ONE passage and find where the corpus
      quotes or echoes it — the classicist's "who cites this line? where does it
      resurface?" (docs/intertext-design.md §1). Query-time over the same FTS
      index as `search`, no precomputation: the anchor is folded to its search
      form, cut into overlapping 4-word grams, and each gram is probed as an
      exact phrase; passages that share grams are candidates, ranked by shared-
      gram count WEIGHTED BY RARITY (a rare shared phrase — a real quotation —
      outweighs a pile of common function-word grams).

      Not to be confused with `align` (the translation-column hub, verse X across
      its witnesses): parallels DISCOVERS reception across the whole corpus, from
      surface text alone.

      Each hit is one DOCUMENT (duplicate witnesses and multi-edition works
      otherwise flood the ranks): its best-matching passage urn, the score, the
      number of shared grams, and — when the document matches in several places —
      a "loci" count. Under each hit the shared PHRASE spans are shown (the grams
      merged back into contiguous text). Evidence is the folded search form, so
      accents/breathings are stripped — it marks WHAT matched; `nabu show <urn>`
      gives the pristine line.

      Elision is folded at gram-build: the apostrophe that some editions write as
      a letter (SBLGNT ἐπʼ) and others as punctuation (Swete/First1K ἐπ’) is
      stripped so a gram matches across editions — the fix that lets Matthew 4:4
      find LXX Deuteronomy 8:3.

      Only the anchor's OWN document is excluded. Translations and other-language
      witnesses self-exclude (they share no folded tokens with the anchor's
      language); a second same-language edition of the anchor's own work is kept
      — it is exactly the corroborating parallel you want.

      LEMMA ECHOES: when the anchor carries gold treebank lemmas (UD/PROIEL/
      TOROT), a second section lists passages sharing ≥2 of its RARE lemmas —
      re-inflected or reordered allusion that verbatim grams miss. Absent (and
      free) for non-lemmatized anchors.

      Filters: --lang / --license (exact class) scope candidates; --limit caps
      each list (default 15). --long expands every truncated list — all shared
      phrase spans and all shared lemmas, untrimmed (compact shows the first few
      with a "… and N more" tail).

      BATCH MODE (P16-1, the links journal): `parallels --batch SCOPE` mines a
      whole corpus slice — SCOPE is a source slug or a document-urn prefix,
      exactly the `formulas` scope grammar — looping this same engine over
      every anchor passage and PERSISTING the hits as kind=parallel edges in
      the links journal (db/links.sqlite3; `nabu links <urn>` reads them, and
      `show` grows a "linked:" footer). Each unordered pair is stored once, in
      the direction the probe found it; a rerun of the same scope supersedes
      the previous run's edges (idempotent). Pruning is explicit, never
      silent: only the top --per-anchor hits (default
      #{Nabu::BatchParallels::DEFAULT_PER_ANCHOR}) clearing --min-score
      (default #{Nabu::BatchParallels::DEFAULT_MIN_SCORE}) persist, and the
      summary line names both. --db writes the journal somewhere else (a
      scratch run). Interactive output is NEVER persisted — recomputing costs
      milliseconds; a stored copy would only go stale.

      Examples:
        nabu parallels urn:nabu:sblgnt:john:1.1          # John 1:1 across the Fathers
        nabu parallels urn:cts:greekLit:tlg0012.tlg002.perseus-grc2:1.1
                                                         # the Odyssey proem — who quotes it
        nabu parallels urn:nabu:sblgnt:matt:4.4 --long   # Matt 4:4 → Luke, Origen, LXX Deut 8:3
        nabu parallels <urn> --lang grc --limit 30       # Greek parallels only, wider page
        nabu parallels --batch urn:nabu:sblgnt:matt --lang grc
                                                         # mine Matthew's parallels into the journal
        nabu parallels --batch sblgnt --min-score 0.1    # a whole source, stricter floor

      Use cases: trace a verse's reception; find the source a Father is quoting;
      seed the citation graph one batch scope at a time.
    HELP
    option :lang, type: :string, desc: "Restrict candidates to a passage language (e.g. grc, lat)"
    option :license, type: :string,
                     desc: "Restrict candidates to an exact license class (open, attribution, nc, …)"
    option :limit, type: :numeric, default: 15, desc: "Maximum hits per signal (default 15)"
    option :long, type: :boolean, default: false,
                  desc: "Expand every truncated list: all shared phrase spans and shared lemmas, untrimmed"
    option :batch, type: :boolean, default: false,
                   desc: "Mine a SCOPE (source slug or urn prefix) and persist edges to the links journal"
    option :min_score, type: :numeric, banner: "S",
                       desc: "With --batch: rarity-score floor an edge must clear " \
                             "(default #{Nabu::BatchParallels::DEFAULT_MIN_SCORE})"
    option :per_anchor, type: :numeric, banner: "N",
                        desc: "With --batch: top document-grain hits kept per anchor " \
                              "(default #{Nabu::BatchParallels::DEFAULT_PER_ANCHOR})"
    option :db, type: :string, banner: "PATH",
                desc: "With --batch: write the links journal at PATH instead of db/links.sqlite3"
    option :lect, type: :string, banner: "LECT-ID",
                  desc: "Restrict candidates to a lect (P59-3, nabu-lects module): keep only hits " \
                        "whose resolution is this lect id or a more specific one under it — the " \
                        "same prefix semantics as search --lect; errors if the module is not synced"
    display_option
    def parallels(urn = nil)
      urn = urn.to_s.strip
      display_mode
      validate_license!(options[:license])
      if options[:batch] && options[:lect]
        raise Thor::Error, "parallels: --lect does not apply with --batch (the miner is corpus-wide)"
      end
      return batch_parallels(urn) if options[:batch]

      %i[min_score per_anchor db].each do |flag|
        next unless options[flag]

        raise Thor::Error, "parallels: --#{flag.to_s.tr('_', '-')} only applies with --batch " \
                           "(interactive results are never persisted)"
      end
      raise Thor::Error, "parallels: give a passage urn" if urn.empty?

      config = Nabu::Config.load
      catalog = open_catalog(config)
      fulltext = open_fulltext(config)
      raise Thor::Error, "no index — run nabu sync or nabu rebuild" unless catalog && fulltext

      result = Nabu::Query::Parallels.new(catalog: catalog, fulltext: fulltext)
                                     .run(urn, limit: options[:limit].to_i,
                                               lang: options[:lang], license: options[:license],
                                               lect: options[:lect])
      print_parallels(result, urn: urn, long: options[:long])
      print_display_footer
    ensure
      catalog&.disconnect
      fulltext&.disconnect
    end

    desc "formulas SCOPE", "Mine the repeated n-gram formulas within a corpus slice (oral-formulaic)"
    long_desc <<~HELP, wrap: false
      Intra-corpus formula mining: point at a corpus SLICE and find its recurring
      formulas — the oral-formulaic scholar's "what are the fixed phrases of this
      tradition, and where does each occur?" (docs/intertext-design.md §5). The
      same gram machinery as `parallels` pointed INWARD: instead of probing one
      passage against the whole corpus, every passage of the slice is folded, cut
      into overlapping n-word grams, and the grams counted in memory — the ones
      that recur are the formulas. Zero precomputation (~0.2 s per ~200k-token
      slice); reads the folded text straight from the catalog.

      SCOPE is a source slug (`aspr`) when one exists, else a urn prefix — a whole
      work (urn:cts:greekLit:tlg0012.tlg001.perseus-grc2) or a super-prefix over
      several (urn:cts:greekLit:tlg0012 = Iliad + Odyssey, the Homeric corpus).

      LANGUAGE: a translation-bearing source rides the same urn prefix as its base
      text (perseus-greek holds Greek AND aligned English), so an unfiltered run
      mixes traditions — pass --lang to mine one (a single-language source like
      ASPR needs none).

      RANKING: by count × gram length. No stoplist — the ranking is self-filtering
      (a genuine formula out-recurs any pure function-word sequence; measured, not
      one all-function-word gram reaches Homer's top). --min-count raises the
      recurrence floor against a noisy tail.

      Each formula prints its count and the folded gram (accents stripped, like
      `search` highlights — `nabu show <urn>` gives the pristine line), with a few
      example loci beneath. --long lists every locus of every reported formula.

      BATCH MODE (P16-2, the links journal): `formulas --batch SCOPE` runs the
      whole-tradition sweep once and PERSISTS kind=formula edges. A formula is
      a refrain across many loci, so it maps onto the pair-shaped journal as a
      STAR: each formula's first locus (urn order — deterministic) is the hub,
      with one edge to every other locus carrying the gram (detail) and the
      count (score); `nabu links <locus>` shows which refrain ties the line to
      the tradition, and `links <hub>` fans out every locus. Pruning is named,
      never silent: the top --max-formulas by rank persist (default
      #{Nabu::BatchFormulas::DEFAULT_MAX_FORMULAS}), at --min-count and
      --gram-size, all recorded in the run's params. A rerun of the same scope
      supersedes (idempotent); --db writes the journal elsewhere. Interactive
      output is never persisted.

      Examples:
        nabu formulas urn:cts:greekLit:tlg0012 --lang grc   # the Homeric formulas
        nabu formulas aspr                                  # Old English verse formulas
        nabu formulas aspr --gram-size 3 --min-count 5      # the riddle refrain "hwæt ic hatte"
        nabu formulas urn:cts:greekLit:tlg0012 --lang grc --long   # every locus
        nabu formulas --batch aspr                          # persist the ASPR formula stars
        nabu formulas --batch urn:cts:greekLit:tlg0012 --lang grc --max-formulas 500

      Use cases: characterize a tradition's formulaic diction; find every
      occurrence of a formula; seed an oral-formulaic study; wire the refrains
      into the mined citation graph (`nabu links`).
    HELP
    option :lang, type: :string,
                  desc: "Restrict the slice to a language (grc, ang) — wanted when a source mixes translations"
    option :min_count, type: :numeric, default: Nabu::Query::Formulas::DEFAULT_MIN_COUNT,
                       desc: "Minimum recurrence to count as a formula (default 3)"
    option :gram_size, type: :numeric, default: Nabu::Query::Formulas::DEFAULT_GRAM_SIZE,
                       desc: "Words per gram (2–8; default 4)"
    option :limit, type: :numeric, default: Nabu::Query::Formulas::DEFAULT_LIMIT,
                   desc: "Maximum formulas shown (default 25)"
    option :long, type: :boolean, default: false,
                  desc: "List every locus of every reported formula (compact shows a few examples)"
    option :batch, type: :boolean, default: false,
                   desc: "Sweep the SCOPE once and persist kind=formula edges to the links journal"
    option :max_formulas, type: :numeric, banner: "N",
                          desc: "With --batch: top formulas by rank persisted " \
                                "(default #{Nabu::BatchFormulas::DEFAULT_MAX_FORMULAS})"
    option :db, type: :string, banner: "PATH",
                desc: "With --batch: write the links journal at PATH instead of db/links.sqlite3"
    def formulas(scope = nil)
      scope = scope.to_s.strip
      return batch_formulas(scope) if options[:batch]

      %i[max_formulas db].each do |flag|
        next unless options[flag]

        raise Thor::Error, "formulas: --#{flag.to_s.tr('_', '-')} only applies with --batch " \
                           "(interactive results are never persisted)"
      end
      raise Thor::Error, "formulas: give a source slug or urn prefix" if scope.empty?

      config = Nabu::Config.load
      catalog = open_catalog(config)
      raise Thor::Error, "no index — run nabu sync or nabu rebuild" unless catalog

      result = Nabu::Query::Formulas.new(catalog: catalog).run(
        scope, gram_size: options[:gram_size].to_i, min_count: options[:min_count].to_i,
               lang: options[:lang], limit: options[:limit].to_i, long: options[:long]
      )
      print_formulas(result, long: options[:long])
    rescue ArgumentError => e
      raise Thor::Error, "formulas: #{e.message}"
    ensure
      catalog&.disconnect
    end

    desc "links URN", "Mined cross-reference edges touching this urn (the links journal)"
    long_desc <<~HELP, wrap: false
      Read the links journal (docs/intertext-design.md §7, architecture §15):
      every batch-mined edge touching URN, BOTH directions, grouped by kind
      (parallel, formula, cognate, reference, etymology). Each edge shows
      its counterpart urn resolved to the document title and language plus
      its kind's evidence — a parallel's rarity score, a formula's gram and
      count (← the hub locus of the refrain's star; `links <hub>` fans out
      every locus), a cognate's meet (ref · root [shelf] — a gem-pro shelf
      under a Slavic witness reads as a borrowing), a reference's asserting
      manifest (P19-4: a local-library article beside the passages it
      discusses), an etymology's ancestor lemma (P28-3: a Coptic dictionary
      entry's hieroglyphic/demotic predecessors from the ORAEC crosswalk);
      → means a batch anchor at URN discovered the counterpart,
      ← means the edge was found from the other end. The footer cites the
      producer run(s) that minted the edges — scope, parameters, and date —
      so every edge is honest about its provenance.

      Edges are urn-keyed and live OUTSIDE the rebuildable dbs, so they
      survive `nabu rebuild` untouched; counterparts re-resolve against the
      current catalog (passage grain first, document grain second,
      dictionary-entry grain third — an ingested shelf's urn:nabu:dict:
      urns read "headword — dictionary"), and one that no longer resolves
      is flagged "(not in catalog)" rather than hidden. Edges are minted
      ONLY by batch producers (`parallels --batch SCOPE`, `formulas --batch
      SCOPE`, `cognates --batch WORK`, and the sync-time reference/etymology
      refreshes of the declaring sources); interactive output never
      persists.

      Compact shows the first few edges per kind; --long lists all. --db
      reads a journal written elsewhere (a scratch batch run).

      Examples:
        nabu links urn:nabu:sblgnt:matt:4.4     # who is wired to Matt 4:4
        nabu links urn:nabu:sblgnt:matt:4.4 --long
        nabu links <urn> --db /tmp/links.sqlite3

      Use cases: walk the mined citation graph passage by passage; audit what
      a batch run asserted; jump between quotation and source via `nabu show`.
    HELP
    option :long, type: :boolean, default: false,
                  desc: "List every edge of every kind (compact shows the first few per kind)"
    option :db, type: :string, banner: "PATH",
                desc: "Read the links journal at PATH instead of db/links.sqlite3"
    def links(urn = nil)
      urn = urn.to_s.strip
      raise Thor::Error, "links: give a passage or document urn" if urn.empty?

      config = Nabu::Config.load
      catalog = open_catalog(config)
      raise Thor::Error, "no catalog — run nabu sync or nabu rebuild" unless catalog

      path = options[:db] || config.links_path
      journal = Nabu::Store::LinksJournal.open_readonly(path)
      return say("no links journal yet — mine one with `nabu parallels --batch SCOPE`") if journal.nil?

      result = Nabu::Query::Links.new(catalog: catalog, journal: journal).run(urn)
      raise Thor::Error, "links: unknown urn #{urn} (no catalog entry, no edges)" if result.nil?

      print_links(result, long: options[:long])
      print_links_notes_lane(catalog, urn)
    ensure
      catalog&.disconnect
      journal&.disconnect
    end

    desc "show URN", "Show a passage or document by urn (withdrawn items shown, flagged)"
    long_desc <<~HELP, wrap: false
      Inspect one passage or one whole document by urn. Unlike search and
      export, show hides nothing: withdrawn and retired-upstream items
      appear too, honestly labeled — this is the "what does my collection
      actually hold" lens.

      A PASSAGE urn prints the pristine text, its document, effective
      license, revision, and the full provenance trail (loaded / revised /
      withdrawn / restored / retired events with timestamps) — the
      passage's complete life story.

      A DOCUMENT urn prints the header (title, language, source, license,
      revision, any withdrawn/retired flag) and every passage in citation
      order, listed as :suffixes relative to the document urn printed once
      above; --full-urn restores absolute urns for copy-paste. Long
      documents: pipe to less.

      urn shapes across the corpus:
        CTS editions   urn:cts:greekLit:tlg0012.tlg002.perseus-grc2       (document)
                       urn:cts:greekLit:tlg0012.tlg002.perseus-grc2:1.1   (book 1, line 1)
        papyri (DDbDP) urn:nabu:ddbdp:aegyptus:89:240:b2:5
                       (:b2 = implicit restart block — an unlabeled column/
                        fragment where the edition's line numbers restart)
        treebanks      urn:nabu:proiel:afnik:194690                     (sentence)
                       urn:nabu:ud:gothic-proiel:got_proiel-ud-dev:37589

      RANGES (URN:<start>-<end>): a document urn plus two citation suffixes
      joined by a hyphen prints an INCLUSIVE, sequence-ordered slice of that
      one document between the endpoints — both endpoints must resolve to
      existing passages of the same document (a clear error names whichever
      fails; a start after its end is refused, suggesting a swap). The slice
      is by STORED sequence, whatever citation shapes lie between: a papyri
      restart block (:b2, an implicit column/fragment) is sliced straight
      through. Precedence: a literal passage urn is resolved FIRST, so a urn
      that itself contains a hyphen is never misparsed as a range; the range
      split is on the LAST hyphen (citation suffixes never contain one, the
      version segment perseus-grc2 does). Ranges compose with --full-urn and
      with --parallel (the range slices the queried edition; pairing then
      applies to the sliced rows only).

      PARALLEL TRANSLATIONS (--parallel [LANG], default eng): for a CTS
      document or passage urn — or an ORACC tablet, whose translation is the
      -en sibling document (P13-4) — find the sibling edition of the SAME
      work in LANG (sources ingest translations only when their registry
      entry sets `translations: true`) and render the two SPAN-GROUPED by
      citation suffix. A verse-for-verse translation pairs line by line —
      :1.1 Greek next to :1.1 English. A card-cited prose translation (both
      English Homers) anchors one block of text at a card's first line: the
      original lines are listed, then the translation ONCE, labeled with its
      coverage in the original's numbering (`eng [:1.1 — covers :1.1–:1.43]`)
      plus a clip note when a range shows only part of a card. ORACC's
      paragraph-grained SAA units render as exactly such blocks over the
      tablet's o.1/r.5 lines. A suffix present in only one edition renders
      honestly one-sided, never fuzzed. Works with --full-urn. Where a
      kind=translation link edge joins documents across sources (the
      Kangyur↔84000 crosswalk), --parallel pairs them at Degé folio/page
      grain — no extra flag.

      Examples:
        nabu show urn:cts:greekLit:tlg0012.tlg002.perseus-grc2:1.1
        nabu show urn:cts:greekLit:tlg0012.tlg001.perseus-grc2:1.1-1.10
                                                  # Iliad 1.1–1.10, one slice
        nabu show urn:nabu:ddbdp:aegyptus:89:240:1-b2:2
                                                  # a papyrus slice across a restart block
        nabu show urn:nabu:ddbdp:aegyptus:89:240            # whole papyrus
        nabu show urn:nabu:ddbdp:aegyptus:89:240 --full-urn # absolute urns
        nabu show urn:cts:greekLit:tlg0013.tlg013.perseus-grc2 --parallel
                                                  # Greek + eng, line by line
        nabu show urn:cts:greekLit:tlg0012.tlg002.perseus-grc2:1.5-1.10 --parallel
                                                  # a mid-card slice: the eng block labeled
                                                  #   "covers :1.1–:1.43; range shows :1.5–:1.10"
        nabu show urn:cts:greekLit:tlg0013.tlg013.perseus-eng2:1 --parallel grc
                                                  # one translated line + its original
        nabu show urn:nabu:oshb:gen:1:1 --tokens  # + the stored token annotations,
                                                  #   verbatim (form, lemma, osm, …)

      TOKENS (--tokens): appends the passage's stored token annotations as
      one line per token — `form` first, then every key the store holds for
      that token, exactly as stored (the honest raw view; nothing decoded,
      nothing invented). A passage without token annotations, and a
      document/range urn, say so.

      SEGMENTED (--segmented): renders Tibetan-language rows (xct/bod/otb)
      with word boundaries — the stored text with a space inserted at each
      boundary (tokens verbatim, trailing tsheg kept), segmented through
      the published nabu-data xct/segmentation dataset. An off-language
      row, or a box that has not run `nabu sync nabu-data`, prints the
      plain text plus one honest note.

      Use cases: read the real edition text behind a search snippet; audit
      a document's revision/provenance history after a sync; eyeball what
      "withdrawn" or "retired upstream" actually holds; read a Greek work
      you can't sight-read next to its English translation; inspect the
      exact lemma/morphology evidence a treebank stored for one passage.
    HELP
    option :full_urn, type: :boolean, default: false,
                      desc: "List document passages with absolute urns instead of :suffixes"
    option :parallel, type: :string, lazy_default: "eng", banner: "[LANG]",
                      desc: "Align with the same work's LANG edition by citation suffix (default eng)"
    option :random, type: :boolean, default: false,
                    desc: "Show random passages instead of a urn (the eyeball ritual at a source flip)"
    option :source, type: :string, banner: "SLUG",
                    desc: "With --random: draw only from this source (default: the whole corpus)"
    option :lang, type: :string, banner: "CODE",
                  desc: "With --random: draw only passages in this language (grc, lat, … — the multi-lang eyeball)"
    option :count, type: :numeric, default: 1,
                   desc: "With --random: how many passages (default 1, cap #{Nabu::Query::Random::MAX_COUNT})"
    option :tokens, type: :boolean, default: false,
                    desc: "Append the passage's stored token annotations verbatim (form + every key present)"
    option :segmented, type: :boolean, default: false,
                       desc: "Render Tibetan (xct/bod/otb) passages with word boundaries " \
                             "(needs the synced nabu-data module)"
    display_option
    def show(urn = nil)
      urn = urn.to_s.strip
      display_mode
      if options[:tokens] && (options[:random] || options[:parallel])
        raise Thor::Error, "show: --tokens does not compose with --random/--parallel"
      end
      if options[:segmented] && (options[:random] || options[:parallel])
        raise Thor::Error, "show: --segmented does not compose with --random/--parallel"
      end

      config = Nabu::Config.load
      catalog = open_catalog(config)
      raise Thor::Error, "no catalog — run nabu sync or nabu rebuild" unless catalog

      if options[:random]
        show_random(catalog, urn, config)
        return print_display_footer
      end
      raise Thor::Error, "show: --source requires --random" if options[:source]
      raise Thor::Error, "show: --lang restricts --random draws — give a urn, or add --random" if options[:lang]
      raise Thor::Error, "show: give a urn" if urn.empty?

      if options[:parallel]
        show_parallel(catalog, urn, options[:parallel], config)
        return print_display_footer
      end

      # pleiades: :auto — the findspot line (P44-2) feature-detects the
      # gazetteer dump lazily; nothing loads unless the shown document
      # carries a captured Pleiades id.
      show_query = Nabu::Query::Show.new(catalog: catalog, pleiades: :auto)
      result = show_query.run(urn)
      raise Thor::Error, "urn not found: #{urn}" if result.nil?

      # --segmented (P54-2): the word-broken Tibetan rendering. The
      # segmentation is Query::Show's (the one serializer MCP shares); here
      # we only swap texts on a copy of the result — or keep the plain
      # output plus the query layer's one honest note line.
      seg_note = nil
      if options[:segmented]
        seg_note = show_query.segmentation_note(result.respond_to?(:language) ? result.language : nil)
        result = segmented_show_result(show_query, result) if seg_note.nil?
      end

      print_show(result)
      say seg_note if seg_note
      print_show_tokens(result) if options[:tokens]
      print_linked_footer(config, result.urn)
      print_notes_footer(catalog, result)
      print_display_footer
    rescue Nabu::Query::Range::Error, Nabu::Query::Random::Error,
           Nabu::Query::Parallel::TranslationMismatch => e
      # A range urn that names two endpoints but can't be honoured (endpoint
      # missing, or reversed), an unknown --random --source, or a --parallel
      # LANG the translation link cannot serve: a clean stderr message + exit 1.
      raise Thor::Error, e.message
    ensure
      catalog&.disconnect
    end

    desc "note URN [TEXT]", "Annotate any urn the corpus knows (owner notes → canonical/local-notes/)"
    long_desc <<~HELP, wrap: false
      The owner's annotation lane (architecture §16) — scholia of one's own,
      keyed by ANY urn the corpus knows: a document, a passage, a range, a
      dictionary entry. Notes are canonical memory: they live as YAML files
      under canonical/local-notes/<topic>.yml (append-only through the
      Nabu::NoteShelf gateway; hand-edits welcome — the file is the record),
      and the catalog only indexes them (urn_notes, rebuilt at every
      sync/rebuild). Once noted, the urn's renders carry the note: `show`
      prints an "owner note (topic, date): …" footer (a document also counts
      its passage-note children), `define` prints entry notes after the
      body, `links` shows an owner-notes lane, and the MCP surface serves
      notes by default (withheld wherever the target document is withheld).

      Modes:
        nabu note URN "TEXT"    scripted append (TEXT may be several words)
        nabu note URN           existing notes? show them; none? prompt for
                                one (TTY only — a pipe without TEXT refuses
                                honestly BEFORE any write)
        nabu note --list        enumerate notes (bounded --limit; --topic
                                narrows)

      The urn must RESOLVE in the catalog — a note on a typo'd urn would sit
      unreachable forever, so a miss is an error naming it. --force records
      a note on a not-yet-held urn deliberately (notes on planned material);
      such notes read "(dangling)" at render until the urn arrives.

      --topic groups notes however you like (default "#{Nabu::NoteShelf::DEFAULT_TOPIC}";
      one file per topic); --tags rides a comma-separated tag list.

      Examples:
        nabu note urn:nabu:ccmh:mar:mt "Collate against Jagić 1883 before citing."
        nabu note urn:nabu:dict:lsj:logos "Anchor for the John 1.1 witness comparison." --topic lexicon
        nabu note urn:nabu:planned:vaillant --force "Order the reprint." --tags acquisitions
        nabu note urn:nabu:ccmh:mar:mt         # read what you said
        nabu note --list --topic lexicon
    HELP
    option :topic, type: :string, banner: "NAME",
                   desc: "Topic file under canonical/local-notes/ (default #{Nabu::NoteShelf::DEFAULT_TOPIC}; " \
                         "with --list: narrow to this topic)"
    option :tags, type: :string, banner: "collation,ocs", desc: "Tags, comma-separated"
    option :force, type: :boolean, default: false,
                   desc: "Record a note on a not-yet-held urn (flagged dangling at render)"
    option :list, type: :boolean, default: false,
                  desc: "Enumerate notes (bounded; --topic narrows, --limit lifts)"
    option :rm, type: :string, banner: "ID",
                desc: "Remove one note by its id (nabu note --list shows ids)"
    option :limit, type: :numeric, default: Nabu::Query::Notes::DEFAULT_LIMIT,
                   desc: "With --list: how many notes (default #{Nabu::Query::Notes::DEFAULT_LIMIT})"
    def note(urn = nil, *text_parts)
      config = Nabu::Config.load
      return note_list(config, urn) if options[:list]
      return note_remove(config, urn) if options[:rm]

      urn = urn.to_s.strip
      raise Thor::Error, "note: give a urn (or --list)" if urn.empty?

      text = text_parts.join(" ").strip
      text = show_notes_or_prompt(config, urn) if text.empty?
      return if text.nil? # existing notes were shown — a read, not a write

      append_note(config, urn, text)
    rescue Nabu::Error => e
      raise Thor::Error, e.message
    end

    desc "align REF", "Render one citation across every witness of a registered work (the alignment hub)"
    long_desc <<~HELP, wrap: false
      Cross-source alignment (architecture §10): one citation of a registered
      WORK rendered in every witness the alignment registry
      (config/alignments.yml) names — the same verse in Greek, Latin, Gothic,
      Classical Armenian, and Old Church Slavonic, in one screen. Witnesses
      render in registry order, each with its language and its EFFECTIVE
      license class (the five NT witnesses are all nc — mind the labels when
      quoting).

      REF is a citation in the work's scheme — for the `nt` work,
      BOOK chapter.verse ("MARK 2.3"; quote it or let Thor join the words).
      Matching is forgiving: case, extra spaces, and chapter:verse colons all
      normalize ("mark 2:3" finds MARK 2.3). REF may also be a PASSAGE URN
      (pivot from a show/search hit): the sentence's verse is looked up and
      aligned across the other witnesses.

      Alignment is at citation grain over the treebanks' verse annotations,
      and sentence≠verse: a witness's sentence that spans a verse boundary is
      shown once, labeled with everything it covers. Honesty rules: a witness
      that simply lacks the verse (the Armenian sample holds only scattered
      chapters; Gothic is fragmentary) reads "not attested"; a registered
      witness whose source was never synced reads "not synced". Adding a
      witness (say, the ISWOC Old English Mark) is a registry entry, not code.

      --work names the work explicitly. Without it, a ref resolves through
      the index: when exactly one registered work attests it, that work is
      picked automatically (nt for "MARK 2.3", ot for "GEN 1.1"); a ref
      several works attest asks you to pick among the attesters.

      Examples:
        nabu align MARK 2.3                 # the paralytic, five ways
        nabu align "mark 2:3"               # same — refs normalize
        nabu align urn:nabu:proiel:marianus:36421
                                            # pivot: this OCS sentence, aligned
        nabu align MATT 5.25 --work nt      # explicit work id

      Use cases: read the Vorlage beside the translation (THE working method
      of comparative philology); check how each witness renders a
      construction; learn OCS/Gothic against the Greek you can already read.
    HELP
    option :work, type: :string, banner: "ID",
                  desc: "Alignment work id from config/alignments.yml (optional when only one is registered)"
    option :collate, type: :boolean, default: false,
                     desc: "Diff the witnesses instead of listing them: a raw-token apparatus per " \
                           "(language, script) group — base reading, then per-witness divergences only " \
                           "(cross-script witnesses rendered undiffed, honestly)"
    option :base, type: :string, banner: "LABEL",
                  desc: "With --collate: the base witness (label or document urn) each group diffs " \
                        "against (default: the first witness in registry order)"
    option :long, type: :boolean, default: false,
                  desc: "Lift the #{Nabu::Query::Align::MAX_REFS}-ref range ceiling and render every ref " \
                        "(compact clips a huge range by default); with --collate, also print each " \
                        "witness's full tokens instead of only its divergences"
    display_option
    def align(*ref_parts)
      ref = ref_parts.join(" ").strip
      raise Thor::Error, "align: give a citation ref (e.g. MARK 2.3) or a passage urn" if ref.empty?

      display_mode
      config = Nabu::Config.load
      catalog = open_catalog(config)
      fulltext = open_fulltext(config)
      raise Thor::Error, "no corpus — run nabu sync or nabu rebuild" unless catalog && fulltext

      registry = Nabu::AlignmentRegistry.load(config.alignments_path)
      if options[:collate]
        result = Nabu::Query::Collation.new(catalog: catalog, fulltext: fulltext, registry: registry)
                                       .run(ref, work: options[:work], base: options[:base], long: options[:long])
        print_collation(result, long: options[:long])
      else
        raise Thor::Error, "align: --base only applies with --collate" if options[:base]

        result = Nabu::Query::Align.new(catalog: catalog, fulltext: fulltext, registry: registry)
                                   .run(ref, work: options[:work], long: options[:long])
        print_align(result)
      end
      print_display_footer
    rescue Nabu::Query::Align::Error, Nabu::ValidationError => e
      raise Thor::Error, e.message
    ensure
      catalog&.disconnect
      fulltext&.disconnect
    end

    desc "define LEMMA", "Look up a lemma in the dictionary shelf (LSJ, L&S, Bosworth-Toller, MW, Wiktionary-OCS)"
    long_desc <<~HELP, wrap: false
      The dictionary shelf (architecture §11): look a dictionary form up in
      the lexica the corpus holds locally — LSJ (A Greek-English Lexicon,
      grc) and Lewis & Short (A Latin Dictionary, lat), both CC BY-SA from
      the Perseus Digital Library, Bosworth-Toller (An Anglo-Saxon
      Dictionary, ang; CC BY 4.0, LINDAT dump), Monier-Williams (A
      Sanskrit-English Dictionary, san; CC BY-NC-SA 3.0, Cologne CDSL —
      SLP1 transcoded to IAST, so aṃśa and amsa both reach the entry, and
      RV./BhP. citations resolve into the GRETIL shelf), and Wiktionary Old
      Church Slavonic (chu; kaikki.org extract, CC-BY-SA + GFDL —
      etymologies with their Proto-Slavic/PIE chains kept in the body).
      Entries print whole:
      headword, short gloss, then the full entry body as structured plain
      text with sense labels on their own lines (the MCP nabu_define surface
      is the bounded sibling).

      Matching folds like lemma search (conventions §9): diacritics optional
      (μηνις finds μῆνις), final sigma both ways (λόγος/λογοσ), Latin v/u j/i
      merged, Old English æ/þ/ð typeable in ASCII (aethele finds æðele,
      thing finds þing). Homographs are separate entries and all print (volo
      the verb, volo the flyer). LEMMA must be a dictionary form —
      `nabu search --lemma` finds the attestations, and its hits carry these
      glosses.

      Citations inside an entry stay as text; those that point at a work THIS
      corpus holds are additionally resolved to passage urns and listed at
      the end of the entry — `nabu show <urn>` opens the cited line. LSJ
      cites editions we may not hold (perseus-grc1 vs our grc2); resolution
      re-anchors to the in-catalog edition of the same work, preferring the
      original language over translations. Unresolvable citations (works not
      ingested, inscriptions, fragment collections) are honest misses, not
      links.

      The reconstruction shelves (P14-1, architecture §12) join in with the
      comparativist's asterisk: `define '*bogъ'` (quote the star — zsh globs
      a bare `*`) scopes to the Wiktionary Proto-Slavic/PIE/Proto-Germanic
      extracts (sla-pro/ine-pro/gem-pro), and a reconstruction entry also
      lists its descendant reflexes — with corpus attestation counts where
      the reflex is a gold lemma here. Proto headwords fold to ASCII (§9:
      ʰ→h, ʷ→w), so `define '*gʷʰew-'` and `define '*gwhew-'` reach the same
      root. `nabu etym` walks the same crosswalk from the attested side.

      --lang grc|lat|ang|san|chu|sla-pro|ine-pro|gem-pro restricts to one
      shelf; --limit caps the entries.

      Examples:
        nabu define μῆνις              # LSJ: wrath — with Il. 1.1 resolved
        nabu define λόγος              # the long one, whole
        nabu define virtus --lang lat  # Lewis & Short only
        nabu define aethele --lang ang # Bosworth-Toller: æðele, noble
        nabu define amsa --lang san    # Monier-Williams: aṃśa/aṃsa, RV. resolved into GRETIL
        nabu define богъ --lang chu    # Wiktionary-OCS: god, ex Proto-Slavic *bogъ
        nabu define '*bogъ'            # the reconstruction, with its reflexes (quote *)
    HELP
    option :lang, type: :string,
                  desc: "Restrict to one dictionary language (any language on the live " \
                        "shelf — the miss message lists what is held)"
    option :limit, type: :numeric, default: Nabu::Query::Define::DEFAULT_LIMIT,
                   desc: "Maximum entries printed (homographs are separate entries)"
    option :long, type: :boolean, default: false,
                  desc: "Expand every truncated reflex list in full, grouped by language " \
                        "(compact is the default; MCP nabu_define stays bounded)"
    option :lect, type: :string, banner: "LECT-ID",
                  desc: "Restrict to shelves whose (language, source) RESOLUTION is this lect id " \
                        "or under it (P59-3; per-source overrides included — derom's la-vul " \
                        "scopes under roa, never lat); errors if the nabu-lects module is not synced"
    def define(*lemma_parts)
      lemma = lemma_parts.join(" ").strip
      raise Thor::Error, "define: give a lemma (e.g. λόγος, virtus)" if lemma.empty?

      config = Nabu::Config.load
      catalog = open_catalog(config)
      raise Thor::Error, "no corpus — run nabu sync or nabu rebuild" unless catalog
      unless catalog.table_exists?(:dictionary_entries)
        raise Thor::Error, "no dictionary shelf in this catalog yet — run nabu sync lexica " \
                           "(or nabu rebuild after one)"
      end
      shelf_langs = catalog[:dictionaries].distinct.order(:language).select_map(:language)
      @shelf_summary = "the shelf holds #{catalog[:dictionaries].count} dictionaries " \
                       "(#{shelf_langs.join(', ')})"
      if options[:lang] && !Nabu::Languages.code_variants(options[:lang]).intersect?(shelf_langs)
        raise Thor::Error, "define: --lang must be a language on the live shelf " \
                           "(#{shelf_langs.join(', ')})"
      end

      fulltext = open_fulltext(config)
      ledger = open_ledger(config)
      @languages = Nabu::Languages.new(catalog: catalog, ledger: ledger)
      # Fetch every matching shelf, cap at render (P34-r2): with the CJK
      # shelves live a Han headword matches 6+ dictionaries, and the old
      # fetch-time cap hid the tail silently (the gate found `define 棄`
      # missing tls-words). --long lifts the cap; compact announces it.
      results = Nabu::Query::Define.new(catalog: catalog, fulltext: fulltext)
                                   .run(lemma, lang: options[:lang], limit: nil, lect: options[:lect])
      shown = options[:long] ? results : results.first(options[:limit].to_i)
      print_define_results(lemma, shown, catalog: catalog)
      if (hidden = results.size - shown.size).positive?
        say format("… %<n>d more %<verb>s (--long shows all; --limit raises the cap)",
                   n: hidden, verb: hidden == 1 ? "entry matches" : "entries match")
      end
    ensure
      catalog&.disconnect
      fulltext&.disconnect
      ledger&.disconnect
    end

    desc "etym LEMMA", "Walk an attested lemma to its reconstructions and cognates (architecture §12)"
    long_desc <<~HELP, wrap: false
      The comparativist's walk: from an ATTESTED lemma (богъ, guþ, deus) to
      every reconstruction whose descendants name it — the Wiktionary proto
      shelves (Proto-Slavic, Proto-Indo-European, Proto-Germanic, and
      (P17-3) Proto-Balto-Slavic, Proto-West Germanic, Proto-Italic,
      Proto-Indo-Iranian; kaikki.org extracts, CC-BY-SA + GFDL) and every
      other shelf carrying reflex edges (StarLing bases, MW comparanda —
      the miss message lists what is live) — then UP the ancestor chain, one indent
      per shelf hop (each shelf enters a walk once, so the chain is bounded
      and cycle-safe): прьстъ reaches *pьrstъ ← *pírštan ← *per- end to
      end. A loan-flagged edge labels its arrow "←(loan)", and a
      loan-flagged cognate reads "(loan)" (the P17-3 borrowed flag; rows
      not yet reparsed carry no label — honest unknown, not a claim).

      Every cognate reflex that is a gold lemma in this catalog carries its
      attestation count (searchable via `nabu search --lemma`); the rest
      are listed honestly as "not attested here". Romanization bridges
      scripts — guþ reaches *gudą through Gothic 𐌲𐌿𐌸 — and the folding is
      the conventions §9 contract (diacritics optional).

      An unstarred lemma that names no descendant FALLS BACK to a
      reconstruction-headword lookup, so the proto form itself resolves —
      typed with its phonetic superscripts (`etym bʰewgʰ`) or in pure ASCII
      (`etym bhewgh`, the §9 fold ʰ→h/ʷ→w), root hyphen optional. A quoted
      leading asterisk looks a reconstruction up directly (`etym '*bogъ'`,
      like `define '*bogъ'`) — quote the star, zsh globs a bare `*`; the
      bare-form fallback makes it mostly unnecessary. --lang scopes the
      attested match; --limit caps the entries. The MCP sibling is nabu_etym
      (bounded); this CLI prints everything.

      A lemma with NO crosswalk path at all falls back once more (P24-2) —
      to the same lookup `nabu define` runs: a prose etymological article
      (Vasmer's Russian dictionary carries no reflex edges) still answers,
      rendered in the define format under an honest "no reconstruction
      path in the crosswalk" header. A genuine total miss enumerates the
      crosswalk's live shelves, derived from the catalog.

      Examples:
        nabu etym богъ --lang chu     # Zographensis god → *bogъ → *bʰeh₂g-
        nabu etym guþ --lang got      # Gothic → *gudą → *ǵʰutós
        nabu etym bhewgh              # bare ASCII proto form → *bʰewgʰ-
        nabu etym '*kaisaraz'         # direct lookup (quoted — zsh globs *)
    HELP
    option :lang, type: :string, banner: "chu|orv|got|grc|lat|…",
                  desc: "Scope the attested-lemma match to one language"
    option :limit, type: :numeric, default: Nabu::Query::Etym::DEFAULT_LIMIT,
                   desc: "Maximum reconstruction entries printed"
    option :long, type: :boolean, default: false,
                  desc: "Expand every truncated cognate list in full, grouped by language " \
                        "(compact is the default; MCP nabu_etym stays bounded)"
    def etym(*lemma_parts)
      lemma = lemma_parts.join(" ").strip
      raise Thor::Error, "etym: give a lemma (e.g. богъ, guþ) or *reconstruction" if lemma.empty?

      config = Nabu::Config.load
      catalog = open_catalog(config)
      raise Thor::Error, "no corpus — run nabu sync or nabu rebuild" unless catalog
      unless catalog.table_exists?(:dictionary_reflexes)
        raise Thor::Error, "no reconstruction shelf in this catalog yet — run " \
                           "nabu sync wiktionary-recon (or nabu rebuild after one)"
      end

      fulltext = open_fulltext(config)
      ledger = open_ledger(config)
      @languages = Nabu::Languages.new(catalog: catalog, ledger: ledger)
      @lects = Nabu::Lects.load_default(config: config)
      query = Nabu::Query::Etym.new(catalog: catalog, fulltext: fulltext)
      results = query.run(lemma, lang: options[:lang], limit: options[:limit].to_i)
      if results.empty?
        # P24-2 coordination (owner incident 2026-07-16: define found the
        # Vasmer сигать article, etym missed flat): on a crosswalk miss,
        # fall back to the SAME Query::Define lookup the define command
        # runs — one execution path, rendered in the define house format.
        # Fallback fires ONLY on a miss: etym's primary contract stays the
        # walk, hits are never mixed.
        entries = Nabu::Query::Define.new(catalog: catalog, fulltext: fulltext)
                                     .run(lemma, lang: options[:lang], limit: options[:limit].to_i)
        print_etym_fallback(lemma, entries, shelves: query.crosswalk_shelves)
      else
        print_etym_results(results)
      end
    ensure
      catalog&.disconnect
      fulltext&.disconnect
      ledger&.disconnect
    end

    desc "char CHAR", "The character desk card: structure, readings, and the diachronic column"
    long_desc <<~HELP, wrap: false
      The character card (P37-4): one Han character composed from every shelf
      the library holds — the join no single dictionary site offers. It
      matches Jisho's synchronic completeness field-for-field where a shelf
      backs it, and exceeds it diachronically with a column no online
      dictionary carries. The binding rule: a field whose shelf can't back
      THIS character is ABSENT, never rendered "—".

      Sections, in render order (each names its backing shelf; absent
      sections are silently omitted):

        header        glyph · total strokes · KangXi radical number+name
                      (Unihan kRSUnicode/kTotalStrokes)
        decomposition the IDS structure + its components, each with the
                      follow-up commands to walk into it (BabelStone IDS)
        components    the flat component index Jisho searches (KRADFILE)
        variants      trad/simp/semantic/z-variant forms (Unihan)
        readings ja   on/kun/nanori + meanings (KANJIDIC2)
        readings      Mandarin/Korean/Vietnamese + the Unihan kJapanese layer
        pedagogy      Jōyō grade · JLPT · newspaper frequency (KANJIDIC2)
        desk-ref      the reference codes, zero suppressed — Unicode always,
                      four-corner/SKIP/JIS/dic numbers where KANJIDIC2 holds
                      them
        — the diachronic column (where nabu exceeds Jisho) —
        Old Chinese   Baxter-Sagart reconstruction + gloss
        Middle Chinese Qieyun reading, 反切, 音韻地位 (tshet-uinh)
        early Japan   positions in the Heian hanzi dictionaries (HDIC)
        TLS           sense-level concepts + classical attestation counts
        corpus        attestation frequency across the held corpora
        search        the printed `search CHAR*`-family follow-ups

      Give exactly ONE character — the card's grain is a single glyph. The
      component-search siblings are `nabu search --radical N`,
      `--strokes A-B` and `--char-component C`.

      Examples:
        nabu char 棄       # reject/abandon — radical 75 木, the whole card
        nabu char 木       # the component itself; its containment neighbours
    HELP
    def char(glyph = nil)
      glyph = glyph.to_s.strip
      raise Thor::Error, "char: give a character (e.g. nabu char 棄)" if glyph.empty?
      if glyph.each_char.to_a.size > 1
        raise Thor::Error, "char: the card's grain is a single character — give one glyph " \
                           "(#{glyph}); search --char-component #{glyph.each_char.first} finds " \
                           "characters that contain one"
      end

      config = Nabu::Config.load
      catalog = open_catalog(config)
      raise Thor::Error, "no corpus — run nabu sync or nabu rebuild" unless catalog
      unless catalog.table_exists?(:dictionary_entries)
        raise Thor::Error, "no dictionary shelf in this catalog yet — run nabu sync unihan " \
                           "(or nabu rebuild after one)"
      end

      fulltext = open_fulltext(config)
      card = Nabu::Query::Char.new(catalog: catalog, fulltext: fulltext).run(glyph)
      print_char_card(card)
    ensure
      catalog&.disconnect
      fulltext&.disconnect
    end

    desc "signs URN|TEXT", "Sign-by-sign reading of ATF transliteration through the Oracc Sign List"
    long_desc <<~HELP, wrap: false
      The cuneiform sign desk (P53-2): ATF transliteration resolved token by
      token through the Oracc Sign List (the osl module, `nabu sync osl`)
      into sign identities — value → sign name → Unicode codepoint(s)/glyph.
      The sign list adds IDENTITY, not curriculum: what each spelled value
      is, never what to make of it.

      Input is EITHER a passage/document urn out of the ATF corpora
      (cdli/oracc/ebl/etcsl shelves — the catalog is opened read-only,
      language taken from the row) OR raw ATF transliteration text
      (language via --lang; no catalog needed). C-ATF ASCII folds apply
      (sz→š, s,→ṣ, t,→ṭ, '→ʾ, u2→u₂); the ETCSL romanization (c→š, j→ŋ)
      folds automatically for etcsl urns and under --dialect etcsl for raw
      text.

      Every token carries one honest status: deterministic · qualified
      (valueₓ(SIGN) — the explicit sign resolved) · ambiguous (ALL candidate
      signs listed, never one silently) · no-codepoint (sign resolved,
      honestly unencoded upstream) · broken (x, [...]) · unknown (not in the
      OSL — said plainly). Determinatives ({d}, {gesz}) are unbraced and
      marked det. Absent data is ABSENT, never "—".

      --json emits the frozen machine contract (one object: mode/urn/
      language/dialect/source envelope, per-line token records with
      input_value · status · sign_name · codepoints[] · candidates[] ·
      language_qualifier) — the same shape the MCP nabu_signs tool serves;
      downstream consumers (Edubba reading panels) script against it.

      Examples:
        nabu signs 'lugal-e {d}en-lil2-ra'      # raw C-ATF, folded and resolved
        nabu signs --dialect etcsl 'cag4-ta'    # ETCSL romanization
        nabu signs urn:nabu:cdli:p469841        # every line of the tablet
        nabu signs --json 'szesz' | jq .        # the frozen contract
    HELP
    option :lang, type: :string, banner: "CODE",
                  desc: "Language filter for %lang-qualified sign readings (urn mode " \
                        "defaults to the passage's language)"
    option :dialect, type: :string, banner: "NAME",
                     desc: "Transliteration dialect: etcsl (c→š, j→ŋ; auto for etcsl urns)"
    option :json, type: :boolean, default: false,
                  desc: "Emit the frozen machine-readable contract instead of columns"
    def signs(*input)
      raw = input.join(" ").strip
      if raw.empty?
        raise Thor::Error, "signs: give a passage urn or raw ATF transliteration " \
                           "(e.g. nabu signs 'lugal-e {d}en-lil2-ra')"
      end

      config = Nabu::Config.load
      list = Nabu::SignList.load_default(config: config)
      if list.nil?
        raise Thor::Error, "signs: no sign list on this box yet — run `nabu sync osl` " \
                           "(the Oracc Sign List module), then retry"
      end

      dialect = signs_dialect(options[:dialect])
      catalog = nil
      if raw.start_with?("urn:")
        catalog = open_catalog(config)
        raise Thor::Error, "signs: no corpus — run nabu sync or nabu rebuild" unless catalog

        result = signs_urn_result(raw, list: list, catalog: catalog, dialect: dialect)
      else
        result = Nabu::Query::Signs.new(sign_list: list)
                                   .run_text(raw, language: options[:lang], dialect: dialect || :catf)
      end

      if options[:json]
        say JSON.generate(Nabu::Query::Signs.json_payload(result))
      else
        print_signs(result)
      end
    ensure
      catalog&.disconnect
    end

    desc "language [CODE]", "The language-code desk reference: name, family, context, holdings"
    long_desc <<~HELP, wrap: false
      Explains any language code the library surfaces — the corpus tags
      (chu, orv, san-Latn) and the Wiktionary etymology codes the etym
      cognate lists are full of (gkm, zle-ort, zlw-opl…). The card merges
      three layers:

      - NAME, derived from the held kaikki extracts: every descendants node
        carries the human name next to its code, censused into the catalog
        with the dictionary shelves (a catalog predating that census shows
        names only for curated codes until the next rebuild or parse-only
        shelf resync).
      - CONTEXT, curated in the canonical/local-language dossier shelf
        (P19-1: one Markdown file per code — edit it in any editor, then
        `nabu sync local-language` re-derives): period, family, what the
        library holds — every held language, plus family-level entries for
        the etymology tail (zle-* East Slavic stages, gkm Medieval Greek…).
        A code without its own dossier falls back to its family; without
        either it says so honestly. (Libraries that predate the dossier
        migration keep reading the ledger's language notes unchanged.)
      - RELEVANCE, live from the db: documents/passages, gold-lemma rows,
        dictionary shelves, reconstruction-crosswalk edges, and the related
        research axes (the desks whose member sources hold the code, in
        ratified order — nabu axis NAME for any desk card). Zero fields
        are suppressed.

      --long adds where-it-appears detail: per-source document counts and
      the upstream-code split of the etymology edges (chu's edges arrive
      as Wiktionary's "cu"). --list shows the held languages only — the
      ~800-code etymology tail is what `language CODE` is for.
      --export-dossiers is THE one-shot canonical-memory migration
      (owner-fired): it writes the ledger's language notes out as dossier
      files, absence-filling only, idempotent; --dry-run previews it.

      Examples:
        nabu language zle-ort      # the code from an etym cognate list
        nabu language chu --long   # a held language, full holdings
        nabu language --list       # every held language
        nabu language --export-dossiers --dry-run   # preview the migration
    HELP
    option :list, type: :boolean, default: false,
                  desc: "List the held languages (corpus documents, gold lemmas, or a shelf)"
    option :"export-dossiers", type: :boolean, default: false,
                               desc: "One-shot migration: write ledger language notes out as " \
                                     "canonical/local-language dossiers (idempotent, absence-filling)"
    option :"dry-run", type: :boolean, default: false,
                       desc: "With --export-dossiers: report what would be written, touch nothing"
    option :long, type: :boolean, default: false,
                  desc: "Add per-source document counts and the upstream-code edge split"
    def language(code = nil)
      config = Nabu::Config.load
      return export_language_dossiers(config) if options[:"export-dossiers"]

      catalog = open_catalog(config)
      fulltext = open_fulltext(config)
      ledger = open_ledger(config)
      languages = Nabu::Languages.new(catalog: catalog, ledger: ledger)
      info = catalog && Nabu::Query::LanguageInfo.new(catalog: catalog, fulltext: fulltext)
      if options[:list]
        print_language_list(languages, info)
      else
        term = code.to_s.strip
        raise Thor::Error, "language: give a code (chu, gkm, zle-ort…) or --list" if term.empty?

        registry = Nabu::SourceRegistry.load(config.sources_path)
        lects = Nabu::Lects.load_default(config: config)
        print_language_card(term, languages, info, registry: registry, lects: lects)
      end
    ensure
      catalog&.disconnect
      fulltext&.disconnect
      ledger&.disconnect
    end

    desc "place NAME|ID", "The place desk card: Pleiades gazetteer facts + the library's holdings there"
    long_desc <<~HELP, wrap: false
      The third dimension of the library (after language and time): one
      ancient place, resolved through the local Pleiades gazetteer dump,
      plus every source's holdings AT that place — counted over the
      Pleiades ids the epigraphic parsers capture from their upstream
      headers (isicily, edh, iip, itant). Only upstream-asserted ids ever
      count: no fuzzy geo-matching anywhere in the pipeline.

      Input is a Pleiades NUMERIC id (or a pleiades.stoa.org/places URL),
      or an EXACT place title, matched case-insensitively against the dump
      — "Segesta" works, "Seges" does not (exact only, by design). Homonym
      titles print one card each.

      The card: title, Pleiades id, place types, the attested time-period
      span, and the representative point (lat, lon — display only; no maps,
      no coordinate math). Then the holdings line, per source, descending.

      An honest labelled tail follows when id-less documents mention the
      name in their captured findspot TEXT (exact substring, case-
      insensitive): "unlinked findspot mentions" — never merged into the
      id-matched counts.

      The gazetteer dump is the pleiades module's canonical asset
      (`nabu sync pleiades`, ~42k places). Since P45-6 the sync also
      derives a place index into the catalog, so lookups here read it
      instantly; the ~3 s in-memory dump load is paid only while that
      index is not yet derived (re-sync or rebuild derives it). Without
      the dump on disk, a numeric id still counts holdings (the catalog
      side needs no dump); a name lookup is refused with the sync hint.

      Examples:
        nabu place Segesta          # exact title → card + holdings
        nabu place 462281           # Lilybaeum by Pleiades id
        nabu place https://pleiades.stoa.org/places/462281   # same
    HELP
    def place(*query_parts)
      query = query_parts.join(" ").strip
      raise Thor::Error, "place: give a Pleiades numeric id or an exact place title" if query.empty?

      config = Nabu::Config.load
      catalog = open_catalog(config)
      raise Thor::Error, "no catalog — run nabu sync or nabu rebuild" unless catalog

      resolver = Nabu::Pleiades.load_default(config: config, catalog: catalog)
      result = Nabu::Query::Place.new(catalog: catalog, pleiades: resolver).run(query)
      print_place(result)
    rescue Nabu::Query::Place::Error => e
      raise Thor::Error, e.message
    ensure
      catalog&.disconnect
    end

    desc "axis [NAME]", "The research-axis desk card: persona, members, holdings, gold coverage (config/axes.yml)"
    long_desc <<~HELP, wrap: false
      The research axes are the owner's desks — TAGS over the source list
      (config/axes.yml), a source appearing under every desk it serves
      (dual-tagging is the point, D35). This is their reference card, the
      `nabu language` mold pointed at a whole desk instead of a code.

      Bare `nabu axis` lists every desk in ratified (file) order — name and
      persona, one line each. `nabu axis NAME` prints the full card:

      - PERSONA, the hat's one-liner, verbatim from config/axes.yml, and the
        membership rationale (desc) beneath it.
      - MEMBERS, every source the desk tags, each with its enablement (on/off,
        from the registry — the authoritative flip) and its live holdings
        (documents/passages, dictionary entries, dossiers, languages, license
        mix — the same census fragments `nabu list` prints). Zero fields are
        suppressed; a member holding nothing yet says so.
      - LANGUAGES, the codes the member sources hold, one merged doc-or-entry
        count each, holdings descending — the counts keep a multilingual
        pack's spillover honest (kat 3 beside hbo 40,000 explains itself).
        Compact shows ten codes with an honest "… and N more"; --long lifts.
      - GOLD COVERAGE, the aggregate gold-lemma rows across the desk's held
        languages (nabu search --lemma) — honest zero when none are gold.
      - the shipped affordances: `nabu list --axis NAME`, `nabu sync NAME`.

      An unknown axis is refused naming the known set (the slug/axis collision
      guarantee makes a bare name unambiguous). No corpus yet is not an error:
      the persona and membership still print, holdings say "no database".

      Examples:
        nabu axis                  # every desk, one persona line each
        nabu axis celtic           # the Celticist's desk, full card
        nabu axis biblical --long  # the scripture hat, every language code
    HELP
    option :long, type: :boolean, default: false,
                  desc: "Lift the languages-line cap (compact shows ten codes)"
    def axis(name = nil)
      config = Nabu::Config.load
      registry = Nabu::SourceRegistry.load(config.sources_path)
      axes = registry.axes
      raise Thor::Error, "axis: no research axes are defined (config/axes.yml)" if axes.empty?

      catalog = open_catalog(config)
      fulltext = catalog ? open_fulltext(config) : nil
      name = name.to_s.strip
      if name.empty?
        print_axis_list(axes)
      else
        definition = axes[name] ||
                     raise(Thor::Error, "axis: unknown axis #{name.inspect} — known axes: #{axes.names.join(', ')}")
        census = catalog ? Nabu::Query::List.new(catalog: catalog).census : nil
        info = catalog ? Nabu::Query::LanguageInfo.new(catalog: catalog, fulltext: fulltext) : nil
        print_axis_card(definition, registry: registry, census: census, info: info)
      end
    ensure
      catalog&.disconnect
      fulltext&.disconnect
    end

    # The one pointer line every deprecated `focus` alias prints (P44-r3b).
    FOCUS_POINTER = "focus is now enable/disable; this alias goes away next release"

    desc "enable AXIS|SOURCE...", "Enable sources or axes on this box (the local enablement config)"
    long_desc <<~HELP, wrap: false
      Add axes and/or sources to config/profile.yml — this box's ENABLEMENT
      CONFIG (P44-r3b). The entries govern BOTH what `nabu sync` / `sync --all`
      acquires AND the default row set of `nabu list` / `status` / `health` and
      the MCP nabu_status sources array. `nabu search` / `show` / `export` stay
      library-wide (enablement scopes acquisition + visibility, never reading).

      enable is ADDITIVE: it APPENDS (never trims). An AXIS is recorded by name
      (it expands to the axis's PUBLIC members); a SOURCE by slug. Enabling an
      axis never implicitly enables its grant-gated (blocked) members — each is
      skipped with the on-ramp line, so a private research source is only ever
      enabled by naming it. Enabling a blocked source BY SLUG runs its grant
      terms and demands a typed `granted` (or --grant-acknowledged) once,
      recorded in the ledger; a later enable skips the prompt.

      Examples:
        nabu enable germanic          # the germanic desk's public sources
        nabu enable sblgnt proiel     # two sources by slug
        nabu enable titus-avestan     # a grant-gated source: shows terms, asks
    HELP
    option :grant_acknowledged, type: :boolean, default: false,
                                desc: "Acknowledge a grant-gated source's terms non-interactively " \
                                      "(scripted use); records the acknowledgment, then enables."
    def enable(*names)
      config = Nabu::Config.load
      registry = Nabu::SourceRegistry.load(config.sources_path)
      names = names.map(&:strip).reject(&:empty?)
      raise Thor::Error, "enable: name at least one axis or source to enable" if names.empty?

      Nabu::Focus.validate_names!(names, registry)
      ledger = open_or_create_ledger(config)
      catalog = open_catalog(config) # read-only: only the migration detector needs it
      run_enable(config, registry, names, ledger: ledger, catalog: catalog)
    rescue Nabu::Focus::UnknownName => e
      raise Thor::Error, "enable: #{e.message}"
    rescue Nabu::Error => e
      raise Thor::Error, e.message
    ensure
      catalog&.disconnect
      ledger&.disconnect
    end

    desc "disable AXIS|SOURCE...", "Disable sources or axes on this box (synced data stays)"
    long_desc <<~HELP, wrap: false
      Remove axes and/or sources from config/profile.yml (the enablement
      config). The synced data STAYS on disk — disabling only drops the entries
      from the enabled set, so `sync`/`list`/`status` stop touching/showing them
      by default (--all still reveals them). Withdrawal of data is a different,
      existing concept. Removing a name the registry no longer knows (drift
      after a hand-edit) is fine — disable never validates, so it also cleans up.

      Examples:
        nabu disable germanic
        nabu disable proiel
    HELP
    def disable(*names)
      config = Nabu::Config.load
      registry = Nabu::SourceRegistry.load(config.sources_path)
      names = names.map(&:strip).reject(&:empty?)
      raise Thor::Error, "disable: name at least one axis or source to disable" if names.empty?

      catalog = open_catalog(config)
      run_disable(config, registry, names, catalog: catalog)
    ensure
      catalog&.disconnect
    end

    desc "focus [only|add|drop|clear] [NAMES…]", "DEPRECATED — alias for enable/disable (removed next release)"
    long_desc <<~HELP, wrap: false
      DEPRECATED (P44-r3b): the focus profile was promoted to the local
      enablement config, and the verbs moved to `nabu enable` / `nabu disable`.
      Each focus subcommand still works for one release as an alias, printing a
      pointer to its replacement:

        nabu focus only <names…>  →  clear, then nabu enable <names…>
        nabu focus add  <names…>  →  nabu enable  <names…>
        nabu focus drop <names…>  →  nabu disable <names…>
        nabu focus clear          →  enable nothing (empty enabled set)
        nabu focus                →  show the current enabled set
    HELP
    def focus(action = nil, *names)
      config = Nabu::Config.load
      registry = Nabu::SourceRegistry.load(config.sources_path)
      names = names.map(&:strip).reject(&:empty?)
      say FOCUS_POINTER
      ledger = open_or_create_ledger(config)
      catalog = open_catalog(config) # read-only: only the migration detector needs it
      case action.to_s.strip
      when "" then show_enablement(effective_profile(config, registry, catalog: catalog), registry)
      when "only"
        Nabu::Focus.validate_names!(names, registry)
        Nabu::Profile.new([]).save(config.profile_path) # clear first (only = clear + enable)
        run_enable(config, registry, names, ledger: ledger, catalog: catalog)
      when "add"
        Nabu::Focus.validate_names!(names, registry)
        run_enable(config, registry, names, ledger: ledger, catalog: catalog)
      when "drop" then run_disable(config, registry, names, catalog: catalog)
      when "clear"
        Nabu::Profile.new([]).save(config.profile_path)
        say "cleared — no sources enabled (nabu enable <axis|source> to add)"
      else
        raise Thor::Error, "focus: unknown action #{action.inspect} — use only, add, drop, clear " \
                           "(or the new nabu enable/disable)"
      end
    rescue Nabu::Focus::UnknownName => e
      raise Thor::Error, "focus: #{e.message}"
    ensure
      catalog&.disconnect
      ledger&.disconnect
    end

    desc "cognates TARGET", "Verses where aligned witnesses use reflexes of the same root (architecture §12)"
    long_desc <<~HELP, wrap: false
      The comparativist's join (P15-3): verses of a registered alignment work
      where witnesses in TWO OR MORE languages use reflexes of the SAME
      reconstruction root — the alignment hub (nabu align) crossed with the
      Wiktionary reconstruction crosswalk (nabu etym). Gothic salt ~ OCS соль
      meet at PIE *sḗh₂l in the salt saying (LUKE 14.34); hlaifs ~ хлѣбъ at
      *hlaibaz in "he who eats my bread" (JOHN 13.18).

      TARGET is a registered work id (nt, ot, psalms — batches the whole
      work), a verse ref (LUKE 14.34), a chapter (LUKE 14), or a book (LUKE).
      Each hit names the root with its SHELF — and the shelf is part of the
      answer: a Slavic witness meeting a Germanic witness at a gem-pro entry
      (*hlaibaz, *kaisaraz) is very possibly a BORROWING, not common descent;
      ine-pro meets are the inheritance signal. Since P17-3 a witness whose
      descent from the root the crosswalk FLAGS as a loan reads "(loan)"
      (chu хлѣбъ (loan) ~ got hlaifs at *hlaibaz — the flag ORs along the
      closure path, so a loan on a proto-to-proto edge still fires); the
      shelf heuristic remains the caption for unflagged edges — upstream
      flags are high-precision, low-recall — and rows predating the flag
      reparse carry no label (honest unknown).

      Corpus-common words are suppressed by default (a lemma in ≥ 10% of its
      language's gold passages, absolute floor 50 — ὁ, jah, и would otherwise
      flood every verse); --all shows them, and the header counts what fell.
      Frequency is a coarse proxy: богъ (4.9% of OCS) and нъ "but" (4.7%) are
      inseparable by df, so some common words survive — read the hits.

      Recall is bounded by Wiktionary descendants coverage (roughly a third
      of Gothic and a fifth of OCS gold lemma types reach any proto entry)
      and by gold lemmatization (~10% of the corpus): absence of a hit is
      absence of evidence, not evidence of unrelatedness.

      --langs got,chu restricts the comparison to the named languages (at
      least two); --work picks the alignment work when the ref is ambiguous;
      --long lifts the #{Nabu::Query::Cognates::MAX_GROUPS}-hit compact cap
      and expands gloss/dictionary/document detail per hit.

      BATCH MODE (P16-2, the links journal): `cognates --batch WORK` maps the
      whole work once and PERSISTS kind=cognate edges between the aligned
      witness passages that meet at a reconstruction root — one edge per
      cross-language passage pair, its detail carrying the meet (ref · root
      [SHELF] — the shelf rides every edge because a gem-pro meet for a
      Slavic witness reads as a borrowing), its score the distinct-root
      count. WORK must be a registered work id (per-ref runs stay
      interactive). Common-word suppression stays on (--all lifts it, and
      the run records that); a rerun of the same work supersedes
      (idempotent); --db writes the journal elsewhere. Interactive output is
      never persisted.

      Examples:
        nabu cognates "LUKE 14.34"            # the salt saying, all languages
        nabu cognates nt --langs got,chu      # the whole NT, Gothic × OCS
        nabu cognates "JOHN 13" --langs got,chu,grc
        nabu cognates nt --langs got,chu --all  # keep the common-word matches
        nabu cognates --batch nt --langs got,chu  # persist the Gothic × OCS cognate map
    HELP
    option :work, type: :string,
                  desc: "Alignment work id (optional when the target decides it)"
    option :langs, type: :string, banner: "got,chu",
                   desc: "Restrict the comparison to these languages (comma-joined, at least two)"
    option :all, type: :boolean, default: false,
                 desc: "Show the common-word matches the default suppresses"
    option :long, type: :boolean, default: false,
                  desc: "Render every hit (compact caps at #{Nabu::Query::Cognates::MAX_GROUPS}) " \
                        "and expand gloss/dictionary/document detail"
    option :batch, type: :boolean, default: false,
                   desc: "Map the whole WORK once and persist kind=cognate edges to the links journal"
    option :db, type: :string, banner: "PATH",
                desc: "With --batch: write the links journal at PATH instead of db/links.sqlite3"
    option :lect, type: :string, banner: "LECT-ID",
                  desc: "Scope witnesses OF THIS LECT'S ANCHOR LANGUAGE to the lect (P59-3: " \
                        "--lect grc:koi keeps cognate sets whose Greek witness is Koine; " \
                        "other-language witnesses pass untouched); errors if the nabu-lects " \
                        "module is not synced"
    display_option
    def cognates(*target_parts)
      target = target_parts.join(" ").strip
      display_mode
      return batch_cognates(target) if options[:batch]

      if options[:db]
        raise Thor::Error, "cognates: --db only applies with --batch " \
                           "(interactive results are never persisted)"
      end
      raise Thor::Error, "cognates: give a work id (nt) or a citation ref (e.g. LUKE 14.34)" if target.empty?

      config = Nabu::Config.load
      catalog = open_catalog(config)
      fulltext = open_fulltext(config)
      raise Thor::Error, "no corpus — run nabu sync or nabu rebuild" unless catalog && fulltext

      registry = Nabu::AlignmentRegistry.load(config.alignments_path)
      result = Nabu::Query::Cognates.new(catalog: catalog, fulltext: fulltext, registry: registry)
                                    .run(target, work: options[:work], langs: parse_langs(options[:langs]),
                                                 all: options[:all], long: options[:long],
                                                 lect: options[:lect])
      print_cognates(result)
      print_display_footer
    rescue Nabu::Query::Cognates::Error, Nabu::ValidationError => e
      raise Thor::Error, e.message
    ensure
      catalog&.disconnect
      fulltext&.disconnect
    end

    desc "vocab URN", "Lemma-frequency profile of a document/range vs the corpus (gold shelves only)"
    long_desc <<~HELP, wrap: false
      Profile the gold-lemma vocabulary of one document, a citation range, or a
      single passage (P14-3, improvements §1.7): total tokens carrying a gold
      lemma, how many distinct lemmas, the most DISTINCTIVE vocabulary, and the
      in-document hapax legomena (lemmas attested exactly once).

      "Distinctive" means over-represented HERE versus the whole corpus, ranked
      by a log-odds-ratio with an informative Dirichlet prior (Monroe et al.
      2008) — the z-score damps rare-lemma noise a plain frequency ratio would
      let blow up, so the list is the text's real subject vocabulary, not its
      accidental singletons (those get their own hapax line). Each row shows the
      lemma's document token count and its corpus passage-frequency.

      Gold lemmas exist only for the treebank shelves (PROIEL, TOROT, ISWOC, the
      UD treebanks) and the ORACC cuneiform layer — about 8% of the corpus. A
      document without gold lemmas (Perseus, First1K, the papyri, ASPR poetry)
      is not an error: it says so plainly and lists the gold-bearing languages
      so you can profile something that works. --limit caps both the distinctive
      list and the hapax spellings printed (default #{Nabu::Query::Vocab::DEFAULT_LIMIT}).

      DIACHRONY (--by-century): instead of one document's lemmas, plot the DATED
      corpus across centuries (P15-2, the timeline). Bare, it is the shape
      of your dated holdings — one row per century (BCE/CE), the document count.
      With a text QUERY it becomes "plot this word across centuries": how many
      dated documents attest the term in each century. Composes with --lang,
      --license, --from/--to/--century, and --place; counts are per DOCUMENT and
      bucketed by EARLIEST year (a ranged papyrus lands in its first century), so
      the footer names how many span more than one century. Most of the corpus is
      undated (papyri via HGV, Slovene goo300k/IMP carry dates); undated
      documents are simply absent here, never an error.

      Examples:
        nabu vocab urn:nabu:proiel:caes-gal          # Caesar's Gallic War
        nabu vocab urn:nabu:proiel:cic-off --limit 30
        nabu vocab urn:nabu:proiel:hdt:1.1-1.100     # a citation range
        nabu vocab --by-century                      # the dated corpus over time
        nabu vocab --by-century στρατηγ --lang grc   # a word plotted across centuries
        nabu vocab --by-century --place oxyrhynch%   # Oxyrhynchus, century by century
    HELP
    option :limit, type: :numeric, default: Nabu::Query::Vocab::DEFAULT_LIMIT,
                   desc: "Cap the distinctive list and hapax spellings printed"
    option :long, type: :boolean, default: false,
                  desc: "List every hapax legomenon (and every gold-bearing language) in full, " \
                        "escaping the --limit display cap (the distinctive ranking stays top-N)"
    option :by_century, type: :boolean, default: false,
                        desc: "Diachronic mode: bucket the DATED corpus (or a text query) by century"
    option :lang, type: :string, desc: "With --by-century: restrict to a language (grc, lat, …)"
    option :license, type: :string, desc: "With --by-century: restrict to an exact license class"
    option :from, type: :numeric, banner: "YEAR", desc: "With --by-century: earliest year (negative = BCE)"
    option :to, type: :numeric, banner: "YEAR", desc: "With --by-century: latest year"
    option :century, type: :numeric, banner: "N", desc: "With --by-century: one century's window (6, -2)"
    option :place, type: :string, banner: "PATTERN", desc: "With --by-century: provenance place LIKE filter"
    def vocab(urn = nil)
      urn = urn.to_s.strip
      return vocab_by_century(urn) if options[:by_century]
      raise Thor::Error, "vocab: give a document, range, or passage urn" if urn.empty?

      config = Nabu::Config.load
      catalog = open_catalog(config)
      fulltext = open_fulltext(config)
      raise Thor::Error, "no index — run nabu sync or nabu rebuild" unless catalog && fulltext
      unless fulltext.table_exists?(Nabu::Store::Indexer::LEMMA_TABLE)
        raise Thor::Error, "no lemma index (the fulltext index predates lemma search) — " \
                           "run nabu sync or nabu rebuild"
      end

      profile = Nabu::Query::Vocab.new(catalog: catalog, fulltext: fulltext)
                                  .run(urn, limit: options[:limit].to_i)
      print_vocab(profile)
    rescue Nabu::Query::Vocab::NotFound, Nabu::Query::Range::Error => e
      raise Thor::Error, e.message
    ensure
      catalog&.disconnect
      fulltext&.disconnect
    end

    desc "mcp", "Serve the corpus to an AI client over MCP (stdio, read-only) — see docs/mcp.md"
    long_desc <<~HELP, wrap: false
      Run the Model Context Protocol server on stdin/stdout: a READ-ONLY
      conversational surface over the local nabu corpus, exposing seven tools —
      nabu_search (full-text + exact-lemma), nabu_show (read by urn, ranges,
      parallel translations), nabu_concord (KWIC), nabu_align (cross-source
      citation alignment), nabu_define (the dictionary shelf: LSJ + Lewis &
      Short), nabu_etym (the reconstruction crosswalk), and nabu_status
      (coverage) — to any MCP client (Claude Code, Claude Desktop). The catalog and index are opened
      SQLITE_OPEN_READONLY: this process is POSITIVELY unable to write to db/.

      This is a plumbing command, not an interactive one. STDOUT IS THE PROTOCOL
      CHANNEL — it carries newline-delimited JSON-RPC and nothing else.
      Diagnostics go to stderr, or appended to a file with --log FILE. The
      openers are lazy and read-only, so a corpus that appears or is rebuilt
      mid-session is picked up without a restart. The server runs until stdin
      closes (EOF) or it is signalled (SIGINT/SIGTERM), then exits 0.

      You normally never type this yourself — a client spawns it. This repo ships
      .mcp.json, so opening Claude Code in the repo registers nabu automatically.
      User-scope, Claude Desktop, the tool reference, the license/attribution
      stance, and an example transcript are in docs/mcp.md.

      Examples:
        nabu mcp                       # a client spawns this; speaks JSON-RPC on stdio
        nabu mcp --log /tmp/nabu-mcp.log   # tee diagnostics to a file (stdout stays clean)
    HELP
    option :log, type: :string, banner: "FILE",
                 desc: "Append diagnostics to FILE instead of stderr (stdout is the protocol channel)"
    def mcp
      config = Nabu::Config.load
      log = mcp_log(options[:log])
      registry = Nabu::SourceRegistry.load(config.sources_path)
      # Lazy, memoizing, read-only openers (Procs, per the Tools contract):
      # resolved on every tool call, so a corpus that appears or is rebuilt
      # mid-session is picked up without a restart. nil when the file is absent
      # (Tools renders the graceful "no corpus" / "rebuilding" states).
      tools = Nabu::MCP::Tools.new(
        catalog: readonly_opener(config.catalog_path) { Nabu::Store.connect(config.catalog_path, readonly: true) },
        fulltext: readonly_opener(config.fulltext_path) do
          Nabu::Store.connect_fulltext(config.fulltext_path, readonly: true)
        end,
        # The history ledger, read-only (P14-12): nabu_status surfaces the
        # cached upstream-drift verdicts from source_probes. MCP reads the raw
        # dataset (no model binding) and NEVER probes upstreams live.
        ledger: readonly_opener(config.history_path) do
          Nabu::Store.connect(config.history_path, readonly: true)
        end,
        # The links journal, read-only (P16-1): nabu_links reads batch-mined
        # edges. Absent file = no batch has run (a graceful state).
        links: readonly_opener(config.links_path) do
          Nabu::Store.connect(config.links_path, readonly: true)
        end,
        # Static config, loaded once — a malformed registry fails HERE, loudly,
        # not mid-conversation.
        alignments: Nabu::AlignmentRegistry.load(config.alignments_path),
        # The source registry (P23-3b): authoritative for enablement, so
        # nabu_status renders a sources.yml flip immediately (the db row only
        # mirrors it at the source's next sync).
        registry: registry,
        # The enabled-slug set (P44-r3b): nabu_status's sources array defaults
        # to this box's enabled sources, matching the CLI list/status default.
        enabled_slugs: mcp_enabled_slugs(config, registry),
        # The Pleiades gazetteer (P44-3): :auto = feature-detect lazily per
        # call (nabu_place, nabu_show findspot) — the derived catalog place
        # index when a sync/rebuild has built it (P45-6, instant), else the
        # canonical dump; an unsynced box degrades exactly like the CLI,
        # never crashes.
        pleiades: :auto,
        # The Oracc Sign List (P53-2): :auto = feature-detect canonical/osl
        # lazily per call (nabu_signs); an unsynced box notes the sync hint,
        # every other tool byte-identical (the lane-off rule).
        sign_list: :auto,
        # Tibetan word segmentation (P54-2): :auto = feature-detect
        # canonical/nabu-data lazily inside Query::Show (nothing loads
        # unless nabu_show is asked for a segmented render); an unsynced
        # box answers the flag with the sync-hint note.
        tibetan_words: :auto,
        # The nabu-lects module (P57-4): :auto = feature-detect
        # canonical/nabu-lects lazily per call (nabu_search's `lect`
        # filter); an unsynced box answers `lect` with an InvalidArguments
        # naming the module, every other tool byte-identical.
        lects: :auto
      )
      $stdout.sync = true
      install_mcp_signal_traps
      # stdout carries protocol only; every diagnostic goes to the log IO.
      Nabu::MCP::Server.new(tools: tools, log: log).run($stdin, $stdout)
    ensure
      log.close if log && !log.equal?($stderr)
    end

    desc "export", "Stream non-withdrawn passages as plain text or JSONL"
    long_desc <<~HELP, wrap: false
      Stream the live corpus to stdout, one passage per line — the
      longevity-hedge exit formats: the data must survive the code.
      Withdrawn passages are excluded; retired-upstream documents are
      INCLUDED (they are part of your collection — that is the point of
      keeping them). Streaming end to end: constant memory at any corpus
      size, so piping a million passages is fine.

      Formats:
        plain   text only, internal newlines collapsed to one space
        jsonl   one JSON object per line: urn, language, text,
                text_normalized, annotations — annotations is a real nested
                object carrying lemmas/morphology where the source provides
                them (the treebanks: UD, PROIEL, TOROT)
        conllu  arrives with the enrichment phase (needs the token model)

      Same --lang / --license / --source filters as search.

      Examples:
        nabu export --format plain --lang got > gothic.txt
        nabu export --format jsonl --source ccmh > ccmh.jsonl
        nabu export --format jsonl --license open | jq -r .urn
        nabu export --format jsonl --lang chu | jq '.annotations' | head

      Use cases: feed a corpus slice to external NLP tooling; a license-clean
      subset for anything you plan to publish; plain-text dumps for grep-scale
      workflows or personal backups independent of nabu itself.
    HELP
    option :format, type: :string, required: true, desc: "plain | jsonl"
    option :lang, type: :string, desc: "Restrict to a passage language (e.g. grc, lat)"
    option :license, type: :string,
                     desc: "Restrict to an exact license class (open, attribution, nc, …)"
    option :source, type: :string, banner: "SLUG",
                    desc: "Restrict to one source (`nabu list` names the slugs)"
    option :axis, type: :string, banner: "NAME[,NAME...]",
                  desc: "Restrict to the members of one or more research axes (config/axes.yml) — the " \
                        "multi-source generalization of --source"
    def export
      format = validate_format!(options[:format])
      validate_license!(options[:license])
      config = Nabu::Config.load
      catalog = open_catalog(config)
      raise Thor::Error, "no catalog — run nabu sync or nabu rebuild" unless catalog

      validate_source!(catalog, options[:source])
      _axis_names, axis_slugs = axis_membership(command: "export", config: config)
      lines = Nabu::Query::Export.new(catalog: catalog)
                                 .run(format: format, lang: options[:lang], license: options[:license],
                                      source: options[:source], sources: axis_slugs)
      # Stream: write each serialized line as it arrives — never join a
      # 238k-passage corpus into one string.
      lines.each { |line| $stdout.puts(line) }
    ensure
      catalog&.disconnect
    end

    desc "backup", "Snapshot canonical/, the history ledger, config/, and the derived dbs to an external volume"
    long_desc <<~HELP, wrap: false
      File-level rsync backup (architecture §8, P7-2) — the concept's promise:
      restorable from a plain rsync copy with zero services running. Backs up
      everything that is NOT re-derivable:

        canonical/   the permanent asset, INCLUDING every .attic/ (upstream-
                     scrapped files that exist nowhere else — a per-slug git
                     mirror would miss them; file-level or nothing)
        db/history.sqlite3   the ledger: run history, sync pins, license
                     baselines, durable revisions (the only copy)
        config/      nabu.yml + sources.yml
        db/catalog + db/fulltext   the derived dbs — included by DEFAULT
                     (a file copy beats an hour of rebuild); --skip-derived omits
                     them (canonical/ + `nabu rebuild` reconstitutes them)

      Target: config/nabu.yml `backup: target:` (a path under a mounted external
      volume), overridable with --to PATH.

      THE MOUNT-POINT GUARD: the target must live on a REAL mounted volume. If
      the volume is not mounted, the path is a bare directory on the boot disk,
      and rsync would silently back up onto it — then shadow the real volume once
      it mounts. backup REFUSES this unless --allow-unmounted (for deliberately
      local targets: the drill, a scratch copy).

      --dry-run prints the rsync plan and changes nothing.

      Examples:
        nabu backup                                   # to the configured volume
        nabu backup --to /Volumes/NabuBackup/nabu     # explicit target
        nabu backup --dry-run                          # show the plan
        nabu backup --skip-derived                     # canonical + ledger + config only
    HELP
    option :to, type: :string, desc: "Target path override (default: config/nabu.yml backup.target)"
    option :skip_derived, type: :boolean, default: false,
                          desc: "Omit the derived dbs (catalog + fulltext); restore rebuilds them"
    option :dry_run, type: :boolean, default: false, desc: "Print the rsync plan and change nothing"
    option :allow_unmounted, type: :boolean, default: false,
                             desc: "Skip the mount-point guard (for a deliberately-local target)"
    def backup
      config = Nabu::Config.load
      result = Nabu::Backup.new(
        config: config, target: options[:to], skip_derived: options[:skip_derived],
        dry_run: options[:dry_run], allow_unmounted: options[:allow_unmounted]
      ).run
      print_backup(result)
      raise Thor::Error, backup_failure_summary(result) unless result.ok?
    rescue Nabu::Backup::Error => e
      # No target, or the mount-point guard tripped: a clean stderr message + exit 1.
      raise Thor::Error, e.message
    end

    # How many evidence spans / shared lemmas a compact `parallels` hit shows
    # before it elides with a "… and N more" tail; --long lifts the cap.
    PARALLELS_COMPACT_ITEMS = 3
    # Compact evidence-span width; --long prints the span untrimmed.
    PARALLELS_SPAN_CHARS = 72
    # Edges shown per kind by `nabu links` before the "… and N more" tail
    # (--long lists all — the conventions §10 house rule).
    LINKS_COMPACT_ITEMS = 10
    # Language codes shown by the `nabu axis` desk card's languages line
    # before the "… and N more" tail (P48-r3; --long lists all — the same
    # house render-cap rule).
    AXIS_LANGUAGES_ITEMS = 10
    # RTL snippet highlight = SGR reverse video (P42-r4, strike 4 — the
    # matrix ruling on the owner's iTerm2). Every CHARACTER-based highlight
    # is at the mercy of the renderer's bidi treatment, and four attempts
    # measured four failure modes; a cell ATTRIBUTE rides the glyph wherever
    # reordering moves it and cannot be broken by any bidi algorithm.
    RTL_HIGHLIGHT_ON = "\e[7m"
    RTL_HIGHLIGHT_OFF = "\e[27m"
    # Batch-mining progress tick cadence (anchors per stderr line); a scope
    # smaller than one tick prints no progress at all — just the summary.
    BATCH_PROGRESS_EVERY = 200

    # The no-silent-script-miss table (P27-2). A zero-hit query carrying
    # codepoints of a script NO fold neutralization covers gets ONE honest
    # hint naming what to try — the owner incident was exactly a silent
    # cross-script miss. Censused entries only: Glagolitic rides the OCS
    # dictionary shelf as variant forms (never passage text), and the
    # Gothic corpora are romanized (conventions §9). Devanagari and
    # Cyrillic do NOT hint — their neutralizations already fold them.
    SCRIPT_MISS_HINTS = {
      "Glagolitic" => [0x2C00..0x2C5F,
                       "no cross-script fold is registered for Glagolitic — the Slavic shelves " \
                       "index Cyrillic and Latin-diplomatic spellings (try въста or vъsta)"],
      "Gothic-script" => [0x10330..0x1034F,
                          "no cross-script fold is registered for Gothic script — the Gothic " \
                          "corpora are romanized (try guþ, jah)"]
    }.freeze

    # H9 (P35-6): the skip-with-note rule for a corrupt annotations_json —
    # Show marks the parse failure (ANNOTATIONS_UNREADABLE) and every
    # render that would have used the lane says so.
    ANNOTATIONS_UNREADABLE_NOTE = "stored annotations are unreadable (invalid JSON) — skipped"

    no_commands do
      # -- display policy (P27-0) ------------------------------------------
      # Passage text reaches the terminal ONLY through display_text, which
      # applies the per-language display.yml policy under the --display mode
      # and records what changed; print_display_footer then hints ONCE per
      # invocation — never silent alteration, never a hint when nothing
      # happened. MCP and export never touch this path: pristine text.

      # Resolve --display MODE against the registry; validate before any
      # output so an unknown mode is a clean named error.
      def display_mode
        @display_mode ||= Nabu::Display.mode(options[:display] || Nabu::Display::DEFAULT_MODE)
      rescue Nabu::Display::UnknownModeError => e
        raise Thor::Error, e.message
      end

      def display_policies
        @display_policies ||= Nabu::Display.load_policies(Nabu::Config.load.display_path)
      rescue Nabu::Display::ConfigError => e
        raise Thor::Error, e.message
      end

      def display_source_policies
        @display_source_policies ||= Nabu::Display.load_source_policies(Nabu::Config.load.display_path)
      rescue Nabu::Display::ConfigError => e
        raise Thor::Error, e.message
      end

      # Render one run of text for the terminal and remember which transforms
      # actually applied (for the footer hint). +source+/+annotations+
      # (P27-1) are the optional edition context — call sites that know the
      # passage's source (the show family) pass them so `--display reading`
      # can apply the per-source convention rules and the ketiv/qere choice;
      # everywhere else the language-level policies alone apply.
      def display_text(text, language, source: nil, annotations: nil)
        @display_gaiji_ladder = true if source && display_source_policies[source]&.gaiji == "ladder"
        rendered = Nabu::Display.render(text.to_s, language: language,
                                                   mode: display_mode, policies: display_policies,
                                                   source: source, annotations: annotations,
                                                   source_policies: display_source_policies,
                                                   gaiji_map: gaiji_map_for(source),
                                                   gaiji_ids: gaiji_ids_for(source),
                                                   gaiji_substitutes: gaiji_substitutes_for(source))
        display_applied.merge(rendered.applied)
        record_gaiji(rendered.gaiji)
        rendered.text
      end

      def display_applied
        @display_applied ||= Set.new
      end

      # Render a SNIPPET — StoredSnippet output with the match in [brackets] —
      # for the terminal (P42-r4, four strikes deep). Square brackets inside
      # RTL text are unrenderable-portably: they are a bidi-mirrored pair,
      # and each character-based fix failed a different way on the owner's
      # iTerm2 (mirrorless reversal showed ]word[; brackets cut OUT of the
      # isolate were swept into the reversed segment anyway; the symmetric ‖
      # detached at passage-edge matches; RLM gluing was ignored — invisible
      # bidi controls do not extend that renderer's runs, though a VISIBLE
      # strong-R paseq does, matrix line 8). The ruling fix highlights with
      # a cell ATTRIBUTE instead of characters: SGR reverse video rides the
      # glyph wherever reordering moves it and no bidi algorithm can touch
      # it (matrix line 9 on the owner's screen). Gated by color_output?
      # (mode + NO_COLOR/NABU_COLOR/tty): piped or colorless output keeps
      # the logical [brackets] — no renderer, no bidi, and the documented
      # grep/MCP contract stays byte-identical. ANSI escapes are ASCII —
      # untouched by mark strips and NFC round-trips (the painted-tokens
      # precedent). Only PAIRED brackets convert (a stored lone Leiden
      # bracket stays literal); a stored [...] lacuna pair colors like a
      # match — the same ambiguity the bracket convention always had.
      def display_snippet(text, language)
        unless Nabu::Display.isolates?(language: language.to_s, mode: display_mode,
                                       policies: display_policies) && color_output?
          return display_text(text, language)
        end

        marked = text.to_s.gsub(/\[([^\[\]]*)\]/) { "#{RTL_HIGHLIGHT_ON}#{Regexp.last_match(1)}#{RTL_HIGHLIGHT_OFF}" }
        display_text(marked, language)
      end

      # The source's three gaiji ladder lanes (P37-3/P38-2), each memoized per
      # source: config/gaiji/<source>.tsv (faithful), <source>-ids.tsv (IDS)
      # and <source>-substitutes.tsv (substitutes) — only kanripo ships them
      # today. A missing file is an empty map (that rung degrades to the next),
      # and the non-show call sites (no source) never load a map at all.
      def gaiji_map_for(source) = gaiji_lane(source, "")

      def gaiji_ids_for(source) = gaiji_lane(source, "-ids")

      def gaiji_substitutes_for(source) = gaiji_lane(source, "-substitutes")

      def gaiji_lane(source, suffix)
        return {} unless source

        (@gaiji_lanes ||= {})[[source, suffix]] ||=
          Nabu::Display.load_gaiji_map(File.join(Nabu::Config.load.gaiji_dir, "#{source}#{suffix}.tsv"))
      end

      # Running per-rung gaiji tallies for the once-per-invocation footer
      # ([faithful, ids, substitute, placeholder], summed across every passage a
      # show-family command renders).
      def display_gaiji
        @display_gaiji ||= [0, 0, 0, 0]
      end

      def record_gaiji(tally)
        return unless tally

        display_gaiji[0] += tally.faithful
        display_gaiji[1] += tally.ids
        display_gaiji[2] += tally.substitute
        display_gaiji[3] += tally.placeholder
      end

      # Per-token language coloring (P27-2): the single-passage show view —
      # the one render where the stored P7-5 tokens annotation is at hand —
      # colorizes tokens tagged with a language OTHER than the passage's own
      # (corph's Latin glosses in Old Irish, OSHB's Aramaic verses). Gated
      # three ways: the mode's #colors? (mono/full say no), NO_COLOR /
      # NABU_COLOR / tty (Display.color?), and the honest-tagging rule
      # (untagged and base-language tokens stay uncolored). Painting wraps
      # PRISTINE token forms before the display transform — ANSI escapes are
      # ASCII, untouched by mark-class strips and NFC round-trips.
      def painted_passage_text(passage)
        return passage.text unless color_output?

        tokens = passage.annotations["tokens"]
        return passage.text unless tokens.is_a?(Array)

        painted, legend = Nabu::Display::TokenColors.paint(passage.text, tokens: tokens,
                                                                         language: passage.language)
        return passage.text if legend.empty?

        display_applied << "token colors: #{legend.map { |lang, color| "#{lang}=#{color}" }.join(' ')}"
        painted
      end

      def color_output?
        mode = display_mode
        (!mode.respond_to?(:colors?) || mode.colors?) && Nabu::Display.color?(tty: $stdout.tty?)
      end

      # The once-per-invocation honesty footer: named only when a transform
      # actually changed something (compact rule — zero-signal silence).
      #   display: cantillation stripped (--display full shows all marks)
      #   display: cantillation stripped · rtl isolates (--display full shows all marks)
      # One footer per invocation, composing every applied transform's
      # vocabulary (P27-0 strips · P27-1 edition · P27-2 translit/colors/
      # spacing); the escape hatch names diplomatic when edition transforms
      # applied, else full.
      def print_display_footer
        gaiji_text = gaiji_clause(*display_gaiji)
        return if display_applied.empty? && gaiji_text.nil?

        labels = display_applied.to_a
        edition = Nabu::Display::EDITION_LABELS & labels
        parts = []
        parts << "transliterated" if labels.delete("translit")
        colors = labels.select { |label| label.start_with?("token colors") }
        strips = labels - colors - edition - ["spacing", Nabu::Display::ISOLATES]
        parts << "#{strips.join(', ')} stripped" unless strips.empty?
        parts << "apparatus simplified: #{edition.join(', ')}" unless edition.empty?
        parts << gaiji_text if gaiji_text
        parts << "spacing" if labels.include?("spacing")
        parts.concat(colors)
        parts << Nabu::Display::ISOLATES if labels.include?(Nabu::Display::ISOLATES)
        say "display: #{parts.join(' · ')} (#{display_footer_hint(edition, !gaiji_text.nil?)})"
      end

      # The escape-hatch hint: diplomatic when any edition-level transform ran
      # (apparatus OR gaiji — both are "shown as stored" under diplomatic),
      # naming "refs" when gaiji is the only edition transform; else full.
      def display_footer_hint(edition, gaiji)
        return "--display diplomatic shows the edition marks" unless edition.empty?
        return "--display diplomatic shows the gaiji refs" if gaiji

        "--display full shows all marks"
      end

      # The gaiji footer clause, per rung. Returns nil when there is nothing to
      # announce. Two shapes, honest to the policy:
      #   ladder (P38-2)     — FAITHFUL is silent (it IS the character); the
      #                        lossy rungs (substitutes, IDS compositions) and
      #                        the ⬚ placeholders DO get announced ("never
      #                        silent"). An all-faithful render says nothing.
      #   placeholder (P37-3) — the preserved rungs-1+4 vocabulary: unresolved
      #                        (⬚) refs and how many resolved to a real glyph.
      def gaiji_clause(faithful, ids, substitute, placeholder)
        return ladder_gaiji_clause(ids, substitute, placeholder) if @display_gaiji_ladder

        placeholder_gaiji_clause(faithful, placeholder)
      end

      def ladder_gaiji_clause(ids, substitute, placeholder)
        bits = []
        bits << "#{substitute} substituted" if substitute.positive?
        bits << "#{ids} composed" if ids.positive?
        bits << "#{placeholder} unresolved gaiji" if placeholder.positive?
        bits.empty? ? nil : bits.join(", ")
      end

      def placeholder_gaiji_clause(resolved, unresolved)
        if unresolved.positive? && resolved.positive?
          "#{unresolved} unresolved gaiji (#{resolved} resolved)"
        elsif unresolved.positive?
          "#{unresolved} unresolved gaiji"
        elsif resolved.positive?
          "#{resolved} gaiji resolved"
        end
      end

      # Reject an unknown --license up front (before opening any db) with the
      # closed enum of valid classes, so the user sees the choices. Shared by
      # search and export.
      def validate_license!(license)
        return if license.nil?
        return if Nabu::SourceManifest::LICENSE_CLASSES.include?(license)

        raise Thor::Error,
              "unknown license #{license.inspect} " \
              "(choose from #{Nabu::SourceManifest::LICENSE_CLASSES.join(', ')})"
      end

      # Resolve --century (a whole century's bounds) OR --from/--to into a
      # [from, to] signed-historical-year window (P15-2). The reviewed guards:
      # no year 0 (1 BCE = -1, 1 CE = +1), a clear F>T message (not a silent
      # empty result), and --century is mutually exclusive with --from/--to.
      def date_window
        if options[:century]
          if options[:from] || options[:to]
            raise Thor::Error, "date filter: --century is shorthand for --from/--to — use one or the other"
          end

          idx = options[:century].to_i
          raise Thor::Error, "date filter: there is no century 0 (1st c. CE is 1, 1st c. BCE is -1)" if idx.zero?

          return Nabu::Timeline.century_bounds(idx)
        end

        from = coerce_year(options[:from], "--from")
        to = coerce_year(options[:to], "--to")
        if from && to && from > to
          raise Thor::Error, "date filter: --from #{from} is after --to #{to} " \
                             "(BCE years are negative — 300 BCE is -300, so -300 comes before -30)"
        end
        [from, to]
      end

      def coerce_year(value, flag)
        return nil if value.nil?

        year = value.to_i
        raise Thor::Error, "date filter: there is no year 0 (#{flag}); 1 BCE is -1, 1 CE is 1" if year.zero?

        year
      end

      # A date/place filter needs document_axes; a catalog that predates
      # migration 008 (never rebuilt) hasn't got it. Fail with a clear pointer
      # rather than a Sequel "no such table".
      def require_timeline!(catalog)
        return if catalog.table_exists?(:document_axes)

        raise Thor::Error, "no timeline (this catalog predates it) — run nabu rebuild"
      end

      # A facet filter needs document_facets (migration 009) — same honest
      # pointer as the timeline guard.
      def require_facets!(catalog)
        return if catalog.table_exists?(:document_facets)

        raise Thor::Error, "no facet table (this catalog predates it) — run nabu rebuild"
      end

      # The active facet filters as {facet name => pattern}, or nil when none
      # (P17-2): --type → genre, --province → province, --material → material.
      def facet_filters
        filters = {}
        filters["genre"] = options[:type] if options[:type]
        filters["province"] = options[:province] if options[:province]
        filters["material"] = options[:material] if options[:material]
        filters.empty? ? nil : filters
      end

      # The active loans code (P34-2), or nil. No validation beyond the strip:
      # the code rides as a bound value (never SQL or a JSON path), so any
      # string is safe and an unattested one is an honest no-match. Needs no
      # rebuild guard either — annotations_json is initial schema.
      def loans_filter
        code = options[:loans].to_s.strip
        code.empty? ? nil : code
      end

      # The content-narrowing filters that make a TERM-LESS browse legal
      # (P42-6): a date window (--from/--to/--century), a provenance --place, a
      # genre facet (--type/--province/--material), or the --loans facet — each
      # narrows WHICH passages, not merely which shelf. --lang/--license/
      # --source/--axis select whole shelves and are deliberately NOT sufficient
      # alone: a term-less listing of a whole language (or license, or source,
      # or axis) is a corpus DUMP, not a browse. The character-structure filters
      # are already a legal term-less path and return earlier (char_structured_search).
      def content_narrowing_filters?
        options[:from] || options[:to] || options[:century] || options[:place] ||
          facet_filters || loans_filter || options[:meter] || options[:meter_pattern] || options[:lect]
      end

      # The refusal for a term-less `search` that carries no content-narrowing
      # filter — the old "give a query" message, extended (P42-6) to say exactly
      # what WOULD make a term-less browse legal, and why the shelf-selectors do not.
      def browse_refusal_message
        "search: give a query — or a content-narrowing filter to browse the corpus " \
          "term-less: a date window (--from/--to/--century), --place, a genre facet " \
          "(--type/--province/--material), --loans, --meter/--meter-pattern, or --lect. " \
          "--lang/--license/--source/--axis " \
          "select whole shelves and cannot stand alone (that would dump the shelf, not browse it)."
      end

      # Term-less filtered browse (P42-6): a legal empty-query `search` — one
      # content-narrowing filter present — lists the corpus in corpus order
      # (Search#browse: passages.id ascending, no ranking) under the standard
      # filters and rendering. Reached only from #search on an empty query, and
      # only after the char/fuzzy/near/lemma paths have returned, so the sole
      # residual flags are the plain path's own; --exact/--word have no term to
      # match here and are refused rather than silently ignored.
      def browse_search
        if options[:exact] || options[:word]
          raise Thor::Error, "search: --exact/--word are glyph/word post-filters over a query term — " \
                             "they cannot run a term-less browse (drop them, or add a query)"
        end
        raise Thor::Error, browse_refusal_message unless content_narrowing_filters?

        validate_license!(options[:license])
        from, to = date_window
        place = options[:place]
        facets = facet_filters
        loans = loans_filter
        config = Nabu::Config.load
        catalog = open_catalog(config)
        fulltext = open_fulltext(config)
        raise Thor::Error, "no index — run nabu sync or nabu rebuild" unless catalog && fulltext

        require_timeline!(catalog) if from || to || place
        require_facets!(catalog) if facets
        validate_source!(catalog, options[:source])
        axis_names, axis_slugs = axis_membership(command: "search", config: config)
        lects = require_lects!(config, options[:lect])

        searcher = Nabu::Query::Search.new(catalog: catalog, fulltext: fulltext, lects: lects || :auto)
        results = searcher.browse(lang: options[:lang], license: options[:license],
                                  limit: options[:limit].to_i, from: from, to: to, place: place,
                                  facets: facets, source: options[:source], sources: axis_slugs,
                                  loans: loans, meter: options[:meter],
                                  meter_pattern: options[:meter_pattern], lect: options[:lect])
        print_search_results(results, facets: facets, query: "", loans: loans, axis: axis_names,
                                      browse: true, from: from, to: to, place: place,
                                      meter_note: searcher.meter_note)
        print_display_footer
      ensure
        catalog&.disconnect
        fulltext&.disconnect
      end

      # --source SLUG (P22-1, search/export): reject an unknown slug up front,
      # naming the valid slugs (the define-miss pattern). Validated against
      # the CATALOG — what is held is what can be filtered.
      def validate_source!(catalog, slug)
        return if slug.nil?
        return if catalog[:sources].where(slug: slug).any?

        known = catalog[:sources].order(:slug).select_map(:slug)
        raise Thor::Error, "unknown source #{slug.inspect} — the catalog holds: #{known.join(', ')}"
      end

      # P57-4: --lect needs the nabu-lects module. nil when +lect+ was not
      # given (no load attempted); the loaded Nabu::Lects when it was and
      # the module is synced; a clean Thor::Error naming the module
      # otherwise (the CLI half of Search's own Nabu::Error guard).
      def require_lects!(config, lect)
        return nil unless lect

        lects = Nabu::Lects.load_default(config: config)
        raise Thor::Error, "search: --lect needs the nabu-lects module — nabu-lects module not synced" unless lects

        lects
      end

      # --axis NAME[,NAME…] (P37-8, search/export): resolve the named research
      # axes to the union of their member slugs — the membership filter, the
      # multi-source generalization of --source. Returns [axis names in the
      # order asked, member slugs] or nil when --axis is absent. An unknown
      # axis is refused naming the known set (the P35-1 resolution guarantee),
      # and an empty registry says so; the slug/axis collision guarantee makes
      # a bare name unambiguous.
      def axis_membership(command:, config:)
        spec = options[:axis].to_s.strip
        return nil if spec.empty?

        registry = Nabu::SourceRegistry.load(config.sources_path)
        axes = registry.axes
        raise Thor::Error, "#{command}: no research axes are defined (config/axes.yml)" if axes.empty?

        names = spec.split(",").map(&:strip).reject(&:empty?).uniq
        names.each do |name|
          axes[name] ||
            raise(Thor::Error, "#{command}: unknown axis #{name.inspect} — known axes: #{axes.names.join(', ')}")
        end
        [names, names.flat_map { |name| registry.axis_members(name) }.uniq]
      end

      # -- list (P22-1) renderers -------------------------------------------

      # The flag grammar: one enumeration mode per invocation, each filter
      # only where it means something — a wrong combination is a named
      # error, never a silently ignored flag.
      def validate_list_flags!(slug)
        modes = %i[documents entries collections].select { |flag| options[flag] }
        modes << :loans if options[:loans]
        if options[:sources] && (!slug.empty? || modes.any? || options.values_at(
          "long", "export-source-dossiers", "dry-run", "prefix", "lang", "license",
          "withdrawn", "from", "to", "century"
        ).any?)
          raise Thor::Error, "list: --sources is the one-page grouped map — it composes with nothing"
        end
        # --axis groups the bare census under the research desks; it is a
        # census view, not an enumeration — like --sources, it composes with
        # nothing (a SOURCE, an enumeration, --long, --sources are all a
        # different question).
        if options[:axis] && (!slug.empty? || modes.any? || options[:sources] ||
                              options.values_at("long", "export-source-dossiers", "dry-run").any?)
          raise Thor::Error, "list: --axis groups the census under the research axes — " \
                             "drop the SOURCE/enumeration flags"
        end
        if modes.size > 1
          raise Thor::Error, "list: give one of --documents, --entries, --collections, --loans per invocation"
        end
        raise Thor::Error, "list: give a SOURCE with --#{modes.first}" if slug.empty? && modes.any?
        if options[:"export-source-dossiers"] && (!slug.empty? || modes.any?)
          raise Thor::Error, "list: --export-source-dossiers scaffolds ALL registered sources — " \
                             "no SOURCE, no enumeration"
        end
        if options[:"dry-run"] && !options[:"export-source-dossiers"]
          raise Thor::Error, "list: --dry-run composes with --export-source-dossiers"
        end
        if options[:long] && (!slug.empty? || modes.any?)
          raise Thor::Error, "list: --long expands the bare census — drop the SOURCE/enumeration flags"
        end
        if options[:prefix] && !options[:entries] && !options[:documents]
          raise Thor::Error, "list: --prefix filters headwords/dossier codes — use it with --entries " \
                             "or --documents"
        end

        doc_only = %i[license withdrawn from to century].select { |flag| options[flag] }
        unless doc_only.empty? || options[:documents]
          raise Thor::Error, "list: --#{doc_only.first} composes with --documents"
        end
        return if options[:lang].nil? || options[:documents] || options[:entries]

        # Bare `list SOURCE --lang X` no longer refuses — it IMPLIES the
        # natural enumeration (dictionary → entries, text → documents;
        # dispatched below). --lang stays refused only where it cannot imply
        # a mode: with no SOURCE (the census spans the whole library), or on
        # a census grain that does not filter by language (--collections /
        # --loans have their own axes). Each refusal names what DOES work.
        if slug.empty?
          raise Thor::Error, "list: --lang needs a SOURCE (nabu list SOURCE --lang CODE) — " \
                             "the bare census spans the whole library"
        end
        return unless options[:collections] || options[:loans]

        grain = options[:collections] ? "collections" : "loans"
        raise Thor::Error, "list: --lang filters a shelf's documents or dictionary entries " \
                           "(bare `nabu list SOURCE --lang CODE`, or --documents/--entries) — not --#{grain}"
      end

      # Bare `list SOURCE --lang X` (P44-r1): with no explicit enumeration
      # flag and a --lang present, the natural mode is IMPLIED by the shelf's
      # content kind. Returns :documents / :entries, or nil when no
      # implication applies (no SOURCE, no --lang, or an explicit mode/census
      # grain already chosen — validate_list_flags! has already refused the
      # meaningless combinations). Reads the catalog fact via the query
      # object, so an unknown slug surfaces as the usual naming error.
      def implied_list_mode(query, slug)
        return nil if slug.empty? || options[:lang].nil?
        return nil if options[:documents] || options[:entries] ||
                      options[:collections] || options[:loans]

        query.natural_mode(slug)
      end

      # The legible header for an implied enumeration: names the mode, the
      # filter that implied it, and the content-kind reason.
      def implied_mode_header(mode, slug, lang)
        reason = mode == :entries ? "a dictionary shelf" : "a text shelf"
        "#{mode} (implied by --lang #{lang}) — #{slug} is #{reason}"
      end

      # The registry entry for one slug, nil when the catalog source is not
      # (or no longer) registered — the card words that honestly.
      def registry_entry(config, slug)
        Nabu::SourceRegistry.load(config.sources_path)[slug]
      end

      # +descriptions+ (P24-0, --long): { slug => dossier description } — one
      # line under each source that has one (zero fields suppressed, the
      # house rule; the dossier shelf is the census's own metadata).
      # The --disabled census (P46-r3 follow-up, owner report: `list
      # --disabled` printed the empty-catalog banner while `status
      # --disabled` showed the row): the menu is REGISTRY-driven — a
      # never-synced complement row is the norm there, not an absence.
      # Census fragments where the catalog holds the slug; an honest
      # per-row "nothing held yet" where it does not. An empty complement
      # prints no table (the stderr footer carries the all-enabled state).
      def print_disabled_census(view, census_rows)
        slugs = view.registry.slugs
        return if slugs.empty?

        by_slug = census_rows.to_h { |row| [row.slug, row] }
        width = slugs.map(&:length).max
        slugs.each do |slug|
          row = by_slug[slug]
          say "#{slug.ljust(width)}  #{row ? census_fragments(row).join('  ') : 'nothing held yet'}"
        end
      end

      def print_census(rows, descriptions = nil)
        return say("nothing held yet — run nabu sync") if rows.empty?

        width = rows.map { |row| row.slug.length }.max
        rows.each do |row|
          say "#{row.slug.ljust(width)}  #{census_fragments(row).join('  ')}"
          description = descriptions && descriptions[row.slug]
          say "#{' ' * (width + 2)}#{truncate_line(description)}" if description
        end
        say census_summary(rows)
      end

      # Resolve the --axis value to the ordered Axis list to render (P35-1).
      # Bare (empty) --axis = every axis in the ratified file order; a
      # comma-list = those axes, in the order asked (deduped, first wins). An
      # unknown name is a clean error naming the known set — the resolution
      # guarantee (an axis name can never collide with a slug, so this is
      # unambiguous). No axes defined at all is its own honest miss.
      # Route `nabu status` (P40-s): a SOURCE argument renders that one row's
      # full labeled detail block; --axis groups the compact rows under the
      # research desks; --long is the extended detail table; bare is the compact
      # v2 table. An unknown SOURCE names the valid slugs, like `list SOURCE`.
      def status_report(registry, db, ledger, slug)
        unless slug.empty?
          detail = Nabu::StatusReport.render_source(registry: registry, db: db, ledger: ledger, slug: slug)
          return detail if detail

          raise Thor::Error, "unknown source #{slug.inspect} — known sources: #{registry.slugs.join(', ')}"
        end
        if options[:axis]
          return Nabu::StatusReport.render_grouped(registry: registry, db: db, ledger: ledger,
                                                   axes: selected_axes(registry.axes), tag_note: AXIS_TAG_NOTE)
        end

        Nabu::StatusReport.render(registry: registry, db: db, ledger: ledger, long: options[:long])
      end

      # -- the local enablement config (P44-r3b, promoted from P40-f focus) --

      # The EFFECTIVE enablement profile for +config+ against +registry+. The
      # promotion's default inversion (P44-r3b): an ABSENT config no longer
      # means "everything". Three cases:
      #   file EXISTS         → its entries are the enabled set, as-is.
      #   absent + a library  → MIGRATION: write every registry source present
      #                         in the catalog out once, announced (no silent
      #                         visibility loss of a built library). Needs the
      #                         catalog to detect it, so surfaces without one
      #                         (remote health) pass catalog: nil and defer.
      #   absent + fresh box  → the quickstart starter set (empty until r3c
      #                         seeds the tags → the honest empty-state).
      def effective_profile(config, registry, catalog: nil)
        path = config.profile_path
        if Nabu::Profile.exist?(path)
          profile = Nabu::Profile.load(path)
          # An EMPTY pre-promotion (P40-f focus-era) file means "no focus
          # trim", never "nothing enabled" — it migrates exactly like an
          # absent file (announced, once). Only an empty file SAVED UNDER
          # THE ENABLEMENT HEADER governs as deliberately-empty (a
          # disable-everything is re-saved with the new header, so it
          # never re-migrates). Files with entries govern as-is either way.
          return profile unless profile.empty? && !Nabu::Profile.enablement_header?(path)
        end

        migrated = migrate_profile(config, registry, catalog)
        return migrated if migrated

        Nabu::Profile.new(Nabu::Profile.default_entries(registry))
      end

      # The one-time migration (P44-r3b): if the box already built a library
      # (the catalog carries source rows) but has no enablement config yet,
      # write one enabling every registry source present in the catalog, so the
      # promotion never drops visibility of what the owner already synced.
      # Returns the saved profile, or nil when there is nothing to migrate.
      def migrate_profile(config, registry, catalog)
        return nil unless catalog&.table_exists?(:sources)

        present = catalog[:sources].select_map(:slug) & registry.slugs
        return nil if present.empty?

        profile = Nabu::Profile.new(present).save(config.profile_path)
        warn "enablement: wrote config/profile.yml enabling your #{pluralize(present.size, 'synced source')} " \
             "(the profile is now this box's enabled set — nabu enable/disable to adjust)."
        profile
      end

      # The working scope for a read surface: the effective enablement resolved
      # against the registry, honoring --all. The filtered registry it carries
      # is what status/list/health render instead of the full one. +catalog+
      # feeds the migration detector (nil where a surface has none open yet).
      def focus_view(config, registry, catalog: nil)
        Nabu::Focus.view(
          profile: effective_profile(config, registry, catalog: catalog),
          registry: registry, all: options[:all], disabled: options[:disabled] || false
        )
      end

      # --all is everything, --disabled the not-yet-enabled complement —
      # together they name contradictory row sets (P46-r3).
      def refuse_all_with_disabled!(command)
        return unless options[:all] && options[:disabled]

        raise Thor::Error, "#{command}: --all and --disabled are exclusive — " \
                           "--all shows every row, --disabled only the rows nabu enable would add"
      end

      # Drop the census rows the view hides (a shelf/enabled source stays, a
      # non-enabled source goes). Under --all the view is the pass-through and
      # every row stays.
      def scoped_census(rows, view)
        view.active? ? rows.select { |row| view.visible?(row.slug) } : rows
      end

      # The enablement META lines go to STDERR, never stdout: piped output stays
      # byte-identical to the table, while the terminal user still sees context.
      # A default view names the enabled set + the exact hidden count, or the
      # honest empty-state when nothing is enabled; --all (the full reveal) is
      # silent.
      def print_focus_note(view, hidden_slugs)
        # The --disabled complement (P46-r3): the rows shown ARE the enable
        # menu, so the footer is the on-ramp (or the all-enabled state) —
        # never the enabled-set summary, never the empty-state.
        return warn(Nabu::Focus.disabled_footer_line(view.registry.slugs)) if view.disabled
        return unless view.active?

        if view.resolution.slugs.empty?
          warn Nabu::Focus.empty_state_line
        else
          warn Nabu::Focus.footer_line(view.entries, hidden_slugs)
        end
      end

      # The SCOPED enablement hint (P44-r1 addendum). A --axis or named-source
      # request never prints the whole-library `enabled:` list (that is the
      # unscoped view's job) — showing every enabled source under a request for
      # ONE desk is noise. Instead, IFF the requested scope has members not yet
      # enabled, one compact line names just those + the enable on-ramp; when
      # everything requested is already enabled, silence (the zero-signal house
      # rule). Blocked (grant-gated private) members are named INDIVIDUALLY with
      # their grant marker — never folded into `enable <axis>`, which skips them
      # (the r3b rule). Meta line → STDERR, like every enablement note.
      def print_axis_enable_hint(view, registry, axes)
        requested = axes.flat_map { |axis| registry.axis_members(axis.name) }.uniq
        print_scoped_enable_hint(view, registry, requested, enable_axes: axes.map(&:name))
      end

      def print_source_enable_hint(view, registry, slug)
        print_scoped_enable_hint(view, registry, [slug], enable_axes: [])
      end

      def print_scoped_enable_hint(view, registry, requested_slugs, enable_axes:)
        return unless view.active? # --all is the full reveal — silent

        enabled = view.resolution.slugs
        gap = requested_slugs.uniq.reject do |slug|
          entry = registry[slug]
          # A shelf always shows and a module only under --all — neither is an
          # `enable` target, so neither counts as an un-enabled gap.
          entry.nil? || entry.shelf? || entry.feature_module? || enabled.include?(slug)
        end
        return if gap.empty?

        blocked_gap, public_gap = gap.partition { |slug| registry.blocked?(slug) }
        clauses = []
        unless public_gap.empty?
          axes = enable_axes.select { |name| registry.public_axis_members(name).intersect?(public_gap) }
          clauses << if axes.empty?
                       "nabu enable #{public_gap.join(' ')}"
                     else
                       "nabu enable #{axes.join(' ')} (#{public_gap.join(', ')})"
                     end
        end
        blocked_gap.each { |slug| clauses << "#{slug} · grant required (nabu enable #{slug})" }

        count = gap.size
        warn "#{count} member#{'s' unless count == 1} not enabled — #{clauses.join('; ')}"
      end

      # Warn once about names the file carries that the registry no longer
      # knows (drift after a hand-edit): ignored, never fatal.
      def warn_focus_drift(view)
        warn Nabu::Focus.drift_line(view.unknown) unless view.unknown.empty?
      end

      # `nabu enable <axis|source…>`: additive. Validate the names, migrate an
      # absent-but-built profile first (no visibility loss), then append —
      # recording the AXIS NAME (the existing profile vocabulary; Focus expands
      # it to its PUBLIC members, blocked ones skipped) or the source slug. A
      # blocked (grant-gated private) source named BY SLUG runs the P42-r1 grant
      # flow here, at the natural consent moment; enabling an AXIS never drags a
      # blocked member in — each is skipped with the on-ramp line.
      def run_enable(config, registry, names, ledger:, catalog:)
        profile = effective_profile(config, registry, catalog: catalog)
        entries = profile.entries.dup
        added = []
        names.each do |name|
          if registry.axes[name]
            note_blocked_axis_members(registry, name)
          else
            enable_source!(registry[name], ledger) # raises (adds nothing) on a refused grant
          end
          added << name unless entries.include?(name)
        end
        Nabu::Profile.new(entries + added).save(config.profile_path)
        announce_enablement(config, registry, verb: "enabled", changed: added, catalog: catalog)
      end

      # One source being enabled by slug: a grant-gated (blocked) source with a
      # grant block runs the P42-r1 acknowledgment before it joins the enabled
      # set — a refusal raises (and the caller adds nothing).
      def enable_source!(entry, ledger)
        return unless entry.blocked? && entry.grant_required?

        enable_grant!(entry, ledger)
      end

      # Print the on-ramp line for every blocked (grant-gated) member an axis
      # would otherwise drag in — enabling an axis never implicitly enables its
      # private members (P44-r3b).
      def note_blocked_axis_members(registry, axis_name)
        registry.blocked_axis_members(axis_name).each do |slug|
          say "#{slug} is grant-gated — enable it explicitly: nabu enable #{slug}", :yellow
        end
      end

      # The P42-r1 grant flow AT ENABLE TIME: a recorded acknowledgment skips
      # the prompt with an honest one-liner; --grant-acknowledged records
      # non-interactively; otherwise show the terms and demand the typed word
      # (no TTY / refusal aborts with the request scaffold, adding nothing).
      def enable_grant!(entry, ledger)
        gate = Nabu::GrantGate.new(ledger: ledger)
        return say("#{entry.slug}: grant already acknowledged — enabling.", :yellow) if gate.acknowledged?(entry.slug)

        if options[:grant_acknowledged]
          gate.record!(slug: entry.slug, terms: entry.grant.terms, how: "flag")
          return say("#{entry.slug}: grant acknowledged (--grant-acknowledged) — recorded, enabling.", :yellow)
        end
        raise Thor::Error, Nabu::GrantGate.abort_message(entry) unless $stdin.tty?

        say Nabu::GrantGate.notice(entry), :yellow
        say Nabu::GrantGate.prompt_line(entry)
        answer = $stdin.gets
        raise Thor::Error, Nabu::GrantGate.abort_message(entry) unless Nabu::GrantGate.acknowledged_answer?(answer)

        gate.record!(slug: entry.slug, terms: entry.grant.terms, how: "typed")
        say "#{entry.slug}: grant acknowledged — recorded, enabling.", :green
      end

      # `nabu disable <axis|source…>`: remove entries from the config (synced
      # data stays — withdrawal is a different, existing concept). Removes any
      # entry that matches a name given, whether it is an axis name or a slug.
      def run_disable(config, registry, names, catalog:)
        profile = effective_profile(config, registry, catalog: catalog)
        removed = profile.entries & names
        Nabu::Profile.new(profile.entries - names).save(config.profile_path)
        announce_enablement(config, registry, verb: "disabled", changed: removed, catalog: catalog)
      end

      # Confirm a write: what changed, then the current enabled set.
      def announce_enablement(config, registry, verb:, changed:, catalog:)
        say(changed.empty? ? "nothing #{verb} (already so)" : "#{verb}: #{changed.sort.join(', ')}")
        show_enablement(effective_profile(config, registry, catalog: catalog), registry)
      end

      # The current enabled set: axes vs sources distinguished, drift flagged,
      # and the resolved source count — or the honest empty-state.
      def show_enablement(profile, registry)
        resolution = Nabu::Focus.resolve(profile, registry)
        return say(Nabu::Focus.empty_state_line) if resolution.slugs.empty?

        count = profile.entries.size
        say "enabled (#{count} #{count == 1 ? 'entry' : 'entries'}):"
        say "  axes:    #{resolution.axes.join(', ')}" unless resolution.axes.empty?
        say "  sources: #{resolution.sources.join(', ')}" unless resolution.sources.empty?
        unless resolution.unknown.empty?
          say "  unknown: #{resolution.unknown.join(', ')} (not a known axis or source — ignored)"
        end
        shown = resolution.slugs.count { |slug| !registry[slug]&.feature_module? }
        say "resolved: #{pluralize(shown, 'source')} enabled (nabu status shows them; --all shows everything)"
      end

      def selected_axes(axis_registry)
        if axis_registry.empty?
          raise Thor::Error, "list: no research axes are defined (config/axes.yml) — --axis needs the registry"
        end

        spec = options[:axis].to_s.strip
        return axis_registry.each_axis.to_a if spec.empty?

        spec.split(",").map(&:strip).reject(&:empty?).uniq.map do |name|
          axis_registry[name] ||
            raise(Thor::Error, "list: unknown axis #{name.inspect} — known axes: #{axis_registry.names.join(', ')}")
        end
      end

      # `list --axis` (P35-1): the census grouped under the research axes
      # (the owner's desks, config/axes.yml). The tag-semantics note is
      # stated once up front; each axis leads with its VERBATIM persona line
      # (P35-0 first-class render data) and then the SAME census rows the
      # flat view prints, indented — a source under every axis it serves
      # (dual-tagging, D35). An axis with nothing held yet says so honestly.
      # Slug width is global so alignment is stable across groups.
      def print_census_by_axis(rows, axes, registry)
        return say("nothing held yet — run nabu sync") if rows.empty?

        width = rows.map { |row| row.slug.length }.max
        say AXIS_TAG_NOTE
        axes.each do |axis|
          say ""
          say "#{axis.name} — #{axis.persona}"
          members = rows.select { |row| registry[row.slug]&.axes&.include?(axis.name) }
          if members.empty?
            say "  (nothing held on this axis yet)"
          else
            members.each { |row| say "  #{row.slug.ljust(width)}  #{census_fragments(row).join('  ')}" }
          end
        end
        say ""
        say census_summary(rows)
      end

      # Compact census fragments, zero fields suppressed (conventions §10).
      def census_fragments(row)
        parts = []
        parts << "docs=#{row.docs}#{" pass=#{row.passages}" if row.passages.positive?}" if row.docs.positive?
        parts << "entries=#{row.entries}" if row.entries.positive?
        parts << "dossiers=#{row.dossiers}" if row.dossiers.positive?
        parts << "empty" if parts.empty?
        parts << "langs=#{census_langs(row.languages)}" unless row.languages.empty?
        parts << "license=#{row.license_classes.join(',')}"
        parts << "withdrawn=#{row.withdrawn}" if row.withdrawn.positive?
        parts << "retired=#{row.retired}" if row.retired.positive?
        parts
      end

      # The codes when few, the count when the list would swamp the row.
      def census_langs(codes)
        codes.size <= 3 ? codes.join(",") : codes.size.to_s
      end

      def census_summary(rows)
        parts = [pluralize(rows.size, "source"), "#{rows.sum(&:docs)} docs", "#{rows.sum(&:passages)} passages"]
        entries = rows.sum(&:entries)
        parts << "#{entries} entries" if entries.positive?
        parts.join(" · ")
      end

      # Bare `nabu axis` (P37-8): one line per desk — name and persona — in
      # ratified (file) order, the `nabu language --list` mold. The full card
      # is one `nabu axis NAME` away.
      def print_axis_list(axes)
        say "research axes — the library's desks (#{axes.size}):"
        width = axes.names.map(&:length).max || 0
        axes.each_axis { |axis| say "  #{axis.name.ljust(width)}  #{axis.persona}" }
        say "nabu axis NAME for the full desk card (members, holdings, gold coverage)"
      end

      # `nabu axis NAME` (P37-8): the research-axis desk card, the `nabu
      # language` mold pointed at a whole desk. The persona rides verbatim
      # (first-class render data), then the membership rationale (desc); then
      # every member the desk tags with its enablement (on/off, from the
      # authoritative registry) and its live holdings (the same census
      # fragments `nabu list` prints); then the aggregate gold-lemma coverage
      # across the desk's held languages; then the shipped affordances. Zero
      # fields suppressed — a member holding nothing says so, a desk with no
      # gold says so, no corpus at all still prints persona + membership.
      def print_axis_card(axis, registry:, census:, info:)
        say "#{axis.name} — #{axis.persona}"
        say_wrapped(axis.desc, indent: 2)
        members = registry.axis_members(axis.name)
        by_slug = (census || []).to_h { |row| [row.slug, row] }
        say "  members (#{members.size}):"
        width = members.map(&:length).max || 0
        members.each do |slug|
          entry = registry[slug]
          # P46-r1: a kind: module row is PERMANENTLY wired: false (nothing
          # mints, nothing to flip) — its cell names the nature; "unwired"
          # is reserved for adapters genuinely awaiting first-sync proof.
          state = if entry&.feature_module?
                    "module "
                  else
                    entry&.wired ? "wired  " : "unwired"
                  end
          say "    #{slug.ljust(width)}  #{state}  #{axis_member_holdings(by_slug[slug], census: census)}"
        end
        print_axis_languages(members, info)
        print_axis_gold(members, by_slug, info, registry: registry)
        say "  commands: nabu list --axis #{axis.name} · nabu sync #{axis.name}"
      end

      # The desk's held language codes (P48-r3): one merged doc-or-entry
      # count per code over the member sources, holdings descending. The
      # counts ARE the honesty mechanism — a multilingual pack's 3-doc
      # spillover reads as 3 beside a 40K holding, never hidden. No catalog,
      # no line (the member cells already say "no database"); a desk holding
      # nothing says so.
      # P49-r4, the deliberate asymmetry: this line KEEPS multilingual pack
      # members (the counts self-explain), while the count-less attribution
      # surfaces (print_language_axes, print_axis_gold) exclude them.
      def print_axis_languages(members, info)
        return unless info

        holdings = info.language_holdings_for(members)
        return say("  languages: none held yet") if holdings.empty?

        shown = options[:long] ? holdings : holdings.first(AXIS_LANGUAGES_ITEMS)
        line = shown.map { |code, count| "#{code} #{commas(count)}" }.join(" · ")
        hidden = holdings.size - shown.size
        line += " … and #{hidden} more (--long lists all)" if hidden.positive?
        say "  languages: #{line}"
      end

      # One member's holdings cell: the census fragments when the source holds
      # something, an honest "nothing held yet" when it is in the registry but
      # empty, and "no database" when the corpus was never built.
      def axis_member_holdings(row, census:)
        return "no database (run nabu sync)" if census.nil?
        return "nothing held yet" if row.nil?

        census_fragments(row).join("  ")
      end

      # The desk's aggregate gold-lemma coverage: gold lemma rows summed over
      # the languages its members actually hold (nabu search --lemma). Honest
      # zero when the held languages carry no gold, honest "no held languages"
      # when the desk holds nothing dated in a language yet.
      # P49-r4: languages reachable ONLY via multilingual pack members stay
      # off the gold claim — the same exclusion rule (and the same rejected-
      # threshold reasoning) as the language card's axes: line, so the hebrew
      # desk stops claiming a treebank pack's kat/phn/xcl gold rows. The
      # languages: line above deliberately KEEPS pack holdings: its per-code
      # counts self-explain a three-doc spillover; this count-less language
      # list cannot.
      def print_axis_gold(members, by_slug, info, registry:)
        attributable = members.reject { |slug| registry.multilingual?(slug) }
        langs = attributable.flat_map { |slug| by_slug[slug]&.languages || [] }.uniq.sort
        return say("  gold lemmas: no held languages yet") if langs.empty?

        total = info ? info.gold_rows_for(langs) : 0
        if total.positive?
          say "  gold lemmas: #{commas(total)} rows across #{langs.join(', ')} (nabu search --lemma)"
        else
          say "  gold lemmas: none in the held languages (#{langs.join(', ')})"
        end
      end

      # P28-4: the one-page grouped map (`list --sources`) — family headers,
      # `slug — first sentence` lines (the dossier description, ~100 chars,
      # honest ellipsis), (off) tags from the REGISTRY (P23-3b: registry
      # authoritative for enablement; catalog value only for orphans), one
      # footer pointing deeper. Descriptions are the payload — no counts.
      def print_source_map(groups, registry)
        return say("nothing held yet — run nabu sync") if groups.empty?

        groups.each_with_index do |(group, lines), index|
          say "" if index.positive?
          say group
          lines.each { |line| say "  #{source_map_line(line, registry)}" }
        end
        say ""
        say "nabu list SLUG for the full card · docs/library.md for the survey"
      end

      def source_map_line(line, registry)
        entry = registry[line.slug]
        wired = entry ? entry.wired : line.enabled
        off = wired ? "" : " (unwired)"
        return "#{line.slug}#{off} — no description; nabu ingest --shelf source #{line.slug}" unless line.description

        "#{line.slug}#{off} — #{truncate_line(first_sentence(line.description))}"
      end

      # The first sentence of a dossier description: up to the first
      # terminal punctuation followed by whitespace; the whole prose when
      # it is a single sentence.
      def first_sentence(text)
        prose = text.tr("\n", " ").squeeze(" ").strip
        prose[/\A.*?[.!?](?=\s)/] || prose
      end

      def print_list_card(card, entry)
        say "#{card.slug} — #{card.name}"
        wrap_text(card.description).each { |line| say "  #{line}" } if card.description
        say "  adapter #{card.adapter_class}#{registry_fragment(entry)}"
        credit = card.license_text.to_s.strip
        say "  license #{card.license_classes.join(',')}#{" · #{truncate_line(credit)}" unless credit.empty?}"
        say "  #{card_counts(card)}"
        say "  langs #{card.languages.map { |code, n| "#{code}=#{n}" }.join(' ')}" unless card.languages.empty?
        say "  records #{card.record_kinds.map { |kind, n| "#{kind}=#{n}" }.join(' ')}" \
          unless card.record_kinds.empty?
        card.dictionaries.each do |dict|
          say "  dict #{dict.slug} — #{dict.title} [#{dict.language}] entries=#{dict.entries}"
        end
        print_card_axes(card)
      end

      # Registry facts on the header line; a catalog source missing from the
      # registry is abnormal and reads loudly. Kind-aware (P39-0): a shelf reads
      # local memory, a module reads machinery — neither has a cadence or an
      # enablement to show.
      def registry_fragment(entry)
        return " · NOT IN REGISTRY" if entry.nil?
        return " · shelf · local memory" if entry.shelf?
        return " · module · machinery (no catalog rows)" if entry.feature_module?

        " · source · sync #{entry.sync_policy} · #{entry.wired ? 'wired' : 'unwired'}"
      end

      def card_counts(card)
        parts = []
        parts << "docs=#{card.docs}" if card.docs.positive?
        parts << "pass=#{card.passages}" if card.passages.positive?
        parts << "entries=#{card.entries}" if card.entries.positive?
        parts << "dossiers=#{card.dossiers}" if card.dossiers.positive?
        parts << "withdrawn=#{card.withdrawn}" if card.withdrawn.positive?
        parts << "retired=#{card.retired}" if card.retired.positive?
        parts.empty? ? "empty" : parts.join(" ")
      end

      # The optional card layers: timeline coverage, facet summary, and the
      # collections census (inlined when small, deferred to --collections
      # when it would swamp the card).
      def print_card_axes(card)
        if card.dated
          say "  dated #{pluralize(card.dated.docs, 'doc')} #{card.dated.min || 'open'}..#{card.dated.max || 'open'}"
        end
        unless card.facets.empty?
          say "  facets #{card.facets.map { |f| "#{f.facet}=#{f.values} values/#{f.docs} docs" }.join(' · ')}"
        end
        return if card.collections.nil?

        if card.collections.size <= 8
          say "  collections #{format_collections(card.collections).join(' ')}"
        else
          say "  collections #{card.collections.size} (see --collections)"
        end
      end

      def format_collections(counts)
        counts.sort_by { |name, count| [-count, name] }.map { |name, count| "#{name}=#{count}" }
      end

      def print_list_documents(page)
        return say("no documents match") if page.rows.empty?

        page.rows.each do |row|
          if row.is_a?(Nabu::Query::List::DossierRow)
            say "#{row.code}#{" — #{row.name}" if row.name}#{" [#{row.family}]" if row.family}"
          else
            flags = "#{' (withdrawn)' if row.withdrawn}#{' (retired upstream)' if row.retired}"
            say "#{row.urn} — #{row.title}#{" [#{row.language}]" if row.language} #{row.license_class}#{flags}"
          end
        end
        print_list_tail(page)
      end

      def print_list_entries(slug, page)
        return say("#{slug} holds no dictionary entries (a passage shelf) — try --documents") if page.nil?
        return say("no entries match") if page.rows.empty?

        page.rows.each do |row|
          gloss = row.gloss.to_s.gsub(/\s+/, " ").strip
          say "#{row.headword} [#{row.dictionary_slug}]#{" — #{truncate_line(gloss)}" unless gloss.empty?}"
        end
        print_list_tail(page)
      end

      # The loans census (P34-2): one row per loan-origin code, token-count
      # order — read straight off the stored P17-1 annotations, no reparse.
      def print_list_loans_census(slug, rows)
        if rows.empty?
          return say("no loan annotations in #{slug} passages (the language-of-origin layer — " \
                     "Coptic Scriptorium parses carry it)")
        end

        width = rows.map { |row| row.code.length }.max
        rows.each do |row|
          say "#{row.code.ljust(width)}  tokens=#{row.tokens}  passages=#{row.passages}  docs=#{row.docs}"
        end
      end

      # `list SOURCE --loans CODE`: the saturation enumeration, most
      # loan-token-heavy documents first.
      def print_list_loan_documents(code, page)
        return say("no documents carry #{code} loan tokens") if page.rows.empty?

        page.rows.each do |row|
          say "#{row.urn} — #{row.title}#{" [#{row.language}]" if row.language} " \
              "tokens=#{row.tokens} passages=#{row.passages}"
        end
        print_list_tail(page)
      end

      def print_list_collections(slug, counts)
        if counts.nil?
          return say("no collection segments in #{slug} document urns " \
                     "(manifest-collection shelves — local-library — carry them)")
        end

        width = counts.keys.map(&:length).max
        format_collections(counts).each do |pair|
          name, count = pair.split("=", 2)
          say "#{name.ljust(width)}  docs=#{count}"
        end
      end

      # The honest truncation tail every list enumeration shares.
      def print_list_tail(page)
        more = page.total - page.rows.size
        say "… #{more} more — raise --limit (0 = all)" if more.positive?
      end

      # Export format gate. CoNLL-U is a first-class exit format (maintenance
      # §7) but needs the token model, so it is deferred to the enrichment
      # phase with an explicit message rather than a generic "unknown format".
      def validate_format!(format)
        raise Thor::Error, "export: --format conllu is deferred until the enrichment phase" if format == "conllu"
        return format if Nabu::Query::Export::FORMATS.include?(format)

        raise Thor::Error,
              "export: unknown format #{format.inspect} " \
              "(choose from #{Nabu::Query::Export::FORMATS.join(', ')})"
      end

      # Render `verify`: one line per source (OK with a count, or FAILED with
      # its itemized issues), then any never-synced skips, then a verdict.
      def print_verify(result)
        result.outcomes.each { |outcome| print_verify_outcome(outcome) }
        result.skips.each { |skip| say "  skip    #{skip.slug} (no canonical data — never synced)" }
        say(result.clean? ? "All canonical documents verified against the catalog." : "Integrity check FAILED.")
      end

      def print_verify_outcome(outcome)
        if outcome.ok?
          say "  OK      #{outcome.slug}  (#{pluralize(outcome.verified, 'document')} verified)"
        else
          say "  FAILED  #{outcome.slug}  (#{outcome.verified} checked, #{pluralize(outcome.issues.size, 'issue')})"
          outcome.issues.each { |issue| say "    #{format_verify_issue(issue)}" }
        end
      end

      def format_verify_issue(issue)
        case issue.kind
        when :mismatch
          "MISMATCH    #{issue.urn}  stored #{issue.detail.fetch(:stored)[0, 12]} != " \
          "recomputed #{issue.detail.fetch(:recomputed)[0, 12]}  (#{issue.canonical_path})"
        when :missing
          "MISSING     #{issue.urn}  (#{issue.canonical_path})"
        when :unparseable
          "UNPARSEABLE #{issue.urn}  #{issue.detail}  (#{issue.canonical_path})"
        end
      end

      def verify_failure_summary(result)
        "verify: #{pluralize(result.issues.size, 'document')} failed the integrity check"
      end

      def pluralize(count, noun) = "#{count} #{noun}#{'s' unless count == 1}"

      # Render `backup`: the target + mode banner, one line per section (name,
      # status, files/size/duration or the failure detail), then a summary.
      def print_backup(result)
        say "#{result.dry_run ? 'Backup plan (dry run — nothing changes)' : 'Backup'} → #{result.target}"
        result.sections.each { |section| say "  #{format_backup_section(section)}" }
        say "  #{backup_summary(result)}"
      end

      def format_backup_section(section)
        label = section.name.ljust(10)
        case section.status
        when :ok
          "#{label} #{section.status.to_s.ljust(8)} #{pluralize(section.files, 'file')}, " \
          "#{human_bytes(section.bytes)}  (#{format('%.2fs', section.duration)}) → #{section.dest}"
        when :skipped
          "#{label} #{'skipped'.ljust(8)} #{section.detail} (#{section.source})"
        else
          "#{label} #{'FAILED'.ljust(8)} #{section.detail}"
        end
      end

      def backup_summary(result)
        verb = result.dry_run ? "would back up" : "backed up"
        base = "#{verb} #{pluralize(result.files, 'file')}, #{human_bytes(result.bytes)} " \
               "in #{format('%.2fs', result.duration)}"
        result.ok? ? "#{base} — OK" : "#{base} — #{pluralize(result.failed.size, 'section')} FAILED"
      end

      def backup_failure_summary(result)
        "backup: #{pluralize(result.failed.size, 'section')} failed — #{result.failed.map(&:name).join(', ')}"
      end

      def human_bytes(bytes)
        units = %w[B KB MB GB TB]
        size = bytes.to_f
        unit = 0
        while size >= 1024 && unit < units.size - 1
          size /= 1024
          unit += 1
        end
        unit.zero? ? "#{bytes} B" : "#{format('%.1f', size)} #{units[unit]}"
      end

      # `show --random` (P11-9): N random visible passages, each in the standard
      # passage layout — the eyeball ritual at a source flip. A urn alongside
      # --random is contradictory (it picks passages for you); an empty result
      # is an honest note, not an error.
      def show_random(catalog, urn, config)
        raise Thor::Error, "show: --random takes no urn (it picks passages for you)" unless urn.empty?
        return show_random_parallel(catalog, config) if options[:parallel]

        results = Nabu::Query::Random.new(catalog: catalog)
                                     .run(source: options[:source], lang: options[:lang], count: options[:count].to_i)
        if results.empty?
          scope = +""
          scope << " in source #{options[:source]}" if options[:source]
          scope << " in #{options[:lang]}" if options[:lang]
          return say("no passages to show#{scope} (nothing visible — the corpus may be empty or all withdrawn)")
        end

        results.each_with_index do |result, index|
          say "" if index.positive?
          print_show_passage(result)
        end
      end

      # P47-r1 (owner: "elephantine is perfect for --parallel showcase!"):
      # --random composes with --parallel — draw ORIGINALS (the sampler
      # already excludes translation siblings) until one carries a parallel
      # in the requested language, render the paired view; a scope that
      # yields none in the attempt budget (12 draws per requested passage —
      # a retry bound, not a corpus claim) says so honestly.
      def show_random_parallel(catalog, config)
        random = Nabu::Query::Random.new(catalog: catalog)
        journal = Nabu::Store::LinksJournal.open_readonly(config.links_path)
        parallel = Nabu::Query::Parallel.new(catalog: catalog, journal: journal)
        wanted = options[:count].to_i.clamp(1, Nabu::Query::Random::MAX_COUNT)
        shown = []
        attempts = 0
        while shown.size < wanted && attempts < wanted * 12
          attempts += 1
          draw = random.run(source: options[:source], lang: options[:lang], count: 1).first
          break if draw.nil?
          next if shown.include?(draw.urn)

          # A draw whose translation edge cannot serve the requested lang is
          # simply not a parallel-bearing draw (P48-r2) — keep drawing.
          pair = begin
            parallel.run(draw.urn, lang: options[:parallel])
          rescue Nabu::Query::Parallel::TranslationMismatch
            nil
          end
          next if pair.nil? || pair.right.nil?

          say "" unless shown.empty?
          print_parallel(pair)
          shown << draw.urn
        end
        return unless shown.empty?

        scope = options[:source] ? " in source #{options[:source]}" : ""
        say "no parallel-bearing draw#{scope} after #{attempts} attempts — the scope may hold no " \
            "#{options[:parallel]} siblings (`show <urn> --parallel` pairs a known document; " \
            "`show --random` alone draws unpaired)"
      ensure
        journal&.disconnect
      end

      # Render `show`: a passage in the context of its document, or a document
      # header plus its passages in sequence. Withdrawn items ARE shown, tagged.
      def print_show(result)
        case result
        when Nabu::Query::Show::PassageResult then print_show_passage(result)
        when Nabu::Query::Show::DocumentResult then print_show_document(result)
        when Nabu::Query::Show::RangeResult then print_show_range(result)
        when Nabu::Query::Define::Result then print_define_entry(result)
        end
      end

      # `show --segmented` (P54-2): the result with every passage text
      # word-broken through Query::Show#segmented_text — a copy, so every
      # existing print path renders unchanged (tokens verbatim, spaces at
      # word boundaries). Only reached when the segmentation note is nil
      # (a Tibetan row with the nabu-data dataset synced).
      def segmented_show_result(query, result)
        case result
        when Nabu::Query::Show::PassageResult
          result.with(text: query.segmented_text(result.text))
        when Nabu::Query::Show::DocumentResult, Nabu::Query::Show::RangeResult
          result.with(passages: result.passages.map { |line| line.with(text: query.segmented_text(line.text)) })
        else
          result
        end
      end

      # The source-level credit line (P43-2, the grant's "clearly indicated
      # wherever displayed" duty), shown only when the source carries one — a
      # nil/blank credit (every ordinary source) prints nothing.
      def print_credit(result)
        credit = result.credit.to_s.strip
        say "  credit: #{credit}" unless credit.empty?
      end

      # P44-7: the meter line — shown only when the passage carries a scansion
      # enrichment (pedecerto over held Perseus-Latin verse), byte-identical
      # absence otherwise. "meter: H DSDS (pedecerto)": metrical code, foot
      # pattern (omitted when empty), producer.
      def print_meter(passage)
        meter = passage.meter
        return if meter.nil?

        pattern = meter.pattern.to_s.strip
        code = [meter.meter.to_s.strip, pattern].reject(&:empty?).join(" ")
        say "  meter: #{code} (#{meter.producer})"
      end

      # Render `place` (P44-2): one card per matched place — headline,
      # holdings per source — then the labelled unlinked tail once. The
      # spec shape: "Lilybaeum, Pleiades 462281 — settlement · archaic…roman
      # · 37.80, 12.43" over "holdings: 214 isicily · 12 edh · 2 iip".
      def print_place(result)
        result.cards.each_with_index do |card, index|
          say "" if index.positive?
          print_place_card(card, dump_loaded: result.dump_loaded)
        end
        return if result.unlinked.empty?

        say "  unlinked findspot mentions of #{result.unlinked_term.inspect} " \
            "(text match, no Pleiades id — not counted above): #{format_source_counts(result.unlinked)}"
      end

      def print_place_card(card, dump_loaded:)
        place = card.place
        if place
          say "#{place.title}, Pleiades #{place.id}#{place_card_tail(place)}"
        elsif dump_loaded
          say "Pleiades #{card.pleiades_id} — not in the local gazetteer dump"
        else
          say "Pleiades #{card.pleiades_id} — gazetteer dump not synced " \
              "(`nabu sync pleiades` adds the card)"
        end
        say "  holdings: #{card.holdings.empty? ? 'none' : format_source_counts(card.holdings)}"
      end

      # " — types · first…last period · lat, lon", each section only when
      # the dump carries it. Periods render as the attested span endpoints
      # (dump attestation order, not re-sorted — honest to upstream).
      def place_card_tail(place)
        sections = [
          place.place_types.join(" · "),
          period_span(place.time_periods),
          place.lat && place.lon ? format("%<lat>.2f, %<lon>.2f", lat: place.lat, lon: place.lon) : nil
        ].compact.reject(&:empty?)
        sections.empty? ? "" : " — #{sections.join(' · ')}"
      end

      def period_span(periods)
        return nil if periods.nil? || periods.empty?
        return periods.first if periods.size == 1

        "#{periods.first}…#{periods.last}"
      end

      def format_source_counts(counts)
        counts.map { |slug, count| "#{count} #{slug}" }.join(" · ")
      end

      # P44-2: the findspot line — shown only when the document's parse-
      # captured Pleiades id resolves through the local gazetteer dump
      # (title + place types; maps and coordinate math are out by design).
      # Absent dump, absent id, unknown id: no line, byte-identical output.
      def print_findspot(result)
        spot = result.findspot
        return if spot.nil?

        types = spot.place_types.empty? ? "" : " (#{spot.place_types.join(' · ')})"
        say "  findspot: #{spot.title} — Pleiades #{spot.id}#{types}"
      end

      # P61-3 (D60-b): the artifact-script line — only where the original
      # artifact's script DIFFERS from the held surface (the lane is minted
      # on difference by construction). Tag + config note, honest and short.
      def print_artifact(result)
        artifact = result.artifact
        return if artifact.nil?

        note = artifact.note ? " — #{artifact.note}" : ""
        say "  artifact script: #{artifact.script}#{note} (held surface differs; see the lect ~axis)"
      end

      def print_show_passage(passage)
        say "#{passage.urn}#{" [#{passage.language}]" if passage.language}#{withdrawn_tag(passage.withdrawn)}"
        say "  #{display_text(painted_passage_text(passage), passage.language,
                              source: passage.source_slug, annotations: passage.annotations)}"
        say "  document: #{passage.document_urn}#{" — #{passage.document_title}" if passage.document_title}"
        say "  source: #{passage.source_slug}   license: #{passage.license_class}   " \
            "sequence: #{passage.sequence}   revision: #{passage.revision}"
        print_credit(passage)
        print_timeline(passage.timeline)
        print_findspot(passage)
        print_meter(passage)
        # H9 (P35-6): a corrupt annotation lane announces itself instead of
        # posing as an unannotated passage.
        say "  note: #{ANNOTATIONS_UNREADABLE_NOTE}" if annotations_unreadable?(passage)
        return if passage.provenance.empty?

        say "  provenance:"
        passage.provenance.each do |event|
          say "    #{event.at}  #{event.event}#{"  #{event.tool}" if event.tool}"
        end
      end

      # `show URN --tokens` (P35-6, the journaled gate find): the honest RAW
      # view of the stored token annotations — one line per token, `form`
      # first, then EVERY other key exactly as stored (lemma/gloss/osm/lang/
      # …, nested values as compact JSON). No display transforms, no
      # invention; a passage without tokens, and a non-passage grain, both
      # say so instead of rendering nothing.
      def print_show_tokens(result)
        unless result.is_a?(Nabu::Query::Show::PassageResult)
          return say "--tokens renders at passage grain — give a passage urn"
        end
        return say ANNOTATIONS_UNREADABLE_NOTE if annotations_unreadable?(result)

        tokens = result.annotations["tokens"]
        tokens = tokens.is_a?(Array) ? tokens.grep(Hash) : []
        return say "no token annotations stored for this passage" if tokens.empty?

        say "tokens (#{tokens.size}):"
        tokens.each { |token| say "  #{token_line(token)}" }
      end

      # One token as `form=… key=…` pairs, form first, stored key order after,
      # non-scalar values as compact JSON — verbatim, never interpreted.
      def token_line(token)
        keys = (["form"] + token.keys).uniq.select { |key| token.key?(key) }
        keys.map do |key|
          value = token[key]
          "#{key}=#{value.is_a?(String) ? value : JSON.generate(value)}"
        end.join("  ")
      end

      def annotations_unreadable?(result)
        result.annotations[Nabu::Query::Show::ANNOTATIONS_UNREADABLE] == true
      end

      def print_unreadable_annotations_count(lines)
        count = lines.count { |line| annotations_unreadable?(line) }
        return unless count.positive?

        say "  note: #{count} #{count == 1 ? 'passage carries' : 'passages carry'} " \
            "unreadable stored annotations (invalid JSON) — skipped"
      end

      def print_show_document(document)
        title = document.title ? " — #{document.title}" : ""
        lang = document.language ? " [#{document.language}]" : ""
        say "#{document.urn}#{title}#{lang}#{withdrawn_tag(document.withdrawn)}#{retired_tag(document)}"
        say "  source: #{document.source_slug}   license: #{document.license_class}   revision: #{document.revision}"
        print_credit(document)
        print_timeline(document.timeline)
        print_findspot(document)
        print_artifact(document)
        print_facets(document.facets)
        say "  passages (#{document.passages.size}):"
        document.passages.each do |line|
          say "    #{passage_label(document, line)}#{withdrawn_tag(line.withdrawn)}  " \
              "#{display_text(line.text, document.language,
                              source: document.source_slug, annotations: line.annotations)}"
        end
        print_unreadable_annotations_count(document.passages)
      end

      # Render a range (P7-6): the document header like a document listing, an
      # honest "[N of M passages]" note plus the two endpoint urns, then the
      # inclusive slice as :suffixes (--full-urn restores absolute urns).
      def print_show_range(range)
        title = range.title ? " — #{range.title}" : ""
        lang = range.language ? " [#{range.language}]" : ""
        say "#{range.urn}#{title}#{lang}#{withdrawn_tag(range.withdrawn)}#{retired_tag(range)}"
        say "  source: #{range.source_slug}   license: #{range.license_class}   revision: #{range.revision}"
        print_credit(range)
        print_timeline(range.timeline)
        say "  range: #{range.start_urn} … #{range.end_urn}  " \
            "[#{range.passages.size} of #{range.total} passages]"
        range.passages.each do |line|
          say "    #{passage_label(range, line)}#{withdrawn_tag(line.withdrawn)}  " \
              "#{display_text(line.text, range.language,
                              source: range.source_slug, annotations: line.annotations)}"
        end
        print_unreadable_annotations_count(range.passages)
      end

      # The timeline line (P15-2), when the document has one. A date span
      # ("113 BCE", "501–700 CE", "≤ 257 BCE") with the informative precision
      # ("low"/"high", not the derived exact/range/year) and the provenance
      # place; place-only rows print as "place:". Undated documents print
      # nothing (an absence, never an error).
      def print_timeline(timeline)
        return if timeline.nil?

        span = Nabu::Timeline.format_span(timeline.not_before, timeline.not_after)
        place = timeline.place_name ? " · #{timeline.place_name}" : ""
        if span
          note = %w[exact range year].include?(timeline.precision) ? "" : " (#{timeline.precision})"
          say "  date: #{span}#{note}#{place}"
        elsif timeline.place_name
          say "  place: #{timeline.place_name}"
        end
      end

      # The facets line (P17-2), one compact line and only when faceted:
      # "facets: genre=epitaph (titsep) · province=Latium et Campania …". The
      # raw code rides in parentheses when it differs from the value (the `?`
      # certainty stays visible).
      def print_facets(facets)
        return if facets.nil? || facets.empty?

        rendered = facets.map do |facet|
          raw = facet.raw && facet.raw != facet.value ? " (#{facet.raw})" : ""
          "#{facet.facet}=#{facet.value}#{raw}"
        end
        say "  facets: #{rendered.join(' · ')}"
      end

      # Print practice: the document urn appears once in the header, each
      # passage line carries only its changing :suffix (":b2:5"). --full-urn
      # restores absolute urns (copy-paste into `show`/scripts). A passage
      # whose urn doesn't extend the document urn (never minted by our
      # adapters, but data is data) falls back to the full urn.
      def passage_label(document, line)
        return line.urn if options[:full_urn]

        suffix = line.urn.delete_prefix(document.urn)
        suffix == line.urn || suffix.empty? ? line.urn : suffix
      end

      # -- show --parallel (P7-4) ------------------------------------------

      # Resolve + align + render, with the honest failure modes: unknown urn
      # (exit 1, same message as plain show), no LANG sibling or translation
      # edge in the catalog (exit 1, names the language), and a translation
      # edge that cannot serve LANG (exit 1 via TranslationMismatch, naming
      # the language that would work). The links journal rides along
      # read-only so the P48-r2 kind=translation edges (Kangyur↔84000) pair
      # cross-source with no extra flag.
      def show_parallel(catalog, urn, lang, config)
        journal = Nabu::Store::LinksJournal.open_readonly(config.links_path)
        result = Nabu::Query::Parallel.new(catalog: catalog, journal: journal).run(urn, lang: lang)
        raise Thor::Error, "urn not found: #{urn}" if result.nil?
        if result.right.nil?
          raise Thor::Error, "no #{lang} parallel edition of this work in the catalog for #{urn} " \
                             "(--parallel pairs sibling CTS editions within one source, or " \
                             "cross-source over a kind=translation link edge; is " \
                             "`translations: true` set and the source resynced?)#{align_hint(urn, config)}"
        end

        print_parallel(result)
      ensure
        journal&.disconnect
      end

      # Cosmetic rider (P11-8): --parallel's "is translations: true set" hint is
      # misleading for a CROSS-source text (Vulgate/LXX/WEB have no sibling CTS
      # edition to pair). When the urn is a registered alignment witness, point
      # at `nabu align` instead — the hub built for exactly this.
      def align_hint(urn, config)
        registry = Nabu::AlignmentRegistry.load(config.alignments_path)
        witnessed = registry.works.any? do |work|
          work.witnesses.any? do |witness|
            witness.document_urns.any? { |doc| urn == doc || urn.start_with?("#{doc}:") }
          end
        end
        witnessed ? " — this text is an alignment-hub witness; try `nabu align REF` for cross-source alignment" : ""
      rescue Nabu::ValidationError
        ""
      end

      # Render the alignment (P8-1b span-grouped): both document headers, the
      # paired/blocks/one-sided counts, then one span-group at a time. A verse
      # pair keeps the compact pair form (byte-identical to pre-P8-1b); a coarse
      # block prints the original lines first, then the translation once with
      # its full coverage (and a clip note when a slice shows only part of it);
      # one-sided rows dash the missing side. Withdrawn passages are shown,
      # tagged (show-family).
      def print_parallel(result)
        say format_parallel_side(result.left)
        say "  parallel: #{format_parallel_side(result.right)}"
        say "  #{parallel_counts(result)}"
        width = [result.left.language.to_s.length, result.right.language.to_s.length].max + 2
        result.groups.each { |group| print_parallel_group(group, result, width) }
      end

      def print_parallel_group(group, result, width)
        case group.kind
        when :pair        then print_parallel_pair(group, result, width)
        when :block       then print_parallel_block(group, result, width)
        when :original    then print_parallel_one_sided(group, result, width, side: :left)
        when :translation then print_parallel_one_sided(group, result, width, side: :right)
        end
      end

      # Verse pair / one-sided rows: the pre-P8-1b two-line form, the suffix (or
      # absolute urn under --full-urn) over one line per language, "—" for the
      # absent side. Kept byte-identical so verse-for-verse output never shifts.
      def print_parallel_pair(group, result, width)
        line = group.originals.first
        say "  #{options[:full_urn] ? line.urn : group.anchor}"
        say "    #{parallel_line(result.left.language, line, width)}"
        say "    #{parallel_line(result.right.language, group.translation, width)}"
      end

      def print_parallel_one_sided(group, result, width, side:)
        present = side == :left ? group.originals.first : group.translation
        say "  #{options[:full_urn] ? present.urn : present.suffix}"
        left = side == :left ? present : nil
        right = side == :right ? present : nil
        say "    #{parallel_line(result.left.language, left, width)}"
        say "    #{parallel_line(result.right.language, right, width)}"
      end

      # Coarse block: each owned original as a suffix-labeled left line, then
      # the translation once, labeled with its full coverage in the original's
      # numbering plus a clip note when the shown slice is only part of it.
      def print_parallel_block(group, result, width)
        group.originals.each do |line|
          say "  #{options[:full_urn] ? line.urn : line.suffix}"
          say "    #{parallel_line(result.left.language, line, width)}"
        end
        say "  #{result.right.language} #{block_coverage(group)}"
        say "    #{display_text(group.translation.text, result.right.language)}" \
            "#{withdrawn_tag(group.translation.withdrawn)}"
      end

      # `[:1.1 — covers :1.1–:1.43; range shows :1.5–:1.10]` — the anchor, the
      # full ownership span, and (only when clipped) the shown sub-range.
      def block_coverage(group)
        covers = "covers #{group.covers_first}–#{group.covers_last}"
        clip = group.clipped ? "; range shows #{group.shown_first}–#{group.shown_last}" : ""
        "[#{group.anchor} — #{covers}#{clip}]"
      end

      # -- align (P11-3) ----------------------------------------------------

      # Render the cross-source alignment: the ref + work header with an
      # honest attestation count, then one block per witness in registry
      # order — title, language, license label, and the sentences (urn line,
      # text line), a multi-verse sentence labeled with its full span.
      def print_align(result)
        return print_align_range(result) if result.is_a?(Nabu::Query::Align::RangeResult)

        attesting = result.witnesses.count { |witness| witness.status == :ok }
        say "#{result.ref} — #{result.title}"
        say "  #{attesting} of #{result.witnesses.size} witnesses attest this ref"
        result.witnesses.each { |witness| print_align_witness(witness, result.ref) }
      end

      # A range/chapter query (P11-8): the query header, a one-line witness
      # legend (title/lang/license shown ONCE, not repeated per ref), then one
      # compact block per ref in document order — ref line, then one line per
      # witness (its text, or an honest not-attested/not-synced dash).
      def print_align_range(result)
        say "#{result.query} — #{result.title}"
        say "  #{result.total} refs; witnesses: #{align_range_legend(result).join('; ')}"
        say "  #{absent_range_summary(result.absent)}" unless result.absent.empty?
        if result.truncated
          say "  showing first #{result.groups.size} of #{result.total} refs " \
              "(cap #{Nabu::Query::Align::MAX_REFS}) — narrow the range, or pass --long to render all"
        end
        result.groups.each { |group| print_align_range_group(group) }
      end

      # P11-9: witnesses absent from every rendered ref are summarized here once
      # (grouped by reason) rather than dashed on every ref line — the owner's
      # readability fix. Partially-attested witnesses stay in the per-ref blocks.
      def absent_range_summary(absent)
        by_reason = absent.group_by(&:reason)
        parts = []
        if (rows = by_reason[:not_attested])
          parts << "not attested in this range: #{rows.map(&:label).join(', ')}"
        end
        if (rows = by_reason[:not_synced])
          parts << "not synced: #{rows.map(&:label).join(', ')}"
        end
        parts.join("; ")
      end

      # One legend entry per witness (registry order): its language + license
      # from the richest view across the shown refs, or "not synced" when the
      # witness holds no data anywhere in the range.
      def align_range_legend(result)
        result.groups.first.witnesses.map(&:label).map do |label|
          views = result.groups.map { |group| group.witnesses.find { |witness| witness.label == label } }
          synced = views.find { |witness| witness.status != :not_synced }
          if synced
            "#{label} [#{synced.language}] license: #{synced.license_class}#{align_numbering_note(synced)}"
          else
            "#{label} not synced"
          end
        end
      end

      def print_align_range_group(group)
        say ""
        say group.ref
        group.witnesses.each { |witness| print_align_range_witness(witness, group.ref) }
      end

      def print_align_range_witness(witness, ref)
        case witness.status
        when :not_synced then say "    #{witness.label} — not synced"
        when :no_match   then say "    #{witness.label} — not attested"
        else
          witness.sentences.each do |sentence|
            say "    #{witness.label}  #{display_text(sentence.text, witness.language)}" \
                "#{align_native_note(witness, sentence)}#{align_span_note(sentence, ref)}"
          end
        end
      end

      def print_align_witness(witness, ref)
        say ""
        if witness.status == :not_synced
          # A nil urn = a multi-book witness whose map lacks this ref's book;
          # naming an unrelated book's urn would mislead — phrase neutrally.
          detail = if witness.document_urn
                     "#{witness.document_urn} is registered but not in the catalog"
                   else
                     "its registered documents are not in the catalog"
                   end
          say "#{witness.label} — not synced (#{detail})"
          return
        end

        # A multi-document witness misses without a book to name — no title.
        say "#{witness.label}#{" — #{witness.title}" if witness.title} [#{witness.language}]   " \
            "license: #{witness.license_class}#{align_numbering_note(witness)}"
        return say "  not attested (this witness lacks #{ref})" if witness.status == :no_match

        witness.sentences.each do |sentence|
          say "  #{sentence.urn}#{align_native_note(witness, sentence)}#{align_span_note(sentence, ref)}"
          say "    #{display_text(sentence.text, witness.language)}"
        end
      end

      # "  · Hebrew (Masoretic) numbering" — flags a witness whose psalter is
      # numbered in a different system than the work vocabulary (P13-5), so the
      # reader knows its refs were remapped to align.
      def align_numbering_note(witness)
        witness.numbering ? "   · #{witness.numbering} numbering" : ""
      end

      # "  [Hebrew (Masoretic): PSA 23.1]" — the witness's OWN ref for this
      # sentence, shown only when its numbering diverges from the queried ref.
      def align_native_note(witness, sentence)
        return "" unless sentence.native_ref

        "  [#{witness.numbering}: #{sentence.native_ref}]"
      end

      # "  [covers MARK 2.3, MARK 2.4]" — only when the sentence spans beyond
      # the queried ref (sentence≠verse, stated honestly).
      def align_span_note(sentence, ref)
        return "" if sentence.refs == [ref]

        "  [covers #{sentence.refs.join(', ')}]"
      end

      # -- align --collate (P15-4) ------------------------------------------------

      # The collation apparatus (intertext-design §2): the query/work header,
      # then one block per ref — each (language, script) cell as a base reading
      # plus the per-witness divergences, uncollated cross-script/sole witnesses
      # rendered undiffed and honestly, and any missing witnesses named once.
      def print_collation(result, long:)
        say "#{result.query} — #{result.title} · collation"
        if result.truncated
          say "  showing first #{result.refs.size} of #{result.total} refs " \
              "(cap #{Nabu::Query::Align::MAX_REFS}) — narrow the range, or pass --long to render all"
        end
        result.refs.each do |ref_collation|
          say ""
          say ref_collation.ref if result.refs.size > 1
          print_collation_ref(ref_collation, long: long)
        end
      end

      def print_collation_ref(ref_collation, long:)
        say "  no witness attests this ref" if ref_collation.cells.empty? && ref_collation.asides.empty?
        ref_collation.cells.each { |cell| print_collation_cell(cell, long: long) }
        ref_collation.asides.each { |aside| print_collation_aside(aside) }
        print_collation_missing(ref_collation.missing)
      end

      # One collated cell: the base line in full, then each other witness — its
      # full tokens under --long, "(agrees with base)" when identical, else its
      # apparatus of divergences (agreements elided).
      def print_collation_cell(cell, long:)
        base = cell.readings.find(&:is_base)
        say "  [#{cell.language}/#{cell.script}] #{cell.readings.size} witnesses, base #{cell.base_label}"
        say "    = #{base.label}  #{display_text(base.tokens.join(' '), cell.language)}"
        cell.readings.reject(&:is_base).each do |reading|
          say "      #{reading.label}  #{collation_reading_body(reading, long: long, language: cell.language)}"
        end
      end

      def collation_reading_body(reading, long:, language:)
        return display_text(reading.tokens.join(" "), language) if long
        return "(agrees with base)" if reading.edits.empty?

        reading.edits.map { |edit| format_collation_edit(edit, language) }.join("; ")
      end

      # Apparatus marks: a substitution as "base → variant", an omission as
      # "om. base" (the witness lacks it), an insertion as "add. variant".
      def format_collation_edit(edit, language)
        case edit.op
        when :sub
          "#{display_text(edit.base.join(' '), language)} → #{display_text(edit.witness.join(' '), language)}"
        when :del then "om. #{display_text(edit.base.join(' '), language)}"
        when :ins then "add. #{display_text(edit.witness.join(' '), language)}"
        end
      end

      # An uncollated witness: rendered undiffed, its reason stated plainly —
      # cross-script (the fold cannot bridge the transcription systems) or the
      # sole witness of its language here.
      def print_collation_aside(aside)
        reason = if aside.reason == :cross_script
                   "not collated — different transcription system, the fold cannot bridge it"
                 else
                   "not collated — sole witness of its language here"
                 end
        say "  [#{aside.language}/#{aside.script}] #{aside.label}  license: #{aside.license_class}  (#{reason})"
        say "    #{display_text(aside.text, aside.language)}"
      end

      def print_collation_missing(missing)
        no_match = missing.select { |witness| witness.status == :no_match }.map(&:label)
        not_synced = missing.select { |witness| witness.status == :not_synced }.map(&:label)
        withheld = missing.select { |witness| witness.status == :withheld }.map(&:label)
        say "  not attested here: #{no_match.join(', ')}" unless no_match.empty?
        say "  not synced: #{not_synced.join(', ')}" unless not_synced.empty?
        say "  license-withheld: #{withheld.join(', ')}" unless withheld.empty?
      end

      def format_parallel_side(side)
        "#{side.urn}#{" — #{side.title}" if side.title}#{" [#{side.language}]" if side.language}"
      end

      # Honest grouped arithmetic: paired counts 1:1 verse pairs; the blocks
      # clause (and its owned-line total) appears only when there ARE coarse
      # blocks, so verse-for-verse output stays byte-identical to pre-P8-1b.
      def parallel_counts(result)
        paired = result.groups.count { |group| group.kind == :pair }
        blocks = result.groups.select { |group| group.kind == :block }
        left_only = result.groups.count { |group| group.kind == :original }
        right_only = result.groups.count { |group| group.kind == :translation }
        block_lines = blocks.sum { |group| group.originals.size }
        blocks_clause = blocks_clause(blocks.size, block_lines)
        "aligned by citation: #{paired} paired, #{blocks_clause}" \
          "#{left_only} #{result.left.language} only, #{right_only} #{result.right.language} only"
      end

      # The blocks clause appears only when there ARE coarse blocks, so
      # verse-for-verse output stays byte-identical to the pre-P8-1b header.
      def blocks_clause(blocks, lines)
        return "" if blocks.zero?

        "#{plural(blocks, 'block')} covering #{plural(lines, 'line')}, "
      end

      def plural(count, noun)
        "#{count} #{noun}#{'s' unless count == 1}"
      end

      def parallel_line(language, line, width)
        label = language.to_s.ljust(width)
        return "#{label}—" if line.nil?

        "#{label}#{display_text(line.text, language)}#{withdrawn_tag(line.withdrawn)}"
      end

      def withdrawn_tag(withdrawn)
        withdrawn ? "  (withdrawn)" : ""
      end

      # P5-2: upstream scrapped the file; the attic kept it. Live, labeled.
      def retired_tag(document)
        document.retired_upstream ? "  (retired upstream)" : ""
      end

      # Open the fulltext index for reading; nil when the file is absent OR the
      # FTS table was never built (both mean "no index" → the sync/rebuild hint).
      def open_fulltext(config)
        return nil unless File.exist?(config.fulltext_path)

        db = Nabu::Store.connect_fulltext(config.fulltext_path)
        return db if db.table_exists?(Nabu::Store::Indexer::TABLE)

        db.disconnect
        nil
      end

      # One hint line per unregistered script present in the zero-hit query;
      # silent (zero-signal) otherwise.
      def print_script_miss_hints(query)
        return if query.nil?

        SCRIPT_MISS_HINTS.each_value do |(range, hint)|
          say "note: #{hint}" if query.each_char.any? { |char| range.cover?(char.ord) }
        end
      end

      # Render hits: urn + optional [language] header, then the snippet. Every
      # path's snippet is a window of the STORED text (P39-r3/P40-w,
      # StoredSnippet) — text_normalized, the folded skeleton, is NEVER shown (it
      # rendered 学 as 學 and だ as た). +proximity: true+ marks the two-term NEAR
      # snippet (both terms bracketed, on the stored glyphs since P40-w); +exact+
      # / +word+ annotate the glyph-literal / whole-word filters, so the footer
      # labels each path truthfully. Active facet filters (P17-2) are named in
      # one compact footer line — and only then. +incomplete+ (P35-6): the query
      # layer's honesty hint (the exhausted-inner-window note, or the
      # --exact/--word scan-ceiling note) — printed whenever present, so a short
      # page never masquerades as a complete answer.
      def print_search_results(results, facets: nil, query: nil, loans: nil, axis: nil, incomplete: nil,
                               exact: false, word: false, proximity: false, rank_note: nil,
                               browse: false, from: nil, to: nil, place: nil, meter_note: nil,
                               words_note: nil)
        if results.empty?
          say "no matches"
          # Empty-under-filter honesty (P35): --exact/--word suppressed the folded
          # candidates, so a "no matches" here must name the filter it applied.
          if exact
            say "note: --exact matched glyph-literally (the default fold would also find " \
                "reform variants, e.g. 学↔學, 弁↔辨/瓣/辯)"
          end
          say "note: --word required a whole-word match (a fragment inside a longer word does not count)" if word
          # The P42-2 guard served a corpus-wide sample (P42-r3) — an empty
          # page over a degraded path says so too, never a clean-looking silence.
          say "note: #{rank_note}" if rank_note
          # The meter facet's honesty line (P45-5): an empty page under
          # --meter says what layer it filtered on — or that the layer is
          # empty / the code unknown — never a silent zero.
          say "note: #{meter_note}" if meter_note
          # The word-grain degrade note (P54-4): --words could not filter
          # (non-Tibetan query / unsynced module) — plain search served.
          say "note: #{words_note}" if words_note
          say "note: #{incomplete}" if incomplete
          return print_script_miss_hints(query)
        end

        results.each do |result|
          say "#{result.urn}#{" [#{result.language}]" if result.language}"
          say "  #{display_snippet(result.snippet, result.language)}"
        end
        say "#{results.size} #{results.size == 1 ? 'hit' : 'hits'} " \
            "(#{search_snippet_label(exact: exact, word: word, proximity: proximity,
                                     rank_note: rank_note, browse: browse)})" \
            "#{browse_window_footer(from: from, to: to, place: place) if browse}" \
            "#{facet_footer(facets, loans: loans, axis: axis)}"
        say "note: #{meter_note}" if meter_note
        say "note: #{words_note}" if words_note
        say "note: #{incomplete}" if incomplete
        print_search_credits(results)
      end

      # The credit duty on the search surface (P43-2): the DISTINCT source
      # credits among the hits just shown, one line each — so a hit's text and
      # the attribution its grant requires appear on the same page. Nothing when
      # no shown source carries a credit (every ordinary search).
      def print_search_credits(results)
        results.filter_map { |r| r.credit&.strip }.reject(&:empty?).uniq.each do |credit|
          say "credit: #{credit}"
        end
      end

      # The date/place clause of a term-less browse footer (P42-6), naming the
      # content filters that made the browse legal (facets/loans/axis are named
      # by facet_footer); empty when neither is active (compact-footer rule).
      def browse_window_footer(from:, to:, place:)
        parts = []
        parts << "dates: #{browse_year_window(from, to)}" if from || to
        parts << "place: #{place}" if place
        parts.empty? ? "" : " · #{parts.join(' · ')}"
      end

      # A signed-year window as a compact footer string: "-300..-30", "from
      # 500", or "to 100" (BCE years negative — the --from/--to grammar).
      def browse_year_window(from, to)
        return "#{from}..#{to}" if from && to
        return "from #{from}" if from

        "to #{to}"
      end

      # The footer clause naming what the snippet shows, per path. All three
      # paths now show the STORED text (P40-w carried proximity off the folded
      # index form); --exact / --word / proximity annotate what the match means.
      # +rank_note+ (P42-2, plain path only) appends the skipped-rank honesty
      # clause: "…; term too common to rank — corpus-wide sample".
      def search_snippet_label(exact:, word: false, proximity: false, rank_note: nil, browse: false)
        return "filtered browse — corpus order, no ranking" if browse
        return "both terms bracketed; snippet shows the text as stored" if proximity

        stored = "snippet shows the text as stored"
        # A filtered path (--exact and/or --word) leads with what the match means;
        # plain search leads with the stored-text promise, then "fold-aware".
        return ["#{stored}; matching is fold-aware", rank_note].compact.join("; ") unless exact || word

        mode = if exact && word then "glyph-exact, whole-word"
               elsif exact then "glyph-exact"
               else "whole-word, fold-aware"
               end
        "#{mode}; #{stored}"
      end

      # " · facets: genre=epitaph province=pannonia% · loans: grc · axis: celtic"
      # — empty when no facet/loans/axis filter is active (zero-signal silence,
      # the compact rule). The axis names the desk(s) the membership filter
      # scoped to (P37-8).
      def facet_footer(facets, loans: nil, axis: nil)
        parts = []
        parts << "facets: #{facets.map { |facet, pattern| "#{facet}=#{pattern}" }.join(' ')}" if facets&.any?
        parts << "loans: #{loans}" if loans
        # The meter facet (P45-5) names its active filter in the footer like
        # every other facet; the source-layer note is a separate line.
        parts << "meter: #{[options[:meter], options[:meter_pattern]].compact.join(' ')}" if
          options[:meter] || options[:meter_pattern]
        parts << "axis: #{Array(axis).join(',')}" if axis && !Array(axis).empty?
        parts.empty? ? "" : " · #{parts.join(' · ')}"
      end

      # Render fuzzy hits (P16-4): the search-hit shape (urn + [language],
      # then the folded snippet with the fragment in [brackets]; --long lifts
      # the snippet window, house rule), plus ONE scope line — the fuzzy
      # index is documentary-only, so every render names what it covers (the
      # honest answer when --lang grc "finds nothing" in the literary corpus).
      def print_fuzzy_results(results, scope:, long: false, facets: nil, loans: nil, axis: nil, incomplete: nil)
        if results.empty?
          say "no matches"
        else
          results.each do |result|
            say "#{result.urn}#{" [#{result.language}]" if result.language}"
            say "  #{display_snippet(long ? result.folded_marked : result.snippet, result.language)}"
          end
          say "#{results.size} #{results.size == 1 ? 'hit' : 'hits'} " \
              "(fuzzy substring; highlights are diacritic-folded)#{facet_footer(facets, loans: loans, axis: axis)}"
        end
        say "note: #{incomplete}" if incomplete
        covered = scope&.any? ? scope.join(", ") : "no sources (flag fuzzy_index: true in config/sources.yml)"
        say "fuzzy index covers: #{covered}"
      end

      # Render KWIC rows (P8-3): left + keyword + right (each side already
      # trimmed to width by Concord), then the urn + [language] tag. The left
      # context is a fixed width, so keyword columns align down the page.
      # Non-gold lemma-mode rows carry the search --lemma tag (P26-4 silver,
      # P34-3 equivalence); gold and text-mode rows render exactly as before.
      # The footer totals each non-gold share so a mixed page is never
      # silently mixed.
      def print_concord_rows(rows)
        return say("no matches") if rows.empty?

        width = options[:width].to_i
        rows.each do |row|
          tier = row.tier && row.tier != "gold" ? " [#{row.tier}]" : ""
          left, keyword, right = concord_display_pieces(row, width)
          say "#{left}#{keyword}#{right}  #{row.urn}#{" [#{row.language}]" if row.language}#{tier}"
        end
        footer = "#{rows.size} #{rows.size == 1 ? 'line' : 'lines'} (KWIC; keyword in pristine text, corpus order)"
        silver = rows.count { |row| row.tier == "silver" }
        footer += " — #{silver} silver (automatic lemmatization)" if silver.positive?
        equivalence = rows.count { |row| row.tier == "equivalence" }
        footer += " — #{equivalence} equivalence (Classical-Latin equivalents)" if equivalence.positive?
        say footer
      end

      # Concord's columns were padded by Concord over the PRE-display pieces;
      # a display transform (stripped marks, isolate wrapping, token coloring)
      # changes their cell width, so re-pad here over DISPLAY CELLS
      # (Nabu::Display.rjust/ljust — ANSI SGR and isolates count 0, wide
      # clusters count 2) to keep the keyword column at exactly +width+ cells.
      def concord_display_pieces(row, width)
        left = display_text(row.left.sub(/\A +/, ""), row.language)
        right = display_text(row.right.sub(/ +\z/, ""), row.language)
        keyword = display_text(row.keyword, row.language)
        [Nabu::Display.rjust(left, width), keyword, Nabu::Display.ljust(right, width)]
      end

      # Render `parallels` (P15-1): the anchor line, then one hit per document —
      # urn [lang], score, shared-gram count and loci, and the shared PHRASE
      # spans indented beneath. A lemma-echoes section follows when the anchor is
      # gold-lemmatized. `--long` expands every truncated list.
      def print_parallels(result, urn:, long:)
        raise Thor::Error, "parallels: no live passage at #{urn} (check `nabu show #{urn}`)" if result.nil?

        title = result.anchor_title ? " — #{result.anchor_title}" : ""
        say "parallels of #{result.anchor_urn}#{title}"
        if result.gram_count.zero?
          say "  passage too short for #{Nabu::Query::Parallels::GRAM_SIZE}-word grams"
          return
        end

        say "  no surface-gram parallels" if result.hits.empty?
        result.hits.each { |hit| print_parallel_hit(hit, long: long) }
        say "#{result.hits.size} #{result.hits.size == 1 ? 'parallel' : 'parallels'} " \
            "from #{result.gram_count} grams (evidence is diacritic-folded)"
        print_lemma_echoes(result.lemma_echoes, long: long) unless result.lemma_echoes.empty?
      end

      def print_parallel_hit(hit, long:)
        loci = hit.loci > 1 ? " · #{hit.loci} loci" : ""
        grams = "#{hit.shared_gram_count} #{hit.shared_gram_count == 1 ? 'gram' : 'grams'}"
        say "#{hit.urn}#{" [#{hit.language}]" if hit.language}  " \
            "score #{format('%.2f', hit.score)} · #{grams}#{loci}"
        lines = compact_list(hit.evidence, long: long) do |span|
          display_text(long ? span : truncate_line(span, PARALLELS_SPAN_CHARS), hit.language)
        end
        lines.each { |line| say "  #{line}" }
      end

      def print_lemma_echoes(echoes, long:)
        say "lemma echoes (rare shared lemmas — re-inflected/reordered allusion):"
        echoes.each do |echo|
          say "#{echo.urn}#{" [#{echo.language}]" if echo.language}  score #{format('%.2f', echo.score)}"
          say "  #{compact_list(echo.shared_lemmas, long: long).join(', ')}"
        end
      end

      # Render `formulas` (P15-5): the slice header (passages/tokens), then one
      # line per formula — count × the folded gram — with example loci beneath
      # (compact) or every locus (--long). The footer states the ranking and the
      # recurring total so the "top N of M" elision is explicit.
      def print_formulas(result, long:)
        lang = result.lang ? " [#{result.lang}]" : ""
        say "formulas in #{result.scope}#{lang} — " \
            "#{plural(result.passage_count, 'passage')} / #{plural(result.token_count, 'token')}"
        return say("  no passages in scope (unknown source slug or urn prefix?)") if result.passage_count.zero?
        return say("  no #{result.gram_size}-grams recur ≥#{result.min_count}× in this slice") if result.formulas.empty?

        result.formulas.each { |formula| print_formula(formula, long: long) }
        say "showing #{result.formulas.size} of #{plural(result.recurring_count, 'formula')} " \
            "recurring ≥#{result.min_count}× (rank = count × #{result.gram_size}-gram length; " \
            "grams are diacritic-folded)"
      end

      def print_formula(formula, long:)
        say "#{formula.count}×  #{formula.gram}"
        return if formula.loci.empty?

        prefix = !long && formula.count > formula.loci.size ? "e.g. " : ""
        say "     #{prefix}#{formula.loci.join(', ')}"
      end

      # -- links journal (P16-1) ------------------------------------------------

      # `parallels --batch SCOPE`: mine the scope with Nabu::BatchParallels and
      # persist edges to the links journal. Progress ticks go to stderr
      # (stdout keeps the summary); the summary NAMES the pruning thresholds —
      # no silent caps — and suppresses zero fields (house style).
      def batch_parallels(scope)
        raise Thor::Error, "parallels --batch: give a source slug or urn prefix" if scope.empty?

        config = Nabu::Config.load
        catalog = open_catalog(config)
        fulltext = open_fulltext(config)
        raise Thor::Error, "no index — run nabu sync or nabu rebuild" unless catalog && fulltext

        journal = Nabu::Store::LinksJournal.open!(options[:db] || config.links_path)
        result = Nabu::BatchParallels.new(catalog: catalog, fulltext: fulltext, journal: journal)
                                     .run(scope, lang: options[:lang], license: options[:license],
                                                 progress: batch_progress,
                                                 **batch_thresholds)
        print_batch_parallels(result)
      ensure
        catalog&.disconnect
        fulltext&.disconnect
        journal&.disconnect
      end

      def batch_thresholds
        thresholds = {}
        thresholds[:min_score] = options[:min_score].to_f if options[:min_score]
        thresholds[:per_anchor] = options[:per_anchor].to_i if options[:per_anchor]
        thresholds
      end

      # A stderr tick every BATCH_PROGRESS_EVERY anchors (and at the end), so a
      # minutes-long mine is visibly alive without flooding the terminal.
      def batch_progress
        lambda do |done, total, edges|
          return unless (done % BATCH_PROGRESS_EVERY).zero? || done == total

          warn "  #{done}/#{total} anchors · #{edges} edges" if total > BATCH_PROGRESS_EVERY
        end
      end

      def print_batch_parallels(result)
        say "batch parallels over #{result.scope}#{" [#{result.lang}]" if result.lang}: " \
            "#{plural(result.edges_written, 'edge')} written#{batch_refreshed(result)} · run #{result.run_id}"
        say "  #{plural(result.anchor_count, 'anchor')} · kept top #{result.per_anchor}/anchor " \
            "at score ≥ #{result.min_score}#{batch_superseded(result)} · #{format('%.1f', result.elapsed)} s"
      end

      # `formulas --batch SCOPE` (P16-2): sweep the whole tradition once and
      # persist each formula as a STAR of kind=formula edges (hub = its first
      # locus in urn order; detail = the gram, score = the count — the
      # edge-shape verdict is argued in Nabu::BatchFormulas). Same summary
      # discipline as batch parallels: every pruning knob named.
      def batch_formulas(scope)
        raise Thor::Error, "formulas --batch: give a source slug or urn prefix" if scope.empty?

        config = Nabu::Config.load
        catalog = open_catalog(config)
        raise Thor::Error, "no index — run nabu sync or nabu rebuild" unless catalog

        journal = Nabu::Store::LinksJournal.open!(options[:db] || config.links_path)
        result = Nabu::BatchFormulas.new(catalog: catalog, journal: journal)
                                    .run(scope, gram_size: options[:gram_size].to_i,
                                                min_count: options[:min_count].to_i,
                                                lang: options[:lang], **max_formulas_option)
        print_batch_formulas(result)
      rescue ArgumentError => e
        raise Thor::Error, "formulas: #{e.message}"
      ensure
        catalog&.disconnect
        journal&.disconnect
      end

      def max_formulas_option
        options[:max_formulas] ? { max_formulas: options[:max_formulas].to_i } : {}
      end

      def print_batch_formulas(result)
        say "batch formulas over #{result.scope}#{" [#{result.lang}]" if result.lang}: " \
            "#{plural(result.edges_written, 'edge')} written#{batch_refreshed(result)} · run #{result.run_id}"
        coalesced = result.coalesced.positive? ? " · #{result.coalesced} overlapping pairs coalesced" : ""
        say "  #{plural(result.formula_count, 'formula')} persisted as stars " \
            "(top #{result.max_formulas} by rank of #{result.recurring_count} recurring " \
            "≥#{result.min_count}× #{result.gram_size}-grams)#{coalesced}" \
            "#{batch_superseded(result)} · #{format('%.1f', result.elapsed)} s"
      end

      # `cognates --batch WORK` (P16-2): map the whole alignment work once and
      # persist kind=cognate edges between cross-language witness passages
      # meeting at a reconstruction root; the meet (ref · root [shelf]) rides
      # each edge's detail (the provenance verdict is argued in
      # Nabu::BatchCognates).
      def batch_cognates(work_id)
        raise Thor::Error, "cognates --batch: give a registered work id (nt)" if work_id.empty?

        config = Nabu::Config.load
        catalog = open_catalog(config)
        fulltext = open_fulltext(config)
        raise Thor::Error, "no corpus — run nabu sync or nabu rebuild" unless catalog && fulltext

        registry = Nabu::AlignmentRegistry.load(config.alignments_path)
        journal = Nabu::Store::LinksJournal.open!(options[:db] || config.links_path)
        result = Nabu::BatchCognates.new(catalog: catalog, fulltext: fulltext,
                                         registry: registry, journal: journal)
                                    .run(work_id, langs: parse_langs(options[:langs]), all: options[:all])
        print_batch_cognates(result)
      ensure
        catalog&.disconnect
        fulltext&.disconnect
        journal&.disconnect
      end

      def print_batch_cognates(result)
        langs = result.langs ? " [#{result.langs.join('×')}]" : ""
        say "batch cognates over #{result.work}#{langs}: " \
            "#{plural(result.edges_written, 'edge')} written#{batch_refreshed(result)} · run #{result.run_id}"
        suppressed = if result.suppressed.positive?
                       " · #{plural(result.suppressed, 'common-word group')} suppressed (--all keeps)"
                     else
                       ""
                     end
        say "  #{plural(result.group_count, 'verse-root group')}#{suppressed}" \
            "#{batch_superseded(result)} · #{format('%.1f', result.elapsed)} s"
      end

      def batch_refreshed(result)
        result.edges_refreshed.positive? ? " (+#{result.edges_refreshed} refreshed in place)" : ""
      end

      def batch_superseded(result)
        return "" unless result.superseded_runs.positive?

        " · superseded #{plural(result.superseded_runs, 'prior run')} " \
          "(#{plural(result.superseded_edges, 'edge')})"
      end

      # Render `nabu links` (P16-1): the urn header, one section per kind with
      # each edge's direction, resolved counterpart, and score, then the
      # provenance footer citing the producer run(s). Compact caps each kind at
      # LINKS_COMPACT_ITEMS; --long lists all (house rule, conventions §10).
      def print_links(result, long:)
        title = result.title ? " — #{result.title}" : ""
        say "links of #{result.urn}#{title}"
        return say("  no links") if result.total.zero?

        result.groups.keys.sort.each { |kind| print_links_group(kind, result.groups.fetch(kind), long: long) }
        result.runs.each do |run|
          say "#{plural(result.total, 'edge')} · run #{run.id}: #{run.producer} over #{run.scope} " \
              "#{format_link_params(run.params)}· #{run.created_at.strftime('%Y-%m-%d')}"
        end
      end

      def print_links_group(kind, edges, long:)
        say "#{kind} (#{edges.size}):"
        shown = long ? edges : edges.first(LINKS_COMPACT_ITEMS)
        shown.each { |edge| say "  #{format_link_edge(edge, kind)}" }
        hidden = edges.size - shown.size
        say "  … and #{hidden} more (--long lists all)" if hidden.positive?
      end

      def format_link_edge(edge, kind)
        arrow = edge.direction == :out ? "→" : "←"
        where = if edge.resolved?
                  "#{" — #{edge.title}" if edge.title}#{" [#{edge.language}]" if edge.language}"
                else
                  " (not in catalog)"
                end
        "#{arrow} #{edge.urn}#{where}#{format_link_evidence(edge, kind)}"
      end

      # The per-kind evidence tail (P16-2): a formula edge shows its gram and
      # slice count (“saga hwaet ic hatte” ×4 — "score 4.00" would misread a
      # count as a rarity score); a cognate edge shows its meet (the detail
      # already carries ref · root [shelf], and its score merely counts the
      # roots listed there — suppressed as zero-signal); a parallel edge keeps
      # the rarity score; an unknown future kind prints whatever it has.
      def format_link_evidence(edge, kind)
        case kind
        when "formula"
          "#{"  “#{edge.detail}”" if edge.detail}#{"  ×#{edge.score.to_i}" if edge.score}"
        when "cognate"
          edge.detail ? "  #{edge.detail}" : ""
        else
          "#{"  score #{format('%.2f', edge.score)}" if edge.score}#{"  #{edge.detail}" if edge.detail}"
        end
      end

      # Array params (cognates' langs) render comma-joined, not as inspected
      # Ruby arrays — compact house style.
      def format_link_params(params)
        pairs = params.except("kind").map do |key, value|
          "#{key} #{value.is_a?(Array) ? value.join(',') : value}"
        end
        pairs.empty? ? "" : "(#{pairs.join(', ')}) "
      end

      # The `show` footer (P16-1): one "linked:" line, ONLY when the links
      # journal holds edges touching this urn — zero-signal silence otherwise
      # (no journal, no edges, nothing printed). Read-only, absent-file-safe.
      def print_linked_footer(config, urn)
        journal = Nabu::Store::LinksJournal.open_readonly(config.links_path)
        return if journal.nil?

        counts = Nabu::Store::LinksJournal.kind_counts(journal, urn)
        return if counts.empty?

        say "  linked: #{counts.sort_by { |kind, _| kind }.map { |kind, count| "#{count} #{kind}" }.join(', ')}"
      ensure
        journal&.disconnect
      end

      # -- nabu note (P24-1) -------------------------------------------------

      # The `show`/`define` notes footer: one "owner note (topic, date): …"
      # line per note on the urn, and — on a document — the passage-note
      # children count. Zero-signal silence when unnoted (the linked-footer
      # stance); a catalog predating migration 015 has no lane at all.
      def print_notes_footer(catalog, result)
        reader = Nabu::Query::Notes.new(catalog: catalog)
        return unless reader.available?

        reader.for_urn(result.urn).each do |row|
          say "  owner note (#{row.topic}, #{row.added}): #{row.note}#{note_tags_fragment(row)}"
        end
        return unless result.is_a?(Nabu::Query::Show::DocumentResult)

        children = reader.child_count(result.urn)
        say "  passage notes: #{children}" if children.positive?
      end

      # The `links` owner-notes lane: the urn's own notes beside its mined
      # edges (curation next to discovery), silent when unnoted.
      def print_links_notes_lane(catalog, urn)
        rows = Nabu::Query::Notes.new(catalog: catalog).for_urn(urn)
        return if rows.empty?

        say "owner notes (#{rows.size}):"
        rows.each { |row| say "  #{note_line(row)}" }
      end

      def note_line(row)
        id = Nabu::NoteFile.record_id(topic: row.topic, urn: row.urn, added: row.added, note: row.note)
        "[#{id}] (#{row.topic}, #{row.added}) #{row.note}#{note_tags_fragment(row)}"
      end

      def note_tags_fragment(row)
        row.tags.empty? ? "" : "  [#{row.tags.join(', ')}]"
      end

      # `nabu note --list`: the bounded enumeration, oldest first, each urn
      # resolution-checked so a --force note on a not-yet-held urn reads
      # honestly dangling.
      # note --rm ID: one removal through the gateway, then the same
      # surgical derived refresh the append uses (file rewritten) or a
      # topic teardown (last note removed the file): rows + pin dropped.
      def note_remove(config, urn_arg)
        raise Thor::Error, "note: --rm takes no urn argument (--topic scopes the id search)" \
          unless urn_arg.to_s.strip.empty?

        shelf = Nabu::NoteShelf.new(dir: Nabu::NoteShelf.dir(config.canonical_dir), resolver: nil)
        removal = shelf.remove_note!(id: options[:rm], topic: options[:topic])
        say "  removed  [#{options[:rm].strip.downcase}] #{removal.record.urn} — " \
            "#{removal.record.note[0, 60]}#{'…' if removal.record.note.length > 60}"
        if removal.file_deleted
          drop_note_topic(config, removal.topic, removal.path)
        else
          refresh_note_topic(config, removal.path)
        end
      end

      # The last note of a topic left the shelf: its derived rows and its
      # ledger pin go with the file (millisecond ops, the fast-path rule).
      def drop_note_topic(config, topic, path)
        catalog = open_catalog(config)
        begin
          catalog[:urn_notes].where(topic: topic).delete if catalog&.table_exists?(:urn_notes)
        ensure
          catalog&.disconnect
        end
        ledger = open_ledger(config)
        begin
          if ledger
            Nabu::Store::Pin.where(source_slug: Nabu::NoteShelf::SLUG,
                                   repo_url: "local:#{File.basename(path)}").delete
          end
        ensure
          ledger&.disconnect
        end
      end

      def note_list(config, urn_arg)
        raise Thor::Error, "note: --list takes no urn (--topic narrows, --limit lifts)" \
          unless urn_arg.to_s.strip.empty?

        catalog = open_catalog(config)
        raise Thor::Error, "no catalog — run nabu sync or nabu rebuild" unless catalog

        page = Nabu::Query::Notes.new(catalog: catalog).list(topic: options[:topic], limit: options[:limit].to_i)
        return say(%(no notes yet — nabu note URN "TEXT" writes the first)) if page.total.zero?

        resolved = Nabu::NoteShelf.catalog_resolver(catalog)
        page.rows.each do |row|
          say "#{row.urn}#{' (dangling)' unless resolved.call(row.urn)} — #{note_line(row)}"
        end
        remaining = page.total - page.rows.size
        say "… and #{remaining} more (--limit lifts, --topic narrows)" if remaining.positive?
      ensure
        catalog&.disconnect
      end

      # `nabu note URN` without TEXT: existing notes are SHOWN (a read —
      # works piped or not); a bare urn with none prompts on a TTY and
      # refuses honestly otherwise, BEFORE any write (the ingest precedent).
      # Returns the text to append, or nil when notes were shown.
      def show_notes_or_prompt(config, urn)
        existing = existing_notes(config, urn)
        unless existing.empty?
          say "notes on #{urn} (#{existing.size}):"
          existing.each { |row| say "  #{note_line(row)}" }
          say %(add another: nabu note #{urn} "TEXT" · remove one: nabu note --rm ID)
          return nil
        end
        unless $stdin.tty?
          raise Thor::Error, "note: no TEXT and no TTY to prompt — pass the note as an argument " \
                             "(nabu note URN \"TEXT\"); nothing was written"
        end

        # Plain $stdin.gets, NOT Thor's ask: Thor routes ask through
        # LineEditor::Readline when the readline ext exists (CI's Ruby 3.3
        # bundles it; homebrew 4.0 dropped it), and Readline reads the real
        # fd — invisible to the suite's $stdin double and to piped input.
        # One prompt, one line; the say keeps the ingest prompt furniture.
        say "  note for #{urn} (type it, Enter saves, ^C aborts):"
        answer = $stdin.gets.to_s.strip
        raise Thor::Error, "note: refusing an empty note — nothing was written" if answer.empty?

        answer
      end

      def existing_notes(config, urn)
        catalog = open_catalog(config)
        return [] unless catalog

        Nabu::Query::Notes.new(catalog: catalog).for_urn(urn, topic: options[:topic])
      ensure
        catalog&.disconnect
      end

      # The write path: resolution-checked append through the NoteShelf
      # gateway, then a SURGICAL derived refresh — parse the one topic file,
      # replace its urn_notes rows, upsert its ledger pin. NEVER the shelf's
      # ordinary sync: that path runs LocalFetch discovery plus the corpus
      # indexer, minutes of machinery for a one-line append (owner defect
      # 2026-07-18: "notes supposed to be lightning fast"). The full sync/
      # rebuild replays the same rows from the same file — consistency is by
      # construction, speed is the feature.
      def append_note(config, urn, text)
        resolved = true
        catalog = open_catalog(config)
        begin
          resolver = catalog && Nabu::NoteShelf.catalog_resolver(catalog)
          resolved = resolver ? resolver.call(urn) : false if options[:force]
          shelf = Nabu::NoteShelf.new(dir: Nabu::NoteShelf.dir(config.canonical_dir), resolver: resolver)
          path = shelf.append_note!(urn: urn, note: text,
                                    topic: options[:topic] || Nabu::NoteShelf::DEFAULT_TOPIC,
                                    tags: (options[:tags] || "").split(","), force: options[:force])
          say "  noted    #{urn} → #{path}"
        ensure
          catalog&.disconnect
        end
        refresh_note_topic(config, path)
        unless resolved
          say "  note: #{urn} is not in the catalog yet — it reads (dangling) until the urn arrives", :yellow
        end
        say "try: bin/nabu show #{urn}" if resolved
      end

      # The fast-append derived refresh (P26 hotfix): one topic file parsed,
      # its urn_notes rows replaced, its per-file ledger pin upserted — the
      # exact rows a full sync would produce for this file, in milliseconds.
      # Other topics' pins are untouched (the sync-time set-reconcile stays
      # the full pipeline's job). Absent db/ledger degrade honestly: the
      # note is canonical either way and the next sync/rebuild indexes it.
      def refresh_note_topic(config, path)
        note_file = Nabu::NoteFile.load(path)
        catalog = open_catalog(config)
        if catalog
          begin
            Nabu::Store::NoteLoader.replace_for_topic!(catalog, note_file)
          ensure
            catalog.disconnect
          end
        else
          say "  (no catalog yet — the note indexes at the next sync/rebuild)"
        end
        ledger = open_ledger(config)
        return unless ledger

        begin
          key = "local:#{File.basename(path)}"
          sha = Digest::SHA256.file(path).hexdigest
          row = Nabu::Store::Pin.first(source_slug: Nabu::NoteShelf::SLUG, repo_url: key)
          if row
            row.update(last_sync_sha: sha)
          else
            Nabu::Store::Pin.create(
              source_slug: Nabu::NoteShelf::SLUG, repo_url: key, last_sync_sha: sha
            )
          end
        ensure
          ledger.disconnect
        end
      end

      # Cap a list to PARALLELS_COMPACT_ITEMS with a "… and N more" tail unless
      # +long+; each kept item passes through the block (span trimming). The tail
      # itself names --long so the elision is discoverable.
      def compact_list(items, long:)
        kept = long ? items : items.first(PARALLELS_COMPACT_ITEMS)
        rendered = kept.map { |item| block_given? ? yield(item) : item }
        extra = items.size - kept.size
        rendered << "… and #{extra} more (--long)" if extra.positive?
        rendered
      end

      # search --lemma FORM (P7-5): exact-lemma lookup over the treebank lemma
      # index. Replaces the FTS query (simplest honest v1 — combining both is
      # future work); composes with --lang/--license/--limit. A fulltext file
      # predating P7-5 lacks the lemma table, so that gets its own honest hint.
      # search --fuzzy FRAGMENT (P16-4): substring/fragment search over the
      # documentary trigram index (Query::Fuzzy — candidates, then verify).
      # Same open/close discipline as the sibling search paths; the trigram
      # table missing means the fulltext index predates P16-4, an honest
      # reindex hint, exactly the lemma-index precedent.
      def char_filter_options?
        options[:radical] || options[:strokes] || options[:char_component]
      end

      # --strokes N or A-B → an inclusive [low, high] range, or nil.
      def parse_strokes_option
        raw = options[:strokes]&.strip or return nil
        if (m = raw.match(/\A(\d+)\z/))
          [m[1].to_i, m[1].to_i]
        elsif (m = raw.match(/\A(\d+)-(\d+)\z/))
          [m[1].to_i, m[2].to_i].minmax
        else
          raise Thor::Error, "search: --strokes takes N or A-B (e.g. --strokes 8 or --strokes 8-12)"
        end
      end

      # The explicit character-structure search (P37-4): --radical/--strokes/
      # --char-component resolve to a glyph set (CharFilter), which filters
      # Han-language passages by containment, composing with a plain text
      # query. Kept visibly distinct from FTS — the footer names the filters.
      def char_structured_search(query)
        validate_license!(options[:license])
        if options[:radical] && !options[:radical].to_i.between?(1, 214)
          raise Thor::Error, "search: --radical is a KangXi radical number 1-214 (got #{options[:radical]})"
        end

        strokes = parse_strokes_option
        config = Nabu::Config.load
        catalog = open_catalog(config)
        fulltext = open_fulltext(config)
        raise Thor::Error, "no index — run nabu sync or nabu rebuild" unless catalog && fulltext
        unless catalog.table_exists?(:dictionary_entries)
          raise Thor::Error, "no char shelf in this catalog — run nabu sync unihan (for --radical/" \
                             "--strokes) or babelstone-ids/kradfile (for --char-component)"
        end
        validate_source!(catalog, options[:source])

        outcome = Nabu::Query::CharSearch.new(catalog: catalog, fulltext: fulltext)
                                         .run(query, radical: options[:radical]&.to_i, strokes: strokes,
                                                     component: options[:char_component], lang: options[:lang],
                                                     license: options[:license], source: options[:source],
                                                     limit: options[:limit].to_i)
        print_char_search_results(outcome, query: query)
        print_display_footer
      ensure
        catalog&.disconnect
        fulltext&.disconnect
      end

      def print_char_search_results(outcome, query:)
        labels = outcome.labels.join(" AND ")
        if outcome.resolved_empty
          return say("no characters match [#{labels}] in the held char shelves — sync unihan " \
                     "(--radical/--strokes) or babelstone-ids/kradfile (--char-component)")
        end
        if outcome.results.empty?
          tail = query.empty? ? "" : " that also match #{query.inspect}"
          return say("no passages carry a character matching [#{labels}]#{tail} " \
                     "(#{outcome.char_count} characters resolved)")
        end

        outcome.results.each do |result|
          say "#{result.urn}  [#{result.language}]  {#{result.matched.join(' ')}}"
          say "  #{result.text}"
        end
        say ""
        text_note = query.empty? ? "" : "; text query #{query.inspect}"
        say "character filter: [#{labels}] — #{outcome.char_count} " \
            "#{outcome.char_count == 1 ? 'character' : 'characters'} resolved#{text_note}"
        say Nabu::Query::CatalogJoin::INCOMPLETE_PAGE_HINT if outcome.incomplete
      end

      def fuzzy_search(query)
        raise Thor::Error, "search: --fuzzy needs a fragment" if query.empty?

        validate_license!(options[:license])
        from, to = date_window
        facets = facet_filters
        config = Nabu::Config.load
        catalog = open_catalog(config)
        fulltext = open_fulltext(config)
        raise Thor::Error, "no index — run nabu sync or nabu rebuild" unless catalog && fulltext
        unless fulltext.table_exists?(Nabu::Store::Indexer::TRIGRAM_TABLE)
          raise Thor::Error, "no fuzzy index (the fulltext index predates fragment search) — " \
                             "run nabu sync or nabu rebuild"
        end

        require_timeline!(catalog) if from || to || options[:place]
        require_facets!(catalog) if facets
        validate_source!(catalog, options[:source])
        axis_names, axis_slugs = axis_membership(command: "search", config: config)
        fuzzy = Nabu::Query::Fuzzy.new(catalog: catalog, fulltext: fulltext)
        results = fuzzy.run(query, lang: options[:lang], license: options[:license],
                                   limit: options[:limit].to_i, from: from, to: to, place: options[:place],
                                   facets: facets, source: options[:source], sources: axis_slugs,
                                   loans: loans_filter)
        print_fuzzy_results(results, scope: fuzzy.scope, long: options[:long], facets: facets,
                                     loans: loans_filter, axis: axis_names, incomplete: fuzzy.incomplete_hint)
        print_display_footer
      rescue Nabu::Query::Fuzzy::QueryTooShort => e
        raise Thor::Error, "search: --fuzzy needs at least 3 characters after folding " \
                           "(#{query.inspect} folds to #{e.folded.inspect}) — the trigram floor"
      ensure
        catalog&.disconnect
        fulltext&.disconnect
      end

      def lemma_search(positional_query)
        unless positional_query.empty?
          raise Thor::Error, "search: --lemma replaces the text query — give one or the other"
        end

        lemma = options[:lemma].strip
        raise Thor::Error, "search: --lemma needs a lemma" if lemma.empty?

        validate_license!(options[:license])
        config = Nabu::Config.load
        catalog = open_catalog(config)
        fulltext = open_fulltext(config)
        raise Thor::Error, "no index — run nabu sync or nabu rebuild" unless catalog && fulltext
        unless fulltext.table_exists?(Nabu::Store::Indexer::LEMMA_TABLE)
          raise Thor::Error, "no lemma index (the fulltext index predates lemma search) — " \
                             "run nabu sync or nabu rebuild"
        end

        validate_source!(catalog, options[:source])
        axis_names, axis_slugs = axis_membership(command: "search", config: config)
        searcher = Nabu::Query::LemmaSearch.new(catalog: catalog, fulltext: fulltext)
        results = searcher.run(lemma, lang: options[:lang], license: options[:license],
                                      limit: options[:limit].to_i, morph: options[:morph],
                                      source: options[:source], sources: axis_slugs,
                                      gold_only: options[:gold_only], loans: loans_filter)
        print_lemma_results(results, query: lemma, axis: axis_names, incomplete: searcher.incomplete_hint)
        print_display_footer
      rescue Nabu::Query::MorphFacets::Error => e
        raise Thor::Error, "search: #{e.message}"
      ensure
        catalog&.disconnect
        fulltext&.disconnect
      end

      # search A --near B [--window N] (P14-8): proximity search over the FTS
      # index via FTS5 NEAR. The anchor is the positional query OR --lemma
      # (expanded to attested surface forms); --near B is the second term;
      # --window N is the max folded tokens between them (default 10, 0 =
      # adjacent). Hits render exactly like plain search — the snippet brackets
      # BOTH terms. --morph does not compose (out of scope, said honestly).
      def proximity_search(positional_query)
        near = options[:near].strip
        raise Thor::Error, "search: --near needs a term" if near.empty?
        if options[:morph]
          raise Thor::Error, "search: --morph does not compose with --near " \
                             "(morphology-narrowed proximity is out of scope)"
        end
        window = options[:window].to_i
        raise Thor::Error, "search: --window must be 0 or more" if window.negative?

        lemma = options[:lemma]&.strip
        if options[:lemma]
          unless positional_query.empty?
            raise Thor::Error,
                  "search: --lemma replaces the text query — give one or the other"
          end
          raise Thor::Error, "search: --lemma needs a lemma" if lemma.empty?
        elsif positional_query.empty?
          raise Thor::Error, "search: --near needs an anchor term (a query, or --lemma)"
        end

        validate_license!(options[:license])
        config = Nabu::Config.load
        catalog = open_catalog(config)
        fulltext = open_fulltext(config)
        raise Thor::Error, "no index — run nabu sync or nabu rebuild" unless catalog && fulltext
        if lemma && !fulltext.table_exists?(Nabu::Store::Indexer::LEMMA_TABLE)
          raise Thor::Error, "no lemma index (the fulltext index predates lemma search) — " \
                             "run nabu sync or nabu rebuild"
        end

        validate_source!(catalog, options[:source])
        axis_names, axis_slugs = axis_membership(command: "search", config: config)
        searcher = Nabu::Query::Proximity.new(catalog: catalog, fulltext: fulltext)
        results = searcher.run(
          query: lemma ? nil : positional_query, lemma: lemma, near: near, window: window,
          lang: options[:lang], license: options[:license], limit: options[:limit].to_i,
          source: options[:source], sources: axis_slugs, loans: loans_filter
        )
        print_search_results(results, loans: loans_filter, axis: axis_names,
                                      incomplete: searcher.incomplete_hint, proximity: true)
        print_display_footer
      ensure
        catalog&.disconnect
        fulltext&.disconnect
      end

      # Render lemma hits: urn + language, the dictionary form with the surface
      # form(s) that attest it, then the PRISTINE passage line (truncated) —
      # the surface form already marks the match, so readability wins over a
      # folded snippet here. Non-gold hits are labeled per hit — gold stays
      # unlabeled, the pre-tier render exactly (P26-0 silver; P34-3
      # equivalence: a Latin key on a non-Latin passage, scholar-curated,
      # never attestation); the footer totals each non-gold share and names
      # the way out.
      def print_lemma_results(results, query: nil, axis: nil, incomplete: nil)
        if results.empty?
          say "no matches"
          say "note: #{incomplete}" if incomplete
          return print_script_miss_hints(query)
        end

        results.each do |result|
          forms = result.surface_forms.empty? ? "(no surface form)" : result.surface_forms
          gloss = result.gloss ? "  (#{result.gloss})" : ""
          morph = result.morph ? "  {#{result.morph}}" : ""
          tier = result.tier == "gold" ? "" : " [#{result.tier}]"
          say "#{result.urn}#{" [#{result.language}]" if result.language}#{tier}  " \
              "#{result.lemma} → #{forms}#{gloss}#{morph}"
          say "  #{display_text(truncate_line(result.text), result.language)}"
        end
        silver = results.count { |result| result.tier == "silver" }
        footer = "#{results.size} #{results.size == 1 ? 'hit' : 'hits'} (exact lemma match; text is pristine)"
        footer += " — #{silver} silver (automatic lemmatization; --gold-only excludes)" if silver.positive?
        equivalence = results.count { |result| result.tier == "equivalence" }
        if equivalence.positive?
          footer += " — #{equivalence} equivalence (scholar-curated Classical-Latin equivalents; " \
                    "--gold-only excludes)"
        end
        footer += " · axis: #{Array(axis).join(',')}" if axis && !Array(axis).empty?
        say footer
        say "note: #{incomplete}" if incomplete
      end

      # Render a vocab profile (P14-3): the header (urn, title, language, scope),
      # then either the gold-lemma summary + distinctive table + hapax line, or
      # the honest no-gold-lemmas notice naming the gold-bearing languages.
      def print_vocab(profile)
        header = "#{profile.urn}#{" — #{profile.title}" if profile.title}"
        header += " [#{profile.language}]" if profile.language
        say header
        say "  #{profile.kind}, #{pluralize(profile.passages, 'passage')}"
        return print_vocab_no_gold(profile) if profile.total_tokens.zero?

        # The tier label (P26-4): a silver document profiles, but its counts
        # never render under the gold name — the line SAYS silver, plus an
        # explicit automatic-lemmatization warning. Gold (and pre-tier nil)
        # keeps the exact pre-tier render.
        silver = profile.lemma_tier == "silver"
        say "  #{silver ? 'silver' : 'gold'} lemmas: #{commafy(profile.total_tokens)} tokens · " \
            "#{commafy(profile.distinct_lemmas)} distinct lemmas · " \
            "#{commafy(profile.hapax_count)} hapax legomena " \
            "(#{profile.annotated_passages} of #{profile.passages} passages annotated)"
        if silver
          say "  lemma tier: silver (automatic lemmatization — token counts are not gold " \
              "attestation; corpus reference frequencies stay gold-only)"
        end
        print_vocab_distinctive(profile.distinctive)
        print_vocab_hapax(profile.hapax, profile.hapax_count)
      end

      # The distinctive-vocabulary table: lemma, its token count here, its corpus
      # passage-frequency, and the log-odds z-score, most distinctive first.
      def print_vocab_distinctive(distinctive)
        return if distinctive.empty?

        say ""
        say "  distinctive vocabulary (log-odds vs corpus, top #{distinctive.size}):"
        # Pad the lemma column by display cells (P35-7): a lzh/ojp lemma of Han
        # is two cells per ideograph, so char-count ljust would drift the table.
        width = distinctive.map { |e| Nabu::Display.width(e.lemma) }.max
        distinctive.each do |entry|
          say "    #{Nabu::Display.ljust(entry.lemma, width)}  #{entry.doc_count}× here · " \
              "#{commafy(entry.corpus_freq)}× corpus  (z=#{format('%.1f', entry.score)})"
        end
      end

      # The hapax legomena line: attested exactly once in this document. The full
      # count, then up to --limit spellings (they can number in the hundreds) —
      # or, under --long (house rule P15-8), every spelling with no "(+N more)"
      # tail. The full list already rides in the profile; --limit only caps the
      # print, so --long is a pure render concern here.
      def print_vocab_hapax(hapax, hapax_count)
        return if hapax_count.zero?

        say ""
        shown = options[:long] ? hapax : hapax.first(options[:limit].to_i)
        more = hapax_count - shown.size
        tail = more.positive? ? " (+#{commafy(more)} more)" : ""
        say "  hapax legomena (#{commafy(hapax_count)}, once each): #{shown.join(', ')}#{tail}"
      end

      # `vocab --by-century` (P15-2): the diachronic histogram of the dated
      # corpus, optionally filtered by a text query (plot a word across
      # centuries) and by --lang/--license/date/--place.
      def vocab_by_century(query)
        validate_license!(options[:license])
        from, to = date_window
        config = Nabu::Config.load
        catalog = open_catalog(config)
        raise Thor::Error, "no catalog — run nabu sync or nabu rebuild" unless catalog

        require_timeline!(catalog)
        fulltext = open_fulltext(config) unless query.empty?
        raise Thor::Error, "no index — run nabu sync or nabu rebuild" if !query.empty? && fulltext.nil?

        result = Nabu::Query::Century.new(catalog: catalog, fulltext: fulltext).run(
          query: query.empty? ? nil : query, lang: options[:lang], license: options[:license],
          from: from, to: to, place: options[:place]
        )
        print_century(result)
      ensure
        catalog&.disconnect
        fulltext&.disconnect
      end

      def print_century(result)
        say(if result.query
              "diachrony of #{result.query.inspect} (dated documents by century)"
            else
              "dated corpus by century"
            end)
        return say("  no dated documents match") if result.buckets.empty?

        width = result.buckets.map { |bucket| bucket.label.length }.max
        result.buckets.each do |bucket|
          say "  #{bucket.label.ljust(width)}  #{commafy(bucket.documents)} " \
              "#{bucket.documents == 1 ? 'document' : 'documents'}"
        end
        multi = result.multi_century.positive? ? "; #{commafy(result.multi_century)} span multiple centuries" : ""
        say "  #{commafy(result.total_documents)} dated documents (bucketed by earliest year#{multi})"
      end

      # A document with no gold lemmas: say so plainly and name the gold-bearing
      # languages (from the lemma index) so the user can profile something real.
      def print_vocab_no_gold(profile)
        say "  no gold lemmas — this document is not linguistically annotated " \
            "(0 of #{pluralize(profile.passages, 'passage')} carry one)."
        say "  Gold lemmas come from the treebank shelves (PROIEL, TOROT, ISWOC, " \
            "Universal Dependencies) and the ORACC cuneiform layer."
        # --long (house rule P15-8) lists every gold-bearing language; the compact
        # default shows the first eight with a "…" elision marker.
        shown = options[:long] ? profile.gold_languages : profile.gold_languages.first(8)
        langs = shown.map { |lang, count| "#{lang} (#{commafy(count)})" }
        ellipsis = profile.gold_languages.size > shown.size ? ", …" : ""
        say "  gold-bearing languages: #{langs.join(', ')}#{ellipsis}"
        say "  Try e.g. nabu vocab urn:nabu:proiel:caes-gal"
      end

      # Group an integer's digits into thousands (12345 → "12,345"). Plain string
      # work — no locale gem for one display nicety.
      def commafy(number)
        number.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
      end

      # One display line of pristine text: newlines flattened, capped at 100
      # chars (treebank sentences are single lines; the cap guards outliers).
      def truncate_line(text, max = 100)
        line = text.tr("\n", " ")
        line.length > max ? "#{line[0, max]}…" : line
      end

      # House-width prose wrap for the card's description lane (P24-0) —
      # whole words, no truncation: the card serves the dossier's 1–3
      # sentences in full.
      def wrap_text(text, width: 76)
        text.split(/\s+/).each_with_object([]) do |word, lines|
          if lines.empty? || lines.last.length + word.length + 1 > width
            lines << word.dup
          else
            lines.last << " " << word
          end
        end
      end

      # Render dictionary entries whole (the CLI is the unbounded surface):
      # header with license label, gloss, the structured body, then the
      # resolved citations as show-able urns. Unresolved citations already
      # read inline in the body text.
      # +catalog+ (P24-1): when given, each entry's owner notes render after
      # its body — the note lane on the dictionary surface.
      def print_define_results(lemma, results, catalog: nil)
        if results.empty?
          return say("no dictionary entry for #{lemma} — #{@shelf_summary}; " \
                     "give a dictionary form (search --lemma finds attestations)")
        end

        results.each_with_index do |result, index|
          say "" if index.positive?
          print_define_entry(result)
          print_notes_footer(catalog, result) if catalog
        end
      end

      # One entry, the define house format — shared verbatim by `show` on a
      # dictionary-entry urn (P22-2), where a withdrawn entry reads honestly.
      # The language code rides the header (P46-r6, owner report: a WOLD hit
      # named no language — obvious for LSJ, load-bearing for the
      # multi-language shelves), the etym-entry style.
      def print_define_entry(result)
        lang = result.language.to_s.empty? ? "" : " [#{result.language}]"
        say "#{result.headword}#{lang} — #{result.dictionary_title} [#{result.license_class}]" \
            "#{' (withdrawn)' if result.withdrawn}  #{result.urn}"
        say "  gloss: #{result.gloss}" if result.gloss
        say ""
        say result.body
        print_reflexes(result.reflexes)
        print_resolved_citations(result)
      end

      # -- nabu signs (P53-2) ----------------------------------------------------

      def signs_dialect(name)
        return nil if name.nil?
        return name.to_sym if Nabu::AtfTokenizer::DIALECTS.map(&:to_s).include?(name)

        raise Thor::Error, "signs: unknown dialect #{name.inspect} — the known dialects are " \
                           "#{Nabu::AtfTokenizer::DIALECTS.join(', ')} (catf is the default)"
      end

      # Urn mode: language from the row (--lang overrides), the :etcsl
      # dialect auto-selected for the etcsl shelf (--dialect overrides).
      def signs_urn_result(urn, list:, catalog:, dialect:)
        result = Nabu::Query::Signs.new(sign_list: list, catalog: catalog)
                                   .run_urn(urn, language: options[:lang], dialect: dialect)
        raise Thor::Error, "signs: urn not found: #{urn}" if result.nil?

        result
      rescue Nabu::Query::Signs::Error => e
        raise Thor::Error, "signs: #{e.message}"
      end

      # The `nabu char` mold: readable columns, absent data ABSENT (a broken
      # token's row is its status; an unknown one says so plainly).
      def print_signs(result)
        say signs_header(result)
        result.lines.each do |line|
          say ""
          say "#{line.urn || "line #{line.number}"}  ·  #{line.text}"
          line.tokens.each { |token| print_signs_token(token) }
        end
        say ""
        say signs_footer(result)
      end

      def signs_header(result)
        parts = [result.mode == :urn ? result.urn : "raw ATF"]
        parts << result.language if result.language
        parts << "[#{result.source_slug}]" if result.source_slug
        parts << "dialect etcsl (c→š, j→ŋ)" if result.dialect == :etcsl
        parts.join("  ·  ")
      end

      def print_signs_token(token)
        columns = [token.input_value.ljust(14), (token.determinative ? "det" : "   "),
                   token.status.ljust(13), signs_token_detail(token)]
        say "  #{columns.join(' ')}".rstrip
        token.candidates.each do |candidate|
          say "  #{' ' * 19}#{candidate.status.ljust(13)} #{signs_candidate_detail(candidate)}"
        end
      end

      def signs_token_detail(token)
        case token.status
        when "ambiguous" then "#{token.candidates.size} candidates:"
        when "unknown" then "not in the sign list"
        when "broken" then nil
        else signs_candidate_detail(token)
        end
      end

      # sign name · codepoints · glyph · (%lang) · (form of X) — only what
      # the record holds; an unencoded sign says "unencoded". The form-of
      # tail is the kunga₃ fix: a sign and its same-named variant form of
      # ANOTHER sign must never render as indistinguishable twins.
      def signs_candidate_detail(token)
        parts = [token.sign_name]
        parts << (token.codepoints ? token.codepoints.join(" ") : "unencoded")
        parts << token.glyph if token.glyph
        parts << "(%#{token.language_qualifier})" if token.language_qualifier
        parts << "(form of #{token.form_of})" if token.form_of
        parts.compact.join("  ")
      end

      def signs_footer(result)
        tokens = result.lines.flat_map(&:tokens)
        tally = tokens.group_by(&:status).transform_values(&:size)
        parts = ["#{tokens.size} token(s)"]
        %w[deterministic qualified ambiguous no-codepoint broken unknown].each do |status|
          parts << "#{status} #{tally[status]}" if tally[status]
        end
        parts << "#{result.skipped_lines} structural line(s) skipped" if result.skipped_lines.positive?
        parts.join("  ·  ")
      end

      # The character card (P37-4): each section printed only when a held
      # shelf backs it for this glyph (the "absent, never —" rule). The
      # diachronic column is what nabu adds over Jisho; the synchronic
      # sections match it field-for-field where the shelves reach.
      def print_char_card(card)
        return say("no dictionary shelf in this catalog yet — run nabu sync unihan") if card.nil?

        say "#{card.glyph}  #{card.codepoint}#{char_header_tail(card)}"
        print_char_decomposition(card)
        print_char_components(card)
        print_char_variants(card)
        print_char_ja_readings(card)
        print_char_sinoxenic(card)
        print_char_pedagogy(card)
        print_char_desk_reference(card)
        print_char_diachronic(card)
        print_char_corpus(card)
        print_char_search_affordances(card)
        print_char_absence(card)
      end

      # glyph · N strokes · radical M NAME — only the parts Unihan backs.
      def char_header_tail(card)
        parts = []
        parts << "#{card.total_strokes} strokes" if card.total_strokes
        parts << "radical #{card.radical.number} #{card.radical.glyph} #{card.radical.name}" if card.radical
        parts.empty? ? "" : "  ·  #{parts.join('  ·  ')}"
      end

      def print_char_decomposition(card)
        return if card.ids.empty?

        say ""
        say "decomposition (BabelStone IDS):"
        card.ids.each do |ids|
          tag = ids.sources ? " (#{ids.sources})" : ""
          say "  #{ids.sequence}#{tag}"
          ids.components.each do |component|
            say "    #{component} — nabu char #{component} · nabu search --char-component #{component}"
          end
        end
      end

      def print_char_components(card)
        return if card.components.empty?

        say ""
        say "components (KRADFILE index): #{card.components.join(' ')}"
      end

      def print_char_variants(card)
        return if card.variants.empty?

        say ""
        say "variants:"
        card.variants.each do |variant|
          say "  #{variant.relation}: #{variant.glyph} (#{variant.codepoint}) — nabu char #{variant.glyph}"
        end
      end

      def print_char_ja_readings(card)
        readings = card.readings_ja or return
        say ""
        say "readings (ja, KANJIDIC2):"
        say "  on: #{readings[:on].join('、')}" if readings[:on].any?
        say "  kun: #{readings[:kun].join('、')}" if readings[:kun].any?
        say "  nanori: #{readings[:nanori].join('、')}" if readings[:nanori].any?
        say "  meanings: #{readings[:meanings].join('; ')}" if readings[:meanings].any?
      end

      def print_char_sinoxenic(card)
        return if card.readings_sinoxenic.empty?

        say ""
        say "readings (sinoxenic, Unihan):"
        card.readings_sinoxenic.each { |label, value| say "  #{label}: #{value}" }
      end

      def print_char_pedagogy(card)
        pedagogy = card.pedagogy or return
        say ""
        labels = { "grade" => "Jōyō grade", "jlpt" => "JLPT", "freq" => "newspaper freq" }
        say "pedagogy: #{pedagogy.map { |k, v| "#{labels[k]} #{v}" }.join('  ·  ')}"
      end

      def print_char_desk_reference(card)
        return if card.desk_reference.empty?

        say ""
        say "desk reference: #{card.desk_reference.map { |k, v| "#{k} #{v}" }.join('  ·  ')}"
      end

      # The diachronic column — the half no dictionary site carries.
      def print_char_diachronic(card)
        print_char_shelf_block("Old Chinese (Baxter-Sagart)", card.old_chinese)
        print_char_shelf_block("Middle Chinese (Qieyun / Baxter-Sagart)", card.middle_chinese)
        print_char_shelf_block("early-Japan lexicography (HDIC)", card.early_japan)
        print_char_tls(card.tls)
      end

      def print_char_shelf_block(label, entries)
        return if entries.empty?

        say ""
        say "#{label}:"
        entries.each do |entry|
          say "  [#{entry.slug}] #{entry.gloss || entry.lines.first}"
          entry.lines.each { |line| say "    #{line}" }
        end
      end

      def print_char_tls(entries)
        return if entries.empty?

        say ""
        say "TLS (Thesaurus Linguae Sericae):"
        entries.each do |entry|
          attest = entry.attestations.positive? ? " — #{entry.attestations} attestation(s)" : ""
          say "  [#{entry.slug}] #{entry.gloss}#{attest}"
          entry.lines.each { |line| say "    #{line}" }
        end
      end

      def print_char_corpus(card)
        return if card.corpus.empty?

        say ""
        totals = card.corpus.sort_by { |_, count| -count }
                            .map { |lang, count| "#{lang} #{count}" }.join("  ·  ")
        say "corpus attestation: #{totals}"
      end

      def print_char_search_affordances(card)
        say ""
        say "search: nabu search #{card.glyph}  ·  nabu search --char-component #{card.glyph}" \
            "#{"  ·  nabu search --radical #{card.radical.number}" if card.radical}"
      end

      # When NOTHING backed the card, say so honestly (the glyph is unknown to
      # every held shelf) rather than printing a bare header.
      def print_char_absence(card)
        return unless card.held_shelves.empty? && card.ids.empty? && card.components.empty? &&
                      card.radical.nil? && card.corpus.empty?

        say ""
        say "no held shelf carries #{card.glyph} yet — sync the CJK shelves " \
            "(unihan, edrdg, babelstone-ids, kradfile, baxter-sagart, tshet-uinh, hdic, tls)"
      end

      # A reconstruction entry's descendant reflexes (P14-1): attested-here
      # cognates first with their gold-lemma passage counts, then an honest
      # one-line summary of the rest (the full tree is in the data; the
      # attested ones are the actionable ones).
      #
      # The tier rule (P26-0): attested_count IS the gold count — a silver
      # (automatic-lemmatization) count renders beside it as "(+N silver)",
      # and a silver-ONLY reflex gets its own labeled section, "silver N
      # passages". NEVER a bare number that could read as gold. The
      # equivalence tier (P34-3) rides the same contract with its own name:
      # "(+N equivalence)" beside gold, an equivalence-only section below —
      # scholar-curated Classical-Latin equivalents on non-Latin passages,
      # never attestation.
      def print_reflexes(reflexes)
        return if reflexes.empty?

        attested, uncounted = reflexes.partition(&:attested_count)
        silver_only, unattested = uncounted.partition(&:silver_count)
        equivalence_only, rest = unattested.partition(&:equivalence_count)
        unless attested.empty?
          say ""
          say "attested in this corpus (nabu search --lemma):"
          attested.sort_by { |r| -r.attested_count }.each do |r|
            say "  [#{r.language}] #{reflex_form(r)} — #{r.attested_count} " \
                "#{r.attested_count == 1 ? 'passage' : 'passages'}#{tier_suffixes(r)}"
          end
        end
        unless silver_only.empty?
          say ""
          say "silver-only (automatic lemmatization — not gold-attested; nabu search --lemma):"
          silver_only.sort_by { |r| -r.silver_count }.each do |r|
            say "  [#{r.language}] #{reflex_form(r)} — silver #{r.silver_count} " \
                "#{r.silver_count == 1 ? 'passage' : 'passages'}"
          end
        end
        unless equivalence_only.empty?
          say ""
          say "equivalence-only (scholar-curated Classical-Latin equivalents on non-Latin " \
              "passages — not attested in this language; nabu search --lemma):"
          equivalence_only.sort_by { |r| -r.equivalence_count }.each do |r|
            say "  [#{r.language}] #{reflex_form(r)} — equivalence #{r.equivalence_count} " \
                "#{r.equivalence_count == 1 ? 'passage' : 'passages'}"
          end
        end
        return if rest.empty?

        say ""
        options[:long] ? print_reflexes_expanded(rest) : print_reflexes_capped(rest)
      end

      # The labeled non-gold riders on a gold-attested line (P26-0 silver,
      # P34-3 equivalence) — each tier under its own name, never summed.
      def tier_suffixes(reflex)
        suffix = reflex.silver_count ? " (+#{reflex.silver_count} silver)" : ""
        suffix += " (+#{reflex.equivalence_count} equivalence)" if reflex.equivalence_count
        suffix
      end

      # Compact default (house compact-CLI rule): the first ten non-attested
      # reflexes inline, the tail honestly summarised as "… and N more".
      def print_reflexes_capped(rest)
        say "other reflexes (not attested here): " \
            "#{rest.first(10).map { |r| "[#{r.lang_code}] #{reflex_form(r)}" }.join(', ')}" \
            "#{" … and #{rest.size - 10} more" if rest.size > 10}"
      end

      # --long (P14-11): the WHOLE non-attested list, grouped by language so a
      # long tail (a Proto-Slavic root can name 25+ descendants) stays readable
      # — languages in first-seen (stored depth-first) order, forms within a
      # language in stored order. Nothing is elided under the flag.
      # P18-4 render verdict: each group header carries the code's NAME
      # inline when the library knows one ("[gkm · Medieval Greek]") — one
      # name per LINE, so the compact rule holds exactly where the owner's
      # pain was; the capped default stays code-only (ten names inline would
      # blow the line) and etym's footer points at `nabu language` instead.
      # P57-4: when Nabu::Lects is present the label prefers the RESOLVED
      # lect id + its composed registry name ("[grc:byz · Byzantine Greek]"
      # for gkm — the codemap default) over the old kaikki-census reading;
      # absent Lects, or a resolved id with no registry entry, unchanged.
      def print_reflexes_expanded(rest)
        say "other reflexes (not attested here) — all #{rest.size}, grouped by language:"
        rest.group_by(&:lang_code).each do |lang_code, group|
          say "  #{reflex_group_label(lang_code)} #{group.map { |r| reflex_form(r) }.join(', ')}"
        end
      end

      def reflex_group_label(lang_code)
        if @lects
          resolved = @lects.resolve(lang_code)
          lect = @lects.lect(resolved)
          return "[#{resolved} · #{lect.name}]" if lect
        end
        name = @languages&.name(lang_code)
        name ? "[#{lang_code} · #{name}]" : "[#{lang_code}]"
      end

      # P17-3: the per-edge loan label — a borrowed-flagged reflex reads
      # "(loan)"; unflagged and not-yet-reparsed (NULL) edges stay bare.
      def reflex_form(reflex)
        base = reflex.roman && reflex.roman != reflex.word ? "#{reflex.word} (#{reflex.roman})" : reflex.word
        reflex.borrowed ? "#{base} (loan)" : base
      end

      # etym (P14-1; multi-hop P17-3): one block per entry — where the walk
      # entered (matched reflex → *headword), the entry's own reflex list,
      # then the ancestor CHAIN, indented one step per shelf hop (the
      # shelf-visited walk: богъ → *bogъ ← *bogù ← *bʰag-). A loan edge
      # labels its arrow: "←(loan)". --long expands the cognate lists; the
      # chain itself is already bounded (each shelf enters once per walk).
      def print_etym_results(results)
        results.each_with_index do |result, index|
          say "" if index.positive?
          print_etym_entry(result, 0)
        end
        # P18-4: one footer line, the desk-reference pointer — the compact
        # render keeps raw codes, this names the way out.
        say ""
        say "codes: nabu language CODE — name, context, and what this library holds"
      end

      # P24-2: the crosswalk-miss path. When the dictionary shelf holds the
      # lemma (Vasmer's prose etymologies carry no reflex edges), render
      # those entries in the define house format under an honest header —
      # print_define_entry, zero renderer divergence. A genuine total miss
      # enumerates the crosswalk shelves DB-DRIVEN (Query::Etym
      # #crosswalk_shelves — the P11 DEFINE_LANGS hardcoded-list lesson),
      # keeping the '*form' quoting hint.
      def print_etym_fallback(lemma, entries, shelves:)
        if entries.empty?
          covered = shelves.empty? ? "no shelves yet (run nabu sync wiktionary-recon)" : shelves.join(", ")
          return say("no reconstruction names #{lemma} as a descendant, no reconstruction " \
                     "headword matches it, and no dictionary entry defines it — the crosswalk " \
                     "covers #{covered} (nabu language CODE explains any). Try the lemma's " \
                     "dictionary form, or a quoted '*form' for a direct lookup (quote the " \
                     "star — zsh expands a bare *)")
        end

        say "no reconstruction path in the crosswalk for #{lemma} — the dictionary shelf holds:"
        entries.each do |result|
          say ""
          print_define_entry(result)
        end
      end

      def print_etym_entry(result, depth)
        indent = "  " * depth
        arrow = if depth.positive?
                  result.edge_borrowed ? "←(loan) " : "← "
                else
                  ""
                end
        say "#{indent}#{arrow}#{etym_entry_line(result)}  #{result.urn}"
        say "#{indent}  gloss: #{result.gloss}" if result.gloss
        print_reflexes(result.cognates)
        result.ancestors.each do |ancestor|
          say ""
          print_etym_entry(ancestor, depth + 1)
        end
      end

      def etym_entry_line(result)
        via = result.matched_reflex
        prefix =
          if via
            "#{via.word} [#{lect_bracket(via.language, via.lect_id, via.lect_name)}]" \
              "#{' (loan)' if via.borrowed} → "
          else
            ""
          end
        "#{prefix}#{result.headword} [#{lect_bracket(result.language, result.lect_id, result.lect_name)}] — " \
          "#{result.dictionary_title} [#{result.license_class}]"
      end

      # P57-4 (etym display through the mapping): when Nabu::Lects is
      # present AND the resolved id has a registry entry, render "id ·
      # name" instead of the bare stored code — display-only, the raw code
      # is never touched. Absent either condition, the bracket is exactly
      # the raw code, unchanged.
      def lect_bracket(code, lect_id, lect_name)
        lect_id && lect_name ? "#{lect_id} · #{lect_name}" : code
      end

      # -- language (P18-4, rehomed P19-1): the code desk reference ---------------

      # THE canonical-memory migration (P19-1, owner-fired): ledger
      # language_notes (+ the retired seed yml, when a checkout still has
      # one) → canonical/local-language/<code>.md dossiers. Absence-filling
      # and idempotent — safe to re-run; a dossier lane that already exists
      # (a redirected accretion landed first, or the owner edited) is never
      # overwritten. After it: bin/nabu sync local-language derives the
      # catalog records the card reads.
      def export_language_dossiers(config)
        ledger = open_ledger(config)
        dir = Nabu::LanguageShelf.dir(config.canonical_dir)
        seed = File.join(config.config_dir, "languages.yml")
        report = Nabu::LanguageDossierExport.new(ledger: ledger, dir: dir,
                                                 seed_path: File.file?(seed) ? seed : nil)
                                            .run!(dry_run: options[:"dry-run"])
        verb = options[:"dry-run"] ? "would write" : "wrote"
        line = "dossiers: #{verb} #{report.written}, #{report.unchanged} unchanged"
        line += ", #{report.lanes_kept} lane(s) kept (already in a dossier)" if report.lanes_kept.positive?
        say "#{line} → #{dir}"
        say "next: bin/nabu sync local-language (derives the catalog records)" unless options[:"dry-run"]
      ensure
        ledger&.disconnect
      end

      # The card: headline (code — name), family line, curated context (or
      # the family's, labeled; or an honest absence), accreted extra-kind
      # notes (P18-5 — "iecor: IE-CoR variety: …", one line per kind), then
      # live relevance with zero fields suppressed, then the P57-4 stage
      # ladder (when Lects is present and the anchor has registered stages —
      # card-worthy on its own even when nothing else about the bare code is
      # curated: a real ladder is content, not a miss). An unknown code
      # misses honestly, with a family hint when the prefix is a known family.
      def print_language_card(code, languages, info, registry: nil, lects: nil)
        name = languages.name(code)
        context = languages.context(code)
        extras = languages.extra_notes(code)
        fallback = languages.family_fallback(code)
        relevance = info&.relevance(code)
        held = relevance && !relevance.empty?
        stages = lects&.stages_of(code) || []
        return print_language_miss(code, fallback) unless name || context || held || extras.any? || stages.any?

        say "#{code} — #{name || '(no name in the held kaikki extracts)'}"
        print_language_family(code, languages, fallback)
        print_language_context(context, fallback)
        # The accreted dossier "stages" section (Nabu::LectDossiers) never
        # renders here — the card owns the LIVE ladder below (same registry
        # facts plus per-stage holdings); printing both would double the
        # surface. Every other accreted kind renders as before.
        extras.except(Nabu::LectDossiers::KIND).each { |kind, body| say_wrapped("#{kind}: #{body}", indent: 2) }
        print_language_witnesses(code, languages)
        print_language_relevance(code, relevance) if relevance
        print_language_axes(code, info, registry)
        print_language_stage_ladder(code, stages, lects, info)
      end

      # P57-4: the stage ladder — every registered stage of +code+ (ord-
      # sorted, already Nabu::Lects#stages_of's contract), each with its
      # band and LIVE holdings: every (language, source) pair the catalog
      # actually carries, resolved through Nabu::Lects#resolve and grouped
      # by resolved lect. A bare-anchor resolution (no stage of its own —
      # still filed under the anchor itself, or reached one whose stage this
      # card does not list) groups under one honest "unstaged" line. A
      # resolution to a DIFFERENT anchor entirely (derom's la-vul -> roa:pro)
      # never enters this ladder — it is a different code's holdings.
      # Reconstructed stages (registry mode: reconstructed) carry the same
      # leading asterisk the etym/define shelves use.
      def print_language_stage_ladder(code, stages, lects, info)
        varieties = lects&.varieties_of(code) || []
        return if (stages.empty? && varieties.empty?) || !info

        totals, variety_totals =
          if info.lect_materialized?
            ladder_totals_from_facets(code, info)
          else
            ladder_totals_from_pairs(code, lects, info)
          end
        return if totals.values.sum.zero? && variety_totals.values.sum.zero?

        if stages.any?
          say "  stages:"
          stages.each do |stage|
            star = stage.mode == :reconstructed ? "*" : ""
            band = stage.band ? " (#{Nabu::Timeline.format_span(stage.band[0], stage.band[1])})" : ""
            say "    #{star}#{stage.stage}  #{stage.name}#{band} — #{plural(totals[stage.id], 'document')}"
          end
        end
        # P58 rider (the owner's zho probe): registered REGISTERS are ladder
        # content — zho/lit is wenyan, not "unstaged". P59-2 (the compose
        # rules): the register line counts EVERY document carrying the
        # variety — stage-less resolutions AND staged-and-varietied ones
        # (akk:na/lit); the latter still fold under their stage above, so
        # the stage column sums to the corpus while the register column
        # reads as an overlay.
        if varieties.any?
          say "  registers:"
          varieties.each do |variety|
            title = variety.name.split(" — ", 2).last
            say "    /#{variety.variety}  #{title} — #{plural(variety_totals[variety.variety], 'document')}"
          end
        end
        unstaged = totals[:unstaged]
        say "    unstaged  — #{plural(unstaged, 'document')}" if unstaged.positive?
      end

      # P58-6: once a materialization exists, the ladder reads the lect
      # facet — the only source that sees per-DOCUMENT journal rulings.
      # Values under other anchors (derom's la-vul -> roa:pro) drop here
      # exactly as they did on the pairs path.
      # Returns [totals, variety_totals]: totals keys stage/register ladder
      # lines (staged-and-varietied folds under its stage); variety_totals
      # counts every carrier of a variety, staged or not — the register
      # line's overlay count (P59-2).
      def ladder_totals_from_facets(code, info)
        totals = Hash.new(0)
        variety_totals = Hash.new(0)
        facet_counts, identity = info.lect_facet_totals(code)
        facet_counts.each do |value, count|
          match = Nabu::Lects.parse_id(value)
          next unless match && match[:anchor] == code.to_s

          totals[ladder_key(code, match)] += count
          variety_totals[match[:variety]] += count if match[:variety]
        end
        totals[:unstaged] += identity if identity.positive?
        [totals, variety_totals]
      end

      # Stage wins (lat:late/ecc groups under lat:late); a stage-less
      # variety is a register line (zho/lit); everything else is honest
      # unstaged.
      def ladder_key(code, match)
        return "#{code}:#{match[:stage]}" if match[:stage]
        return "#{code}/#{match[:variety]}" if match[:variety]

        :unstaged
      end

      # The P57-4 path — a never-materialized catalog resolves (language,
      # source) pairs live, byte-identically to before.
      def ladder_totals_from_pairs(code, lects, info)
        totals = Hash.new(0)
        variety_totals = Hash.new(0)
        info.language_source_pairs.each do |(language, source_slug), count|
          resolved = lects.resolve(language, source: source_slug)
          match = Nabu::Lects.parse_id(resolved)
          next unless match && match[:anchor] == code.to_s

          totals[ladder_key(code, match)] += count
          variety_totals[match[:variety]] += count if match[:variety]
        end
        [totals, variety_totals]
      end

      # P48-r3: the related research desks — every axis whose member
      # sources hold this code (≥1 live document or a dictionary shelf),
      # in ratified (file) order. A code held by no axis-tagged source
      # prints nothing (the house zero-field rule).
      # P49-r4: multilingual packs (the registry marker) never attribute —
      # a pack's whole-grain axes union describes no single held language,
      # so its three hbo docs must not drag twelve desks onto the hbo card.
      # The desks keep the code via any DEDICATED source that holds it.
      # The simple exclusion was chosen over a dominance/share threshold
      # deliberately (era-bound-constants doctrine): any tuned cutoff is a
      # census claim that rots as packs grow, while "packs never attribute,
      # dedicated holders always do" stays true at every census. A pack-only
      # code honestly gets no axes line; its desks still surface the code
      # WITH COUNTS on the axis card's languages: line — the deliberate
      # asymmetry (counts are the honesty mechanism there, print_axis_languages).
      def print_language_axes(code, info, registry)
        return unless info && registry && !registry.axes.empty?

        slugs = info.holding_slugs(code).reject { |slug| registry.multilingual?(slug) }
        return if slugs.empty?

        names = registry.axes.each_axis.map(&:name)
                        .select { |name| registry.axis_members(name).intersect?(slugs) }
        say "  axes: #{names.join(', ')}" unless names.empty?
      end

      # P18-6: the per-source witness notes (kind "witness:<slug>" — what
      # each held source says about this language stage; LIV/EDL accrete
      # them at sync with per-record provenance). One wrapped line per
      # source, quiet when none.
      def print_language_witnesses(code, languages)
        languages.witnesses(code).each do |source, body|
          say_wrapped("witness (#{source}): #{body}", indent: 2)
        end
      end

      def print_language_miss(code, fallback)
        say "#{code} — unknown here: no held text, no shelf, no etymology edge, " \
            "and no name in the held kaikki extracts"
        if fallback
          hint = [fallback.name, fallback.context].compact.join(": ")
          say_wrapped("family hint: #{fallback.code}-* — #{hint}", indent: 2)
        end
        say "  held languages: nabu language --list"
      end

      def print_language_family(code, languages, fallback)
        family = languages.family(code)
        if family
          say_wrapped("family: #{family}", indent: 2)
        elsif fallback&.name
          say_wrapped("family: #{fallback.code}-* — #{fallback.name}", indent: 2)
        end
      end

      def print_language_context(context, fallback)
        if context
          say_wrapped(context, indent: 2)
        elsif fallback&.context
          say_wrapped("(no curated note for this code — its #{fallback.code}-* family:) " \
                      "#{fallback.context}", indent: 2)
        else
          say "  (no curated note)"
        end
      end

      def print_language_relevance(code, rel)
        corpus = []
        corpus << plural(rel.documents, "document") if rel.documents.positive?
        corpus << "#{commas(rel.passages)} passages" if rel.passages.positive?
        say "  corpus: #{corpus.join(' · ')}" unless corpus.empty?
        say "  gold lemmas: #{commas(rel.lemma_rows)} rows (nabu search --lemma)" if rel.lemma_rows.positive?
        unless rel.shelves.empty?
          shelf_list = rel.shelves.map { |shelf| "#{shelf.title} (#{commas(shelf.entries)} entries)" }
          say "  dictionary: #{shelf_list.join(' · ')}"
        end
        say "  etymology: #{commas(rel.reflex_edges)} reflex #{rel.reflex_edges == 1 ? 'edge' : 'edges'}" \
          if rel.reflex_edges.positive?
        print_language_long(code, rel) if options[:long]
      end

      # --long: per-source document counts and the upstream-code split of
      # the etymology edges (chu's edges arrive as Wiktionary's "cu").
      def print_language_long(code, rel)
        unless rel.sources.empty?
          say "  by source: #{rel.sources.map { |slug, docs| "#{slug} #{commas(docs)}" }.join(' · ')}"
        end
        return unless rel.edge_codes.any? && rel.edge_codes.keys != [code]

        say "  edge codes: #{rel.edge_codes.map { |edge_code, n| "#{edge_code} #{commas(n)}" }.join(' · ')}"
      end

      # --list: the held languages only (a full dump of the ~800-code
      # etymology tail would be unusable and unpageable; the tail is what
      # `language CODE` is for — stated in the footer, never implied away).
      def print_language_list(languages, info)
        raise Thor::Error, "no corpus — run nabu sync or nabu rebuild" unless info

        held = info.held
        say "held languages (#{held.size} with corpus documents, gold lemmas, or a shelf):"
        width = held.map { |entry| entry.code.length }.max || 0
        held.each do |entry|
          say "  #{entry.code.ljust(width)}  #{languages.name(entry.code) || '(unnamed)'} — " \
              "#{held_line(entry)}"
        end
        say "etymology tail: ~800 more codes appear in reflex edges — nabu language CODE explains any"
      end

      def held_line(entry)
        bits = []
        bits << "#{commas(entry.documents)} docs" if entry.documents.positive?
        bits << "#{commas(entry.lemma_rows)} lemma rows" if entry.lemma_rows.positive?
        (bits + entry.shelves).join(" · ")
      end

      def commas(count)
        count.to_s.gsub(/\B(?=(\d{3})+\z)/, ",")
      end

      # Wrap prose to the card's width, every line indented.
      def say_wrapped(text, indent:, width: 78)
        pad = " " * indent
        line = +""
        text.split(/\s+/).each do |word|
          if line.empty?
            line << word
          elsif pad.length + line.length + 1 + word.length > width
            say "#{pad}#{line}"
            line = +word
          else
            line << " " << word
          end
        end
        say "#{pad}#{line}" unless line.empty?
      end

      # --langs as an array: comma-joined on the CLI, validated by the query.
      def parse_langs(value)
        return nil if value.nil?

        value.split(",").map(&:strip).reject(&:empty?)
      end

      # cognates (P15-3): header with honest totals + the suppression count,
      # then one compact block per (verse, root) hit — the root line carries
      # the SHELF (a gem-pro meet with a Slavic witness reads as a borrowing;
      # see the command help), each witness its lemma and attested forms.
      def print_cognates(result)
        say "#{result.query} — work #{result.work} · shared-root verses across witnesses"
        say "  #{cognates_counts(result)}"
        if result.truncated
          say "  showing first #{result.groups.size} of #{result.total} hits — narrow the " \
              "target, or pass --long to render all"
        end
        result.groups.each { |group| print_cognates_group(group, result.documents) }
      end

      def cognates_counts(result)
        verses = result.groups.map(&:ref).uniq.size
        roots = result.groups.map { |group| group.root.urn }.uniq.size
        counts = if result.total.zero?
                   "no hits — no verse here has two witnesses on one root"
                 else
                   "#{plural(result.total, 'hit')} · #{plural(verses, 'verse')} · " \
                     "#{plural(roots, 'root')}"
                 end
        return counts if result.suppressed.zero?

        "#{counts}; #{result.suppressed} common-word #{result.suppressed == 1 ? 'hit' : 'hits'} " \
          "suppressed (--all shows them)"
      end

      def print_cognates_group(group, documents)
        say ""
        say "#{group.ref}  #{group.root.headword} [#{group.root.shelf} · #{group.root.license_class}]"
        if options[:long]
          say "    #{group.root.dictionary_title}#{" · gloss: #{group.root.gloss}" if group.root.gloss}"
        end
        group.witnesses.each do |witness|
          loan = witness.borrowed ? " (loan)" : ""
          say "    #{witness.language.ljust(4)} #{display_text(witness.lemma, witness.language)}" \
              "#{loan}#{cognates_surfaces(witness)}"
          next unless options[:long]

          witness.document_urns.each do |urn|
            doc = documents[urn]
            say "         #{urn}#{" — #{doc[:title]} [#{doc[:license_class]}]" if doc}"
          end
        end
      end

      # The attested forms, shown when they add anything over the lemma.
      def cognates_surfaces(witness)
        forms = witness.surfaces - [witness.lemma]
        return "" if forms.empty?

        " — attested as #{forms.map { |form| display_text(form, witness.language) }.join(', ')}"
      end

      # Compact default (house compact-CLI rule, the print_reflexes
      # precedent's inline-cap shape): TLS attestation citations (P34-4)
      # put thousands of resolved rows on common words (之 carries 2,587
      # attestations), so the first 12 print inline and the tail is
      # summarised; --long expands every one. LSJ/MW-scale entries sit
      # under the cap and never see it.
      def print_resolved_citations(result)
        resolved = result.citations.select(&:resolved_urn)
        return if resolved.empty?

        say ""
        say "resolved citations (in this corpus — nabu show <urn>):"
        shown = options[:long] ? resolved : resolved.first(12)
        shown.each { |citation| say "  #{citation.label} → #{citation.resolved_urn}" }
        rest = resolved.size - shown.size
        say "  … and #{rest} more (--long shows all)" if rest.positive?
      end

      # A print-free runner needs a sink for live progress; the CLI owns all
      # formatting and tty decisions here. Progress goes to $stderr (final counts
      # go to $stdout via `say`, so scripts piping stdout are unaffected). When
      # $stderr is a tty: git output streams raw (its own \r overwrites the line)
      # and a \r-updating "loading…" counter refreshes each tick. Non-tty: no git
      # streaming (callbacks stay nil) and one plain line per 100 documents.
      def progress_reporter
        tty = $stderr.tty?
        state = { stage: nil, started: nil, processed: 0, errored: 0, last: 0 }
        @progress_state = state
        Nabu::ProgressReporter.new(
          on_fetch_line: tty ? ->(line) { $stderr.print(line) } : nil,
          on_load_tick: load_tick(tty, state),
          on_stage: stage_tick(tty, state)
        )
      end

      # Owner feedback (2026-07-18): a long rebuild must name the source it
      # is on and how long each stage took. A stage closes when the next one
      # opens (or at finish_progress), its line ending in final counts +
      # elapsed; sync paths never call stage, so they keep the bare counter.
      def stage_tick(tty, state)
        lambda do |label|
          close_stage(state)
          state[:stage] = label
          state[:started] = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          state[:processed] = state[:errored] = state[:last] = 0
          $stderr.print("\r\e[K  #{label}… ") if tty
        end
      end

      def close_stage(state)
        return if state[:stage].nil?

        line = "  #{state[:stage]}… #{stage_counts(state)}#{format_elapsed(state)}"
        $stderr.tty? ? $stderr.print("\r\e[K#{line}\n") : warn(line)
        state[:stage] = nil
      end

      # Zero docs is a timeline/facet/index stage, not an empty shelf — show
      # only the timing (compact-output convention: suppress zero fields).
      def stage_counts(state)
        return "" if state[:processed].zero? && state[:errored].zero?

        "#{state[:processed]} docs#{quarantine_suffix(state[:errored])} "
      end

      def format_elapsed(state)
        secs = Process.clock_gettime(Process::CLOCK_MONOTONIC) - state[:started]
        secs < 60 ? "#{secs.round(1)}s" : "#{(secs / 60).floor}m#{format('%02d', (secs % 60).round)}s"
      end

      def load_tick(tty, state)
        lambda do |processed, errored|
          state[:processed] = processed
          state[:errored] = errored
          label = state[:stage] || "loading"
          if tty
            $stderr.print("\r\e[K  #{label}… #{processed} docs#{quarantine_suffix(errored)}  ")
          elsif processed - state[:last] >= (state[:stage] ? 1000 : 100)
            state[:last] = processed
            warn("  #{label}… #{processed} docs#{quarantine_suffix(errored)}")
          end
        end
      end

      def quarantine_suffix(errored)
        errored.positive? ? " (#{errored} quarantined)" : ""
      end

      # Break off the \r-updated counter line before the final counts —
      # closing the open stage (with its timing) when there is one.
      def finish_progress
        if @progress_state && @progress_state[:stage]
          close_stage(@progress_state)
        elsif $stderr.tty?
          $stderr.print("\n")
        end
      end

      # sync dispatch (P35-2): --all first (flat batch), then --axis (grouped),
      # then the positional NAME resolved EXACT-SLUG-FIRST-THEN-AXIS. The
      # slug/axis namespaces can never collide (a load-time guarantee), so a
      # name that is not a slug but is an axis is unambiguous; a name that is
      # neither is the unknown-target error (naming BOTH namespaces). A nil
      # name falls to sync_one's own "slug or --all" guard, unchanged.
      def run_sync(runner, registry, slug, db, ledger, enabled:)
        return sync_all(runner, enabled: enabled) if options[:all]
        return sync_axes(runner, registry, options[:axis].split(","), db, ledger) if options[:axis]

        if slug.nil? || registry[slug]
          # P44-r3b: the enablement acquisition gate is on the EXPLICIT
          # single-source path only. Axis fan-out keeps its registry-enabled
          # membership rule (below); --all applies the enabled-set filter itself.
          enforce_enablement!(registry[slug], enabled) unless slug.nil?
          return sync_one(runner, registry, slug, db, ledger)
        end
        return sync_axes(runner, registry, [slug], db, ledger) if registry.axes[slug]

        raise Thor::Error, unknown_sync_target_message(registry, slug)
      end

      # The enabled-slug set governing sync acquisition (P44-r3b), or nil when
      # the box is UNCONFIGURED (no enablement config file AND no library yet) —
      # bootstrap, where sync stays ungated so a fresh box can acquire its first
      # source without an enable dance. A present file or a built catalog means
      # the profile governs.
      def sync_enabled_slugs(config, registry, db)
        return nil unless Nabu::Profile.exist?(config.profile_path) || catalog_has_sources?(db)

        Nabu::Focus.resolve(effective_profile(config, registry, catalog: db), registry).slugs
      end

      def catalog_has_sources?(db)
        db&.table_exists?(:sources) && db[:sources].any?
      end

      # The sync acquisition gate (P44-r3b): a real fetch of a non-enabled
      # kind: source is refused with the enable on-ramp. Exemptions: --parse-only
      # (repair/rebuild re-derives already-synced data — never an acquisition),
      # an unconfigured box (enabled nil — bootstrap), and non-source rows
      # (shelves are the owner's own; modules are machinery). A blocked source's
      # grant terms are a separate, later gate (enforce_grant!).
      def enforce_enablement!(entry, enabled)
        return if options[:parse_only]
        return if enabled.nil?
        return unless entry&.source?
        return if enabled.include?(entry.slug)

        raise Thor::Error,
              "#{entry.slug} is not enabled on this box — enable it first: nabu enable #{entry.slug} " \
              "(or re-derive already-synced data with nabu sync #{entry.slug} --parse-only)"
      end

      # sync <axis> / --axis a,b: expand each named axis to its members and
      # sync them through the ORDINARY per-source path (sync_one), so every
      # per-source report line is byte-identical to a direct sync — grouping
      # is pure fan-out. One axis header precedes each group; DISABLED members
      # are skipped (an axis expansion is not an explicit per-source request)
      # and named on one `skipped (unwired): …` line, never silently. A slug
      # reachable via two selected axes syncs once, under its first group.
      def sync_axes(runner, registry, names, db, ledger)
        names = names.map(&:strip).reject(&:empty?)
        raise Thor::Error, "sync --axis: name at least one axis — known axes: #{axis_menu(registry)}" if names.empty?

        unknown = names.reject { |name| registry.axes[name] }
        unless unknown.empty?
          raise Thor::Error, "sync --axis: unknown axis #{unknown.first.inspect} — known axes: #{axis_menu(registry)}"
        end

        synced = []
        names.each { |name| sync_axis_group(runner, registry, name, db, ledger, synced) }
      end

      # One axis's group: the header, then each not-yet-synced WIRED member
      # through sync_one, then the named skip line for the unwired members.
      def sync_axis_group(runner, registry, name, db, ledger, synced)
        wired, unwired = registry.axis_members(name).partition { |member| registry[member].wired }
        # P46-r1: modules are PERMANENTLY wired: false (registry invariant) —
        # their sync is an explicit owner act (`sync <slug>`), so the batch
        # skip is right, but the label must name the nature, not "unwired".
        modules, unwired = unwired.partition { |member| registry[member].feature_module? }
        # P42-r1: an axis expansion is a batch, not an explicit per-source
        # request, so a grant-blocked member is SKIPPED with the honest line —
        # never prompted mid-group (the prompt is reserved for `sync <slug>`).
        gate = Nabu::GrantGate.new(ledger: ledger)
        grant_blocked, runnable = wired.partition { |member| gate.blocked?(registry[member]) }
        say axis_header(registry.axes[name])
        (runnable - synced).each do |member|
          sync_one(runner, registry, member, db, ledger)
          synced << member
        end
        say "skipped (unwired): #{unwired.join(', ')}" unless unwired.empty?
        say "skipped (module — sync directly): #{modules.join(', ')}" unless modules.empty?
        (grant_blocked - synced).each do |member|
          say Nabu::GrantGate.skip_line(member)
          synced << member
        end
      end

      # The one-line axis header: the hat's persona verbatim (first-class
      # render data, P35-0), grouping the members below it.
      def axis_header(axis)
        "axis #{axis.name} — #{axis.persona}"
      end

      # The known-axes menu for error messages, honest when none are defined.
      def axis_menu(registry)
        names = registry.axes.names
        names.empty? ? "(none defined)" : names.join(", ")
      end

      # A name that is neither source slug nor axis: name both namespaces so
      # the user sees the axes too (the error the unknown-slug path grew into).
      def unknown_sync_target_message(registry, name)
        slugs = registry.slugs.empty? ? "(none)" : registry.slugs.join(", ")
        "unknown source or axis #{name.inspect} — sources: #{slugs}; axes: #{axis_menu(registry)}"
      end

      # sync <slug>: explicit, unconditional (disabled sources allowed, with a
      # note). A tripped breaker prints its counts + the --force hint and exits 1.
      def sync_one(runner, registry, slug, db, ledger)
        raise Thor::Error, "sync: give a source slug or --all" if slug.nil?

        entry = registry[slug]
        # P39-0: name a non-source row's nature up front, so an owner who fires
        # `sync kr-gaiji` / `sync local-notes` knows what it does (and does not) do.
        say kind_nature_note(entry), :yellow if entry && !entry.source?
        # The verification-pending note belongs to kind: source rows alone —
        # module/shelf rows are PERMANENTLY wired: false by registry invariant
        # (the P46-r1 rule; P52 owner report caught this last surface still
        # promising a flip that never comes).
        if entry && !entry.wired && entry.source?
          say "Note: #{slug} is not wired yet (this sync is the verification); syncing anyway (explicit request).",
              :yellow
        end
        # P42-r1: the fetch-grant gate — a permission-bound source needs a
        # recorded acknowledgment before its first fetch (interactive here, on
        # the explicit path; the batch paths pre-skip blocked sources).
        enforce_grant!(entry, ledger)
        redownload_wipe!(config_for_runner(runner), slug) if options[:redownload]
        outcome = runner.sync(slug, parse_only: options[:parse_only], force: options[:force],
                                    progress: progress_reporter)
        finish_progress
        raise Thor::Error, "#{slug}: #{outcome.breaker.message}" if outcome.aborted?

        say format_sync_outcome(outcome)
        print_discovery_accounting(outcome)
        print_sync_warnings(outcome)
        print_analyzed(outcome.analyzed)
        print_citation_coverage(entry, db)
        run_review_hook(outcome, db, ledger) if options[:review]
      end

      # The fetch-grant gate (P42-r1) for an EXPLICIT `sync <slug>`. A grant-
      # required source with no recorded acknowledgment shows its terms and
      # requires a typed `granted` (or the scripted --grant-acknowledged flag),
      # recording the acknowledgment durably in the ledger; refusal or a no-TTY
      # environment aborts with the request scaffold (the on-ramp, never a bare
      # wall). A non-grant or already-acknowledged source passes silently — so
      # this is a no-op for every ordinary source and every second sync.
      def enforce_grant!(entry, ledger)
        return unless entry&.grant_required?

        gate = Nabu::GrantGate.new(ledger: ledger)
        return if gate.acknowledged?(entry.slug)

        if options[:grant_acknowledged]
          gate.record!(slug: entry.slug, terms: entry.grant.terms, how: "flag")
          return say("#{entry.slug}: grant acknowledged (--grant-acknowledged) — recorded.", :yellow)
        end

        # No TTY to prompt: abort honestly with the terms + request scaffold,
        # BEFORE any fetch (the ingest/note precedent).
        raise Thor::Error, Nabu::GrantGate.abort_message(entry) unless $stdin.tty?

        say Nabu::GrantGate.notice(entry), :yellow
        say Nabu::GrantGate.prompt_line(entry)
        # Plain $stdin.gets, NOT Thor's ask (the note precedent): ask routes
        # through Readline, invisible to the suite's $stdin double and to pipes.
        answer = $stdin.gets
        raise Thor::Error, Nabu::GrantGate.abort_message(entry) unless Nabu::GrantGate.acknowledged_answer?(answer)

        gate.record!(slug: entry.slug, terms: entry.grant.terms, how: "typed")
        say "#{entry.slug}: grant acknowledged — recorded. Syncing.", :green
      end

      # P39-0: the one-line nature note for a non-source sync target. A module
      # refreshes reference machinery and mints no catalog rows; a shelf is
      # gateway-written owner memory re-scanned locally with no network.
      # --redownload (P44-i1, owner ruling): wipe the source's canonical
      # snapshot and re-acquire from scratch — the operator's override for
      # any partial/wedged state the fetcher believes is resumable. The
      # ATTIC is preserved (it is history, not snapshot); everything else
      # under canonical/<slug> goes, announced. Composes with the atomic
      # fresh-clone path: the re-acquisition either lands whole or not at
      # all. Refused with --parse-only (contradictory) and --all (wipe is
      # a per-source, explicit decision).
      def redownload_wipe!(config, slug)
        dir = File.join(config.canonical_dir, slug)
        return unless Dir.exist?(dir)

        kept_attic = false
        Dir.children(dir).each do |child|
          if child == ".attic"
            kept_attic = true
            next
          end
          FileUtils.remove_entry_secure(File.join(dir, child))
        end
        say "redownload: wiped canonical/#{slug}#{' (attic preserved)' if kept_attic} — re-acquiring from scratch",
            :yellow
      end

      def config_for_runner(runner)
        runner.config
      end

      def kind_nature_note(entry)
        if entry.feature_module?
          "#{entry.slug}: feature module — refreshes canonical reference data; mints no catalog rows."
        else
          "#{entry.slug}: local memory shelf — gateway-written owner data; sync re-scans canonical (no network)."
        end
      end

      # P18-7, the optional AI-review rider: assemble the JSON brief and pipe
      # it to the --review command. The hook's output is relayed and its exit
      # status REPORTED — never raised: the sync already happened, and a
      # review's failure is advisory information, not a sync failure.
      def run_review_hook(outcome, db, ledger)
        result = Nabu::ReviewHook.run(
          command: options[:review],
          brief: Nabu::ReviewHook.brief(outcome: outcome, db: db, ledger: ledger)
        )
        result.output.each_line { |line| say "  review| #{line.chomp}" }
        if result.ok?
          say "  review hook: exit 0"
        else
          status = result.status ? "exit #{result.status}" : "could not start"
          say "  review hook: #{status} (advisory — sync unaffected)", :yellow
        end
      end

      # P17-4 per-siglum citation coverage: an adapter that declares
      # .citation_coverage (MW → GRETIL) gets its live-resolution accounting
      # printed after every sync — the survey's projections as verifiable
      # output, recomputed against THIS catalog, never faked.
      def print_citation_coverage(entry, db)
        adapter_class = entry&.adapter_class
        return unless adapter_class.respond_to?(:citation_coverage)

        adapter_class.citation_coverage(catalog: db).each { |line| say("  #{line}") }
      end

      # sync --all: the ENABLED, live source set (P44-r3b), reported one per
      # line, never aborting the batch on one source's error. The enabled-set
      # filter is passed to the runner (nil = unconfigured/bootstrap or a repair
      # --parse-only run → the registry's live-enabled sweep, unchanged). The
      # summary line names the enabled scope honestly.
      def sync_all(runner, enabled:)
        filter = options[:parse_only] ? nil : enabled
        results = runner.sync_all(parse_only: options[:parse_only], force: options[:force],
                                  progress: progress_reporter, enabled: filter)
        finish_progress
        return say("Nothing to sync: no wired, auto-cadence sources.") if results.empty?

        say "syncing #{pluralize(results.size, 'enabled source')}:"
        results.each do |slug, result|
          say("  #{sync_all_line(slug, result)}")
          next unless result.is_a?(Nabu::SyncRunner::Outcome)

          print_discovery_accounting(result)
          print_sync_warnings(result)
          print_analyzed(result.analyzed)
        end
      end

      def sync_all_line(slug, result)
        # P42-r1: a grant-blocked source was skipped, not run — the honest line.
        return Nabu::GrantGate.skip_line(result.slug) if result.is_a?(Nabu::SyncRunner::GrantRequired)
        return "#{slug.ljust(24)} FAILED — #{result.message}" unless result.is_a?(Nabu::SyncRunner::Outcome)
        return "#{slug.ljust(24)} ABORTED — #{result.breaker.message}" if result.aborted?

        format_sync_outcome(result)
      end

      # P5-5 inline deviation warnings: advisory one-liners after the counts line,
      # in yellow, never affecting the exit code. Empty on a clean sync.
      def print_sync_warnings(outcome)
        outcome.warnings.each { |finding| say("  ! #{finding.message}", :yellow) }
      end

      # P42-4: the one honest planner-hygiene line — printed only when a bulk
      # load or a rebuild actually refreshed the query-planner statistics,
      # silent otherwise (a sub-threshold sync, a clean-swept incremental run).
      def print_analyzed(analyzed)
        return unless analyzed

        say "  analyzed #{analyzed.scope} (planner stats refreshed, #{format('%.1f', analyzed.seconds)}s)"
      end

      # -- quickstart (P18-2) -------------------------------------------------

      # `quickstart --list`: the starter set, sizes, and what each source
      # unlocks — no network, no db, nothing created.
      # Additively enable the starter slugs in the enablement config
      # (P44-r3c). Existing entries are preserved; the save carries the
      # enablement header, so the file governs from here on.
      def enable_starter_set(config)
        profile = Nabu::Profile.exist?(config.profile_path) ? Nabu::Profile.load(config.profile_path) : Nabu::Profile.new([])
        slugs = self.class.starter_sources.map(&:slug)
        merged = (profile.entries + slugs).uniq
        return if merged.sort == profile.entries.sort

        Nabu::Profile.new(merged).save(config.profile_path)
        # stderr, the r3b enablement-honesty convention: data stdout stays
        # byte-identical/pipe-clean.
        warn "enabled the starter shelf: #{slugs.join(', ')} (config/profile.yml)"
      end

      def print_starter_list
        say "starter shelf (#{STARTER_TOTAL} canonical, minutes to sync):"
        self.class.starter_sources.each do |starter|
          say "  #{starter.slug.ljust(8)} #{starter.size.rjust(8)}  #{starter.blurb}"
        end
        say "sync it: bin/nabu quickstart"
      end

      # Sync the starter list IN ORDER through the normal per-source path
      # (fetch → load → index — SyncRunner#sync, the same code `nabu sync
      # <slug>` runs, so the command is idempotent by construction). One
      # source's failure never stops the rest (sync --all's posture): failures
      # collect as [slug, message] pairs and report after the batch. An
      # unregistered starter slug fails the same way (ValidationError is a
      # Nabu::Error), never aborting the run.
      def run_starter_syncs(runner)
        failures = []
        self.class.starter_sources.each do |starter|
          outcome = runner.sync(starter.slug, progress: progress_reporter)
          finish_progress
          if outcome.aborted?
            failures << [starter.slug, outcome.breaker.message]
          else
            say format_sync_outcome(outcome)
            print_discovery_accounting(outcome)
            print_sync_warnings(outcome)
            print_analyzed(outcome.analyzed)
          end
        rescue Nabu::Error => e
          finish_progress
          failures << [starter.slug, e.message]
        end
        failures
      end

      # The "try these" epilogue: any failures first (so what follows is read
      # against an honest shelf), then the three marvels with their
      # expected-shape hints, then the growth pointer. Compact house style.
      def print_quickstart_epilogue(failures)
        unless failures.empty?
          say ""
          failures.each { |slug, message| say("  #{slug.ljust(8)} FAILED — #{message}", :red) }
        end
        say ""
        say "try these:"
        say %(  bin/nabu align "MARK 2.3"      # one verse, seven witnesses: Greek ×2, Latin, Gothic, OCS, Old English)
        say "  bin/nabu search --lemma λέγω    # every inflection over the gold treebanks: λέγουσι, εἶπας, εἰπεῖν…"
        say "  bin/nabu define λόγος           # the whole LSJ entry, citations resolved (Latin: define virtus)"
        say "grow the library: bin/nabu sync --all (live sources) or bin/nabu sync <slug> — " \
            "the menu is config/sources.yml, the shelf map docs/library.md"
      end

      # -- ingest (P19-5): the canonical-memory intake front door ---------------

      # `--shelf X`: the canonical-memory scaffold front doors, one per
      # local dossier shelf (language P19-5, source P24-0).
      def ingest_shelf(config, args)
        case options[:shelf]
        when "language" then ingest_language(config, args)
        when "source" then ingest_source(config, args)
        else
          raise Thor::Error, "ingest: unknown shelf #{options[:shelf].inspect} — `--shelf language CODE` " \
                             "and `--shelf source SLUG` are the front doors"
        end
      end

      # `--shelf language CODE`: scaffold a dossier through LanguageShelf
      # (the shelf's sanctioned gateway), then sync the dossier shelf. THIN
      # by design — a skeleton, not an editor.
      def ingest_language(config, codes)
        raise Thor::Error, "ingest --shelf language: give exactly one CODE (e.g. zle-ort)" unless codes.size == 1

        %w[collection title creator year languages tags related provenance license_class].each do |flag|
          next unless options[flag]

          raise Thor::Error, "ingest: --#{flag.tr('_', '-')} is a library-shelf field — " \
                             "with --shelf language use --name/--family/--context"
        end
        %w[description themes key_works].each do |flag|
          next unless options[flag]

          raise Thor::Error, "ingest: --#{flag.tr('_', '-')} is a source-shelf field — " \
                             "with --shelf language use --name/--family/--context"
        end
        shelf = Nabu::LanguageShelf.new(dir: Nabu::LanguageShelf.dir(config.canonical_dir))
        engine = Nabu::Ingest.new(resolver: ingest_resolver, assist_command: options[:assist],
                                  overrides: ingest_overrides(%w[name family context]),
                                  notify: ingest_notify)
        outcome = engine.scaffold_language(codes.first, language_shelf: shelf)
        print_ingest_outcome(outcome)
        return unless outcome.status == :added

        run_shelf_sync(config, Nabu::LanguageShelf::SLUG)
        say ""
        say "try: bin/nabu language #{codes.first}"
      rescue Nabu::Error => e
        raise Thor::Error, e.message
      end

      # `--shelf source SLUG` (P24-0): scaffold a source dossier through
      # SourceShelf (the third sanctioned gateway), then sync. The
      # description prompt prefills from the registered source's name.
      def ingest_source(config, slugs)
        raise Thor::Error, "ingest --shelf source: give exactly one SLUG (e.g. edh)" unless slugs.size == 1

        %w[collection title creator year languages tags related provenance license_class name family
           context].each do |flag|
          next unless options[flag]

          raise Thor::Error, "ingest: --#{flag.tr('_', '-')} is another shelf's field — " \
                             "with --shelf source use --description/--themes/--key-works"
        end
        slug = slugs.first
        entry = registry_entry(config, slug)
        if entry.nil?
          raise Thor::Error, "ingest --shelf source: #{slug.inspect} is not a registered source " \
                             "(config/sources.yml) — dossiers describe held shelves"
        end
        shelf = Nabu::SourceShelf.new(dir: Nabu::SourceShelf.dir(config.canonical_dir))
        engine = Nabu::Ingest.new(resolver: ingest_resolver, assist_command: options[:assist],
                                  overrides: ingest_overrides(Nabu::Ingest::SOURCE_FIELDS),
                                  notify: ingest_notify)
        outcome = engine.scaffold_source(slug, source_shelf: shelf, source_name: entry.manifest.name)
        print_ingest_outcome(outcome)
        return unless outcome.status == :added

        run_shelf_sync(config, Nabu::SourceShelf::SLUG)
        say ""
        say "try: bin/nabu list #{slug}"
      rescue Nabu::Error => e
        raise Thor::Error, e.message
      end

      # THE SEED (P24-0, owner-fired): a canonical/local-source dossier for
      # every registered source, descriptions from the best existing prose
      # (docs/library.md sections/bullets, sources.yml standalone comments)
      # — honest stubs where none exists, never invented. Idempotent at the
      # file grain: existing dossiers are untouched, so it is safe to
      # re-run after registering new sources. After it: bin/nabu sync
      # local-source derives the catalog records the card/census read.
      def export_source_dossiers(config)
        registry = Nabu::SourceRegistry.load(config.sources_path)
        dir = Nabu::SourceShelf.dir(config.canonical_dir)
        report = Nabu::SourceDossierExport.new(
          registry: registry, dir: dir,
          library_md: File.expand_path("../../docs/library.md", __dir__),
          sources_yml: config.sources_path
        ).run!(dry_run: options[:"dry-run"])
        verb = options[:"dry-run"] ? "would scaffold" : "scaffolded"
        say "dossiers: #{verb} #{report.written}, #{report.unchanged} existing untouched → #{dir}"
        if report.stubs.positive?
          say "  #{report.stubs} honest stub(s) — no existing prose found, write the description: " \
              "#{report.stub_slugs.join(', ')}"
        end
        say "next: bin/nabu sync local-source (derives the catalog records)" unless options[:"dry-run"]
      end

      def build_ingest_engine(config)
        shelf = Nabu::LibraryShelf.new(dir: Nabu::LibraryShelf.dir(config.canonical_dir))
        Nabu::Ingest.new(
          shelf: shelf, resolver: ingest_resolver, assist_command: options[:assist],
          overrides: ingest_overrides(Nabu::Ingest::LIBRARY_FIELDS), notify: ingest_notify
        )
      end

      # The three categorization modes, decided here: --yes accepts, a TTY
      # prompts (Thor ask, injectable into the engine as a plain callable),
      # anything else is an honest refusal — assist suggestions never land
      # unreviewed by accident.
      def ingest_resolver
        return Nabu::Ingest::AcceptResolver.new if options[:yes]

        unless $stdin.tty?
          raise Thor::Error, "ingest: interactive categorization needs a TTY — pass --yes " \
                             "(fields from flags), or run in a terminal"
        end
        # The header prints at the FIRST prompt, not at resolver construction:
        # the engine's staging pass (existence checks, downloads) must be
        # able to fail BEFORE any interactive furniture appears (the
        # 2026-07-14 archive.org incident, P20-0).
        header_printed = false
        Nabu::Ingest::PromptResolver.new(
          ask: lambda do |label, default|
            unless header_printed
              say "categorize (Enter keeps the [default]; '-' clears a field):"
              header_printed = true
            end
            default ? ask("  #{label}", default: default) : ask("  #{label}:")
          end,
          # An invalid answer's one-line reason (P20-1) — the prompt repeats.
          warn: ->(line) { say "  ! #{line}", :yellow }
        )
      end

      def ingest_overrides(keys)
        keys.each_with_object({}) do |key, map|
          value = options[key]
          map[key] = value unless value.nil?
        end
      end

      # Advisory engine notes (assist diagnostics, degrade notes) — yellow,
      # never affecting the exit code.
      def ingest_notify
        ->(line) { say "  #{line}", :yellow }
      end

      def print_ingest_outcome(outcome)
        case outcome.status
        when :added then say "  added    #{outcome.file} #{outcome.message}"
        when :revised then say "  revised  #{outcome.file} — #{outcome.message}"
        when :skipped then say "  skipped  #{outcome.file} — #{outcome.message}"
        when :aborted then say "  aborted  #{outcome.file} — #{outcome.message}", :yellow
        else say "  FAILED   #{outcome.file} — #{outcome.message}", :red
        end
      end

      # Minted urns + the compact "try:" epilogue: show always; search only
      # when the file actually yielded text (metadata-only scans are not
      # searchable — honesty over symmetry); links when the entry asserted
      # related urns (they just became reference edges).
      def print_ingest_epilogue(outcomes)
        added = outcomes.select { |outcome| outcome.status == :added }
        return if added.empty?

        say ""
        say "minted:"
        added.each { |outcome| say "  #{outcome.urn}" }
        say "try:"
        first = added.first
        say "  bin/nabu show #{first.urn}"
        if first.search_term
          say "  bin/nabu search #{first.search_term} --license " \
              "#{first.entry['license_class'] || Nabu::LibraryManifest::DEFAULT_LICENSE_CLASS}"
        end
        linked = added.find { |outcome| (outcome.entry["related"] || []).any? { |r| r.start_with?("urn:") } }
        say "  bin/nabu links #{linked.urn}" if linked
      end

      # Run one local shelf's ordinary sync (fetch = the LocalFetch re-scan;
      # no network) and print the standard sync accounting.
      def run_shelf_sync(config, slug)
        registry = Nabu::SourceRegistry.load(config.sources_path)
        ledger = open_or_create_ledger(config)
        db = open_or_create_catalog(config)
        runner = Nabu::SyncRunner.new(config: config, registry: registry, db: db, ledger: ledger)
        outcome = runner.sync(slug, progress: progress_reporter)
        finish_progress
        raise Thor::Error, "#{slug}: #{outcome.breaker.message}" if outcome.aborted?

        say format_sync_outcome(outcome)
        print_discovery_accounting(outcome)
        print_sync_warnings(outcome)
      ensure
        db&.disconnect
        ledger&.disconnect
      end

      # P11-7 discovery accounting: classify every content-pattern file
      # selected / skipped-by-rule / unrecognized, combining the loader's fate
      # of discovered refs (loaded → selected; parse-skipped → skipped-by-rule;
      # quarantined → unrecognized) with the adapter's discovery census (0-byte
      # skeletons, non-editions → skipped-by-rule; a tree with no ingestible
      # content → unrecognized). unrecognized ≥ 1 is rendered loudly, with its
      # notes, so a silent-ingestion gap can never hide again.
      def print_discovery_accounting(outcome)
        report = outcome.load_report
        discovery = outcome.discovery
        return unless report && discovery

        selected = report.added + report.updated + report.skipped
        skipped = report.skipped_by_rule + discovery.skipped_by_rule
        # A collided document (P39-4) was discovered but rejected keep-first, so
        # it belongs in the loud not-ingested bucket, never among the selected.
        unrecognized = report.errored + report.collided + discovery.unrecognized
        say("  discovery: #{selected} selected · #{skipped} skipped-by-rule · " \
            "#{unrecognized} unrecognized", unrecognized.positive? ? :yellow : nil)
        discovery.notes.each { |note| say("  ! #{note}", :yellow) }
      end

      def format_sync_outcome(outcome)
        # P43-i1: an id-sweep fetch (trismegistos) has no single content
        # sha — its FetchReport carries sha: nil honestly. Render the
        # report's presence, not a sliced nil.
        fetched = if outcome.fetch_report
                    outcome.fetch_report.sha ? outcome.fetch_report.sha[0, 12] : "fetched"
                  else
                    "parse-only"
                  end
        report = outcome.load_report
        "#{outcome.slug.ljust(24)} #{fetched}  " \
          "+#{report.added} added  ~#{report.updated} updated  " \
          "=#{report.skipped} skipped  -#{report.withdrawn} withdrawn  !#{report.errored} errored" \
          "#{format_collided(report)}" \
          "#{format_sync_indexed(outcome)}#{format_sync_references(outcome.references)}" \
          "#{format_sync_enrichments(outcome.enrichments)}#{format_sync_place_index(outcome.place_index)}"
      end

      # P39-4: the within-pass collision tail — silent at zero (house
      # compact-zero rule; collisions are pathological), loud when one bit.
      def format_collided(report)
        report.collided.positive? ? "  !#{report.collided} collision" : ""
      end

      # P26-5: syncs index incrementally, so the count is the SOURCE's live
      # passage rows — "indexed 17942 passages (corph)" — never the corpus
      # total (which would imply work that no longer happens). Suppressed for
      # index-inert shelves (indexed nil — no index work at all) and for
      # zero-passage grains like dictionaries (compact zero-field rule).
      def format_sync_indexed(outcome)
        return "" if outcome.indexed.nil? || outcome.indexed.zero?

        "  indexed #{outcome.indexed} passages (#{outcome.slug})"
      end

      # P19-4: the reference-edge tail for a local-shelf sync — silent when
      # the source mints no reference edges (references nil), compact
      # otherwise (zero counts suppressed, house style).
      def format_sync_references(refs)
        return "" if refs.nil?

        parts = []
        parts << "+#{refs.edges_written}" if refs.edges_written.positive?
        parts << "~#{refs.edges_refreshed}" if refs.edges_refreshed.positive?
        parts << "-#{refs.superseded_edges}" if refs.superseded_edges.positive?
        # P43-i1: producers that census unknown upstream ids say so — a
        # third of the first TM sweep was "not in our database", and a
        # silent zero would misread as full coverage.
        parts << "?#{refs.unknown_ids} unknown upstream" if refs.respond_to?(:unknown_ids) && refs.unknown_ids.positive?
        counts = parts.empty? ? "0" : parts.join(" ")
        "  refs #{counts}"
      end

      # P44-7: the meter-enrichment tail for a pedecerto sync — silent when the
      # source mints no enrichments (nil). The HONEST CENSUS the packet demands:
      # matched vs unmatched LINES (unmatched = works we do not hold or citation
      # mismatches), never hidden. "meter 41 lines matched, 12 unmatched (2 works)".
      def format_sync_enrichments(enr)
        return "" if enr.nil?

        works = enr.mapped_works + enr.unmapped_works
        "  meter #{enr.matched} lines matched, #{enr.unmatched} unmatched " \
          "(#{plural(enr.mapped_works, 'work')} of #{works})#{format_malformed_files(enr.malformed_files)}"
      end

      # P45-6: the place-index tail for a pleiades sync — silent for every
      # source that derives no place index (nil, including a pleiades
      # parse-only sync before the first fetch). "place index 42242 places
      # derived (3.1s)".
      def format_sync_place_index(census)
        return "" if census.nil?

        "  place index #{census.places} places derived (#{format('%.1f', census.seconds)}s)"
      end

      # The P44-i3b honesty tail: unreadable upstream files are named (the
      # status-footer idiom — a bare count is a guessing game), first three
      # outright, the rest as a count.
      def format_malformed_files(names)
        return "" if names.empty?

        shown = names.first(3).join(", ")
        more = names.size > 3 ? " +#{names.size - 3} more" : ""
        "; #{names.size} malformed upstream, skipped: #{shown}#{more}"
      end

      # rebuild --incremental (P36-1): dirty sources re-derive through the
      # rebuild replay seam + per-source index refresh; clean ones are
      # skipped on their derivation stamp. Refusals (schema drift, orphan
      # rows, no catalog) are loud exit-1 errors — full rebuild required.
      def rebuild_incremental(config, registry)
        incremental = Nabu::IncrementalRebuild.new(config: config, registry: registry)
        return print_incremental_plan(incremental.plan) if options[:dry_run]

        result = incremental.run(progress: progress_reporter)
        finish_progress
        print_incremental_result(result)
      rescue Nabu::Error => e
        raise Thor::Error, e.message
      end

      # --dry-run --incremental: the owner's planning view — one clean/dirty
      # verdict per source, nothing touched.
      def print_incremental_plan(plan)
        say "Dry run — nothing will change."
        raise Thor::Error, "cannot rebuild incrementally: #{plan.refusal}" if plan.refusal

        say "Incremental rebuild against #{plan.db_path}:"
        plan.verdicts.each do |verdict|
          case verdict.state
          in :clean then say "  clean   #{verdict.slug} (stamp #{verdict.stamp_short})"
          in :dirty then say "  dirty   #{verdict.slug} (#{verdict.reason})"
          in :skip then say "  skip    #{verdict.slug} (no canonical data)"
          end
        end
      end

      def print_incremental_result(result)
        say "Incremental rebuild against #{result.db_path}:"
        result.cleans.each { |clean| say "  #{clean.slug} clean (stamp #{clean.stamp_short})" }
        result.outcomes.each { |outcome| say "  #{format_report(outcome.slug, outcome.report)}" }
        result.skips.each { |skip| say "  skip    #{skip.slug} (no canonical data — never synced)" }
        result.warnings.each do |outcome|
          say "  WARNING: #{outcome.slug} #{outcome.quarantine.message}", :yellow
        end
        say "  re-derived #{result.outcomes.size}, clean #{result.cleans.size}, " \
            "skipped #{result.skips.size}"
        say "  indexed #{result.indexed} passages" if result.indexed
        print_analyzed(result.analyzed)
      end

      # --dry-run: report the plan, touch nothing.
      def print_plan(plan)
        say "Dry run — nothing will change."
        say "Would drop catalog db: #{plan.db_path} (#{plan.db_exists ? 'exists' : 'absent'})"
        plan.items.each do |slug, action|
          say(action == :replay ? "  replay  #{slug}" : "  skip    #{slug} (no canonical data)")
        end
      end

      # Real run: per-source counts, skips, warnings, then a grand total.
      def print_result(result)
        existed = result.db_existed ? "" : " (did not exist)"
        say "Dropped catalog db: #{result.db_path}#{existed}"
        result.outcomes.each { |outcome| say "  #{format_report(outcome.slug, outcome.report)}" }
        result.skips.each { |skip| say "  skip    #{skip.slug} (no canonical data — never synced)" }
        # DELTA-aware (P18-7): silence when a source's errored count matches its
        # recorded ledger baseline; a change (or first recording) speaks.
        result.warnings.each do |outcome|
          say "  WARNING: #{outcome.slug} #{outcome.quarantine.message}", :yellow
        end
        say "  #{format_report('TOTAL', total_report(result))}"
        say "  indexed #{result.indexed} passages"
        if result.axes
          say "  dated/placed #{result.axes.total} documents " \
              "(hgv #{result.axes.hgv}, goo300k #{result.axes.goo300k}, imp #{result.axes.imp}, " \
              "oracc #{result.axes.oracc}, torot #{result.axes.torot}, coptic #{result.axes.coptic}, " \
              "edh #{result.axes.edh}, damaskini #{result.axes.damaskini}, corph #{result.axes.corph}, " \
              "riig #{result.axes.riig}, tla-hf #{result.axes.tla_hf}, aes #{result.axes.aes}, " \
              "ceipom #{result.axes.ceipom}, " \
              "isicily #{result.axes.isicily}, " \
              "open-etruscan #{result.axes.open_etruscan}, " \
              "lexlep #{result.axes.lexlep}, tir #{result.axes.tir}, " \
              "iip #{result.axes.iip}, cdli #{result.axes.cdli}, " \
              "rundata #{result.axes.rundata}, openiti #{result.axes.openiti})"
        end
        print_analyzed(result.analyzed)
        return unless result.facets&.rows&.positive? # zero-signal silence (compact rule)

        say "  facets #{result.facets.rows} rows across #{result.facets.documents} documents"
      end

      # The P36-0 profile table: every source's load and every corpus stage,
      # heaviest first with its share of the grand total, then a stage-share
      # summary (parse/insert inside load; corpus index total) — the numbers
      # that tier P36-2 (bulk load) vs P36-3 (parallel parse). Print-only:
      # the profile is in-memory observability, never persisted, so `nabu
      # rebuild` regenerates it wholesale every run.
      def print_profile(profile)
        return if profile.nil? || profile.empty?

        width = [profile.rows.map { |label, _, _| label.to_s.length }.max || 0, 18].max
        say ""
        say "Rebuild profile — wall time by stage (heaviest first):"
        profile.rows.each do |label, secs, share|
          say format("  %-#{width}s  %10s  %5.1f%%", label, format_duration(secs), share * 100)
        end
        say "  #{'-' * (width + 20)}"
        say format("  %-#{width}s  %10s   (of load)", "parse (+fold)", format_duration(profile.parse_total))
        say format("  %-#{width}s  %10s   (of load)", "insert", format_duration(profile.insert_total))
        say format("  %-#{width}s  %10s", "load total", format_duration(profile.load_total))
        say format("  %-#{width}s  %10s", "corpus index total", format_duration(profile.index_total))
        say format("  %-#{width}s  %10s", "GRAND TOTAL", format_duration(profile.grand_total))
        say "  note: fts+lemma is one fused pass; parse/insert are per-document samples inside load."
        say "  note: text-normalization/fold (search_form) runs at Passage build, so it is inside parse."
      end

      # Seconds → the rebuild-progress voice (Xs under a minute, else XmYYs).
      def format_duration(secs)
        secs < 60 ? "#{secs.round(1)}s" : "#{(secs / 60).floor}m#{format('%02d', (secs % 60).round)}s"
      end

      def format_report(label, report)
        "#{label.ljust(24)} +#{report.added} added  ~#{report.updated} updated  " \
          "=#{report.skipped} skipped  -#{report.withdrawn} withdrawn  !#{report.errored} errored" \
          "#{format_collided(report)}"
      end

      def total_report(result)
        reports = result.outcomes.map(&:report)
        Nabu::Store::LoadReport.new(
          added: reports.sum(&:added), updated: reports.sum(&:updated),
          skipped: reports.sum(&:skipped), withdrawn: reports.sum(&:withdrawn),
          errored: reports.sum(&:errored), skipped_by_rule: reports.sum(&:skipped_by_rule),
          collided: reports.sum(&:collided)
        )
      end

      # --remote (P5-3): the no-clone upstream probe. Pins + baselines live in
      # the history ledger (P7-1), which the probe writes (baseline recording),
      # so this is a write path: create + migrate + lift. Its own exit-1 raise.
      def run_remote_health
        config = Nabu::Config.load
        registry = Nabu::SourceRegistry.load(config.sources_path)
        catalog = open_catalog(config)
        view = focus_view(config, registry, catalog: catalog)
        catalog&.disconnect
        warn_focus_drift(view)
        ledger = open_or_create_ledger(config)
        report = Nabu::Health::RemoteProbe.new(
          registry: view.registry, ledger: ledger, canonical_dir: config.canonical_dir
        ).run(progress: remote_health_ticker)
        $stderr.print("\r\e[K") if $stderr.tty? # clear the ticker before the table
        print_remote_health(report)
        print_focus_note(view, view.registry_hidden_slugs)
        # A gone upstream is the only red finding; the table is already on stdout,
        # so raise for the exit-1 signal (Thor prints the summary to stderr).
        raise Thor::Error, remote_health_failure(report) if report.any_gone?
      ensure
        ledger&.disconnect
      end

      # The transient probe ticker (P31 rider — the same owner ask as the
      # P28-5 rebuild progress): on a TTY, one stderr line naming the source
      # currently on the wire, overwritten in place and cleared before the
      # table prints. Non-TTY prints nothing — the table already lists every
      # source, and pipes stay clean (compact-output convention).
      def remote_health_ticker
        return nil unless $stderr.tty?

        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        lambda do |slug, index, total|
          elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
          suffix = elapsed >= 1 ? format(" %ds", elapsed) : ""
          $stderr.print("\r\e[K  probing #{index}/#{total} #{slug}…#{suffix}")
        end
      end

      # --backfill-pins (P15-7): record ledger pins for sources synced before
      # the pins ledger existed (P7) — the ones that read "unpinned". No
      # network, read-only on canonical/ (a local git rev-parse / state-file
      # read); writes ONLY the ledger pins, idempotently. A write path, so the
      # ledger is opened + migrated + lifted like the remote probe's.
      def run_backfill_pins
        config = Nabu::Config.load
        registry = Nabu::SourceRegistry.load(config.sources_path)
        ledger = open_or_create_ledger(config)
        recorded = Nabu::Health::RemoteProbe.new(
          registry: registry, ledger: ledger, canonical_dir: config.canonical_dir
        ).backfill_pins
        print_backfill(recorded)
      ensure
        ledger&.disconnect
      end

      def print_backfill(recorded)
        if recorded.empty?
          return say("backfill-pins: nothing to backfill — every synced source already carries its ledger pin.")
        end

        width = recorded.map { |row| row.slug.length }.max
        recorded.each do |row|
          say "#{row.slug.ljust(width)}  pinned #{row.sha[0, 12]}  (#{backfill_origin(row.origin)})"
        end
        say "backfill-pins: recorded #{pluralize(recorded.size, 'pin')} " \
            "(ledger only; canonical/ untouched, no network)."
      end

      def backfill_origin(origin)
        origin == :git_clone ? "backfilled-from-local-clone" : "backfilled-from-state-file"
      end

      # `status --remote` (P14-12): run the live upstream probe through the SAME
      # RemoteProbe as `health --remote`, whose run persists each verdict into
      # the ledger's source_probes cache, then hand the (write-opened, migrated)
      # ledger back so status renders the just-refreshed up= column. Returns the
      # ledger handle; the caller owns disconnecting it. The probe's exit-code
      # gate is health's concern, not status's — status just reports.
      def probe_upstreams(config, registry)
        ledger = open_or_create_ledger(config)
        Nabu::Health::RemoteProbe.new(
          registry: registry, ledger: ledger, canonical_dir: config.canonical_dir
        ).run
        ledger
      end

      # --accept-creep (P43-0, D42-c): the owner reviewed a quarantine-creep
      # anomaly and accepts the source's CURRENT baseline. Durable by design —
      # the acceptance lives in the history ledger (migration 008), so a
      # rebuild never un-quiets a ruled-on alarm. A write path: create +
      # migrate + lift, its own ledger lifetime. The active-anomaly probe runs
      # BEFORE the acceptance lands (recording first would quiet the very
      # finding the honesty line reports on).
      def run_accept_creep(slug)
        config = Nabu::Config.load
        registry = Nabu::SourceRegistry.load(config.sources_path)
        if registry[slug].nil?
          raise Thor::Error, "accept-creep: unknown source '#{slug}' — not in #{config.sources_path}"
        end

        ledger = open_or_create_ledger(config)
        active = Nabu::Health::QuarantineBaseline.creep_finding(ledger, slug)
        accepted = Nabu::Health::QuarantineBaseline.accept!(ledger, slug, note: options[:note])
        if accepted.nil?
          raise Thor::Error, "accept-creep: no quarantine baseline recorded for '#{slug}' — nothing to accept " \
                             "(a baseline is recorded at the source's first ok sync or rebuild)"
        end
        say "accepted quarantine baseline #{accepted} for #{slug} — the creep alarm re-arms past #{accepted}"
        # Pre-accepting (no live anomaly, or one an earlier acceptance already
        # quiets to the info note) is allowed but never passes silently.
        say "(no active creep anomaly for #{slug} — recorded as a pre-acceptance)" if active.nil? || !anomaly?(active)
      ensure
        ledger&.disconnect
      end

      # A finding that affects (or warns toward) the exit code — as opposed to
      # an info-grade note like an already-quieted creep.
      def anomaly?(finding)
        finding.loud? || finding.soft?
      end

      # Bare health (P5-5): run-history trends + live golden replay, no network.
      # open_catalog binds the Store models the LocalCheck queries; open_ledger
      # binds the run history (absent ledger = empty history, honestly). Exit 1
      # on any loud finding (quarantine spike, >15% creep, a lost golden query);
      # soft warnings (collapse, 5–15% creep, stale) stay exit 0.
      def run_local_health
        config = Nabu::Config.load
        registry = Nabu::SourceRegistry.load(config.sources_path)
        catalog = open_catalog(config)
        view = focus_view(config, registry, catalog: catalog)
        warn_focus_drift(view)
        fulltext = catalog ? open_fulltext(config) : nil
        ledger = open_ledger(config)
        report = Nabu::Health::LocalCheck.new(
          registry: view.registry, catalog: catalog, fulltext: fulltext, ledger: ledger,
          golden_queries: Nabu::Health::LocalCheck.golden_queries,
          canonical_dir: config.canonical_dir
        ).run
        print_local_health(report)
        print_focus_note(view, view.registry_hidden_slugs)
        raise Thor::Error, local_health_failure(report) if report.any_loud?
      ensure
        catalog&.disconnect
        fulltext&.disconnect
        ledger&.disconnect
      end

      # Per-source trend rows, then the golden-replay section, then the verdict
      # and a hint toward the upstream probe.
      def print_local_health(report)
        print_source_health(report.sources)
        # Library-wide invariant findings (P18-7: pending migrations) — printed
        # only when present, so a green library shows nothing new here.
        report.global.each { |finding| say "#{finding_tag(finding)} #{finding.message}" }
        print_golden_health(report)
        say local_health_verdict(report)
        say "Hint: run `nabu health --remote` for the no-clone upstream probe."
      end

      def print_source_health(sources)
        return say("No sources registered.") if sources.empty?

        width = sources.map { |source| source.slug.length }.max
        sources.each { |source| print_source_row(source, width) }
      end

      # A healthy source is one "ok" line; a flagged one repeats its slug column
      # blank for continuation findings so multi-finding sources stay aligned.
      def print_source_row(source, width)
        return say("#{source.slug.ljust(width)}  ok") if source.findings.empty?

        source.findings.each_with_index do |finding, index|
          label = index.zero? ? source.slug.ljust(width) : " " * width
          say "#{label}  #{finding_tag(finding)} #{finding.message}"
        end
      end

      def finding_tag(finding)
        { loud: "ANOMALY", soft: "warning", info: "note" }.fetch(finding.severity)
      end

      def print_golden_health(report)
        case report.corpus
        when :absent
          return say("golden replay: no corpus — run nabu sync or nabu rebuild")
        when :no_index
          return say("golden replay: no fulltext index — run nabu sync or nabu rebuild")
        end

        lost = report.golden.select(&:lost?)
        lost.each { |result| say "golden query lost: #{result.query}  (expected #{result.expect_urn})" }
        found = report.golden.count { |result| result.status == :found }
        skipped = report.golden.count { |result| result.status == :skipped }
        say "golden replay: #{found} found, #{lost.size} lost, #{skipped} skipped (source not in this corpus)"
      end

      def local_health_verdict(report)
        return "health: #{report.loud_count} anomaly finding(s) — see above (exit 1)" if report.any_loud?
        return "health: OK, #{pluralize(report.soft_count, 'warning')}" if report.soft_count.positive?

        "health: OK"
      end

      def local_health_failure(report)
        "health: #{report.loud_count} loud finding(s) — see the report above"
      end

      # Render the remote probe: one aligned row per source (slug, liveness,
      # drift, license) plus any trailing detail, then a one-line summary.
      def print_remote_health(report)
        rows = report.rows
        return say("No sources registered.") if rows.empty?

        slug_w = rows.map { |row| row.slug.length }.max
        live_w = rows.map { |row| live_cell(row.liveness).length }.max
        drift_w = rows.map { |row| drift_cell(row.drift).length }.max
        rows.each do |row|
          line = "#{row.slug.ljust(slug_w)}  #{live_cell(row.liveness).ljust(live_w)}  " \
                 "#{drift_cell(row.drift).ljust(drift_w)}  #{license_cell(row.license)}#{health_detail(row)}"
          say line.rstrip
        end
        say remote_health_summary(report)
      end

      def live_cell(liveness)
        { alive: "alive", moved: "MOVED", gone: "GONE" }.fetch(liveness.status)
      end

      def drift_cell(drift)
        { current: "current", behind: "behind", unpinned: "unpinned",
          never_synced: "never-synced", unknown: "—", multi: "multi-repo",
          frozen: "frozen", local: "local" }.fetch(drift)
      end

      # :unchecked renders as NOTHING — "license: unchecked" reads like a
      # problem when it only means "no machine-checkable license artifact
      # upstream" (non-github, or a repo without a top-level license file).
      # The verdict still lands in the ledger; the row just doesn't speak
      # (owner rule, conventions §10: suppress zero-signal fields).
      def license_cell(license)
        { baseline_recorded: "license: baseline recorded", unchanged: "license: ok",
          changed: "license: CHANGED", unchecked: "" }.fetch(license.status)
      end

      # Trailing context: why an upstream is not alive, or why a license row is
      # flagged. Kept off the aligned columns so the table stays readable.
      def health_detail(row)
        bits = []
        bits << row.liveness.detail if row.liveness.detail && row.liveness.status != :alive
        bits << row.drift_detail if row.drift_detail && %i[behind unpinned].include?(row.drift)
        bits << row.license.detail if row.license.status == :changed
        bits.empty? ? "" : "   #{bits.join(' · ')}"
      end

      def remote_health_summary(report)
        rows = report.rows
        counts = { alive: 0, moved: 0, gone: 0 }
        rows.each { |row| counts[row.liveness.status] += 1 }
        behind = rows.count { |row| row.drift == :behind }
        parts = [pluralize(rows.size, "source"), "#{counts[:alive]} alive"]
        parts << "#{counts[:moved]} moved" if counts[:moved].positive?
        parts << "#{counts[:gone]} gone" if counts[:gone].positive?
        parts << "#{behind} behind" if behind.positive?
        parts.join(", ")
      end

      def remote_health_failure(report)
        gone = report.rows.count { |row| row.liveness.status == :gone }
        "health: #{pluralize(gone, 'upstream')} gone — see the table above"
      end

      # -- mcp entrypoint plumbing (P8-2) ----------------------------------

      # A lazy, memoizing, read-only opener returned as a PROC (the Tools
      # contract resolves each connection slot per tool call). On every call:
      # absent file → nil (Tools renders the "no corpus" state); present file →
      # an open read-only handle, cached across calls so a long session does not
      # churn file descriptors. The cached handle is dropped and reopened when
      # the file's identity changes — `nabu rebuild` deletes and recreates the
      # catalog, so a mid-session rebuild is genuinely picked up, not served
      # stale from a handle onto the deleted inode.
      def readonly_opener(path, &open)
        handle = nil
        identity = nil
        lambda do
          current = file_identity(path)
          if current.nil?
            handle&.disconnect
            handle = identity = nil
          elsif current != identity
            handle&.disconnect
            handle = open.call
            identity = current
          end
          handle
        end
      end

      # The enabled-slug set nabu_status defaults to (P44-r3b). READ-ONLY: unlike
      # the CLI's effective_profile, the MCP server never WRITES a migration
      # (serving is not the moment to touch config). It mirrors the same three
      # cases in memory: a present config governs; an absent config on a built
      # box uses the catalog's synced sources (no visibility loss); a fresh box
      # falls to the quickstart default. nil is never returned — an explicit set
      # (possibly empty) so the tool filters honestly.
      def mcp_enabled_slugs(config, registry)
        if Nabu::Profile.exist?(config.profile_path)
          return Nabu::Focus.resolve(Nabu::Profile.load(config.profile_path), registry).slugs
        end

        present = mcp_catalog_slugs(config) & registry.slugs
        present.empty? ? Nabu::Profile.default_entries(registry) : present
      end

      # The catalog's source slugs, read-only, for the MCP enablement fallback —
      # [] when there is no catalog yet.
      def mcp_catalog_slugs(config)
        return [] unless File.exist?(config.catalog_path)

        db = Nabu::Store.connect(config.catalog_path, readonly: true)
        db.table_exists?(:sources) ? db[:sources].select_map(:slug) : []
      ensure
        db&.disconnect
      end

      # (device, inode) — a file replaced in place (delete + recreate) changes
      # inode, which is how the opener notices a rebuild. nil when absent.
      def file_identity(path)
        return nil unless File.exist?(path)

        stat = File.stat(path)
        [stat.dev, stat.ino]
      end

      # The diagnostics sink for `nabu mcp`: stderr by default, or a file opened
      # for append (line-buffered) when --log FILE is given. NEVER stdout —
      # stdout is the JSON-RPC protocol channel.
      def mcp_log(path)
        return $stderr if path.to_s.strip.empty?

        # No block form: the log must stay open for the whole server lifetime;
        # `mcp` closes it in its ensure.
        file = File.open(path, "a") # rubocop:disable Style/FileOpen
        file.sync = true
        file
      end

      # SIGINT/SIGTERM → clean shutdown with EOF semantics: exit 0, unwinding the
      # command's ensure (which closes the log). A client that stops the server
      # by closing our stdin gets the same path via the run loop reaching EOF.
      def install_mcp_signal_traps
        %w[INT TERM].each { |signal| trap(signal) { exit(0) } }
      end

      # Open the catalog db for reading if it has been built; nil otherwise so
      # status degrades gracefully to registry-only output.
      def open_catalog(config)
        return nil unless File.exist?(config.catalog_path)

        db = Nabu::Store.connect(config.catalog_path)
        Nabu::Store.setup!(db)
        db
      end

      # Open the catalog for writing, creating + migrating it if this is the
      # first sync before any rebuild. Migrations are idempotent (only pending
      # ones run), so this is safe on an existing db too. Callers that also
      # open the ledger MUST open it first (open_or_create_ledger lifts a
      # pre-P7-1 catalog's history before migration 005 drops those tables).
      def open_or_create_catalog(config)
        require "fileutils"
        FileUtils.mkdir_p(File.dirname(config.catalog_path))
        db = Nabu::Store.connect(config.catalog_path)
        Nabu::Store.migrate!(db)
        Nabu::Store.setup!(db)
        db
      end

      # Open the history ledger for reading; nil when absent (fresh machine —
      # read paths treat that as empty history) or not yet migrated.
      def open_ledger(config)
        return nil unless File.exist?(config.history_path)

        db = Nabu::Store::Ledger.connect(config.history_path)
        return Nabu::Store::Ledger.setup!(db) if db.table_exists?(:runs)

        db.disconnect
        nil
      end

      # Open the history ledger for writing: create + migrate it, and lift a
      # pre-P7-1 catalog's runs/pins/baselines into it (one-shot; the catalog
      # is then migrated forward, dropping the moved tables).
      def open_or_create_ledger(config)
        Nabu::Store::Ledger.open_with_lift!(
          history_path: config.history_path, catalog_path: config.catalog_path
        )
      end
    end
  end
end
