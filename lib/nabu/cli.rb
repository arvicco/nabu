# frozen_string_literal: true

require "thor"
require_relative "version"

module Nabu
  # Command-line entry point. Only `version` is functional in Phase 0; the
  # ingest/query subcommands are stubs that report "not implemented" and exit 1
  # so scripts and CI can rely on the failure signal before the real work lands.
  class CLI < Thor
    # Raise Thor::Error (rather than aborting the process abruptly) so failures
    # surface a clean stderr message and a non-zero exit status.
    def self.exit_on_failure?
      true
    end

    desc "version", "Print the Nabu version"
    def version
      say Nabu::VERSION
    end

    desc "sync [SOURCE]", "Fetch and load a source (or --all live sources) into the store"
    option :all, type: :boolean, default: false,
                 desc: "Sync every enabled source with sync_policy: live"
    option :parse_only, type: :boolean, default: false,
                        desc: "Skip fetch; re-parse the snapshot already on disk"
    option :force, type: :boolean, default: false,
                   desc: "Override the >20% withdrawal circuit breaker"
    def sync(slug = nil)
      config = Nabu::Config.load
      registry = Nabu::SourceRegistry.load(config.sources_path)
      db = open_or_create_catalog(config)
      runner = Nabu::SyncRunner.new(config: config, registry: registry, db: db)
      options[:all] ? sync_all(runner) : sync_one(runner, registry, slug)
    rescue Nabu::Error => e
      # Unknown slug (ValidationError), fetch failure (FetchError), ... all
      # surface as a clean stderr message and exit 1.
      raise Thor::Error, e.message
    ensure
      db&.disconnect
    end

    desc "status", "Show per-source sync status and passage counts"
    def status
      config = Nabu::Config.load
      registry = Nabu::SourceRegistry.load(config.sources_path)
      db = open_catalog(config)
      say Nabu::StatusReport.render(registry: registry, db: db)
    ensure
      db&.disconnect
    end

    desc "rebuild", "Rebuild the derived db/ from canonical/ (parse-only; no fetch)"
    option :dry_run, type: :boolean, default: false,
                     desc: "Print what would happen and change nothing"
    def rebuild
      config = Nabu::Config.load
      registry = Nabu::SourceRegistry.load(config.sources_path)
      # db/ is derived data by design (architecture §1); dropping it is the whole
      # point, so a real run needs no confirmation. An empty registry has nothing
      # to replay.
      return say("Nothing to rebuild: no sources registered.") if registry.empty?

      rebuilder = Nabu::Rebuild.new(config: config, registry: registry)
      if options[:dry_run]
        print_plan(rebuilder.plan)
      else
        result = rebuilder.run(progress: progress_reporter)
        finish_progress
        print_result(result)
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
    def health
      # Bare `health` is the local, no-network P5-5 check (run-history trends +
      # live golden replay). --remote is the P5-3 upstream probe. The two share
      # nothing at runtime, so keep them in separate helpers with their own db
      # lifetimes and exit-code raises.
      options[:remote] ? run_remote_health : run_local_health
    end

    desc "search QUERY", "Full-text search the corpus (FTS5 over folded text)"
    option :lang, type: :string, desc: "Restrict to a passage language (e.g. grc, lat)"
    option :license, type: :string,
                     desc: "Restrict to an exact license class (open, attribution, nc, …)"
    option :limit, type: :numeric, default: 20, desc: "Maximum number of hits"
    def search(query = nil)
      query = query.to_s.strip
      raise Thor::Error, "search: give a query" if query.empty?

      validate_license!(options[:license])
      config = Nabu::Config.load
      catalog = open_catalog(config)
      fulltext = open_fulltext(config)
      # Either half of the derived store missing means the corpus was never
      # built/indexed; a search cannot run.
      raise Thor::Error, "no index — run nabu sync or nabu rebuild" unless catalog && fulltext

      results = Nabu::Query::Search.new(catalog: catalog, fulltext: fulltext)
                                   .run(query, lang: options[:lang], license: options[:license],
                                               limit: options[:limit].to_i)
      print_search_results(results)
    ensure
      catalog&.disconnect
      fulltext&.disconnect
    end

    desc "show URN", "Show a passage or document by urn (withdrawn items shown, flagged)"
    option :full_urn, type: :boolean, default: false,
                      desc: "List document passages with absolute urns instead of :suffixes"
    def show(urn = nil)
      urn = urn.to_s.strip
      raise Thor::Error, "show: give a urn" if urn.empty?

      config = Nabu::Config.load
      catalog = open_catalog(config)
      raise Thor::Error, "no catalog — run nabu sync or nabu rebuild" unless catalog

      result = Nabu::Query::Show.new(catalog: catalog).run(urn)
      raise Thor::Error, "urn not found: #{urn}" if result.nil?

      print_show(result)
    ensure
      catalog&.disconnect
    end

    desc "export", "Stream non-withdrawn passages as plain text or JSONL"
    option :format, type: :string, required: true, desc: "plain | jsonl"
    option :lang, type: :string, desc: "Restrict to a passage language (e.g. grc, lat)"
    option :license, type: :string,
                     desc: "Restrict to an exact license class (open, attribution, nc, …)"
    def export
      format = validate_format!(options[:format])
      validate_license!(options[:license])
      config = Nabu::Config.load
      catalog = open_catalog(config)
      raise Thor::Error, "no catalog — run nabu sync or nabu rebuild" unless catalog

      lines = Nabu::Query::Export.new(catalog: catalog)
                                 .run(format: format, lang: options[:lang], license: options[:license])
      # Stream: write each serialized line as it arrives — never join a
      # 238k-passage corpus into one string.
      lines.each { |line| $stdout.puts(line) }
    ensure
      catalog&.disconnect
    end

    no_commands do
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

      # Render `show`: a passage in the context of its document, or a document
      # header plus its passages in sequence. Withdrawn items ARE shown, tagged.
      def print_show(result)
        case result
        when Nabu::Query::Show::PassageResult then print_show_passage(result)
        when Nabu::Query::Show::DocumentResult then print_show_document(result)
        end
      end

      def print_show_passage(passage)
        say "#{passage.urn}#{" [#{passage.language}]" if passage.language}#{withdrawn_tag(passage.withdrawn)}"
        say "  #{passage.text}"
        say "  document: #{passage.document_urn}#{" — #{passage.document_title}" if passage.document_title}"
        say "  source: #{passage.source_slug}   license: #{passage.license_class}   " \
            "sequence: #{passage.sequence}   revision: #{passage.revision}"
        return if passage.provenance.empty?

        say "  provenance:"
        passage.provenance.each do |event|
          say "    #{event.at}  #{event.event}#{"  #{event.tool}" if event.tool}"
        end
      end

      def print_show_document(document)
        title = document.title ? " — #{document.title}" : ""
        lang = document.language ? " [#{document.language}]" : ""
        say "#{document.urn}#{title}#{lang}#{withdrawn_tag(document.withdrawn)}#{retired_tag(document)}"
        say "  source: #{document.source_slug}   license: #{document.license_class}   revision: #{document.revision}"
        say "  passages (#{document.passages.size}):"
        document.passages.each do |line|
          say "    #{passage_label(document, line)}#{withdrawn_tag(line.withdrawn)}  #{line.text}"
        end
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

      # Render hits: urn + optional [language] header, then the FTS snippet
      # (diacritic-folded highlight). The footer labels that so nobody reads the
      # stripped accents in the highlight as corpus truth.
      def print_search_results(results)
        return say("no matches") if results.empty?

        results.each do |result|
          say "#{result.urn}#{" [#{result.language}]" if result.language}"
          say "  #{result.snippet}"
        end
        say "#{results.size} #{results.size == 1 ? 'hit' : 'hits'} " \
            "(highlights are diacritic-folded)"
      end

      # A print-free runner needs a sink for live progress; the CLI owns all
      # formatting and tty decisions here. Progress goes to $stderr (final counts
      # go to $stdout via `say`, so scripts piping stdout are unaffected). When
      # $stderr is a tty: git output streams raw (its own \r overwrites the line)
      # and a \r-updating "loading…" counter refreshes each tick. Non-tty: no git
      # streaming (callbacks stay nil) and one plain line per 100 documents.
      def progress_reporter
        tty = $stderr.tty?
        Nabu::ProgressReporter.new(
          on_fetch_line: tty ? ->(line) { $stderr.print(line) } : nil,
          on_load_tick: load_tick(tty)
        )
      end

      def load_tick(tty)
        last = 0
        lambda do |processed, errored|
          if tty
            $stderr.print("\r#{loading_line(processed, errored)}  ")
          elsif processed - last >= 100
            last = processed
            warn(loading_line(processed, errored))
          end
        end
      end

      def loading_line(processed, errored)
        suffix = errored.positive? ? " (#{errored} quarantined)" : ""
        "  loading… #{processed} docs#{suffix}"
      end

      # Break off the \r-updated counter line before the final counts, tty only.
      def finish_progress
        $stderr.print("\n") if $stderr.tty?
      end

      # sync <slug>: explicit, unconditional (disabled sources allowed, with a
      # note). A tripped breaker prints its counts + the --force hint and exits 1.
      def sync_one(runner, registry, slug)
        raise Thor::Error, "sync: give a source slug or --all" if slug.nil?

        entry = registry[slug]
        say "Note: #{slug} is disabled; syncing anyway (explicit request).", :yellow if entry && !entry.enabled
        outcome = runner.sync(slug, parse_only: options[:parse_only], force: options[:force],
                                    progress: progress_reporter)
        finish_progress
        raise Thor::Error, "#{slug}: #{outcome.breaker.message}" if outcome.aborted?

        say format_sync_outcome(outcome)
        print_sync_warnings(outcome)
      end

      # sync --all: enabled + live sources only; report each, never abort the
      # batch on one source's error.
      def sync_all(runner)
        results = runner.sync_all(parse_only: options[:parse_only], force: options[:force],
                                  progress: progress_reporter)
        finish_progress
        return say("Nothing to sync: no enabled, live sources.") if results.empty?

        results.each do |slug, result|
          say("  #{sync_all_line(slug, result)}")
          print_sync_warnings(result) if result.is_a?(Nabu::SyncRunner::Outcome)
        end
      end

      def sync_all_line(slug, result)
        return "#{slug.ljust(24)} FAILED — #{result.message}" unless result.is_a?(Nabu::SyncRunner::Outcome)
        return "#{slug.ljust(24)} ABORTED — #{result.breaker.message}" if result.aborted?

        format_sync_outcome(result)
      end

      # P5-5 inline deviation warnings: advisory one-liners after the counts line,
      # in yellow, never affecting the exit code. Empty on a clean sync.
      def print_sync_warnings(outcome)
        outcome.warnings.each { |finding| say("  ! #{finding.message}", :yellow) }
      end

      def format_sync_outcome(outcome)
        fetched = outcome.fetch_report ? outcome.fetch_report.sha[0, 12] : "parse-only"
        report = outcome.load_report
        "#{outcome.slug.ljust(24)} #{fetched}  " \
          "+#{report.added} added  ~#{report.updated} updated  " \
          "=#{report.skipped} skipped  -#{report.withdrawn} withdrawn  !#{report.errored} errored  " \
          "indexed #{outcome.indexed} passages"
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
        result.warnings.each do |outcome|
          say "  WARNING: #{outcome.slug} quarantined #{outcome.report.errored} document(s) — parser regression?"
        end
        say "  #{format_report('TOTAL', total_report(result))}"
        say "  indexed #{result.indexed} passages"
      end

      def format_report(label, report)
        "#{label.ljust(24)} +#{report.added} added  ~#{report.updated} updated  " \
          "=#{report.skipped} skipped  -#{report.withdrawn} withdrawn  !#{report.errored} errored"
      end

      def total_report(result)
        reports = result.outcomes.map(&:report)
        Nabu::Store::LoadReport.new(
          added: reports.sum(&:added), updated: reports.sum(&:updated),
          skipped: reports.sum(&:skipped), withdrawn: reports.sum(&:withdrawn),
          errored: reports.sum(&:errored)
        )
      end

      # --remote (P5-3): the no-clone upstream probe. Its own db handle (migrated
      # so the license-baseline column exists), its own exit-1 raise.
      def run_remote_health
        config = Nabu::Config.load
        registry = Nabu::SourceRegistry.load(config.sources_path)
        db = open_catalog_for_health(config)
        report = Nabu::Health::RemoteProbe.new(registry: registry, db: db).run
        print_remote_health(report)
        # A gone upstream is the only red finding; the table is already on stdout,
        # so raise for the exit-1 signal (Thor prints the summary to stderr).
        raise Thor::Error, remote_health_failure(report) if report.any_gone?
      ensure
        db&.disconnect
      end

      # Bare health (P5-5): run-history trends + live golden replay, no network.
      # open_catalog binds the Store models the LocalCheck queries. Exit 1 on any
      # loud finding (quarantine spike, >15% creep, a lost golden query); soft
      # warnings (collapse, 5–15% creep, stale) stay exit 0.
      def run_local_health
        config = Nabu::Config.load
        registry = Nabu::SourceRegistry.load(config.sources_path)
        catalog = open_catalog(config)
        fulltext = catalog ? open_fulltext(config) : nil
        report = Nabu::Health::LocalCheck.new(
          registry: registry, catalog: catalog, fulltext: fulltext,
          golden_queries: Nabu::Health::LocalCheck.golden_queries
        ).run
        print_local_health(report)
        raise Thor::Error, local_health_failure(report) if report.any_loud?
      ensure
        catalog&.disconnect
        fulltext&.disconnect
      end

      # Per-source trend rows, then the golden-replay section, then the verdict
      # and a hint toward the upstream probe.
      def print_local_health(report)
        print_source_health(report.sources)
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

      # Like open_catalog, but also applies pending migrations so the P5-3
      # license-baseline column exists on catalogs built before it (add_column
      # is idempotent — only pending migrations run). nil when no catalog has
      # been built yet: the probe then treats every source as never-synced and
      # records no baseline.
      def open_catalog_for_health(config)
        return nil unless File.exist?(config.catalog_path)

        db = Nabu::Store.connect(config.catalog_path)
        Nabu::Store.migrate!(db)
        Nabu::Store.setup!(db)
        db
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
          say "#{row.slug.ljust(slug_w)}  #{live_cell(row.liveness).ljust(live_w)}  " \
              "#{drift_cell(row.drift).ljust(drift_w)}  #{license_cell(row.license)}#{health_detail(row)}"
        end
        say remote_health_summary(report)
      end

      def live_cell(liveness)
        { alive: "alive", moved: "MOVED", gone: "GONE" }.fetch(liveness.status)
      end

      def drift_cell(drift)
        { current: "current", behind: "behind", never_synced: "never-synced",
          unknown: "—", multi: "multi-repo" }.fetch(drift)
      end

      def license_cell(license)
        { baseline_recorded: "license: baseline recorded", unchanged: "license: ok",
          changed: "license: CHANGED", unchecked: "license: unchecked" }.fetch(license.status)
      end

      # Trailing context: why an upstream is not alive, or why a license row is
      # flagged. Kept off the aligned columns so the table stays readable.
      def health_detail(row)
        bits = []
        bits << row.liveness.detail if row.liveness.detail && row.liveness.status != :alive
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
      # ones run), so this is safe on an existing db too.
      def open_or_create_catalog(config)
        require "fileutils"
        FileUtils.mkdir_p(File.dirname(config.catalog_path))
        db = Nabu::Store.connect(config.catalog_path)
        Nabu::Store.migrate!(db)
        Nabu::Store.setup!(db)
        db
      end
    end
  end
end
