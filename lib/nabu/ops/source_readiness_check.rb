# frozen_string_literal: true

require "date"
require "yaml"

module Nabu
  module Ops
    # The registered-never-synced probe (`rake boards:check`): a source
    # registered in config/sources.yml whose first sync never ran leaves
    # no mark anywhere a gate reads — the run ledger is the only surface
    # a sync writes — so a build-complete adapter can hang unattended
    # indefinitely (one module sat three weeks until the owner happened
    # to ask). The probe diffs the registry against the ledger's runs
    # and fails BY NAME on any source with zero runs once its grace
    # window, counted from the entry's adopted date, has passed. A box
    # without the ledger (any public clone, a lane worktree) gets an
    # announced skip, never a failure.
    class SourceReadinessCheck
      GRACE_DAYS = 7

      Report = Data.define(:skipped, :findings) do
        def clean? = findings.empty?
      end

      def initialize(sources_path:, ledger_path:, today: Date.today)
        @sources_path = sources_path
        @ledger_path = ledger_path
        @today = today
      end

      def run
        return Report.new(skipped: true, findings: []) unless File.exist?(@ledger_path)

        synced = synced_slugs
        findings = registry.filter_map do |slug, entry|
          next if synced.include?(slug)

          adopted = entry.is_a?(Hash) ? entry["adopted"] : nil
          if adopted.nil?
            "#{slug}: registered with no adopted date and zero runs in the ledger — " \
              "run its first sync or date the entry"
          elsif @today - Date.parse(adopted.to_s) > GRACE_DAYS
            "#{slug}: registered #{adopted}, zero runs in the ledger after the " \
              "#{GRACE_DAYS}-day grace — a ready source is hanging unsynced"
          end
        end
        Report.new(skipped: false, findings: findings)
      end

      private

      def registry
        YAML.safe_load_file(@sources_path) || {}
      end

      def synced_slugs
        db = Nabu::Store.connect(@ledger_path, readonly: true)
        db[:runs].distinct.select_map(:source_slug).to_set
      ensure
        db&.disconnect
      end
    end
  end
end
