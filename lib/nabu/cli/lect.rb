# frozen_string_literal: true

# Nabu::CLI — the `nabu lect` subcommand family (LectCLI). Carved out of
# lib/nabu/cli.rb, the registry that loads it.
module Nabu
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
      check_basis!(options[:basis], config: config)
      if options[:from_file]
        import_batch!(config, registry, options[:from_file])
      else
        raise Thor::Error, "lect assign: URN and LECT_ID are required (or --from-file FILE)" unless urn && lect_id

        check_lect!(registry, lect_id)
        code = options[:code] || infer_code!(config, urn)
        # P70 (the derivability contract): an OWNER ruling's source of
        # truth is config/lect_rulings.yml — written FIRST; the journal
        # row is its derived mirror (rebuild re-derives it). Rule-basis
        # rows are compiled derivations and stay journal-only.
        if options[:basis] == "owner"
          Nabu::LectRulings.append!(config.lect_rulings_path, urn: urn, code: code,
                                                              lect_id: lect_id, note: options[:note])
        end
        journal = Nabu::Store::LectJournal.open!(config.lects_journal_path)
        verdict = Nabu::Store::LectJournal.assign!(journal, urn: urn, code: code, lect_id: lect_id,
                                                            basis: options[:basis], note: options[:note])
        say "#{verdict}  #{urn}  #{code} → #{lect_id}  (#{options[:basis]}" \
            "#{' · config/lect_rulings.yml' if options[:basis] == 'owner'})"
        refresh_lect_facet(config, urn)
      end
    end

    desc "list", "The journaled assignments (--urn/--basis filters; --format tsv is the flat backup)"
    option :urn, banner: "URN"
    option :basis, banner: "owner|rule:<id>"
    option :format, banner: "tsv"
    # census: render cap only — the full journal is always in the tsv export;
    # truncation is announced (the house honesty vocabulary)
    option :limit, type: :numeric, default: 50,
                   desc: "Rows shown (truncation is announced; --format tsv prints the full journal)"
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
    option :verbose, type: :boolean, default: false, desc: Nabu::Ops::StageGuide::OPTION_DESC
    def apply_rules
      config = Nabu::Config.load
      guard_catalog_free!(config) unless options[:"dry-run"]
      registry = require_lects_module!(config)
      rules = Nabu::LectRules.load(config.lect_facet_rules_paths)
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
      lect_narrator&.intro(:lect_apply_rules) unless options[:dry_run]
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
    option :verbose, type: :boolean, default: false, desc: Nabu::Ops::StageGuide::OPTION_DESC
    def infer_dates
      config = Nabu::Config.load
      guard_catalog_free!(config) unless options[:"dry-run"]
      registry = require_lects_module!(config)
      unless File.exist?(config.catalog_path)
        raise Thor::Error,
              "lect infer-dates: no catalog at #{config.catalog_path}"
      end

      catalog = Nabu::Store.connect(config.catalog_path)
      lect_narrator&.intro(:lect_infer_dates) unless options[:dry_run]
      dates = Nabu::LectDates.new(registry: registry)
      scope = [options[:source], options[:lang]].compact
      say "scanning dated documents#{scope.empty? ? ' (whole catalog)' : " (#{scope.join(', ')})"}…"
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
    option :verbose, type: :boolean, default: false, desc: Nabu::Ops::StageGuide::OPTION_DESC
    def materialize
      config = Nabu::Config.load
      guard_catalog_free!(config)
      require_lects_module!(config)
      unless File.exist?(config.catalog_path)
        raise Thor::Error,
              "lect materialize: no catalog at #{config.catalog_path}"
      end

      lect_narrator&.intro(:lect_materialize)
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
      shelf = Nabu::LanguageShelf.new(dir: Nabu::LanguageShelf.dir(config))
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
    option :dry_run, type: :boolean, default: false,
                     desc: "Preview the assignment rows that would be removed; write nothing"
    def withdraw(urn)
      config = Nabu::Config.load
      journal = Nabu::Store::LectJournal.open_readonly(config.lects_journal_path)
      raise Thor::Error, "lect withdraw: no journal at #{config.lects_journal_path}" unless journal

      # P90-3 (lane 3): the one destructive lect command gains a
      # preview — the victim rows in the `lect list` shape, nothing touched
      # (neither the journal nor the rulings config).
      if options[:dry_run]
        scope = journal[:lect_assignments].where(urn: urn)
        scope = scope.where(code: options[:code]) if options[:code]
        rows = scope.order(:code).all
        journal.disconnect
        say "would withdraw #{rows.size} assignment#{'s' unless rows.size == 1}  " \
            "#{urn}#{" #{options[:code]}" if options[:code]}"
        rows.each { |row| say "  #{row[:urn]}  #{row[:code]}  #{row[:lect_id]}  (#{row[:basis]})" }
        say "dry run — nothing written"
        return
      end

      journal.disconnect
      writable = Nabu::Store::LectJournal.open!(config.lects_journal_path)
      # P70: the config source of truth FIRST — a failure between the two
      # writes must leave the ruling gone from config (rebuild then heals
      # the journal forward), never lingering there to resurrect a
      # journal-withdrawn ruling at the next rebuild.
      Nabu::LectRulings.remove!(config.lect_rulings_path, urn: urn, code: options[:code])
      count = Nabu::Store::LectJournal.withdraw!(writable, urn: urn, code: options[:code])
      say "withdrew #{count} assignment#{'s' unless count == 1}  #{urn}#{" #{options[:code]}" if options[:code]}"
      refresh_lect_facet(config, urn)
    end

    no_commands do
      # P62 rider: the quarter-second write-lock pre-flight for journal/facet
      # writers — one clean sentence instead of a BusyException stack.
      def guard_catalog_free!(config)
        Nabu::Store.assert_writable!(config.catalog_path)
      rescue Nabu::CatalogBusyError => e
        raise Thor::Error, e.message
      end

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

      def check_basis!(basis, where: nil, config: nil)
        return if basis == "owner"

        unless basis.match?(/\Arule:[a-z0-9][a-z0-9-]*\z/)
          raise Thor::Error, "lect: basis must be owner or rule:<id>, got #{basis.inspect}#{where}"
        end
        # P71-6 (the derivability law): a rule: row is re-minted at rebuild
        # ONLY if its rule exists in the compiled rules files — a row with
        # an unknown rule id would silently VANISH at the next rederive.
        return if config.nil?

        rules = Nabu::LectRules.load(config.lect_facet_rules_paths)
        id = basis.delete_prefix("rule:")
        return if rules&.rules&.any? { |rule| rule.id == id }

        raise Thor::Error, "lect: basis #{basis.inspect}#{where} names no rule in the compiled rules " \
                           "files — the row would silently vanish at the next rebuild's re-derivation " \
                           "(add the rule to config/lect_facet_rules.yml or its local/config/ overlay first)"
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

        rows = parse_batch!(registry, path, config: config)
        journal = Nabu::Store::LectJournal.open!(config.lects_journal_path)
        # P70: owner-basis batch rows write through config/lect_rulings.yml
        # first (the source of truth) — the journal rows are derived.
        rows.each do |row|
          next unless row.fetch(:basis, "owner") == "owner"

          Nabu::LectRulings.append!(config.lect_rulings_path, urn: row[:urn], code: row[:code],
                                                              lect_id: row[:lect_id], note: row[:note])
        end
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
        # P90-3 (lane 4b): the generalized front door covers all four
        # core layers; this lect-only view stays for depth.
        say "  (the all-layers census is `nabu layer suggest #{report.slug}` — lect, dating, places, script)"
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
        if dating.annotation_candidates.any?
          keys = dating.annotation_candidates.first(6).map { |key, count| "#{key} (#{count})" }.join(", ")
          say "    annotation sniff — date-shaped keys on undated docs' passages: #{keys} " \
              "(sampled ≤#{Nabu::LectSuggest::SNIFF_SAMPLE} passages)"
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
        count = Nabu::Store::LectFacets.rebuild!(catalog: catalog, registry: registry,
                                                 progress: facet_progress)
        say "lect facet: #{count} rows materialized"
      end

      # --verbose (Ops::StageGuide): green narration on stderr; the
      # before-hook breaks off a tty row ticker so no line splices.
      def lect_narrator
        return nil unless options[:verbose]

        @lect_narrator ||= Nabu::Ops::StageGuide::Narrator.new(
          io: $stderr, before: -> { $stderr.print("\r\e[K") if $stderr.tty? }
        )
      end

      # A minimal announce-and-tick reporter for the facet rebuild (the
      # no-silent-passes rule — this subcommand class has no loader
      # plumbing to borrow): stages to stderr; on a tty a \r-updating
      # counter, else one plain line per 100k rows.
      def facet_progress
        tty = $stderr.tty?
        Nabu::ProgressReporter.new(
          on_explain: lect_narrator,
          on_stage: ->(label, _eta = nil) { warn(label) },
          on_load_tick: lambda do |processed, _errored|
            if tty
              $stderr.print("\r  #{processed} rows…")
            elsif (processed % 100_000) < Nabu::Store::LectFacets::INSERT_BATCH
              warn("  #{processed} rows…")
            end
          end
        )
      end

      def parse_batch!(registry, path, config: nil)
        File.readlines(path).each_with_index.filter_map do |line, index|
          text = line.chomp
          next if text.strip.empty? || text.lstrip.start_with?("#")

          urn, code, lect_id, basis, note = text.split("\t", 5)
          where = " (#{File.basename(path)} line #{index + 1})"
          raise Thor::Error, "lect assign: urn/code/lect_id required#{where}" if lect_id.to_s.strip.empty?

          check_lect!(registry, lect_id, where: where)
          basis = options[:basis] if basis.to_s.strip.empty?
          check_basis!(basis, where: where, config: config)
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
end
