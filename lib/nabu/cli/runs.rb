# frozen_string_literal: true

# The `nabu runs` command family — ledger run-row remedies. Lives under
# cli/ (the by-area layout; outside the derivation fingerprint).
module Nabu
  # `nabu runs`: the history ledger's run rows — today one command,
  # close-stale, the remedy the health stale-open-runs finding names.
  class RunsCLI < Thor
    namespace "runs"

    def self.exit_on_failure?
      true
    end

    desc "close-stale", "Close run rows still \"running\" past the stale threshold as \"abandoned\""
    long_desc <<~HELP, wrap: false
      A run row closes at operation end; a process that dies first (killed,
      crashed, slept through) leaves it "running" forever, and `nabu health`
      reports every such row older than the stale threshold
      (#{Nabu::Health::Invariants::STALE_OPEN_RUN_SECONDS / 3_600} h after start). This closes exactly those rows
      "abandoned" — finished_at stamped, the reason in notes — through the
      run gateway, and prints each one (slug, kind, started_at). Rows inside
      the threshold (a live operation) and closed rows are never touched.
      The row is history: whatever the dead run left in the catalog is
      judged by the per-source checks, and a later run of the source
      supersedes it. --dry-run lists the rows and writes nothing.
    HELP
    option :dry_run, type: :boolean, default: false, desc: "List the stale rows; write nothing"
    def close_stale
      config = Nabu::Config.load
      unless File.exist?(config.history_path)
        say "no ledger at #{config.history_path} — no run rows to close"
        return
      end

      # --dry-run reads the ledger as it stands — never migrates it (a
      # migrated ledger is unreadable to an older checkout's migrator); the
      # write path migrates first, since "abandoned" needs the widened CHECK.
      ledger = options[:dry_run] ? read_ledger(config) : Nabu::Store::Ledger.open!(config.history_path)
      cutoff = Time.now - Nabu::Health::Invariants::STALE_OPEN_RUN_SECONDS
      rows = if options[:dry_run]
               ledger ? Nabu::Store::RunRecorder.stale(before: cutoff) : []
             else
               Nabu::Store::RunRecorder.close_stale(before: cutoff)
             end
      report_stale(rows)
    ensure
      ledger&.disconnect
    end

    no_commands do
      def read_ledger(config)
        db = Nabu::Store::Ledger.connect(config.history_path)
        return Nabu::Store::Ledger.setup!(db) if db.table_exists?(:runs)

        db.disconnect
        nil
      end

      def report_stale(rows)
        if rows.empty?
          say "no stale run rows (none still \"running\" " \
              "#{Nabu::Health::Invariants::STALE_OPEN_RUN_SECONDS / 3_600} h+ after start)"
          return
        end

        noun = "stale run row#{'s' unless rows.size == 1}"
        say options[:dry_run] ? "would close #{rows.size} #{noun}" : "closed #{rows.size} #{noun} \"abandoned\""
        rows.each do |row|
          say format("  %<slug>-28s %<kind>-8s %<at>s", slug: row.source_slug, kind: row.kind,
                                                        at: row.started_at.strftime("%Y-%m-%d %H:%M"))
        end
        say "dry run — nothing written" if options[:dry_run]
      end
    end
  end
end
