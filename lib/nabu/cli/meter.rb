# frozen_string_literal: true

# Nabu::CLI — the scansion lane (P152): scan-meter. Carved out of
# lib/nabu/cli.rb, the registry that loads it.
module Nabu
  class CLI < Thor
    desc "scan-meter", "The scansion lane: silver Greek/Latin dactylic scansions on the local-meter shelf (P152)"
    long_desc <<~HELP, wrap: false
      The scansion lane (P152): a rule-based syllabifier + quantitative
      scanner for Greek and Latin dactylic verse (hexameter, elegiac
      pentameter — nothing else yet). It reads only what the text
      licenses — position, diphthongs, the Greek long/short letters and
      accent laws, Latin vocalis ante vocalem, elision — and a line scans
      only when exactly one template fits (or the metrical laws / the
      Latin final-syllable defaults leave one, and the scan says so).
      Anything else is UNSCANNED with its reason, never guessed.

      HEAVY-derived under the cost law: the full pass reads ~6.8M lat/grc
      passages, so its output lives on the local-meter shelf
      (local/shelves/local-meter/, JSONL shards through the
      Nabu::MeterShelf gateway), produced only by --run — never by
      `nabu rebuild`.

      Modes (one at a time):
        (bare)       census: shelf records, scanner versions, staleness,
                     arm state, projected rows
        --validate   run the scanner over every passage the HELD gold
                     covers (pedecerto Latin H/P, hypotactic Greek
                     dactylic lines) and print agreement per language,
                     meter and split (dev = the rules' development slice,
                     held_out = the rest). Read-only. --split narrows.
        --estimate   count the candidate passages in scope (no scanning)
        --run        the campaign: scan the scope onto the shelf
                     (resumable, delta-only; a document whose lines do
                     not scan as verse shelves one gate record instead)
        --project    the OWNER's gate: arm the shelf and project its
                     scanned lines into the meter layer as SILVER rows
                     (model nabu-scan, grade silver) — never over a gold
                     row, never over a text that moved since the scan.
                     Once armed, every rebuild flavor and builders:refresh
                     re-projects (the lane survives `nabu rebuild`).
        --retract    disarm and drop the projected rows (shelf kept)

      Scope (--run / --estimate / --validate): --lang lat|grc,
      --source SLUG, --urn PREFIX (a document urn prefix).

      Examples:
        nabu scan-meter --validate
        nabu scan-meter --validate --lang grc --split held_out
        nabu scan-meter --estimate --source perseus-lat
        nabu scan-meter --run --urn urn:cts:latinLit:phi0690.
        nabu scan-meter --project
    HELP
    option :validate, type: :boolean, default: false, desc: "Score the scanner against the held meter gold"
    option :estimate, type: :boolean, default: false, desc: "Count the candidate passages in scope"
    option :run, type: :boolean, default: false, desc: "Scan the scope onto the local-meter shelf"
    option :project, type: :boolean, default: false, desc: "Arm the shelf and project it as silver meter rows"
    option :retract, type: :boolean, default: false, desc: "Disarm the shelf and drop the projected rows"
    option :lang, type: :string, enum: %w[lat grc], desc: "Scope: one language"
    option :source, type: :string, banner: "SLUG", desc: "Scope: one registered source"
    option :urn, type: :string, banner: "PREFIX", desc: "Scope: documents whose urn starts with PREFIX"
    option :split, type: :string, enum: %w[dev held_out], desc: "With --validate: one split only"
    def scan_meter
      modes = %i[validate estimate run project retract].select { |mode| options[mode] }
      raise Thor::Error, "scan-meter: one of --validate/--estimate/--run/--project/--retract at a time" if
        modes.size > 1
      raise Thor::Error, "scan-meter: --split only accompanies --validate" if options[:split] && !options[:validate]

      config = Nabu::Config.load
      shelf = Nabu::MeterShelf.new(dir: Nabu::MeterShelf.dir(config))
      case modes.first
      when :validate then scan_meter_validate(config)
      when :estimate then scan_meter_estimate(config)
      when :run then scan_meter_run(config, shelf)
      when :project then scan_meter_project(config, shelf)
      when :retract then scan_meter_retract(config, shelf)
      else scan_meter_census(config, shelf)
      end
    rescue Nabu::Error => e
      raise Thor::Error, "scan-meter: #{e.message}"
    end

    no_commands do
      def scan_meter_catalog(config)
        raise Thor::Error, "scan-meter: no catalog at #{config.catalog_path} — run nabu sync first" unless
          File.exist?(config.catalog_path)

        Nabu::Store.connect(config.catalog_path, readonly: true)
      end

      def scan_meter_scope
        { language: options[:lang], source: options[:source], urn_prefix: options[:urn] }
      end

      def scan_meter_validate(config)
        catalog = scan_meter_catalog(config)
        split = options[:split]&.to_sym
        report = Nabu::Scansion::GoldCheck.new(catalog: catalog).run(language: options[:lang], split: split)
        say "scansion vs the held meter gold (#{Nabu::Scansion::VERSION}) — " \
            "#{commas(report.total.lines)} gold-covered dactylic lines"
        say "  dev split = #{Nabu::Scansion::GoldCheck::DEV_SET.map { |w, c| "#{w}#{c}" }.join(', ')}"
        keys = report.tallies.keys.sort_by { |k| k.map(&:to_s) }
        keys.each { |key| say scan_meter_line(key.join(" / "), report.tallies[key]) }
        %w[lat grc].each do |language|
          total = report.total(language: language)
          say scan_meter_line("#{language} / all", total) if total.lines.positive?
        end
        scan_meter_syllables(report)
        return unless report.lines_per_second

        say format("  %<seconds>.1f s scanning, %<rate>s lines/s",
                   seconds: report.seconds, rate: commas(report.lines_per_second.to_i))
      ensure
        catalog&.disconnect
      end

      def scan_meter_line(label, tally)
        bases = tally.by_basis.sort.map { |basis, (s, a)| "#{basis} #{a}/#{s}" }.join(", ")
        unscanned = tally.unscanned.sort.map { |reason, n| "#{reason} #{n}" }.join(", ")
        format("  %<label>-34s %<lines>6s lines  agree %<agree>5.1f%%  coverage %<coverage>5.1f%%  " \
               "precision %<precision>5.1f%%  [%<bases>s]  unscanned: %<unscanned>s",
               label: label, lines: commas(tally.lines), agree: 100 * tally.agreement,
               coverage: 100 * tally.coverage, precision: 100 * (tally.precision || 0),
               bases: bases, unscanned: unscanned.empty? ? "none" : unscanned)
      end

      def scan_meter_syllables(report)
        greek = report.total(language: "grc")
        return unless greek.syllables_compared.positive?

        say format("  grc syllable quantities vs hypotactic: %<share>.1f%% of %<n>s syllables " \
                   "(final anceps excluded)",
                   share: 100.0 * greek.syllables_agree / greek.syllables_compared,
                   n: commas(greek.syllables_compared))
      end

      def scan_meter_estimate(config)
        catalog = scan_meter_catalog(config)
        shelf = Nabu::MeterShelf.new(dir: Nabu::MeterShelf.dir(config))
        count = Nabu::MeterScan.new(catalog: catalog, shelf: shelf).candidate_passages(**scan_meter_scope)
        say "#{commas(count)} candidate lat/grc passage(s) in scope — `nabu scan-meter --run` with the same " \
            "scope scans them (prose documents end at the #{Nabu::MeterScan::PROBE}-passage probe)"
      ensure
        catalog&.disconnect
      end

      def scan_meter_run(config, shelf)
        catalog = scan_meter_catalog(config)
        progress = lambda do |done, total|
          warn "  scan-meter: #{commas(done)}/#{commas(total)} documents" if (done % 500).zero? || done == total
        end
        report = Nabu::MeterScan.new(catalog: catalog, shelf: shelf).run(**scan_meter_scope, progress: progress)
        say "scanned #{commas(report.passages)} passage(s) in #{commas(report.documents)} document(s) " \
            "(#{format('%.1f', report.seconds)} s): #{commas(report.verse_documents)} verse, " \
            "#{commas(report.gated_documents)} gated as not dactylic verse, " \
            "#{commas(report.current_documents)} already current"
        say "  #{commas(report.scanned)} line(s) scanned; #{commas(report.records)} record(s) → " \
            "#{commas(report.shards)} shard(s) on #{shelf.dir}"
        say "  not yet in the meter layer — `nabu scan-meter --project` projects the shelf" unless shelf.armed?
        say "  the shelf is armed — re-project now with `nabu scan-meter --project`" if shelf.armed?
      ensure
        catalog&.disconnect
      end

      def scan_meter_project(config, shelf)
        raise Thor::Error, "scan-meter: the local-meter shelf at #{shelf.dir} is empty — --run first" if
          shelf.shard_paths.empty?

        catalog = open_or_create_catalog(config)
        shelf.arm!
        report = Nabu::Store::SilverMeter.project!(catalog: catalog, shelf: shelf)
        say "projected #{commas(report.projected)} silver scansion(s) — #{commas(report.gold_covered)} " \
            "gold-covered line(s) left to the gold, #{commas(report.stale)} stale (text moved since the scan), " \
            "#{commas(report.unresolved)} naming no live passage, #{commas(report.unscanned)} unscanned"
        say "  armed: every rebuild and builders:refresh now re-projects the shelf"
      ensure
        catalog&.disconnect
      end

      def scan_meter_retract(config, shelf)
        shelf.disarm!
        catalog = open_catalog(config)
        removed = catalog ? Nabu::Store::SilverMeter.retract!(catalog: catalog) : 0
        say "retracted #{commas(removed)} silver scansion(s); the shelf is disarmed (its records stay shelved)"
      ensure
        catalog&.disconnect
      end

      def scan_meter_census(config, shelf)
        census = Nabu::MeterShelf::Census.of(shelf)
        say "local-meter shelf: #{shelf.dir}"
        say "  #{commas(census.scanned)} scanned + #{commas(census.unscanned)} unscanned line(s), " \
            "#{commas(census.gates)} document gate record(s) in #{commas(shelf.shard_paths.size)} shard(s)"
        say "  newest record #{census.newest || 'none'}; scanner versions: " \
            "#{census.versions.empty? ? 'none' : census.versions.map { |v, n| "#{v} ×#{commas(n)}" }.join(', ')}"
        if census.old_code.positive?
          say "  STALE: #{commas(census.old_code)} line(s) scanned by an older scanner than " \
              "#{Nabu::Scansion::VERSION} — `nabu scan-meter --run` re-scans them"
        end
        say "  #{shelf.armed? ? 'ARMED — projected at every rebuild/builders:refresh' : 'not armed — never projected'}"
        catalog = open_catalog(config)
        return unless catalog&.table_exists?(:enrichments)

        rows = catalog[:enrichments].where(kind: "meter", model: Nabu::Store::SilverMeter::MODEL).count
        say "  #{commas(rows)} silver scansion row(s) in the meter layer"
      ensure
        catalog&.disconnect
      end
    end
  end
end
